@testable import FeatureLobby

import ClientCatalog
import ClientCatalogTest
import ComposableArchitecture
import Foundation
import Models
import XCTest

// swiftlint:disable file_length type_body_length
@MainActor
final class LobbyReducerTests: XCTestCase {
    private typealias Axis = LobbyReducer.Axis

    private let allAny = MatchCategory.make("any", "any", "any", "any")
    private let ballad2010s = MatchCategory.make("2010s", "any", "any", "korean_ballad")
    private let soloFemaleBallad = MatchCategory.make("2010s", "solo", "female", "korean_ballad")
    private let groupMalePop = MatchCategory.make("2020s", "group", "male", "synthetic_pop")

    private func makeStore(
        catalog: CatalogClient,
        storage: LockIsolated<MatchCategory?> = LockIsolated(nil),
        uuid: UUIDGenerator = .incrementing,
        state: LobbyReducer.State = LobbyReducer.State()
    ) -> TestStoreOf<LobbyReducer> {
        TestStore(initialState: state) {
            LobbyReducer()
        } withDependencies: {
            $0.catalogClient = catalog
            $0.categoryPreferenceClient = .inMemory(storage)
            $0.uuid = uuid
        }
    }

    /// 카탈로그를 읽고 `selection`까지 고른 상태의 store
    private func makeLoadedStore(
        storage: LockIsolated<MatchCategory?> = LockIsolated(nil),
        uuid: UUIDGenerator = .incrementing
    ) async throws -> (TestStoreOf<LobbyReducer>, CatalogProjection) {
        let catalog = try LobbyFixtures.testV1()
        let store = makeStore(catalog: .returning(catalog), storage: storage, uuid: uuid)
        await store.send(.onAppear) {
            $0.catalog = .available(catalog)
        }
        return (store, catalog)
    }

    private func select(_ category: MatchCategory, in store: TestStoreOf<LobbyReducer>) async {
        for axis in Axis.allCases where store.state.selection[axis] != category[axis] {
            await store.send(.candidateTapped(axis, value: category[axis])) {
                $0.selection[axis] = category[axis]
            }
        }
    }

    // MARK: - 기본값 (REQ-CAT-01~03)

    func test_초기_상태는_카탈로그_로딩과_전부_상관없음과_조건_선택이다() {
        let state = LobbyReducer.State()
        XCTAssertEqual(state.catalog, .loading)
        XCTAssertEqual(state.selection, allAny)
        XCTAssertEqual(state.phase, .selecting)
        XCTAssertNil(state.activeRequestID)
        XCTAssertFalse(state.isMatchButtonEnabled)
        XCTAssertFalse(state.isUnavailable)
        XCTAssertEqual(state.candidates(for: .decade), [])
    }

    func test_저장값이_없으면_진입_시_전부_상관없음으로_시작하고_매칭할_수_있다() async throws {
        let (store, _) = try await makeLoadedStore()
        XCTAssertEqual(store.state.selection, allAny)
        XCTAssertTrue(store.state.isMatchButtonEnabled)
        XCTAssertFalse(store.state.isUnavailable)
    }

    func test_후보_목록은_상관없음이_처음이고_연대만_모든_연대를_갖고_카탈로그_순서를_따른다() async throws {
        let (store, _) = try await makeLoadedStore()
        let state = store.state

        XCTAssertEqual(state.candidates(for: .decade).map(\.value), ["any", "all", "2010s", "2020s"])
        XCTAssertEqual(
            state.candidates(for: .decade).map(\.label),
            [.any, .allDecades, .catalog("2010s"), .catalog("2020s")]
        )
        XCTAssertEqual(state.candidates(for: .artistType).map(\.value), ["any", "solo", "group"])
        XCTAssertEqual(state.candidates(for: .gender).map(\.value), ["any", "male", "female"])
        XCTAssertEqual(state.candidates(for: .genre).map(\.value), ["any", "korean_ballad", "synthetic_pop"])
        XCTAssertEqual(
            state.candidates(for: .genre).map(\.label),
            [.any, .catalog("Synthetic ballad (test only)"), .catalog("Synthetic pop (test only)")]
        )
        for axis in [Axis.artistType, .gender, .genre] {
            XCTAssertFalse(state.candidates(for: axis).contains { $0.value == "all" }, "\(axis)에 all이 있다")
        }
        for axis in Axis.allCases {
            XCTAssertEqual(state.candidates(for: axis).filter(\.isSelected).map(\.value), ["any"])
        }
    }

