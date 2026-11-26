import Foundation

/// 클라이언트 → 서버 메시지 (protocol.md v1).
/// ID는 어떤 대소문자로 넣어도 `MessageCodec.encodeClient`가 소문자로 보낸다.
public enum ClientMessage: Equatable, Sendable {
    case matchRequest(WireV1.MatchRequestPayload)
    case matchCancel(requestID: String)
    case leaveRoom(roomID: String)
    case startGame(roomID: String)
    case readyToPlay(roomID: String, roundNumber: Int)
    case submitAnswer(roomID: String, answer: String)
    case kickPlayer(roomID: String, targetPlayerID: String)

    /// wire의 `type` 값
    public var type: String {
        switch self {
        case .matchRequest: "MATCH_REQUEST"
        case .matchCancel: "MATCH_CANCEL"
        case .leaveRoom: "LEAVE_ROOM"
        case .startGame: "START_GAME"
        case .readyToPlay: "READY_TO_PLAY"
        case .submitAnswer: "SUBMIT_ANSWER"
        case .kickPlayer: "KICK_PLAYER"
        }
    }
}
