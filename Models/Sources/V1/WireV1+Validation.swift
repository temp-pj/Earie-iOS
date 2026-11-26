import Foundation

/// 디코딩 직후와 인코딩 직전에 payload가 protocol.md v1 계약을 만족하는지 검사한다.
/// 위반하면 `MessageCodecError.invalidField`를 던진다.
protocol WireValidatable {
    func validate() throws
}

private func requireID(_ value: String, _ field: String) throws {
    try require(WireRules.isCanonicalID(value), field)
}

private func require(_ condition: Bool, _ field: String) throws {
    guard condition else { throw MessageCodecError.invalidField(field) }
}

/// 승자가 없으면 빈 문자열이다.
private func requireWinner(_ winner: String) throws {
    try require(winner.isEmpty || WireRules.isCanonicalID(winner), "winner")
}

private func requireScores(_ scores: [String: Int]) throws {
    try require(scores.keys.allSatisfy(WireRules.isCanonicalID), "scores")
}

// MARK: - 매칭

extension WireV1.MatchRequestPayload: WireValidatable {
    /// 카테고리 값과 catalogVersion은 검사하지 않는다. 서버가 MATCH_FAILED(INVALID_CRITERIA)로 답할 대상이다.
    func validate() throws {
        try requireID(requestID, "requestID")
    }
}

extension WireV1.RequestPayload: WireValidatable {
    func validate() throws {
        try requireID(requestID, "requestID")
    }
}

extension WireV1.MatchFailedPayload: WireValidatable {
    func validate() throws {
        try requireID(requestID, "requestID")
    }
}

extension WireV1.WelcomePayload: WireValidatable {
    func validate() throws {
        try requireID(requestID, "requestID")
        try requireID(roomID, "roomID")
        try requireID(playerID, "playerID")
        try requireID(hostID, "hostID")
        try require(!players.isEmpty, "players")
        try require(players.allSatisfy(WireRules.isCanonicalID), "players")
        try require(Set(players).count == players.count, "players")
        try require(players.contains(playerID), "players")
        try require(players.contains(hostID), "hostID")
        try require(roomState == "waiting", "roomState")
        try require(maxPlayers == 8, "maxPlayers")
        try require(WireRules.isResolvedCategory(category), "category")
        try require(WireRules.isCatalogVersion(catalogVersion), "catalogVersion")
    }
}

// MARK: - 방

extension WireV1.RoomPayload: WireValidatable {
    func validate() throws {
        try requireID(roomID, "roomID")
    }
}

extension WireV1.RoomCommandFailedPayload: WireValidatable {
    func validate() throws {
        try requireID(roomID, "roomID")
        try require(command == "START_GAME", "command")
    }
}

extension WireV1.GameAbortedPayload: WireValidatable {
    func validate() throws {
        try requireID(roomID, "roomID")
    }
}

extension WireV1.PlayerPayload: WireValidatable {
    func validate() throws {
        try requireID(roomID, "roomID")
        try requireID(playerID, "playerID")
    }
}

extension WireV1.KickPlayerPayload: WireValidatable {
    func validate() throws {
        try requireID(roomID, "roomID")
        try requireID(targetPlayerID, "targetPlayerID")
    }
}

// MARK: - 게임

extension WireV1.PreloadSongPayload: WireValidatable {
    func validate() throws {
        try requireID(roomID, "roomID")
    }
}

extension WireV1.RoundStartedPayload: WireValidatable {
    func validate() throws {
        try requireID(roomID, "roomID")
    }
}

extension WireV1.CountDownPayload: WireValidatable {
    func validate() throws {
        try requireID(roomID, "roomID")
    }
}

extension WireV1.WrongAnswerPayload: WireValidatable {
    func validate() throws {
        try requireID(roomID, "roomID")
        try requireID(playerID, "playerID")
    }
}

extension WireV1.RoundResultPayload: WireValidatable {
    func validate() throws {
        try requireID(roomID, "roomID")
        try requireWinner(winner)
        try requireScores(scores)
    }
}

extension WireV1.GameOverPayload: WireValidatable {
    func validate() throws {
        try requireID(roomID, "roomID")
        try requireWinner(winner)
        try requireScores(scores)
    }
}

extension WireV1.ReadyToPlayPayload: WireValidatable {
    func validate() throws {
        try requireID(roomID, "roomID")
        try require(roundNumber >= 1, "roundNumber")
    }
}

extension WireV1.SubmitAnswerPayload: WireValidatable {
    func validate() throws {
        try requireID(roomID, "roomID")
    }
}
