import ClientSession
import Foundation
import Models
import XCTest

/// T7: 로컬 v1 서버(test-v1 fixture)에 `SessionClient.live(host:)`로 실제 연결 여러 개를 붙여
/// 전송 계층, 코덱, 서버 계약을 검증한다 (tasks.md 9번, requirements DONE-13).
///
/// 서버는 `bundle exec fastlane integration`이 띄운다. App의 거르기와 화면 전환은 T6 TestStore 테스트 범위다.
/// 각 테스트는 끝날 때 자기 연결의 방과 대기 요청을 정리하고 연결을 닫는다 (`IntegrationPlayer.cleanUp`).
final class SessionIntegrationTests: XCTestCase {
    /// 서버가 읽는 `catalog.json`과 같은 버전·요청 조합을 담은 fixture projection.
    private var catalog: CatalogProjection {
        get throws { try Self.loadCatalog() }
    }

    // MARK: - 1. 같은 조합 매칭

    func test_1_같은_조합의_두_연결은_같은_방으로_매칭되고_players_순서가_같다() async throws {
        let playerA = try await player("A")
        let playerB = try await player("B")

        let requestA = try await playerA.requestMatch(try anyCategory(), catalogVersion: catalog.version)
        let requestB = try await playerB.requestMatch(try anyCategory(), catalogVersion: catalog.version)

        let welcomeA = try await expectWelcome(playerA, requestID: requestA)
        let welcomeB = try await expectWelcome(playerB, requestID: requestB)

        XCTAssertEqual(welcomeA.roomID, welcomeB.roomID)
        XCTAssertEqual(welcomeA.players, welcomeB.players, "양쪽 players 순서가 같아야 한다")
        XCTAssertEqual(welcomeA.hostID, welcomeB.hostID)
        XCTAssertEqual(welcomeA.players.count, 2)
        XCTAssertNotEqual(welcomeA.playerID, welcomeB.playerID)
        XCTAssertEqual(Set(welcomeA.players), [welcomeA.playerID, welcomeB.playerID])
        XCTAssertTrue(welcomeA.players.contains(welcomeA.hostID))
        let version = try catalog.version
        for welcome in [welcomeA, welcomeB] {
            XCTAssertEqual(welcome.roomState, "waiting")
            XCTAssertEqual(welcome.maxPlayers, 8)
            XCTAssertEqual(welcome.catalogVersion, version)
            // any + any는 모든 축이 all로 확정된다 (protocol.md "Category 공통 타입").
            XCTAssertEqual(welcome.category, MatchCategory(decade: "all", artistType: "all", gender: "all", genre: "all"))
        }
    }

    // MARK: - 2. 조건 불일치

    func test_2_조건이_맞지_않는_두_연결은_둘_다_대기하고_배정되지_않는다() async throws {
        let playerA = try await player("A")
        let playerB = try await player("B")
        let ballad = try allowedCategory(decade: "2010s", artistType: "solo", gender: "female", genre: "korean_ballad")
        let pop = try allowedCategory(decade: "2020s", artistType: "group", gender: "male", genre: "synthetic_pop")

        let requestA = try await playerA.requestMatch(ballad, catalogVersion: catalog.version)
        try await expectWaiting(playerA, requestID: requestA)
        let requestB = try await playerB.requestMatch(pop, catalogVersion: catalog.version)
        try await expectWaiting(playerB, requestID: requestB)

        // 배정은 요청 접수 즉시 일어나므로, 2초 동안 아무 메시지도 없으면 배정되지 않은 것으로 본다.
        let lateA = try await playerA.messageIfAny(within: .seconds(2))
        XCTAssertNil(lateA, "A는 배정되면 안 된다")
        let lateB = try await playerB.messageIfAny(within: .milliseconds(200))
        XCTAssertNil(lateB, "B는 배정되면 안 된다")

        // 둘 다 아직 대기 중이었는지 취소 응답으로 확인한다. 그 사이에 WELCOME이 끼면 실패한다.
        try await playerA.send(.matchCancel(requestID: requestA))
        try await expectCancelled(playerA, requestID: requestA)
        try await playerB.send(.matchCancel(requestID: requestB))
        try await expectCancelled(playerB, requestID: requestB)
    }

    // MARK: - 3. 대기 중 취소 후 같은 연결 재매칭

