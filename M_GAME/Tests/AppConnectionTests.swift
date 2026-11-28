@testable import M_GAME

import ClientSessionTest
import ComposableArchitecture
import FeatureLobby
import Foundation
import Models
import XCTest

/// design 9번 표: 연결 상태 × 일어난 일, 연결 시도 10초 (REQ-FAIL-05), 송신 실패
@MainActor
final class AppConnectionTests: XCTestCase {
    // MARK: - .disconnected

    func test_연결_없음에서_매칭하면_새_세대로_연결을_시작한다() async throws {
        let harness = try AppHarness()
        await harness.tapMatchFromDisconnected()
        await Task.megaYield()
        XCTAssertEqual(harness.session.connectCount, 1)
        // 연결만으로는 아무것도 보내지 않는다 (REQ-MATCH-02)
        let sent = await harness.sent()
        XCTAssertEqual(sent, [])
        await harness.finish()
    }

    func test_연결_없음에서_취소는_아무것도_보내지_않는다() async throws {
        let catalog = try AppFixtures.testV1()
        let harness = try AppHarness(phase: .lobby(LobbyReducer.State(
            catalog: .available(catalog),
            phase: .matching(requestID: TestID.request(9))
        )))
        await harness.store.send(.lobby(.cancelButtonTapped)) {
            $0.phase.lobby?.phase = .selecting
        }
        await harness.store.receive(\.lobby.delegate.cancelMatch)
        let sent = await harness.sent()
        XCTAssertEqual(sent, [])
        XCTAssertEqual(harness.session.connectCount, 0)
    }

    func test_연결_없음에서_이전_세대_이벤트는_무시한다() async throws {
        let harness = try AppHarness()
        await harness.store.send(.session(generation: UUID(7), event: .connected))
        await harness.store.send(.session(generation: UUID(7), event: .disconnected(.networkError)))
    }

    // MARK: - .connecting

    func test_연결_중에_다시_매칭해도_새_연결을_만들지_않고_연결되면_요청_하나만_보낸다() async throws {
        // EDGE-05: 연결 중 취소 후 재매칭
        let harness = try AppHarness()
        await harness.tapMatchFromDisconnected()
        await harness.store.send(.lobby(.cancelButtonTapped)) {
            $0.phase.lobby?.phase = .selecting
        }
        await harness.store.receive(\.lobby.delegate.cancelMatch)
        await harness.store.send(.lobby(.matchButtonTapped)) {
            $0.phase.lobby?.phase = .matching(requestID: TestID.request(2))
        }
        await harness.store.receive(\.lobby.delegate.requestMatch)

        harness.session.yield(.connected, connection: 0)
        await harness.store.receive(\.session) {
            $0.connection = .connected(generation: UUID(1))
        }
        let sent = await harness.sent()
        XCTAssertEqual(sent, [.matchRequest(WireV1.MatchRequestPayload(
            requestID: TestID.request(2),
            catalogVersion: "test-v1",
            category: AppFixtures.allAny
        ))])
        XCTAssertEqual(harness.session.connectCount, 1)
        await harness.finish()
    }

    func test_연결_중에_취소하면_연결된_뒤에도_MATCH_REQUEST를_보내지_않고_연결을_닫지_않는다() async throws {
        // REQ-CANCEL-04, EDGE-04
        let harness = try AppHarness()
        await harness.tapMatchFromDisconnected()
        await harness.store.send(.lobby(.cancelButtonTapped)) {
            $0.phase.lobby?.phase = .selecting
        }
        await harness.store.receive(\.lobby.delegate.cancelMatch)

        harness.session.yield(.connected, connection: 0)
        await harness.store.receive(\.session) {
            $0.connection = .connected(generation: UUID(1))
        }
        let sent = await harness.sent()
        XCTAssertEqual(sent, [])
        XCTAssertEqual(harness.session.disconnectCount, 0)
        // 연결 타이머는 이미 취소됐다
        await harness.clock.advance(by: .seconds(30))
        await harness.finish()
    }

