import Foundation

/// protocol.md v1 payload DTO.
/// 구 DTO(`WelcomePayload`, `PreloadSongPayload` 등)와 이름이 겹쳐 네임스페이스에 둔다 (design 6).
/// 필드 이름이 곧 JSON 키다. ID는 모두 소문자 canonical UUID 문자열이다.
public enum WireV1 {}

// MARK: - 매칭

public extension WireV1 {
    /// MATCH_REQUEST (C→S)
    struct MatchRequestPayload: Codable, Equatable, Sendable {
        public let requestID: String
        public let catalogVersion: String
        public let category: MatchCategory

        public init(requestID: String, catalogVersion: String, category: MatchCategory) {
            self.requestID = requestID
            self.catalogVersion = catalogVersion
            self.category = category
        }
    }

    /// MATCH_CANCEL (C→S), MATCH_WAITING / MATCH_CANCELLED (S→C)
    struct RequestPayload: Codable, Equatable, Sendable {
        public let requestID: String

        public init(requestID: String) {
            self.requestID = requestID
        }
    }

    /// MATCH_FAILED (S→C)
    struct MatchFailedPayload: Codable, Equatable, Sendable {
        public let requestID: String
        public let code: MatchFailureCode

        public init(requestID: String, code: MatchFailureCode) {
            self.requestID = requestID
            self.code = code
        }
    }

    /// WELCOME (S→C)
    struct WelcomePayload: Codable, Equatable, Sendable {
        public let requestID: String
        public let roomID: String
        public let playerID: String
        public let hostID: String
        /// 서버 접수 순서. 자기 자신과 방장을 포함한다.
        public let players: [String]
        /// 항상 "waiting"
        public let roomState: String
        /// 항상 8
        public let maxPlayers: Int
        /// 확정된 방 조건. any가 없다.
        public let category: MatchCategory
        public let catalogVersion: String

        public init(
            requestID: String,
            roomID: String,
            playerID: String,
            hostID: String,
            players: [String],
            roomState: String,
            maxPlayers: Int,
            category: MatchCategory,
            catalogVersion: String
        ) {
            self.requestID = requestID
            self.roomID = roomID
            self.playerID = playerID
            self.hostID = hostID
            self.players = players
            self.roomState = roomState
            self.maxPlayers = maxPlayers
            self.category = category
            self.catalogVersion = catalogVersion
        }
    }
}

// MARK: - 방

public extension WireV1 {
    /// LEAVE_ROOM / START_GAME (C→S), ROOM_LEFT / PLAYER_KICKED / GAME_STARTED (S→C)
    struct RoomPayload: Codable, Equatable, Sendable {
        public let roomID: String

        public init(roomID: String) {
            self.roomID = roomID
        }
    }

    /// ROOM_COMMAND_FAILED (S→C)
    struct RoomCommandFailedPayload: Codable, Equatable, Sendable {
        public let roomID: String
        /// 항상 "START_GAME"
        public let command: String
        public let code: RoomFailureCode

        public init(roomID: String, command: String, code: RoomFailureCode) {
            self.roomID = roomID
            self.command = command
            self.code = code
        }
    }

    /// GAME_ABORTED (S→C)
    struct GameAbortedPayload: Codable, Equatable, Sendable {
        public let roomID: String
        public let reason: AbortReason

        public init(roomID: String, reason: AbortReason) {
            self.roomID = roomID
            self.reason = reason
        }
    }

    /// PLAYER_JOINED / PLAYER_LEFT / HOST_CHANGED (S→C)
    struct PlayerPayload: Codable, Equatable, Sendable {
        public let roomID: String
        public let playerID: String

        public init(roomID: String, playerID: String) {
            self.roomID = roomID
            self.playerID = playerID
        }
    }

    /// KICK_PLAYER (C→S)
    struct KickPlayerPayload: Codable, Equatable, Sendable {
        public let roomID: String
        public let targetPlayerID: String

        public init(roomID: String, targetPlayerID: String) {
            self.roomID = roomID
            self.targetPlayerID = targetPlayerID
        }
    }
}

// MARK: - 게임

public extension WireV1 {
    /// PRELOAD_SONG (S→C)
    struct PreloadSongPayload: Codable, Equatable, Sendable {
        public let roomID: String
        public let isrc: String
        public let startTime: Int
        public let roundNumber: Int

        public init(roomID: String, isrc: String, startTime: Int, roundNumber: Int) {
            self.roomID = roomID
            self.isrc = isrc
            self.startTime = startTime
            self.roundNumber = roundNumber
        }
    }

    /// ROUND_STARTED (S→C)
    struct RoundStartedPayload: Codable, Equatable, Sendable {
        public let roomID: String
        public let roundNumber: Int
        public let totalRounds: Int
        public let answerLength: Int
        public let letterCards: [String]

        public init(roomID: String, roundNumber: Int, totalRounds: Int, answerLength: Int, letterCards: [String]) {
            self.roomID = roomID
            self.roundNumber = roundNumber
            self.totalRounds = totalRounds
            self.answerLength = answerLength
            self.letterCards = letterCards
        }
    }

    /// COUNT_DOWN (S→C)
    struct CountDownPayload: Codable, Equatable, Sendable {
        public let roomID: String
        public let remaining: Int

        public init(roomID: String, remaining: Int) {
            self.roomID = roomID
            self.remaining = remaining
        }
    }

    /// WRONG_ANSWER (S→C)
    struct WrongAnswerPayload: Codable, Equatable, Sendable {
        public let roomID: String
        public let playerID: String
        public let wrongAnswer: String

        public init(roomID: String, playerID: String, wrongAnswer: String) {
            self.roomID = roomID
            self.playerID = playerID
            self.wrongAnswer = wrongAnswer
        }
    }

    /// ROUND_RESULT (S→C)
    struct RoundResultPayload: Codable, Equatable, Sendable {
        public let roomID: String
        /// 승자 playerID. 승자가 없으면 빈 문자열.
        public let winner: String
        public let correctAnswer: String
        /// playerID → 점수
        public let scores: [String: Int]

        public init(roomID: String, winner: String, correctAnswer: String, scores: [String: Int]) {
            self.roomID = roomID
            self.winner = winner
            self.correctAnswer = correctAnswer
            self.scores = scores
        }
    }

    /// GAME_OVER (S→C)
    struct GameOverPayload: Codable, Equatable, Sendable {
        public let roomID: String
        /// 승자 playerID. 승자가 없으면 빈 문자열.
        public let winner: String
        /// playerID → 점수
        public let scores: [String: Int]

        public init(roomID: String, winner: String, scores: [String: Int]) {
            self.roomID = roomID
            self.winner = winner
            self.scores = scores
        }
    }

    /// READY_TO_PLAY (C→S)
    struct ReadyToPlayPayload: Codable, Equatable, Sendable {
        public let roomID: String
        /// 1 이상
        public let roundNumber: Int

        public init(roomID: String, roundNumber: Int) {
            self.roomID = roomID
            self.roundNumber = roundNumber
        }
    }

    /// SUBMIT_ANSWER (C→S)
    struct SubmitAnswerPayload: Codable, Equatable, Sendable {
        public let roomID: String
        public let answer: String

        public init(roomID: String, answer: String) {
            self.roomID = roomID
            self.answer = answer
        }
    }
}