    func test_3_대기_중_취소하면_MATCH_CANCELLED이고_같은_연결로_새_요청이_매칭된다() async throws {
        let playerA = try await player("A")
        let playerB = try await player("B")

        let firstRequest = try await playerA.requestMatch(try anyCategory(), catalogVersion: catalog.version)
        try await expectWaiting(playerA, requestID: firstRequest)
        try await playerA.send(.matchCancel(requestID: firstRequest))
        try await expectCancelled(playerA, requestID: firstRequest)

        let secondRequest = try await playerA.requestMatch(try anyCategory(), catalogVersion: catalog.version)
        XCTAssertNotEqual(firstRequest, secondRequest)
        try await expectWaiting(playerA, requestID: secondRequest)
        let requestB = try await playerB.requestMatch(try anyCategory(), catalogVersion: catalog.version)

        let welcomeA = try await expectWelcome(playerA, requestID: secondRequest)
        let welcomeB = try await expectWelcome(playerB, requestID: requestB)
        XCTAssertEqual(welcomeA.roomID, welcomeB.roomID)
        XCTAssertEqual(welcomeA.players, welcomeB.players)
    }

    // MARK: - 4. 시작 후 곡 준비 없음 → GAME_ABORTED

    func test_4_방장이_시작하면_GAME_STARTED와_PRELOAD_SONG이_오고_준비하지_않으면_약_30초_뒤_GAME_ABORTED() async throws {
        let pair = try await matchedPair()
        let roomID = pair.roomID

        try await pair.host.send(.startGame(roomID: roomID))

        var preloadReceived: [String: ContinuousClock.Instant] = [:]
        for member in pair.members {
            let started = try await expect(member, "GAME_STARTED") { message -> String? in
                if case let .gameStarted(payload) = message { return payload.roomID }
                return nil
            }
            XCTAssertEqual(started, roomID)

            let preload = try await expect(member, "PRELOAD_SONG") { message -> WireV1.PreloadSongPayload? in
                if case let .preloadSong(payload) = message { return payload }
                return nil
            }
            preloadReceived[member.name] = .now
            XCTAssertEqual(preload.roomID, roomID)
            XCTAssertEqual(preload.roundNumber, 1)
            XCTAssertFalse(preload.isrc.isEmpty)
        }

        // READY_TO_PLAY를 보내지 않는다. 서버의 곡 준비 제한(30초)이 지나면 방 전체가 중단된다.
        for member in pair.members {
            let aborted = try await expect(member, "GAME_ABORTED", timeout: .seconds(45)) { message -> WireV1.GameAbortedPayload? in
                if case let .gameAborted(payload) = message { return payload }
                return nil
            }
            XCTAssertEqual(aborted.roomID, roomID)
            XCTAssertEqual(aborted.reason, .internalError)

            let preloadAt = try XCTUnwrap(preloadReceived[member.name])
            let elapsed = preloadAt.duration(to: .now)
            XCTAssertGreaterThanOrEqual(elapsed, .seconds(25), "\(member.name): PRELOAD_SONG 후 \(elapsed)만에 중단됨")
            XCTAssertLessThanOrEqual(elapsed, .seconds(40), "\(member.name): PRELOAD_SONG 후 \(elapsed)만에 중단됨")
        }
    }

    // MARK: - 5. 1명 남은 방에서 시작

    func test_5_한_명만_남은_방에서_시작하면_NOT_ENOUGH_PLAYERS() async throws {
        let pair = try await matchedPair()
        let roomID = pair.roomID

        try await pair.guest.send(.leaveRoom(roomID: roomID))
        try await expectRoomLeft(pair.guest, roomID: roomID)
        let left = try await expect(pair.host, "PLAYER_LEFT") { message -> WireV1.PlayerPayload? in
            if case let .playerLeft(payload) = message { return payload }
            return nil
        }
        XCTAssertEqual(left.roomID, roomID)
        XCTAssertEqual(left.playerID, pair.guestID)

        try await pair.host.send(.startGame(roomID: roomID))
        let failed = try await expect(pair.host, "ROOM_COMMAND_FAILED") { message -> WireV1.RoomCommandFailedPayload? in
            if case let .roomCommandFailed(payload) = message { return payload }
            return nil
        }
        XCTAssertEqual(failed.roomID, roomID)
        XCTAssertEqual(failed.command, "START_GAME")
        XCTAssertEqual(failed.code, .notEnoughPlayers)
    }

    // MARK: - 6. 방 나가기 후 같은 연결 재매칭

