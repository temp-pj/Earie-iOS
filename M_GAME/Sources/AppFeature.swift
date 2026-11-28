import ClientAudio
import ClientMusicEntitlement
import ClientSession
import ComposableArchitecture
import FeatureLobby
import FeatureRoom
import Foundation
import Models
import OSLog

/// 앱 최상위: 연결 수명, 스트림 단일 소비, 메시지 거르기와 라우팅, 송신, 화면 단계 전환, 알럿 (design 3, 8, 9).
///
/// 비교할 ID의 원본은 Feature 상태에 있다 (design 5). 활성 requestID는 `LobbyReducer.State.activeRequestID`,
/// 현재 roomID와 나가는 중 여부는 `RoomReducer.State`. App은 따로 들고 있지 않다.
@Reducer
struct AppFeature {
    @ObservableState
    struct State: Equatable {
        var connection: Connection = .disconnected
        /// 로비와 방 중 정확히 하나 (INV-01)
        var phase: Phase = .lobby(LobbyReducer.State())
        /// 화면 전환을 동반하는 알럿. 문구는 `AppCopy`가 정한다.
        var alert: AppAlert?
    }

    /// 연결 상태와 연결 세대. 세대는 연결을 시작할 때마다 새로 만든다 (design 6, 9).
    enum Connection: Equatable {
        case disconnected
        case connecting(generation: UUID)
        case connected(generation: UUID)

        var generation: UUID? {
            switch self {
            case .disconnected: nil
            case let .connecting(generation), let .connected(generation): generation
            }
        }
    }

    enum Phase: Equatable {
        case lobby(LobbyReducer.State)
        case room(RoomReducer.State)

        /// `ifLet`용. 현재 단계가 로비일 때만 값이 있고, 로비일 때만 쓴다.
        var lobby: LobbyReducer.State? {
            get {
                guard case let .lobby(state) = self else { return nil }
                return state
            }
            set {
                guard case .lobby = self, let newValue else { return }
                self = .lobby(newValue)
            }
        }

        /// `ifLet`용. 현재 단계가 방일 때만 값이 있고, 방일 때만 쓴다.
        /// 단계가 로비로 바뀌면 `ifLet`이 Room·Game 효과를 취소한다 (design 12).
        var room: RoomReducer.State? {
            get {
                guard case let .room(state) = self else { return nil }
                return state
            }
            set {
                guard case .room = self, let newValue else { return }
                self = .room(newValue)
            }
        }
    }

    enum AppAlert: Hashable, Identifiable, Sendable {
        /// REQ-FAIL-01
        case matchFailed(MatchFailureCode)
        /// REQ-FAIL-02
        case disconnected
        /// REQ-ROOM-07
        case kicked

        var id: Self { self }
    }

    enum Action {
        case onAppear
        case lobby(LobbyReducer.Action)
        case room(RoomReducer.Action)
        /// 연결 효과가 스트림 순서대로 보낸다 (INV-07)
        case session(generation: UUID, event: SessionEvent)
        case connectTimedOut(generation: UUID)
        case sendFailed(generation: UUID)
        case alertDismissed
    }

    enum CancelID: Hashable, Sendable {
        /// 연결 스트림 소비 효과 (동시에 1개, design 12)
        case connection
        /// 연결 시도 타이머 (동시에 1개, design 12)
        case connectTimeout
    }

    /// REQ-FAIL-05
    static let connectTimeout: Duration = .seconds(10)

    @Dependency(\.audioClient) var audioClient
    @Dependency(\.continuousClock) var clock
    @Dependency(\.musicEntitlementClient) var musicEntitlementClient
    @Dependency(\.sessionClient) var sessionClient
    @Dependency(\.uuid) var uuid

