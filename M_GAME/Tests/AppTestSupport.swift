@testable import M_GAME

import ClientAudio
import ClientCatalogTest
import ClientSession
import ClientSessionTest
import ComposableArchitecture
import FeatureLobby
import FeatureRoom
import Foundation
import Models
import XCTest

/// 테스트에서 쓰는 ID. 모두 소문자 canonical UUID v4다.
enum TestID {
    static let room1 = "22222222-2222-4222-8222-222222222222"
    static let room2 = "55555555-5555-4555-8555-555555555555"
    static let myself = "33333333-3333-4333-8333-333333333333"
    static let opponent = "44444444-4444-4444-8444-444444444444"
    static let newcomer = "66666666-6666-4666-8666-666666666666"

    /// `UUIDGenerator.incrementing`가 n번째로 만든 값의 소문자 문자열 (로비의 requestID)
    static func request(_ index: Int) -> String {
        UUID(index).uuidString.lowercased()
    }
}

enum AppFixtures {
    /// `docs/specs/random-matchmaking/fixtures/catalog-projection.json` (test-v1)
    static func testV1() throws -> CatalogProjection {
        let bundle = Bundle(for: BundleToken.self)
        let url = try XCTUnwrap(
            bundle.url(forResource: "catalog-projection", withExtension: "json"),
            "catalog-projection.json이 M_GAMETests 리소스에 없다"
        )
        return try JSONDecoder().decode(CatalogProjection.self, from: Data(contentsOf: url))
    }

    static let allAny = MatchCategory(decade: "any", artistType: "any", gender: "any", genre: "any")
    static let roomCategory = MatchCategory(decade: "2010s", artistType: "all", gender: "all", genre: "korean_ballad")

    static func welcome(
        requestID: String,
        roomID: String = TestID.room1,
        players: [String] = [TestID.myself, TestID.opponent],
        hostID: String = TestID.myself
    ) -> WireV1.WelcomePayload {
        WireV1.WelcomePayload(
            requestID: requestID,
            roomID: roomID,
            playerID: TestID.myself,
            hostID: hostID,
            players: players,
            roomState: "waiting",
            maxPlayers: 8,
            category: roomCategory,
            catalogVersion: "test-v1"
        )
    }

    /// test-v1 카탈로그에서 `roomCategory`의 방 화면 이름
    static let roomCategoryLabel = RoomReducer.CategoryLabel(
        decade: "2010s",
        artistType: "전체",
        gender: "전체",
        genre: "Synthetic ballad (test only)"
    )

    static func roomState(
        _ welcome: WireV1.WelcomePayload
    ) -> RoomReducer.State {
        RoomReducer.State(welcome: welcome, categoryLabel: roomCategoryLabel)
    }

    private final class BundleToken {}
}

/// 음악 정지 호출 수와 곡 준비 취소를 기록하는 `AudioClient`
final class AudioSpy: Sendable {
    let stopCount = LockIsolated(0)
    let preloadStarted = LockIsolated(false)
    let preloadCancelled = LockIsolated(false)

    /// 곡 준비는 취소될 때까지 끝나지 않는다.
    var client: AudioClient {
        AudioClient(
            preload: { [preloadStarted, preloadCancelled] _, _, _ in
                preloadStarted.setValue(true)
                do {
                    try await Task.never()
                } catch {
                    preloadCancelled.setValue(true)
                    throw error
                }
            },
            play: {},
            stop: { [stopCount] in stopCount.withValue { $0 += 1 } },
            playbackState: { AsyncStream { $0.finish() } }
        )
    }
}

/// App 테스트 환경 하나: store, 테스트 세션, 시계, 오디오
@MainActor
struct AppHarness {
    let store: TestStoreOf<AppFeature>
    let session: TestSessionClient
    let clock: TestClock<Duration>
    let audio: AudioSpy
    let catalog: CatalogProjection

    init(phase: AppFeature.Phase? = nil, connection: AppFeature.Connection = .disconnected) throws {
        let catalog = try AppFixtures.testV1()
        let session = TestSessionClient()
        let clock = TestClock()
        let audio = AudioSpy()
        let initial = AppFeature.State(
            connection: connection,
            phase: phase ?? .lobby(LobbyReducer.State(catalog: .available(catalog)))
        )
        self.store = TestStore(initialState: initial) {
            AppFeature()
        } withDependencies: {
            $0.sessionClient = session.client
            $0.catalogClient = .returning(catalog)
            $0.categoryPreferenceClient = .inMemory()
            $0.audioClient = audio.client
            $0.continuousClock = clock
            $0.uuid = .incrementing
        }
        self.session = session
        self.clock = clock
        self.audio = audio
        self.catalog = catalog
    }

    var matchRequest0: ClientMessage {
        .matchRequest(WireV1.MatchRequestPayload(
            requestID: TestID.request(0),
            catalogVersion: catalog.version,
            category: AppFixtures.allAny
        ))
    }

    /// 송신 효과가 실행될 기회를 준 뒤 보낸 메시지를 돌려준다.
    func sent() async -> [ClientMessage] {
        await Task.megaYield()
        return session.sentMessages
    }

    /// 매칭 탭(requestID 0) → 새 연결(세대 1)
    func tapMatchFromDisconnected() async {
        await store.send(.lobby(.matchButtonTapped)) {
            $0.phase.lobby?.phase = .matching(requestID: TestID.request(0))
        }
        await store.receive(\.lobby.delegate.requestMatch) {
            $0.connection = .connecting(generation: UUID(1))
        }
    }

    /// 매칭 탭 → 연결 완료 → MATCH_REQUEST
    func matchAndConnect() async {
        await tapMatchFromDisconnected()
        session.yield(.connected, connection: 0)
        await store.receive(\.session) {
            $0.connection = .connected(generation: UUID(1))
        }
    }

    /// 매칭 → 연결 → WELCOME으로 방 입장
    func enterRoom(_ welcome: WireV1.WelcomePayload? = nil) async {
        await matchAndConnect()
        let welcome = welcome ?? AppFixtures.welcome(requestID: TestID.request(0))
        session.yield(.message(.welcome(welcome)), connection: 0)
        await store.receive(\.session) {
            $0.phase = .room(AppFixtures.roomState(welcome))
        }
    }

    /// 현재 연결에 서버 메시지를 넣고 `.session` 액션을 받는다.
    func receive(
        _ message: ServerMessage,
        connection: Int = 0,
        assert updateStateToExpectedResult: ((inout AppFeature.State) throws -> Void)? = nil
    ) async {
        session.yield(.message(message), connection: connection)
        await store.receive(\.session, assert: updateStateToExpectedResult)
    }

    /// 연결 시도를 마친 뒤 테스트 스트림을 닫고, 다른 효과까지 모두 종료됐는지 확인한다.
    func finish() async {
        if case let .connecting(generation) = store.state.connection {
            session.yield(.connected)
            await store.receive(\.session) {
                $0.connection = .connected(generation: generation)
            }
        }
        for index in 0..<session.connectCount {
            session.finish(connection: index)
        }
        await store.finish()
    }
}
