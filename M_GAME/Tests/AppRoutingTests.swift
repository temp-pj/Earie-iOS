@testable import M_GAME

import ClientSessionTest
import ComposableArchitecture
import FeatureLobby
import FeatureRoom
import Foundation
import Models
import XCTest

/// 메시지 거르기와 라우팅 (REQ-FILTER-01~03, REQ-CANCEL-02, REQ-FAIL-01, REQ-MATCH-06·07, DONE-07·08·12)
@MainActor
final class AppRoutingTests: XCTestCase {
    // MARK: - 매칭 메시지

    func test_활성_요청의_WELCOME으로_방에_들어간다() async throws {
        // REQ-MATCH-07
        let harness = try AppHarness()
        await harness.enterRoom()
        XCTAssertEqual(harness.store.state.phase.room?.roomID, TestID.room1)
        XCTAssertEqual(harness.store.state.phase.room?.categoryLabel, AppFixtures.roomCategoryLabel)
        await harness.finish()
    }

    func test_활성_요청의_MATCH_WAITING과_MATCH_CANCELLED는_화면을_바꾸지_않는다() async throws {
        // REQ-MATCH-06
        let harness = try AppHarness()
        await harness.matchAndConnect()
        let request = WireV1.RequestPayload(requestID: TestID.request(0))
        await harness.receive(.matchWaiting(request))
        await harness.receive(.matchCancelled(request))
        await harness.finish()
    }

    func test_취소한_요청의_늦은_응답은_모두_무시한다() async throws {
        // REQ-CANCEL-02, EDGE-01
        let harness = try AppHarness()
        await harness.matchAndConnect()
        await harness.store.send(.lobby(.cancelButtonTapped)) {
            $0.phase.lobby?.phase = .selecting
        }
        await harness.store.receive(\.lobby.delegate.cancelMatch)

        let cancelled = TestID.request(0)
        await harness.receive(.matchWaiting(WireV1.RequestPayload(requestID: cancelled)))
        await harness.receive(.welcome(AppFixtures.welcome(requestID: cancelled)))
        await harness.receive(.matchFailed(WireV1.MatchFailedPayload(requestID: cancelled, code: .internalError)))
        await harness.receive(.matchCancelled(WireV1.RequestPayload(requestID: cancelled)))
        let sent = await harness.sent()
        XCTAssertEqual(sent, [harness.matchRequest0, .matchCancel(requestID: cancelled)])
        await harness.finish()
    }

    func test_취소_후_재매칭하면_이전_요청의_WELCOME은_무시하고_새_요청의_WELCOME만_처리한다() async throws {
        // EDGE-03, requirements 11번 REQ-CANCEL-02 예시
        let harness = try AppHarness()
        await harness.matchAndConnect()
        await harness.store.send(.lobby(.cancelButtonTapped)) {
            $0.phase.lobby?.phase = .selecting
        }
        await harness.store.receive(\.lobby.delegate.cancelMatch)
        await harness.store.send(.lobby(.matchButtonTapped)) {
            $0.phase.lobby?.phase = .matching(requestID: TestID.request(2))
        }
        await harness.store.receive(\.lobby.delegate.requestMatch)

        // A의 WELCOME → 매칭 대기(B) 유지
        await harness.receive(.welcome(AppFixtures.welcome(requestID: TestID.request(0), roomID: TestID.room1)))
        // B의 WELCOME → 방
        let welcome = AppFixtures.welcome(requestID: TestID.request(2), roomID: TestID.room2)
        await harness.receive(.welcome(welcome)) {
            $0.phase = .room(AppFixtures.roomState(welcome))
        }
        await harness.finish()
    }

    func test_MATCH_FAILED는_코드별_알럿과_조건_선택() async throws {
        // REQ-FAIL-01, DONE-08
        let expected: [(MatchFailureCode, String)] = [
            (.invalidCriteria, "음악 조건 정보가 변경됐어요. 앱 업데이트를 확인해 주세요."),
            (.internalError, "매칭 중 문제가 생겼어요. 잠시 후 다시 시도해 주세요."),
            (.alreadyMatching, "이미 매칭 중이에요."),
            (.alreadyInRoom, "이미 방에 참여 중이에요.")
        ]
        for (code, message) in expected {
            let harness = try AppHarness()
            await harness.matchAndConnect()
            await harness.receive(.matchFailed(WireV1.MatchFailedPayload(requestID: TestID.request(0), code: code))) {
                $0.alert = .matchFailed(code)
            }
            await harness.store.receive(\.lobby.matchEnded) {
                $0.phase.lobby?.phase = .selecting
            }
            XCTAssertEqual(harness.store.state.alert.map(AppCopy.alertTitle), message, "\(code)")
            // 연결은 유지한다
            XCTAssertEqual(harness.store.state.connection, .connected(generation: UUID(1)))
            await harness.finish()
        }
    }