    func test_진입을_다시_알려도_고른_조합을_다시_읽지_않는다() async throws {
        let (store, _) = try await makeLoadedStore()
        await select(ballad2010s, in: store)
        await store.send(.onAppear)
        XCTAssertEqual(store.state.selection, ballad2010s)
    }

    // MARK: - 후보 활성 판정 (REQ-CAT-04, DONE-04)

    func test_전부_상관없음에서는_허용_조합에_나오는_후보만_활성이다() async throws {
        let (store, _) = try await makeLoadedStore()
        let state = store.state

        XCTAssertEqual(enabledValues(state, .decade), ["any", "all", "2010s", "2020s"])
        XCTAssertEqual(enabledValues(state, .artistType), ["any", "solo", "group"])
        XCTAssertEqual(enabledValues(state, .gender), ["any", "male", "female"])
        XCTAssertEqual(enabledValues(state, .genre), ["any", "korean_ballad", "synthetic_pop"])
    }

    func test_다른_축의_현재_값과_함께_쓸_수_없는_후보는_비활성이다() async throws {
        let (store, _) = try await makeLoadedStore()

        await store.send(.candidateTapped(.decade, value: "2010s")) {
            $0.selection.decade = "2010s"
        }
        XCTAssertEqual(enabledValues(store.state, .artistType), ["any", "solo"])
        XCTAssertEqual(enabledValues(store.state, .gender), ["any", "female"])
        XCTAssertEqual(enabledValues(store.state, .genre), ["any", "korean_ballad"])
        XCTAssertEqual(enabledValues(store.state, .decade), ["any", "all", "2010s", "2020s"])

        await store.send(.candidateTapped(.genre, value: "korean_ballad")) {
            $0.selection.genre = "korean_ballad"
        }
        // 장르가 korean_ballad면 all, 2020s 연대 조합은 없다.
        XCTAssertEqual(enabledValues(store.state, .decade), ["any", "2010s"])
    }

    func test_상관없음은_어떤_선택에서도_항상_활성이다() {
        let allowed = [groupMalePop]
        for axis in Axis.allCases {
            XCTAssertTrue(LobbyReducer.isCandidateEnabled(
                "any", axis: axis, selection: soloFemaleBallad, allowedRequests: allowed
            ))
            XCTAssertTrue(LobbyReducer.isCandidateEnabled(
                "any", axis: axis, selection: allAny, allowedRequests: []
            ))
        }
    }

    func test_비활성_후보를_눌러도_선택이_바뀌지_않는다() async throws {
        let (store, _) = try await makeLoadedStore()
        await store.send(.candidateTapped(.decade, value: "2010s")) {
            $0.selection.decade = "2010s"
        }
        await store.send(.candidateTapped(.genre, value: "synthetic_pop"))
        await store.send(.candidateTapped(.artistType, value: "group"))
        // 후보 목록에 없는 값도 무시한다.
        await store.send(.candidateTapped(.artistType, value: "all"))
        await store.send(.candidateTapped(.decade, value: "1990s"))
        XCTAssertEqual(store.state.selection, MatchCategory.make("2010s", "any", "any", "any"))
    }

    func test_한_축을_바꿔도_다른_축의_선택은_자동으로_바뀌지_않는다() async throws {
        let (store, _) = try await makeLoadedStore()
        await select(ballad2010s, in: store)

        await store.send(.candidateTapped(.decade, value: "any")) {
            $0.selection.decade = "any"
        }
        XCTAssertEqual(store.state.selection.genre, "korean_ballad")
        // any/any/any/korean_ballad는 허용 조합이 아니다.
        XCTAssertFalse(store.state.isMatchButtonEnabled)
    }

    func test_전부_상관없음에서_test_v1의_두_목표_조합에_도달하고_매칭할_수_있다() async throws {
        for target in [ballad2010s, groupMalePop] {
            let (store, _) = try await makeLoadedStore()
            // 축을 하나씩 바꿀 때마다 그 후보가 활성이어야 한다.
            for axis in Axis.allCases where target[axis] != "any" {
                XCTAssertTrue(
                    store.state.candidates(for: axis).contains { $0.value == target[axis] && $0.isEnabled },
                    "\(target)로 가는 중 \(axis)=\(target[axis])가 비활성"
                )
                await store.send(.candidateTapped(axis, value: target[axis])) {
                    $0.selection[axis] = target[axis]
                }
            }
            XCTAssertEqual(store.state.selection, target)
            XCTAssertTrue(store.state.isMatchButtonEnabled, "\(target)에서 매칭 버튼이 비활성")
        }
    }

