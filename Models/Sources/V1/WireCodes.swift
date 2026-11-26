import Foundation

/// MATCH_FAILED.code
public enum MatchFailureCode: String, Codable, Equatable, Sendable {
    case invalidCriteria = "INVALID_CRITERIA"
    case internalError = "INTERNAL_ERROR"
    case alreadyMatching = "ALREADY_MATCHING"
    case alreadyInRoom = "ALREADY_IN_ROOM"
}

/// ROOM_COMMAND_FAILED.code
public enum RoomFailureCode: String, Codable, Equatable, Sendable {
    case notHost = "NOT_HOST"
    case notEnoughPlayers = "NOT_ENOUGH_PLAYERS"
    case invalidState = "INVALID_STATE"
    case internalError = "INTERNAL_ERROR"
}

/// GAME_ABORTED.reason
public enum AbortReason: String, Codable, Equatable, Sendable {
    case insufficientPlayers = "INSUFFICIENT_PLAYERS"
    case internalError = "INTERNAL_ERROR"
}