    func test_다른_requestID의_MATCH_FAILED는_무시한다() async throws {
        let harness = try AppHarness()
        await harness.matchAndConnect()
        await harness.receive(.matchFailed(WireV1.MatchFailedPayload(requestID: TestID.request(5), code: .internalError)))
        await harness.finish()
    }

    func test_방에_있을_때의_매칭_메시지는_무시한다() async throws {
        let harness = try AppHarness()
        await harness.enterRoom()
        await harness.receive(.welcome(AppFixtures.welcome(requestID: TestID.request(0), roomID: TestID.room2)))
        await harness.receive(.matchFailed(WireV1.MatchFailedPayload(requestID: TestID.request(0), code: .internalError)))
        await harness.finish()
    }

    // MARK: - 방·게임 메시지

    func test_현재_방의_메시지는_Room에_전달한다() async throws {
        // EDGE-06: WELCOME 뒤 같은 방의 PLAYER_JOINED
        let harness = try AppHarness()
        await harness.enterRoom()
        await harness.receive(.playerJoined(WireV1.PlayerPayload(roomID: TestID.room1, playerID: TestID.newcomer)))
        await harness.store.receive(\.room.server) {
            $0.phase.room?.players.append(TestID.newcomer)
            $0.phase.room?.opponentOrder.append(TestID.newcomer)
        }
        await harness.receive(.hostChanged(WireV1.PlayerPayload(roomID: TestID.room1, playerID: TestID.opponent)))
        await harness.store.receive(\.room.server) {
            $0.phase.room?.hostID = TestID.opponent
        }
        await harness.finish()
    }

    func test_다른_방의_메시지는_Room에_전달하지_않는다() async throws {
        // REQ-FILTER-02, requirements 11번 예시, INV-04
        let harness = try AppHarness()
        await harness.enterRoom()
        let other = TestID.room2
        await harness.receive(.playerJoined(WireV1.PlayerPayload(roomID: other, playerID: TestID.newcomer)))
        await harness.receive(.playerLeft(WireV1.PlayerPayload(roomID: other, playerID: TestID.opponent)))
        await harness.receive(.hostChanged(WireV1.PlayerPayload(roomID: other, playerID: TestID.opponent)))
        await harness.receive(.gameStarted(WireV1.RoomPayload(roomID: other)))
        await harness.receive(.gameAborted(WireV1.GameAbortedPayload(roomID: other, reason: .internalError)))
        await harness.receive(.roomCommandFailed(WireV1.RoomCommandFailedPayload(
            roomID: other, command: "START_GAME", code: .notHost
        )))
        await harness.receive(.playerKicked(WireV1.RoomPayload(roomID: other)))
        await harness.receive(.roomLeft(WireV1.RoomPayload(roomID: other)))
        await harness.finish()
    }

    func test_로비에서_받은_방_메시지는_무시한다() async throws {
        let harness = try AppHarness()
        await harness.matchAndConnect()
        await harness.receive(.playerJoined(WireV1.PlayerPayload(roomID: TestID.room1, playerID: TestID.newcomer)))
        await harness.receive(.roomLeft(WireV1.RoomPayload(roomID: TestID.room1)))
        await harness.receive(.playerKicked(WireV1.RoomPayload(roomID: TestID.room1)))
        await harness.finish()
    }

    func test_방을_나와_새_방에_들어간_뒤_이전_방의_메시지는_무시한다() async throws {
        // EDGE-07
        let harness = try AppHarness()
        await harness.enterRoom()
        await leave(harness, roomID: TestID.room1)

        await harness.store.send(.lobby(.onAppear)) {
            $0.phase.lobby?.catalog = .available(harness.catalog)
        }
        await harness.store.send(.lobby(.matchButtonTapped)) {
            $0.phase.lobby?.phase = .matching(requestID: TestID.request(2))
        }
        await harness.store.receive(\.lobby.delegate.requestMatch)
        let welcome = AppFixtures.welcome(requestID: TestID.request(2), roomID: TestID.room2)
        await harness.receive(.welcome(welcome)) {
            $0.phase = .room(AppFixtures.roomState(welcome))
        }

        await harness.receive(.playerLeft(WireV1.PlayerPayload(roomID: TestID.room1, playerID: TestID.opponent)))
        await harness.receive(.gameStarted(WireV1.RoomPayload(roomID: TestID.room1)))
        await harness.receive(.playerKicked(WireV1.RoomPayload(roomID: TestID.room1)))
        XCTAssertEqual(harness.store.state.phase.room?.roomID, TestID.room2)
        await harness.finish()
    }