    func test_6_LEAVE_ROOM하면_ROOM_LEFT이고_같은_연결로_다시_매칭된다() async throws {
        let pair = try await matchedPair()
        let oldRoomID = pair.roomID

        try await pair.host.send(.leaveRoom(roomID: oldRoomID))
        try await expectRoomLeft(pair.host, roomID: oldRoomID)
        // 남은 사람도 나가서 이전 방이 닫히게 한다. 재매칭이 이전 방 빈자리에 들어가는 경우를 섞지 않기 위해서다.
        let left = try await expect(pair.guest, "PLAYER_LEFT") { message -> WireV1.PlayerPayload? in
            if case let .playerLeft(payload) = message { return payload }
            return nil
        }
        XCTAssertEqual(left, WireV1.PlayerPayload(roomID: oldRoomID, playerID: pair.hostID))
        // 방장이 나갔으므로 남은 참가자가 방장이 된다.
        let hostChanged = try await expect(pair.guest, "HOST_CHANGED") { message -> WireV1.PlayerPayload? in
            if case let .hostChanged(payload) = message { return payload }
            return nil
        }
        XCTAssertEqual(hostChanged, WireV1.PlayerPayload(roomID: oldRoomID, playerID: pair.guestID))
        try await pair.guest.send(.leaveRoom(roomID: oldRoomID))
        try await expectRoomLeft(pair.guest, roomID: oldRoomID)

        let rematchHost = try await pair.host.requestMatch(try anyCategory(), catalogVersion: catalog.version)
        try await expectWaiting(pair.host, requestID: rematchHost)
        let rematchGuest = try await pair.guest.requestMatch(try anyCategory(), catalogVersion: catalog.version)

        let welcomeHost = try await expectWelcome(pair.host, requestID: rematchHost)
        let welcomeGuest = try await expectWelcome(pair.guest, requestID: rematchGuest)
        XCTAssertEqual(welcomeHost.roomID, welcomeGuest.roomID)
        XCTAssertNotEqual(welcomeHost.roomID, oldRoomID)
        XCTAssertEqual(welcomeHost.players, welcomeGuest.players)
    }

    // MARK: - 7. 잘못된 카탈로그 버전

    func test_7_다른_카탈로그_버전으로_요청하면_INVALID_CRITERIA이고_연결은_유지된다() async throws {
        let playerA = try await player("A")
        let staleVersion = "\(try catalog.version)-outdated"

        let requestID = try await playerA.requestMatch(try anyCategory(), catalogVersion: staleVersion)
        let failed = try await expect(playerA, "MATCH_FAILED") { message -> WireV1.MatchFailedPayload? in
            if case let .matchFailed(payload) = message { return payload }
            return nil
        }
        XCTAssertEqual(failed.requestID, requestID)
        XCTAssertEqual(failed.code, .invalidCriteria)

        // 1008 종료가 아니라 요청 거절이다. 같은 연결로 올바른 요청을 접수받는다.
        let validRequest = try await playerA.requestMatch(try anyCategory(), catalogVersion: catalog.version)
        try await expectWaiting(playerA, requestID: validRequest)
    }
}

// MARK: - 도우미

private extension SessionIntegrationTests {
    struct MatchedPair {
        let host: IntegrationPlayer
        let guest: IntegrationPlayer
        let roomID: String
        let hostID: String
        let guestID: String

        var members: [IntegrationPlayer] { [host, guest] }
    }

    /// 실제 연결을 열고, 테스트가 끝나면 서버 쪽 상태를 정리하고 닫도록 등록한다.
    func player(_ name: String) async throws -> IntegrationPlayer {
        let player = try await IntegrationPlayer.connect(name)
        addTeardownBlock { await player.cleanUp() }
        return player
    }

    /// 전부 any 조합으로 두 연결을 매칭하고 방장과 다른 참가자를 나눈다.
    func matchedPair() async throws -> MatchedPair {
        let playerA = try await player("A")
        let playerB = try await player("B")
        let requestA = try await playerA.requestMatch(try anyCategory(), catalogVersion: catalog.version)
        let requestB = try await playerB.requestMatch(try anyCategory(), catalogVersion: catalog.version)
        let welcomeA = try await expectWelcome(playerA, requestID: requestA)
        let welcomeB = try await expectWelcome(playerB, requestID: requestB)
        XCTAssertEqual(welcomeA.roomID, welcomeB.roomID)
        XCTAssertEqual(welcomeA.hostID, welcomeB.hostID)

        let aIsHost = welcomeA.hostID == welcomeA.playerID
        XCTAssertTrue(aIsHost || welcomeB.hostID == welcomeB.playerID, "방장이 두 참가자 중에 없다")
        return MatchedPair(
            host: aIsHost ? playerA : playerB,
            guest: aIsHost ? playerB : playerA,
            roomID: welcomeA.roomID,
            hostID: aIsHost ? welcomeA.playerID : welcomeB.playerID,
            guestID: aIsHost ? welcomeB.playerID : welcomeA.playerID
        )
    }

