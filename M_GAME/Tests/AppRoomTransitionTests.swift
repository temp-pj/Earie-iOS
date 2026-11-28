@testable import M_GAME

import ClientSessionTest
import ComposableArchitecture
import FeatureLobby
@testable import FeatureRoom
import Foundation
import Models
import XCTest

/// 방 ↔ 로비 전환 (REQ-ROOM-05·07, REQ-FAIL-02·03, REQ-GAME-07, DONE-10 전환, design 8 "로비로 전환", design 12)
@MainActor
final class AppRoomTransitionTests: XCTestCase {
    // MARK: - 방 안의 송신

    func test_Room의_송신은_현재_연결로_보낸다() async throws {
        let harness = try AppHarness()
        await harness.enterRoom()
        await harness.store.send(.room(.startTapped)) {
            $0.phase.room?.isStartRequesting = true
        }
        await harness.store.receive(\.room.delegate.send)
        let sent = await harness.sent()
        XCTAssertEqual(sent.last, .startGame(roomID: TestID.room1))
        await harness.finish()
    }

    // MARK: - ROOM_LEFT

    func test_나가는_중인_현재_방의_ROOM_LEFT로_조건_선택에_돌아가고_연결은_유지한다() async throws {
        // REQ-ROOM-05, REQ-FAIL-03, INV-09
        let harness = try AppHarness()
        await harness.enterRoom()
        await harness.store.send(.room(.leaveTapped)) {
            $0.phase.room?.isLeaving = true
        }
        await harness.store.receive(\.room.delegate.send)
        await harness.receive(.roomLeft(WireV1.RoomPayload(roomID: TestID.room1))) {
            $0.phase = .lobby(LobbyReducer.State())
        }
        XCTAssertNil(harness.store.state.alert)
        XCTAssertEqual(harness.store.state.connection, .connected(generation: UUID(1)))
        let sent = await harness.sent()
        XCTAssertEqual(sent.last, .leaveRoom(roomID: TestID.room1))
        XCTAssertEqual(harness.session.disconnectCount, 0)
        await harness.finish()
    }

    func test_나가는_중이_아니면_현재_방의_ROOM_LEFT도_무시한다() async throws {
        // requirements 8번 "무시 (나가는 중 아님)"
        let harness = try AppHarness()
        await harness.enterRoom()
        await harness.receive(.roomLeft(WireV1.RoomPayload(roomID: TestID.room1)))
        XCTAssertNotNil(harness.store.state.phase.room)
        await harness.finish()
    }

    func test_ROOM_LEFT가_두_번_오면_첫_번째만_처리한다() async throws {
        // EDGE-08
        let harness = try AppHarness()
        await harness.enterRoom()
        await harness.store.send(.room(.leaveTapped)) {
            $0.phase.room?.isLeaving = true
        }
        await harness.store.receive(\.room.delegate.send)
        await harness.receive(.roomLeft(WireV1.RoomPayload(roomID: TestID.room1))) {
            $0.phase = .lobby(LobbyReducer.State())
        }
        await harness.receive(.roomLeft(WireV1.RoomPayload(roomID: TestID.room1)))
        await harness.finish()
    }

    func test_나가는_중에_다른_roomID의_ROOM_LEFT는_무시한다() async throws {
        let harness = try AppHarness()
        await harness.enterRoom()
        await harness.store.send(.room(.leaveTapped)) {
            $0.phase.room?.isLeaving = true
        }
        await harness.store.receive(\.room.delegate.send)
        await harness.receive(.roomLeft(WireV1.RoomPayload(roomID: TestID.room2)))
        await harness.finish()
    }

    // MARK: - 강퇴