    // MARK: - 매칭 버튼 (REQ-CAT-05)

    func test_현재_조합이_허용_조합이_아니면_매칭_버튼이_비활성이다() async throws {
        let (store, _) = try await makeLoadedStore()

        await store.send(.candidateTapped(.decade, value: "2020s")) {
            $0.selection.decade = "2020s"
        }
        XCTAssertFalse(store.state.isMatchButtonEnabled)
        await store.send(.candidateTapped(.artistType, value: "group")) {
            $0.selection.artistType = "group"
        }
        XCTAssertFalse(store.state.isMatchButtonEnabled)
        await store.send(.candidateTapped(.gender, value: "male")) {
            $0.selection.gender = "male"
        }
        XCTAssertFalse(store.state.isMatchButtonEnabled)
        await store.send(.candidateTapped(.genre, value: "synthetic_pop")) {
            $0.selection.genre = "synthetic_pop"
        }
        XCTAssertTrue(store.state.isMatchButtonEnabled)

        await store.send(.candidateTapped(.decade, value: "any")) {
            $0.selection.decade = "any"
        }
        XCTAssertFalse(store.state.isMatchButtonEnabled)
    }

    func test_매칭_버튼이_비활성일_때_누르면_아무_일도_없다() async throws {
        let storage = LockIsolated<MatchCategory?>(nil)
        let (store, _) = try await makeLoadedStore(storage: storage)
        await store.send(.candidateTapped(.decade, value: "2020s")) {
            $0.selection.decade = "2020s"
        }
        await store.send(.matchButtonTapped)
        XCTAssertNil(storage.value)
    }

    // MARK: - 이용 불가 (REQ-CAT-06, DONE-03)

    func test_카탈로그를_읽지_못하면_이용_불가와_매칭_버튼_비활성() async throws {
        let store = makeStore(catalog: .failing())
        await store.send(.onAppear) {
            $0.catalog = .unavailable
        }
        assertUnavailable(store.state)
        await store.send(.matchButtonTapped)
    }

    func test_허용_조합이_빈_카탈로그는_이용_불가다() async throws {
        let store = makeStore(catalog: .returning(try LobbyFixtures.unavailable()))
        await store.send(.onAppear) {
            $0.catalog = .unavailable
        }
        assertUnavailable(store.state)
    }

    func test_전부_상관없음_조합이_없는_카탈로그는_이용_불가다() async throws {
        let testV1 = try LobbyFixtures.testV1()
        let withoutAllAny = CatalogProjection(
            version: testV1.version,
            decades: testV1.decades,
            genres: testV1.genres,
            allowedRequests: testV1.allowedRequests.filter { $0 != allAny },
            pools: testV1.pools
        )
        let storage = LockIsolated<MatchCategory?>(soloFemaleBallad)
        let store = makeStore(catalog: .returning(withoutAllAny), storage: storage)
        await store.send(.onAppear) {
            $0.catalog = .unavailable
        }
        assertUnavailable(store.state)
        await store.send(.matchButtonTapped)
    }

    // MARK: - 매칭 (REQ-MATCH-01, 03~05, REQ-CAT-07)

    func test_매칭_탭_즉시_매칭_대기와_delegate와_조합_저장() async throws {
        let storage = LockIsolated<MatchCategory?>(nil)
        let (store, catalog) = try await makeLoadedStore(storage: storage)
        await select(ballad2010s, in: store)

        await store.send(.matchButtonTapped) {
            $0.phase = .matching(requestID: "00000000-0000-0000-0000-000000000000")
        }
        XCTAssertEqual(store.state.activeRequestID, "00000000-0000-0000-0000-000000000000")
        XCTAssertFalse(store.state.isMatchButtonEnabled)
        await store.receive(.delegate(.requestMatch(
            requestID: "00000000-0000-0000-0000-000000000000",
            category: ballad2010s,
            catalogVersion: catalog.version
        )))
        await store.finish()
        XCTAssertEqual(catalog.version, "test-v1")
        XCTAssertEqual(storage.value, ballad2010s)
    }

    func test_requestID는_소문자_UUID_문자열이다() async throws {
        let upper = UUID(uuidString: "ABCDEF01-2345-4678-89AB-CDEF01234567")!
        let (store, _) = try await makeLoadedStore(uuid: UUIDGenerator { upper })
        let expected = "abcdef01-2345-4678-89ab-cdef01234567"

        await store.send(.matchButtonTapped) {
            $0.phase = .matching(requestID: expected)
        }
        await store.receive(.delegate(.requestMatch(
            requestID: expected,
            category: allAny,
            catalogVersion: "test-v1"
        )))
        await store.finish()
    }

