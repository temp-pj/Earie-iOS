import Foundation

/// App이 거르기를 통과한 방·게임 메시지를 Room에 전달할 때 쓰는 이벤트.
/// ROOM_LEFT와 PLAYER_KICKED는 App이 직접 처리하므로 없다.
/// 승자가 빈 문자열이면 `RoundResult.winnerId`는 nil이다.
public enum RoomServerEvent: Equatable, Sendable {
    case playerJoined(playerID: String)
    case playerLeft(playerID: String)
    case hostChanged(playerID: String)
    case gameStarted
    case preloadSong(isrc: String, startTime: Int, roundNumber: Int)
    case game(GameEvent)
    case gameOver(GameResult)
    case gameAborted(AbortReason)
    case commandFailed(RoomFailureCode)
}
