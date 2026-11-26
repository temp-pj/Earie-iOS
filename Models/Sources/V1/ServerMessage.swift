import Foundation

/// 서버 → 클라이언트 메시지 (protocol.md v1의 S→C type 전체).
/// `MessageCodec.decodeServer`를 통과한 값만 만들어지므로 ID 형식과 enum 값은 계약을 만족한다.
public enum ServerMessage: Equatable, Sendable {
    case matchWaiting(WireV1.RequestPayload)
    case matchCancelled(WireV1.RequestPayload)
    case matchFailed(WireV1.MatchFailedPayload)
    case welcome(WireV1.WelcomePayload)
    case roomLeft(WireV1.RoomPayload)
    case roomCommandFailed(WireV1.RoomCommandFailedPayload)
    case gameAborted(WireV1.GameAbortedPayload)
    case playerJoined(WireV1.PlayerPayload)
    case playerLeft(WireV1.PlayerPayload)
    case hostChanged(WireV1.PlayerPayload)
    case playerKicked(WireV1.RoomPayload)
    case gameStarted(WireV1.RoomPayload)
    case preloadSong(WireV1.PreloadSongPayload)
    case roundStarted(WireV1.RoundStartedPayload)
    case countDown(WireV1.CountDownPayload)
    case wrongAnswer(WireV1.WrongAnswerPayload)
    case roundResult(WireV1.RoundResultPayload)
    case gameOver(WireV1.GameOverPayload)

    /// wire의 `type` 값
    public var type: String {
        switch self {
        case .matchWaiting: "MATCH_WAITING"
        case .matchCancelled: "MATCH_CANCELLED"
        case .matchFailed: "MATCH_FAILED"
        case .welcome: "WELCOME"
        case .roomLeft: "ROOM_LEFT"
        case .roomCommandFailed: "ROOM_COMMAND_FAILED"
        case .gameAborted: "GAME_ABORTED"
        case .playerJoined: "PLAYER_JOINED"
        case .playerLeft: "PLAYER_LEFT"
        case .hostChanged: "HOST_CHANGED"
        case .playerKicked: "PLAYER_KICKED"
        case .gameStarted: "GAME_STARTED"
        case .preloadSong: "PRELOAD_SONG"
        case .roundStarted: "ROUND_STARTED"
        case .countDown: "COUNT_DOWN"
        case .wrongAnswer: "WRONG_ANSWER"
        case .roundResult: "ROUND_RESULT"
        case .gameOver: "GAME_OVER"
        }
    }
}