    var body: some ReducerOf<Self> {
        Reduce { state, action in
            switch action {
            case .onAppear:
                return .run { _ in
                    await musicEntitlementClient.requestAuthorization()
                }

            case let .lobby(.delegate(.requestMatch(requestID, category, catalogVersion))):
                return requestMatch(
                    WireV1.MatchRequestPayload(requestID: requestID, catalogVersion: catalogVersion, category: category),
                    state: &state
                )

            case let .lobby(.delegate(.cancelMatch(requestID))):
                // 연결 중이면 요청도 나가지 않았으므로 보내지 않는다 (REQ-CANCEL-04, design 9)
                guard case let .connected(generation) = state.connection else { return .none }
                return send(.matchCancel(requestID: requestID), generation: generation)

            case .lobby:
                return .none

            case let .room(.delegate(.send(message))):
                guard case let .connected(generation) = state.connection else {
                    Self.logger.error("연결 없이 방 메시지 송신 시도, 버림: \(message.type, privacy: .public)")
                    return .none
                }
                return send(message, generation: generation)

            case .room:
                return .none

            case let .session(generation, event):
                // INV-08: 현재 세대가 아닌 연결의 이벤트는 버린다 (design 9 "이전 세대 이벤트")
                guard generation == state.connection.generation else {
                    Self.logger.debug("이전 세대 이벤트 무시")
                    return .none
                }
                return handle(event, generation: generation, state: &state)

            case let .connectTimedOut(generation):
                guard state.connection == .connecting(generation: generation) else { return .none }
                // design 11: 연결 끊김과 같게 처리하고, 해당 세대 효과를 취소한 뒤 disconnect
                return .concatenate(
                    connectionLost(state: &state),
                    .run { _ in await sessionClient.disconnect() }
                )

            case let .sendFailed(generation):
                // design 8 "송신 실패": 현재 세대 연결 끊김과 같게 처리
                guard generation == state.connection.generation else { return .none }
                return connectionLost(state: &state)

            case .alertDismissed:
                state.alert = nil
                return .none
            }
        }
        .ifLet(\.phase.lobby, action: \.lobby) { LobbyReducer() }
        .ifLet(\.phase.room, action: \.room) { RoomReducer() }
    }

    // MARK: - 연결

    /// design 8 "매칭 요청", 9번 표 `requestMatch` 열
    private func requestMatch(_ payload: WireV1.MatchRequestPayload, state: inout State) -> Effect<Action> {
        switch state.connection {
        case let .connected(generation):
            return send(.matchRequest(payload), generation: generation)
        case .connecting:
            // 연결되면 로비의 활성 요청으로 보낸다
            return .none
        case .disconnected:
            return connect(state: &state)
        }
    }

    private func connect(state: inout State) -> Effect<Action> {
        let generation = uuid()
        state.connection = .connecting(generation: generation)
        return .merge(
            .run { send in
                // INV-06: 스트림을 소비하는 곳은 이 효과 하나뿐이다
                let events = await sessionClient.connect()
                for await event in events {
                    await send(.session(generation: generation, event: event))
                }
            }
            .cancellable(id: CancelID.connection, cancelInFlight: true),
            .run { send in
                try await clock.sleep(for: Self.connectTimeout)
                await send(.connectTimedOut(generation: generation))
            }
            .cancellable(id: CancelID.connectTimeout, cancelInFlight: true)
        )
    }

    private func handle(_ event: SessionEvent, generation: UUID, state: inout State) -> Effect<Action> {
        switch event {
        case .connected:
            guard case .connecting = state.connection else { return .none }
            state.connection = .connected(generation: generation)
            // design 8 "연결 완료": 로비가 매칭 중이면 그 요청을 보낸다
            guard let lobby = state.phase.lobby,
                  let requestID = lobby.activeRequestID,
                  case let .available(catalog) = lobby.catalog
            else { return .cancel(id: CancelID.connectTimeout) }
            let payload = WireV1.MatchRequestPayload(
                requestID: requestID,
                catalogVersion: catalog.version,
                category: lobby.selection
            )
            return .merge(
                .cancel(id: CancelID.connectTimeout),
                send(.matchRequest(payload), generation: generation)
            )

        case let .message(message):
            guard case .connected = state.connection else {
                Self.logger.debug("연결 전 메시지 무시: \(message.type, privacy: .public)")
                return .none
            }
            return route(message, state: &state)

        case .disconnected:
            return connectionLost(state: &state)
        }
    }

    /// REQ-FAIL-02, design 9 `.disconnected` 열. 매칭 대기나 방이면 알럿과 조건 선택, 아니면 연결 상태만 바꾼다.
    private func connectionLost(state: inout State) -> Effect<Action> {
        state.connection = .disconnected
        let cleanup: Effect<Action> = .merge(
            .cancel(id: CancelID.connection),
            .cancel(id: CancelID.connectTimeout)
        )
        switch state.phase {
        case let .lobby(lobby):
            guard lobby.activeRequestID != nil else { return cleanup }
            state.alert = .disconnected
            return .merge(cleanup, .send(.lobby(.matchEnded)))
        case .room:
            state.alert = .disconnected
            return .merge(cleanup, returnToLobby(state: &state))
        }
    }