    func test_매칭_버튼을_연타해도_delegate는_한_번만_나간다() async throws {
        let (store, _) = try await makeLoadedStore()

        await store.send(.matchButtonTapped) {
            $0.phase = .matching(requestID: "00000000-0000-0000-0000-000000000000")
        }
        await store.receive(.delegate(.requestMatch(
            requestID: "00000000-0000-0000-0000-000000000000",
            category: allAny,
            catalogVersion: "test-v1"
        )))
        // 이후 탭은 상태도 바꾸지 않고 액션도 내지 않는다 (exhaustive TestStore가 추가 delegate를 잡는다).
        await store.send(.matchButtonTapped)
        await store.send(.matchButtonTapped)
        await store.finish()
    }

    func test_매칭_대기는_시간이_지나도_끝나지_않는다() async throws {
        let clock = TestClock()
        let catalog = try LobbyFixtures.testV1()
        let store = TestStore(initialState: LobbyReducer.State()) {
            LobbyReducer()
        } withDependencies: {
            $0.catalogClient = .returning(catalog)
            $0.categoryPreferenceClient = .inMemory()
            $0.uuid = .incrementing
            $0.continuousClock = clock
        }
        await store.send(.onAppear) {
            $0.catalog = .available(catalog)
        }
        await store.send(.matchButtonTapped) {
            $0.phase = .matching(requestID: "00000000-0000-0000-0000-000000000000")
        }
        await store.receive(\.delegate.requestMatch)
        await store.finish()

        await clock.advance(by: .seconds(60 * 60))
        // 받은 액션이 없고 상태가 그대로다 (exhaustive TestStore).
        XCTAssertEqual(store.state.phase, .matching(requestID: "00000000-0000-0000-0000-000000000000"))
        XCTAssertEqual(store.state.selection, allAny)
    }

    func test_매칭_대기_중에는_조건을_바꿀_수_없다() async throws {
        let (store, _) = try await makeLoadedStore()
        await store.send(.matchButtonTapped) {
            $0.phase = .matching(requestID: "00000000-0000-0000-0000-000000000000")
        }
        await store.receive(\.delegate.requestMatch)
        await store.finish()
        await store.send(.candidateTapped(.decade, value: "2010s"))
    }

    // MARK: - 취소 (REQ-CANCEL-01, 03, REQ-CAT-07)

    func test_취소_즉시_조건_선택과_delegate() async throws {
        let (store, _) = try await makeLoadedStore()
        await store.send(.matchButtonTapped) {
            $0.phase = .matching(requestID: "00000000-0000-0000-0000-000000000000")
        }
        await store.receive(\.delegate.requestMatch)
        await store.finish()

        await store.send(.cancelButtonTapped) {
            $0.phase = .selecting
        }
        XCTAssertNil(store.state.activeRequestID)
        await store.receive(.delegate(.cancelMatch(requestID: "00000000-0000-0000-0000-000000000000")))
    }

    func test_조건_선택_중_취소는_아무_일도_없다() async throws {
        let (store, _) = try await makeLoadedStore()
        await store.send(.cancelButtonTapped)
    }

    func test_취소_후에도_저장값과_현재_조합이_유지되고_새_requestID로_다시_매칭한다() async throws {
        let storage = LockIsolated<MatchCategory?>(nil)
        let (store, _) = try await makeLoadedStore(storage: storage)
        await select(soloFemaleBallad, in: store)

        await store.send(.matchButtonTapped) {
            $0.phase = .matching(requestID: "00000000-0000-0000-0000-000000000000")
        }
        await store.receive(\.delegate.requestMatch)
        await store.finish()
        await store.send(.cancelButtonTapped) {
            $0.phase = .selecting
        }
        await store.receive(\.delegate.cancelMatch)

        XCTAssertEqual(storage.value, soloFemaleBallad)
        XCTAssertEqual(store.state.selection, soloFemaleBallad)
        XCTAssertTrue(store.state.isMatchButtonEnabled)

        await store.send(.matchButtonTapped) {
            $0.phase = .matching(requestID: "00000000-0000-0000-0000-000000000001")
        }
        await store.receive(.delegate(.requestMatch(
            requestID: "00000000-0000-0000-0000-000000000001",
            category: soloFemaleBallad,
            catalogVersion: "test-v1"
        )))
        await store.finish()
    }

