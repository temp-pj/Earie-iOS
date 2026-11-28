import Foundation
import Models

extension ServerMessage {
    /// 방·게임 메시지의 roomID와 Room에 넘길 이벤트. 매칭 메시지와 App이 직접 처리하는 ROOM_LEFT, PLAYER_KICKED는 nil.
    var roomEvent: (roomID: String, event: RoomServerEvent)? {
        switch self {
        case let .playerJoined(payload):
            (payload.roomID, .playerJoined(playerID: payload.playerID))
        case let .playerLeft(payload):
            (payload.roomID, .playerLeft(playerID: payload.playerID))
        case let .hostChanged(payload):
            (payload.roomID, .hostChanged(playerID: payload.playerID))
        case let .gameStarted(payload):
            (payload.roomID, .gameStarted)
        case let .preloadSong(payload):
            (payload.roomID, .preloadSong(isrc: payload.isrc, startTime: payload.startTime, roundNumber: payload.roundNumber))
        case let .roundStarted(payload):
            (payload.roomID, .game(.roundStarted(RoundData(
                roundNumber: payload.roundNumber,
                totalRounds: payload.totalRounds,
                letterCards: payload.letterCards,
                answerLength: payload.answerLength
            ))))
        case let .countDown(payload):
            (payload.roomID, .game(.countDown(payload.remaining)))
        case let .wrongAnswer(payload):
            (payload.roomID, .game(.wrongAnswer(playerID: payload.playerID, wrongAnswer: payload.wrongAnswer)))
        case let .roundResult(payload):
            // design 6: 승자가 빈 문자열이면 winnerId는 nil
            (payload.roomID, .game(.roundEnded(RoundResult(
                winnerId: payload.winner.isEmpty ? nil : payload.winner,
                correctAnswer: payload.correctAnswer,
                scores: payload.scores
            ))))
        case let .gameOver(payload):
            (payload.roomID, .gameOver(GameResult(winner: payload.winner, scores: payload.scores)))
        case let .gameAborted(payload):
            (payload.roomID, .gameAborted(payload.reason))
        case let .roomCommandFailed(payload):
            (payload.roomID, .commandFailed(payload.code))
        case .matchWaiting, .matchCancelled, .matchFailed, .welcome, .roomLeft, .playerKicked:
            nil
        }
    }
}