    func test_연결_중에_끊기면_매칭_중이면_알럿과_조건_선택() async throws {
        let harness = try AppHarness()
        await harness.tapMatchFromDisconnected()
        harness.session.yield(.disconnected(.networkError), connection: 0)
        await harness.store.receive(\.session) {
            $0.connection = .disconnected
            $0.alert = .disconnected
        }
        await harness.store.receive(\.lobby.matchEnded) {
            $0.phase.lobby?.phase = .selecting
        }
        await harness.clock.advance(by: .seconds(30))
    }

    func test_연결_중에_끊겨도_취소한_뒤면_알럿_없이_연결_상태만_바뀐다() async throws {
        let harness = try AppHarness()
        await harness.tapMatchFromDisconnected()
        await harness.store.send(.lobby(.cancelButtonTapped)) {
            $0.phase.lobby?.phase = .selecting
        }
        await harness.store.receive(\.lobby.delegate.cancelMatch)
        harness.session.yield(.disconnected(.networkError), connection: 0)
        await harness.store.receive(\.session) {
            $0.connection = .disconnected
        }
    }

    func test_연결_시도가_10초_안에_되지_않으면_연결_실패로_처리하고_disconnect를_부른다() async throws {
        // REQ-FAIL-05, design 11
        let harness = try AppHarness()
        await harness.tapMatchFromDisconnected()
        await harness.clock.advance(by: .seconds(9))
        await harness.clock.advance(by: .seconds(1))
        await harness.store.receive(\.connectTimedOut) {
            $0.connection = .disconnected
            $0.alert = .disconnected
        }
        await harness.store.receive(\.lobby.matchEnded) {
            $0.phase.lobby?.phase = .selecting
        }
        await Task.megaYield()
        XCTAssertEqual(harness.session.disconnectCount, 1)

        // 해당 세대의 늦은 연결 이벤트는 무시한다 (스트림 소비 효과도 취소됐다)
        harness.session.yield(.connected, connection: 0)
        await Task.megaYield()
    }

    func test_연결_시도_10초_전에_연결되면_타이머가_취소된다() async throws {
        let harness = try AppHarness()
        await harness.matchAndConnect()
        await harness.clock.advance(by: .seconds(30))
        let sent = await harness.sent()
        XCTAssertEqual(sent, [harness.matchRequest0])
        XCTAssertEqual(harness.session.disconnectCount, 0)
        await harness.finish()
    }

    // MARK: - .connected

    func test_연결되면_매칭_중인_요청으로_MATCH_REQUEST를_보낸다() async throws {
        // DONE-06, REQ-MATCH-03
        let harness = try AppHarness()
        await harness.matchAndConnect()
        let sent = await harness.sent()
        XCTAssertEqual(sent, [harness.matchRequest0])
        await harness.finish()
    }

    func test_연결된_상태에서_매칭하면_연결을_재사용해_즉시_보낸다() async throws {
        // REQ-MATCH-02, DONE-06
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
        let sent = await harness.sent()
        XCTAssertEqual(sent, [
            harness.matchRequest0,
            .matchCancel(requestID: TestID.request(0)),
            .matchRequest(WireV1.MatchRequestPayload(
                requestID: TestID.request(2),
                catalogVersion: "test-v1",
                category: AppFixtures.allAny
            ))
        ])
        XCTAssertEqual(harness.session.connectCount, 1)
        await harness.finish()
    }

    func test_연결된_상태의_connected는_무시한다() async throws {
        let harness = try AppHarness()
        await harness.matchAndConnect()
        harness.session.yield(.connected, connection: 0)
        await harness.store.receive(\.session)
        let sent = await harness.sent()
        XCTAssertEqual(sent, [harness.matchRequest0])
        await harness.finish()
    }

    func test_조건_선택_화면에서_끊기면_알럿_없이_연결_상태만_바뀐다() async throws {
        // REQ-FAIL-02 마지막 문장, DONE-08
        let harness = try AppHarness()
        await harness.matchAndConnect()
        await harness.store.send(.lobby(.cancelButtonTapped)) {
            $0.phase.lobby?.phase = .selecting
        }
        await harness.store.receive(\.lobby.delegate.cancelMatch)
        harness.session.yield(.disconnected(.normal), connection: 0)
        await harness.store.receive(\.session) {
            $0.connection = .disconnected
        }
    }