    func test_매칭이_끝나면_조건_선택으로_돌아가고_저장값은_유지된다() async throws {
        let storage = LockIsolated<MatchCategory?>(nil)
        let (store, _) = try await makeLoadedStore(storage: storage)
        await select(groupMalePop, in: store)
        await store.send(.matchButtonTapped) {
            $0.phase = .matching(requestID: "00000000-0000-0000-0000-000000000000")
        }
        await store.receive(\.delegate.requestMatch)
        await store.finish()

        await store.send(.matchEnded) {
            $0.phase = .selecting
        }
        XCTAssertEqual(storage.value, groupMalePop)
        XCTAssertEqual(store.state.selection, groupMalePop)
    }

    // MARK: - 복원 (REQ-CAT-07, 08, EDGE-14, DONE-05)

    func test_저장한_허용_조합은_로비_진입_시_복원한다() async throws {
        let catalog = try LobbyFixtures.testV1()
        let storage = LockIsolated<MatchCategory?>(groupMalePop)
        let store = makeStore(catalog: .returning(catalog), storage: storage)
        await store.send(.onAppear) {
            $0.catalog = .available(catalog)
            $0.selection = self.groupMalePop
        }
        XCTAssertTrue(store.state.isMatchButtonEnabled)
    }

    func test_저장값이_카탈로그에_없으면_전부_상관없음으로_시작한다() async throws {
        let catalog = try LobbyFixtures.testV1()
        // requirements 11번 예시: 저장값 2000s, 카탈로그 연대 2010s, 2020s
        let storage = LockIsolated<MatchCategory?>(.make("2000s", "any", "any", "any"))
        let store = makeStore(catalog: .returning(catalog), storage: storage)
        await store.send(.onAppear) {
            $0.catalog = .available(catalog)
        }
        XCTAssertEqual(store.state.selection, allAny)
        XCTAssertEqual(storage.value, .make("2000s", "any", "any", "any"))
    }

    func test_축마다_유효해도_허용_조합이_아닌_저장값은_전부_상관없음으로_시작한다() async throws {
        let catalog = try LobbyFixtures.testV1()
        let storage = LockIsolated<MatchCategory?>(.make("2020s", "any", "any", "any"))
        let store = makeStore(catalog: .returning(catalog), storage: storage)
        await store.send(.onAppear) {
            $0.catalog = .available(catalog)
        }
        XCTAssertEqual(store.state.selection, allAny)
    }

    func test_다시_로비에_들어오면_마지막으로_매칭한_조합을_복원한다() async throws {
        let storage = LockIsolated<MatchCategory?>(nil)
        let (store, catalog) = try await makeLoadedStore(storage: storage)
        await select(ballad2010s, in: store)
        await store.send(.matchButtonTapped) {
            $0.phase = .matching(requestID: "00000000-0000-0000-0000-000000000000")
        }
        await store.receive(\.delegate.requestMatch)
        await store.finish()

        // App은 방에서 로비로 돌아올 때 새 State를 만든다 (design 8 "로비로 전환").
        let reentered = makeStore(catalog: .returning(catalog), storage: storage)
        await reentered.send(.onAppear) {
            $0.catalog = .available(catalog)
            $0.selection = self.ballad2010s
        }
    }

    func test_매칭하지_않고_바꾼_조합은_저장하지_않는다() async throws {
        let storage = LockIsolated<MatchCategory?>(nil)
        let (store, catalog) = try await makeLoadedStore(storage: storage)
        await select(ballad2010s, in: store)
        XCTAssertNil(storage.value)

        let reentered = makeStore(catalog: .returning(catalog), storage: storage)
        await reentered.send(.onAppear) {
            $0.catalog = .available(catalog)
        }
        XCTAssertEqual(reentered.state.selection, allAny)
    }

    // MARK: - 헬퍼

    private func enabledValues(_ state: LobbyReducer.State, _ axis: Axis) -> [String] {
        state.candidates(for: axis).filter(\.isEnabled).map(\.value)
    }

    private func assertUnavailable(_ state: LobbyReducer.State, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertTrue(state.isUnavailable, file: file, line: line)
        XCTAssertFalse(state.isMatchButtonEnabled, file: file, line: line)
        XCTAssertEqual(state.selection, allAny, file: file, line: line)
        for axis in Axis.allCases {
            XCTAssertEqual(state.candidates(for: axis), [], file: file, line: line)
        }
    }
}
// swiftlint:enable file_length type_body_length