    private func send(_ message: ClientMessage, generation: UUID) -> Effect<Action> {
        .run { send in
            do {
                try await sessionClient.send(message)
            } catch {
                Self.logger.error("송신 실패: \(message.type, privacy: .public)")
                await send(.sendFailed(generation: generation))
            }
        }
    }

    // MARK: - 거르기와 라우팅

    /// design 8 "수신과 라우팅", REQ-FILTER-01~03
    private func route(_ message: ServerMessage, state: inout State) -> Effect<Action> {
        switch message {
        case .matchWaiting, .matchCancelled, .matchFailed, .welcome:
            return routeMatch(message, state: &state)
        case .roomLeft, .playerKicked, .playerJoined, .playerLeft, .hostChanged, .gameStarted, .preloadSong,
             .roundStarted, .countDown, .wrongAnswer, .roundResult, .gameOver, .gameAborted, .roomCommandFailed:
            return routeRoom(message, state: &state)
        }
    }

    /// REQ-FILTER-01: requestID가 활성 요청과 같을 때만
    private func routeMatch(_ message: ServerMessage, state: inout State) -> Effect<Action> {
        switch message {
        case let .matchWaiting(payload), let .matchCancelled(payload):
            // REQ-MATCH-06: 활성 요청이어도 화면을 바꾸지 않는다
            guard isActiveRequest(payload.requestID, state: state) else { return ignore(message) }
            return .none

        case let .matchFailed(payload):
            guard isActiveRequest(payload.requestID, state: state) else { return ignore(message) }
            state.alert = .matchFailed(payload.code)
            return .send(.lobby(.matchEnded))

        case let .welcome(payload):
            guard isActiveRequest(payload.requestID, state: state), let lobby = state.phase.lobby else {
                return ignore(message)
            }
            // REQ-MATCH-07
            state.phase = .room(RoomReducer.State(
                welcome: payload,
                categoryLabel: AppCopy.categoryLabel(payload.category, lobby: lobby)
            ))
            return .none

        default:
            return ignore(message)
        }
    }

    /// REQ-FILTER-02: roomID가 현재 방과 같을 때만
    private func routeRoom(_ message: ServerMessage, state: inout State) -> Effect<Action> {
        switch message {
        case let .roomLeft(payload):
            // REQ-FILTER-02: 나가는 중인 현재 방의 ROOM_LEFT만 (EDGE-08)
            guard let room = state.phase.room, room.roomID == payload.roomID, room.isLeaving else {
                return ignore(message)
            }
            return returnToLobby(state: &state)

        case let .playerKicked(payload):
            guard let room = state.phase.room, room.roomID == payload.roomID else { return ignore(message) }
            // REQ-ROOM-07
            state.alert = .kicked
            return returnToLobby(state: &state)

        default:
            guard case let (roomID, event)? = message.roomEvent,
                  let room = state.phase.room, room.roomID == roomID
            else { return ignore(message) }
            return .send(.room(.server(event)))
        }
    }

    private func isActiveRequest(_ requestID: String, state: State) -> Bool {
        guard let activeRequestID = state.phase.lobby?.activeRequestID else { return false }
        return activeRequestID == requestID
    }

    /// REQ-FILTER-03: 거른 메시지는 로그만 남긴다
    private func ignore(_ message: ServerMessage) -> Effect<Action> {
        Self.logger.debug("거른 메시지: \(message.type, privacy: .public)")
        return .none
    }

    /// design 8 "로비로 전환": 새 로비 상태, 음악 정지. Room·Game 효과는 방 상태가 없어지며 `ifLet`이 취소한다.
    /// 연결은 닫지 않는다 (REQ-FAIL-03, INV-09).
    private func returnToLobby(state: inout State) -> Effect<Action> {
        state.phase = .lobby(LobbyReducer.State())
        return .run { _ in
            do {
                try await audioClient.stop()
            } catch {
                Self.logger.error("음악 정지 실패: \(String(describing: error), privacy: .public)")
            }
        }
    }

    private static let logger = Logger(subsystem: "M_GAME", category: "AppFeature")
}