    private func leave(_ harness: AppHarness, roomID: String) async {
        await harness.store.send(.room(.leaveTapped)) {
            $0.phase.room?.isLeaving = true
        }
        await harness.store.receive(\.room.delegate.send)
        await harness.receive(.roomLeft(WireV1.RoomPayload(roomID: roomID))) {
            $0.phase = .lobby(LobbyReducer.State())
        }
    }
}

/// ServerMessage → RoomServerEvent 변환 (design 6, 8)
final class ServerMessageRoomEventTests: XCTestCase {
    func test_ROUND_RESULT_승자가_빈_문자열이면_winnerId는_nil() {
        let message = ServerMessage.roundResult(WireV1.RoundResultPayload(
            roomID: TestID.room1, winner: "", correctAnswer: "답", scores: [TestID.myself: 0]
        ))
        XCTAssertEqual(message.roomEvent?.roomID, TestID.room1)
        XCTAssertEqual(
            message.roomEvent?.event,
            .game(.roundEnded(RoundResult(winnerId: nil, correctAnswer: "답", scores: [TestID.myself: 0])))
        )
    }

    func test_ROUND_RESULT_승자가_있으면_그대로() {
        let message = ServerMessage.roundResult(WireV1.RoundResultPayload(
            roomID: TestID.room1, winner: TestID.myself, correctAnswer: "답", scores: [TestID.myself: 1]
        ))
        XCTAssertEqual(
            message.roomEvent?.event,
            .game(.roundEnded(RoundResult(winnerId: TestID.myself, correctAnswer: "답", scores: [TestID.myself: 1])))
        )
    }

    func test_게임_메시지_변환() {
        let room = TestID.room1
        XCTAssertEqual(
            ServerMessage.roundStarted(WireV1.RoundStartedPayload(
                roomID: room, roundNumber: 1, totalRounds: 10, answerLength: 2, letterCards: ["가", "나"]
            )).roomEvent?.event,
            .game(.roundStarted(RoundData(roundNumber: 1, totalRounds: 10, letterCards: ["가", "나"], answerLength: 2)))
        )
        XCTAssertEqual(
            ServerMessage.countDown(WireV1.CountDownPayload(roomID: room, remaining: 3)).roomEvent?.event,
            .game(.countDown(3))
        )
        XCTAssertEqual(
            ServerMessage.wrongAnswer(WireV1.WrongAnswerPayload(
                roomID: room, playerID: TestID.opponent, wrongAnswer: "다"
            )).roomEvent?.event,
            .game(.wrongAnswer(playerID: TestID.opponent, wrongAnswer: "다"))
        )
        XCTAssertEqual(
            ServerMessage.preloadSong(WireV1.PreloadSongPayload(
                roomID: room, isrc: "KRA381234567", startTime: 30, roundNumber: 1
            )).roomEvent?.event,
            .preloadSong(isrc: "KRA381234567", startTime: 30, roundNumber: 1)
        )
        XCTAssertEqual(
            ServerMessage.gameOver(WireV1.GameOverPayload(roomID: room, winner: "", scores: [:])).roomEvent?.event,
            .gameOver(GameResult(winner: "", scores: [:]))
        )
        XCTAssertEqual(
            ServerMessage.gameAborted(WireV1.GameAbortedPayload(roomID: room, reason: .insufficientPlayers)).roomEvent?.event,
            .gameAborted(.insufficientPlayers)
        )
        XCTAssertEqual(
            ServerMessage.roomCommandFailed(WireV1.RoomCommandFailedPayload(
                roomID: room, command: "START_GAME", code: .notEnoughPlayers
            )).roomEvent?.event,
            .commandFailed(.notEnoughPlayers)
        )
    }

    func test_App이_직접_처리하는_메시지는_Room_이벤트가_아니다() {
        XCTAssertNil(ServerMessage.roomLeft(WireV1.RoomPayload(roomID: TestID.room1)).roomEvent)
        XCTAssertNil(ServerMessage.playerKicked(WireV1.RoomPayload(roomID: TestID.room1)).roomEvent)
        XCTAssertNil(ServerMessage.welcome(AppFixtures.welcome(requestID: TestID.request(0))).roomEvent)
        XCTAssertNil(ServerMessage.matchWaiting(WireV1.RequestPayload(requestID: TestID.request(0))).roomEvent)
    }
}