    func test_현재_방의_PLAYER_KICKED는_강퇴_알럿과_조건_선택이고_연결은_유지한다() async throws {
        // REQ-ROOM-07
        let harness = try AppHarness()
        await harness.enterRoom()
        await harness.receive(.playerKicked(WireV1.RoomPayload(roomID: TestID.room1))) {
            $0.phase = .lobby(LobbyReducer.State())
            $0.alert = .kicked
        }
        XCTAssertEqual(harness.store.state.alert.map(AppCopy.alertTitle), "방에서 내보내졌어요.")
        XCTAssertEqual(harness.store.state.connection, .connected(generation: UUID(1)))
        XCTAssertEqual(harness.session.disconnectCount, 0)
        await harness.finish()
    }

    func test_나가는_중에도_PLAYER_KICKED는_강퇴_알럿과_조건_선택() async throws {
        // requirements 8번 "방 나가는 중" 행
        let harness = try AppHarness()
        await harness.enterRoom()
        await harness.store.send(.room(.leaveTapped)) {
            $0.phase.room?.isLeaving = true
        }
        await harness.store.receive(\.room.delegate.send)
        await harness.receive(.playerKicked(WireV1.RoomPayload(roomID: TestID.room1))) {
            $0.phase = .lobby(LobbyReducer.State())
            $0.alert = .kicked
        }
        await harness.finish()
    }

    // MARK: - 끊김

    func test_방에서_끊기면_끊김_알럿과_조건_선택이고_방_상태를_버린다() async throws {
        // REQ-FAIL-02
        let harness = try AppHarness()
        await harness.enterRoom()
        harness.session.yield(.disconnected(.networkError), connection: 0)
        await harness.store.receive(\.session) {
            $0.connection = .disconnected
            $0.phase = .lobby(LobbyReducer.State())
            $0.alert = .disconnected
        }
        XCTAssertEqual(harness.store.state.alert.map(AppCopy.alertTitle), "서버와 연결이 끊어졌어요.")
        await Task.megaYield()
        XCTAssertEqual(harness.audio.stopCount.value, 1)
    }

    func test_게임_중에_끊기면_끊김_알럿과_조건_선택() async throws {
        let harness = try AppHarness()
        await harness.enterRoom()
        await startGame(harness)
        harness.session.yield(.disconnected(.networkError), connection: 0)
        await harness.store.receive(\.session) {
            $0.connection = .disconnected
            $0.phase = .lobby(LobbyReducer.State())
            $0.alert = .disconnected
        }
    }

    func test_방에서_송신이_실패하면_끊김과_같게_처리한다() async throws {
        let harness = try AppHarness()
        await harness.enterRoom()
        harness.session.setSendError(TestSessionSendError())
        await harness.store.send(.room(.startTapped)) {
            $0.phase.room?.isStartRequesting = true
        }
        await harness.store.receive(\.room.delegate.send)
        await harness.store.receive(\.sendFailed) {
            $0.connection = .disconnected
            $0.phase = .lobby(LobbyReducer.State())
            $0.alert = .disconnected
        }
    }

    // MARK: - 로비 전환의 정리 (design 12)

    func test_로비로_전환하면_음악을_멈추고_곡_준비와_페널티_타이머를_취소한다() async throws {
        let harness = try AppHarness()
        await harness.enterRoom()
        await startGame(harness)

        await harness.receive(.preloadSong(WireV1.PreloadSongPayload(
            roomID: TestID.room1, isrc: "KRA381234567", startTime: 0, roundNumber: 1
        )))
        await harness.store.receive(\.room.server)
        await harness.receive(.wrongAnswer(WireV1.WrongAnswerPayload(
            roomID: TestID.room1, playerID: TestID.myself, wrongAnswer: "x"
        )))
        await harness.store.receive(\.room.server)
        await harness.store.receive(\.room.game.serverEvent) {
            $0.phase.room?.game?.inputState = .penalized
        }
        await Task.megaYield()
        XCTAssertTrue(harness.audio.preloadStarted.value)
        let stopsBefore = harness.audio.stopCount.value

        await harness.receive(.playerKicked(WireV1.RoomPayload(roomID: TestID.room1))) {
            $0.phase = .lobby(LobbyReducer.State())
            $0.alert = .kicked
        }
        await Task.megaYield()
        XCTAssertTrue(harness.audio.preloadCancelled.value)
        XCTAssertEqual(harness.audio.stopCount.value, stopsBefore + 1)
        // READY_TO_PLAY와 penaltyFinished가 오지 않는다
        await harness.clock.advance(by: .seconds(10))
        let sent = await harness.sent()
        XCTAssertFalse(sent.contains { if case .readyToPlay = $0 { true } else { false } })
        await harness.finish()
    }