    /// 다음 메시지가 기대한 종류가 아니면 실패한다.
    func expect<Value>(
        _ player: IntegrationPlayer,
        _ expected: String,
        timeout: Duration = .seconds(10),
        file: StaticString = #filePath,
        line: UInt = #line,
        _ extract: (ServerMessage) -> Value?
    ) async throws -> Value {
        let message = try await player.nextMessage(timeout: timeout, expected)
        guard let value = extract(message) else {
            XCTFail("\(player.name): \(expected)를 기대했지만 \(message.type) 수신: \(message)", file: file, line: line)
            throw UnexpectedMessage()
        }
        return value
    }

    func expectWaiting(_ player: IntegrationPlayer, requestID: String, file: StaticString = #filePath, line: UInt = #line) async throws {
        let waiting = try await expect(player, "MATCH_WAITING", file: file, line: line) { message -> String? in
            if case let .matchWaiting(payload) = message { return payload.requestID }
            return nil
        }
        XCTAssertEqual(waiting, requestID, file: file, line: line)
    }

    func expectCancelled(_ player: IntegrationPlayer, requestID: String, file: StaticString = #filePath, line: UInt = #line) async throws {
        let cancelled = try await expect(player, "MATCH_CANCELLED", file: file, line: line) { message -> String? in
            if case let .matchCancelled(payload) = message { return payload.requestID }
            return nil
        }
        XCTAssertEqual(cancelled, requestID, file: file, line: line)
    }

    func expectRoomLeft(_ player: IntegrationPlayer, roomID: String, file: StaticString = #filePath, line: UInt = #line) async throws {
        let left = try await expect(player, "ROOM_LEFT", file: file, line: line) { message -> String? in
            if case let .roomLeft(payload) = message { return payload.roomID }
            return nil
        }
        XCTAssertEqual(left, roomID, file: file, line: line)
    }

    /// WELCOME을 기다린다. 그 앞에는 같은 요청의 MATCH_WAITING만 올 수 있다 (protocol.md "대기→배정", "즉시 배정").
    func expectWelcome(
        _ player: IntegrationPlayer,
        requestID: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async throws -> WireV1.WelcomePayload {
        while true {
            let message = try await player.nextMessage(timeout: .seconds(10), "WELCOME")
            switch message {
            case let .matchWaiting(payload) where payload.requestID == requestID:
                continue
            case let .welcome(payload):
                XCTAssertEqual(payload.requestID, requestID, "\(player.name): 다른 요청의 WELCOME", file: file, line: line)
                XCTAssertTrue(payload.players.contains(payload.playerID), file: file, line: line)
                return payload
            default:
                XCTFail("\(player.name): WELCOME을 기대했지만 \(message.type) 수신: \(message)", file: file, line: line)
                throw UnexpectedMessage()
            }
        }
    }

    func anyCategory() throws -> MatchCategory {
        try allowedCategory(decade: "any", artistType: "any", gender: "any", genre: "any")
    }

    /// 앱이 보낼 수 있는 조합만 쓴다. fixture 카탈로그의 allowedRequests에 없으면 테스트 전제가 깨진 것이다.
    func allowedCategory(decade: String, artistType: String, gender: String, genre: String) throws -> MatchCategory {
        let category = MatchCategory(decade: decade, artistType: artistType, gender: gender, genre: genre)
        guard try catalog.allowedRequests.contains(category) else {
            XCTFail("fixture allowedRequests에 \(category)가 없다")
            throw UnexpectedMessage()
        }
        return category
    }

    static func loadCatalog() throws -> CatalogProjection {
        let url = try XCTUnwrap(
            Bundle(for: SessionIntegrationTests.self).url(forResource: "catalog-projection", withExtension: "json"),
            "catalog-projection.json이 SessionIntegrationTests 리소스에 없다"
        )
        return try JSONDecoder().decode(CatalogProjection.self, from: Data(contentsOf: url))
    }
}

private struct UnexpectedMessage: Error {}
