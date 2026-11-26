import Foundation

public enum MessageCodecError: Error, Equatable, Sendable {
    /// 모르는 type이거나 방향이 맞지 않는 type
    case unknownType(String)
    /// 형식은 맞지만 계약을 어긴 값 (UUID 형식, 고정값, 목록 규칙 등). 값은 필드 이름이다.
    case invalidField(String)
}

/// protocol.md v1 메시지의 인코딩·디코딩.
///
/// 판정 기준은 protocol.md와 `fixtures/`다: 필수 필드, null 금지, 타입, 소문자 canonical UUID v4,
/// 오류 코드 enum, 서버 메시지의 `timestamp` 필수, 방향이 맞지 않는 type 거부, 모르는 type 거부, 모르는 필드 무시.
public enum MessageCodec {
    public static func decodeServer(_ data: Data) throws -> ServerMessage {
        try JSONDecoder().decode(ServerEnvelope.self, from: data).message
    }

    /// 보낼 때 ID를 소문자로 바꾸고, `timestamp`는 넣지 않는다.
    /// 카테고리 값과 catalogVersion은 검사하지 않는다 (서버가 INVALID_CRITERIA로 답할 대상).
    public static func encodeClient(_ message: ClientMessage) throws -> Data {
        switch message {
        case let .matchRequest(payload):
            return try encode(message.type, WireV1.MatchRequestPayload(
                requestID: payload.requestID.lowercased(),
                catalogVersion: payload.catalogVersion,
                category: payload.category
            ))
        case let .matchCancel(requestID):
            return try encode(message.type, WireV1.RequestPayload(requestID: requestID.lowercased()))
        case let .leaveRoom(roomID), let .startGame(roomID):
            return try encode(message.type, WireV1.RoomPayload(roomID: roomID.lowercased()))
        case let .readyToPlay(roomID, roundNumber):
            return try encode(message.type, WireV1.ReadyToPlayPayload(roomID: roomID.lowercased(), roundNumber: roundNumber))
        case let .submitAnswer(roomID, answer):
            return try encode(message.type, WireV1.SubmitAnswerPayload(roomID: roomID.lowercased(), answer: answer))
        case let .kickPlayer(roomID, targetPlayerID):
            return try encode(message.type, WireV1.KickPlayerPayload(
                roomID: roomID.lowercased(),
                targetPlayerID: targetPlayerID.lowercased()
            ))
        }
    }

    /// fixture 재인코딩 검증용.
    /// 카테고리 값과 catalogVersion은 검사하지 않는다 (`fixtures/criteria-invalid.json`).
    public static func decodeClient(_ data: Data) throws -> ClientMessage {
        try JSONDecoder().decode(ClientEnvelope.self, from: data).message
    }

    private static func encode<Payload: Encodable & WireValidatable>(_ type: String, _ payload: Payload) throws -> Data {
        try payload.validate()
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(OutgoingEnvelope(type: type, payload: payload))
    }
}

// MARK: - 봉투

private enum EnvelopeKey: String, CodingKey {
    case type
    case payload
    case timestamp
}

private typealias EnvelopeContainer = KeyedDecodingContainer<EnvelopeKey>
private typealias PayloadDecoder<Message> = @Sendable (EnvelopeContainer) throws -> Message

/// payload를 `Payload`로 디코딩하고 계약을 검사한 뒤 메시지로 만든다.
private func payload<Payload: Decodable & WireValidatable, Message>(
    _ make: @escaping @Sendable (Payload) -> Message
) -> PayloadDecoder<Message> {
    { container in
        let payload = try container.decode(Payload.self, forKey: .payload)
        try payload.validate()
        return make(payload)
    }
}

private let serverDecoders: [String: PayloadDecoder<ServerMessage>] = [
    "MATCH_WAITING": payload { .matchWaiting($0) },
    "MATCH_CANCELLED": payload { .matchCancelled($0) },
    "MATCH_FAILED": payload { .matchFailed($0) },
    "WELCOME": payload { .welcome($0) },
    "ROOM_LEFT": payload { .roomLeft($0) },
    "ROOM_COMMAND_FAILED": payload { .roomCommandFailed($0) },
    "GAME_ABORTED": payload { .gameAborted($0) },
    "PLAYER_JOINED": payload { .playerJoined($0) },
    "PLAYER_LEFT": payload { .playerLeft($0) },
    "HOST_CHANGED": payload { .hostChanged($0) },
    "PLAYER_KICKED": payload { .playerKicked($0) },
    "GAME_STARTED": payload { .gameStarted($0) },
    "PRELOAD_SONG": payload { .preloadSong($0) },
    "ROUND_STARTED": payload { .roundStarted($0) },
    "COUNT_DOWN": payload { .countDown($0) },
    "WRONG_ANSWER": payload { .wrongAnswer($0) },
    "ROUND_RESULT": payload { .roundResult($0) },
    "GAME_OVER": payload { .gameOver($0) }
]

private let clientDecoders: [String: PayloadDecoder<ClientMessage>] = [
    "MATCH_REQUEST": payload { .matchRequest($0) },
    "MATCH_CANCEL": payload { (body: WireV1.RequestPayload) in .matchCancel(requestID: body.requestID) },
    "LEAVE_ROOM": payload { (body: WireV1.RoomPayload) in .leaveRoom(roomID: body.roomID) },
    "START_GAME": payload { (body: WireV1.RoomPayload) in .startGame(roomID: body.roomID) },
    "READY_TO_PLAY": payload { (body: WireV1.ReadyToPlayPayload) in
        .readyToPlay(roomID: body.roomID, roundNumber: body.roundNumber)
    },
    "SUBMIT_ANSWER": payload { (body: WireV1.SubmitAnswerPayload) in
        .submitAnswer(roomID: body.roomID, answer: body.answer)
    },
    "KICK_PLAYER": payload { (body: WireV1.KickPlayerPayload) in
        .kickPlayer(roomID: body.roomID, targetPlayerID: body.targetPlayerID)
    }
]

private struct ServerEnvelope: Decodable {
    let message: ServerMessage

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: EnvelopeKey.self)
        let type = try container.decode(String.self, forKey: .type)
        // S→C timestamp는 필수 int64다.
        _ = try container.decode(Int64.self, forKey: .timestamp)
        guard let decodePayload = serverDecoders[type] else { throw MessageCodecError.unknownType(type) }
        message = try decodePayload(container)
    }
}

private struct ClientEnvelope: Decodable {
    let message: ClientMessage

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: EnvelopeKey.self)
        let type = try container.decode(String.self, forKey: .type)
        // C→S timestamp는 선택이지만, 있으면 null이 아닌 int64여야 한다.
        if container.contains(.timestamp) {
            _ = try container.decode(Int64.self, forKey: .timestamp)
        }
        guard let decodePayload = clientDecoders[type] else { throw MessageCodecError.unknownType(type) }
        message = try decodePayload(container)
    }
}

private struct OutgoingEnvelope<Payload: Encodable>: Encodable {
    let type: String
    let payload: Payload
}