    // MARK: - 같은 연결 재매칭

    func test_로비로_돌아와_다시_매칭하면_같은_연결을_재사용한다() async throws {
        // REQ-GAME-07, SCOPE-08
        let harness = try AppHarness()
        await harness.enterRoom()
        await harness.store.send(.room(.leaveTapped)) {
            $0.phase.room?.isLeaving = true
        }
        await harness.store.receive(\.room.delegate.send)
        await harness.receive(.roomLeft(WireV1.RoomPayload(roomID: TestID.room1))) {
            $0.phase = .lobby(LobbyReducer.State())
        }
        // 로비는 진입 시 카탈로그와 저장된 조합을 다시 읽는다
        await harness.store.send(.lobby(.onAppear)) {
            $0.phase.lobby?.catalog = .available(harness.catalog)
        }
        await harness.store.send(.lobby(.matchButtonTapped)) {
            $0.phase.lobby?.phase = .matching(requestID: TestID.request(2))
        }
        await harness.store.receive(\.lobby.delegate.requestMatch)
        let sent = await harness.sent()
        XCTAssertEqual(sent.last, .matchRequest(WireV1.MatchRequestPayload(
            requestID: TestID.request(2),
            catalogVersion: "test-v1",
            category: AppFixtures.allAny
        )))
        XCTAssertEqual(harness.session.connectCount, 1)
        await harness.finish()
    }

    private func startGame(_ harness: AppHarness) async {
        await harness.receive(.gameStarted(WireV1.RoomPayload(roomID: TestID.room1)))
        await harness.store.receive(\.room.server) {
            $0.phase.room?.stage = .playing
            $0.phase.room?.game = GameReducer.State()
        }
    }
}

/// 방 화면용 조건 이름 (#38 인계: 로비 이름과 맞춘다)
final class AppCopyCategoryLabelTests: XCTestCase {
    func test_확정_조합의_이름은_로비_후보_이름과_카탈로그_label을_쓴다() throws {
        let catalog = try AppFixtures.testV1()
        let lobby = LobbyReducer.State(catalog: .available(catalog))

        XCTAssertEqual(
            AppCopy.categoryLabel(
                MatchCategory(decade: "2020s", artistType: "group", gender: "male", genre: "synthetic_pop"),
                lobby: lobby
            ),
            RoomReducer.CategoryLabel(decade: "2020s", artistType: "그룹", gender: "남성", genre: "Synthetic pop (test only)")
        )
        XCTAssertEqual(
            AppCopy.categoryLabel(
                MatchCategory(decade: "all", artistType: "solo", gender: "female", genre: "korean_ballad"),
                lobby: lobby
            ),
            RoomReducer.CategoryLabel(decade: "모든 연대", artistType: "솔로", gender: "여성", genre: "Synthetic ballad (test only)")
        )
    }

    func test_로비에_없는_all은_임시_이름을_쓴다() throws {
        let catalog = try AppFixtures.testV1()
        let lobby = LobbyReducer.State(catalog: .available(catalog))
        XCTAssertEqual(
            AppCopy.categoryLabel(
                MatchCategory(decade: "all", artistType: "all", gender: "all", genre: "all"),
                lobby: lobby
            ),
            RoomReducer.CategoryLabel(decade: "모든 연대", artistType: "전체", gender: "전체", genre: "전체")
        )
    }
}