    func test_매칭_대기_중에_끊기면_알럿과_조건_선택() async throws {
        let harness = try AppHarness()
        await harness.matchAndConnect()
        harness.session.yield(.disconnected(.networkError), connection: 0)
        await harness.store.receive(\.session) {
            $0.connection = .disconnected
            $0.alert = .disconnected
        }
        await harness.store.receive(\.lobby.matchEnded) {
            $0.phase.lobby?.phase = .selecting
        }
        // 알럿을 닫는다
        await harness.store.send(.alertDismissed) {
            $0.alert = nil
        }
    }

    func test_끊긴_뒤_다시_매칭하면_새_연결을_맺는다() async throws {
        // REQ-FAIL-02 "다음 매칭 때 새 연결"
        let harness = try AppHarness()
        await harness.matchAndConnect()
        harness.session.yield(.disconnected(.networkError), connection: 0)
        await harness.store.receive(\.session) {
            $0.connection = .disconnected
            $0.alert = .disconnected
        }
        await harness.store.receive(\.lobby.matchEnded) {
            $0.phase.lobby?.phase = .selecting
        }
        await harness.store.send(.lobby(.matchButtonTapped)) {
            $0.phase.lobby?.phase = .matching(requestID: TestID.request(2))
        }
        await harness.store.receive(\.lobby.delegate.requestMatch) {
            $0.connection = .connecting(generation: UUID(3))
        }
        await Task.megaYield()
        XCTAssertEqual(harness.session.connectCount, 2)
        await harness.finish()
    }

    func test_송신_실패는_연결_끊김과_같게_처리한다() async throws {
        // design 8 "송신 실패", 9번 표 마지막 열
        let harness = try AppHarness()
        harness.session.setSendError(TestSessionSendError())
        await harness.matchAndConnect()
        await harness.store.receive(\.sendFailed) {
            $0.connection = .disconnected
            $0.alert = .disconnected
        }
        await harness.store.receive(\.lobby.matchEnded) {
            $0.phase.lobby?.phase = .selecting
        }
    }

    // MARK: - 세대

    func test_새_연결을_맺은_뒤_이전_세대_연결의_이벤트는_무시한다() async throws {
        // INV-08, design 9 "이전 세대 이벤트"
        let harness = try AppHarness()
        await harness.matchAndConnect()
        harness.session.yield(.disconnected(.networkError), connection: 0)
        await harness.store.receive(\.session) {
            $0.connection = .disconnected
            $0.alert = .disconnected
        }
        await harness.store.receive(\.lobby.matchEnded) {
            $0.phase.lobby?.phase = .selecting
        }
        await harness.store.send(.lobby(.matchButtonTapped)) {
            $0.phase.lobby?.phase = .matching(requestID: TestID.request(2))
        }
        await harness.store.receive(\.lobby.delegate.requestMatch) {
            $0.connection = .connecting(generation: UUID(3))
        }

        // 이전 세대(1)의 이벤트가 늦게 도착해도 상태가 바뀌지 않는다
        await harness.store.send(.session(generation: UUID(1), event: .connected))
        await harness.store.send(.session(generation: UUID(1), event: .message(.welcome(
            AppFixtures.welcome(requestID: TestID.request(2))
        ))))
        await harness.store.send(.session(generation: UUID(1), event: .disconnected(.normal)))

        // 새 세대의 연결은 정상 처리한다
        harness.session.yield(.connected, connection: 1)
        await harness.store.receive(\.session) {
            $0.connection = .connected(generation: UUID(3))
        }
        let sent = await harness.sent()
        XCTAssertEqual(sent.last, .matchRequest(WireV1.MatchRequestPayload(
            requestID: TestID.request(2),
            catalogVersion: "test-v1",
            category: AppFixtures.allAny
        )))
        await harness.finish()
    }
}
