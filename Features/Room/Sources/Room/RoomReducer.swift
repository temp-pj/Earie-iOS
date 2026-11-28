//
//  RoomReducer.swift
//  FeatureRoom
//
//  Created by 송지혁 on 5/12/26.
//

import ClientAudio
import ComposableArchitecture
import Foundation
import Models
import OSLog

/// 방 대기, 나가는 중, 게임, 결과를 맡는다 (design 3, 5, 6).
///
/// 연결과 송신, 메시지 거르기는 하지 않는다. App이 거르기를 통과한 이벤트를 `.server`로 넣고,
/// 서버로 보낼 메시지는 `.delegate(.send)`로 App에 넘긴다. ROOM_LEFT와 PLAYER_KICKED는 App이 직접 처리한다.
@Reducer
public struct RoomReducer {
    public init() { }

    @ObservableState
    public struct State: Equatable {
        public var roomID: String
        public var myPlayerID: String
        public var hostID: String
        /// 서버 접수 순서 (REQ-ROOM-01)
        public var players: [String]
        public var maxPlayers: Int
        /// 확정된 방 조건 (wire 값)
        public var category: MatchCategory
        /// 확정된 방 조건의 표시용 이름. 부모가 카탈로그로 만들어 넘긴다.
        public var categoryLabel: CategoryLabel
        /// 나를 뺀 참가자의 참가 순서. 나간 참가자도 빼지 않아 "상대 N" 번호가 바뀌지 않는다.
        public var opponentOrder: [String]
        public var stage: Stage
        public var isLeaving: Bool
        /// START_GAME을 보내고 GAME_STARTED나 ROOM_COMMAND_FAILED를 기다리는 중 (REQ-ROOM-09)
        public var isStartRequesting: Bool
        public var game: GameReducer.State?
        /// 명령 실패 알럿과 게임 중 나가기 확인창
        @Presents public var alert: AlertState<Action.Alert>?

        public init(
            roomID: String,
            myPlayerID: String,
            hostID: String,
            players: [String],
            maxPlayers: Int,
            category: MatchCategory,
            categoryLabel: CategoryLabel,
            opponentOrder: [String]? = nil,
            stage: Stage = .waiting,
            isLeaving: Bool = false,
            isStartRequesting: Bool = false,
            game: GameReducer.State? = nil,
            alert: AlertState<Action.Alert>? = nil
        ) {
            self.roomID = roomID
            self.myPlayerID = myPlayerID
            self.hostID = hostID
            self.players = players
            self.maxPlayers = maxPlayers
            self.category = category
            self.categoryLabel = categoryLabel
            self.opponentOrder = opponentOrder ?? players.filter { $0 != myPlayerID }
            self.stage = stage
            self.isLeaving = isLeaving
            self.isStartRequesting = isStartRequesting
            self.game = game
            self.alert = alert
        }

        /// 활성 요청의 WELCOME으로 방을 만든다 (REQ-MATCH-07). WELCOME의 형식 검증은 `MessageCodec`이 이미 했다.
        /// `categoryLabel`은 `welcome.category`의 표시용 이름이다. Room은 카탈로그를 모른다.
        public init(welcome: WireV1.WelcomePayload, categoryLabel: CategoryLabel) {
            self.init(
                roomID: welcome.roomID,
                myPlayerID: welcome.playerID,
                hostID: welcome.hostID,
                players: welcome.players,
                maxPlayers: welcome.maxPlayers,
                category: welcome.category,
                categoryLabel: categoryLabel
            )
        }

        public var isHost: Bool { hostID == myPlayerID }

        /// REQ-ROOM-03: 내가 방장이고, 2명 이상이고, 대기 상태이고, 나가는 중이 아닐 때만.
        /// REQ-ROOM-09: 시작 요청 중에도 비활성
        public var canStart: Bool {
            isHost && players.count >= 2 && stage == .waiting && !isLeaving && !isStartRequesting
        }

        /// REQ-ROOM-06: 나가는 중에는 나가기를 다시 보내지 않는다
        public var canLeave: Bool { !isLeaving }

        /// GAME_OVER의 승자. 빈 문자열이면 승자 없음 (REQ-GAME-04)
        public var winnerID: String? {
            guard case .finished(let result) = stage, !result.winner.isEmpty else { return nil }
            return result.winner
        }

        public var winnerLabel: PlayerLabel? {
            guard case .finished(let result) = stage, let winnerID else { return nil }
            return playerLabels(for: result)[winnerID]
        }

        /// 결과 화면의 점수. 서버 참가자 순서를 따르고, 목록에 없는 플레이어는 뒤에 ID 순으로 붙인다.
        public var scoreboard: [Score] {
            guard case .finished(let result) = stage else { return [] }
            let labels = playerLabels(for: result)
            let ordered = players.filter { result.scores[$0] != nil }
            let others = result.scores.keys.filter { !players.contains($0) }.sorted()
            return (ordered + others).compactMap { playerID in
                guard let score = result.scores[playerID], let label = labels[playerID] else { return nil }
                return Score(playerID: playerID, label: label, score: score)
            }
        }

        /// 참가자 표시: 나는 `.myself`, 다른 참가자는 참가 순서대로 `.opponent(1)`, `.opponent(2)`, ...
        public func playerLabel(_ playerID: String) -> PlayerLabel? {
            if playerID == myPlayerID { return .myself }
            return opponentOrder.firstIndex(of: playerID).map { .opponent($0 + 1) }
        }

        /// 결과에만 있고 참가 기록에 없는 플레이어는 참가 순서 뒤에 ID 순으로 번호를 잇는다.
        private func playerLabels(for result: GameResult) -> [String: PlayerLabel] {
            let resultIDs = Set(result.scores.keys).union(result.winner.isEmpty ? [] : [result.winner])
            let unknown = resultIDs.filter { $0 != myPlayerID && !opponentOrder.contains($0) }.sorted()
            var labels: [String: PlayerLabel] = [myPlayerID: .myself]
            for (index, playerID) in (opponentOrder + unknown).enumerated() {
                labels[playerID] = .opponent(index + 1)
            }
            return labels
        }

        /// GAME_ABORTED 사유별 문구 (REQ-GAME-05)
        public var abortMessage: String? {
            guard case .aborted(let reason) = stage else { return nil }
            return RoomCopy.abortMessage(reason)
        }
    }

    public enum Stage: Equatable, Sendable {
        case waiting
        case playing
        case finished(GameResult)
        case aborted(AbortReason)
    }

    public struct Score: Equatable, Sendable, Identifiable {
        public let playerID: String
        public let label: PlayerLabel
        public let score: Int
        public var id: String { playerID }
    }

    /// 확정 조합의 표시용 이름. `MatchCategory`와 같은 네 축이다.
    public struct CategoryLabel: Equatable, Sendable {
        public var decade: String
        public var artistType: String
        public var gender: String
        public var genre: String

        public init(decade: String, artistType: String, gender: String, genre: String) {
            self.decade = decade
            self.artistType = artistType
            self.gender = gender
            self.genre = genre
        }
    }

    /// 참가자 표시. 문구는 RoomView가 정한다.
    public enum PlayerLabel: Equatable, Sendable {
        case myself
        /// 참가 순서 번호 (1부터)
        case opponent(Int)
    }

    public enum Action {
        /// App이 거르기를 통과시킨 현재 방의 이벤트
        case server(RoomServerEvent)
        case startTapped
        case leaveTapped
        case preloadFailed(roundNumber: Int)
        case game(GameReducer.Action)
        case alert(PresentationAction<Alert>)
        case delegate(Delegate)

        @CasePathable
        public enum Alert: Equatable, Sendable {
            case confirmLeave
        }

        @CasePathable
        public enum Delegate: Equatable, Sendable {
            /// App이 현재 연결로 보낸다
            case send(ClientMessage)
        }
    }

    /// Room이 직접 시작하는 효과. Game의 효과는 `GameReducer.CancelID`.
    public enum CancelID: Hashable, Sendable {
        /// PRELOAD_SONG 곡 준비와 그 뒤의 READY_TO_PLAY
        case preload
    }

    /// 곡 준비 제한 시간 (design 8)
    static let preloadTimeLimit: TimeInterval = 30

    @Dependency(\.audioClient) var audioClient

    public var body: some ReducerOf<Self> {
        Reduce { state, action in
            switch action {
            case .server(let event):
                return handle(event, state: &state)

            case .startTapped:
                guard state.canStart else { return .none }
                state.isStartRequesting = true
                return .send(.delegate(.send(.startGame(roomID: state.roomID))))

            case .leaveTapped:
                guard state.canLeave else { return .none }
                if state.stage == .playing {
                    state.alert = RoomCopy.confirmLeaveAlert
                    return .none
                }
                return leave(&state)

            case .alert(.presented(.confirmLeave)):
                guard state.canLeave else { return .none }
                return leave(&state)

            case .alert:
                return .none

            case .preloadFailed(let roundNumber):
                // REQ-GAME-02: READY_TO_PLAY를 보내지 않고 서버의 GAME_ABORTED를 기다린다
                Self.logger.error("곡 준비 실패, READY_TO_PLAY 보내지 않음 (round \(roundNumber))")
                return .none

            case .game(.delegate(.submitAnswer(let answer))):
                return .send(.delegate(.send(.submitAnswer(roomID: state.roomID, answer: answer))))

            case .game(.delegate(.playMusic)):
                return .run { _ in try await audioClient.play() }

            case .game(.delegate(.stopMusic)):
                return stopMusic()

            case .game:
                return .none

            case .delegate:
                return .none
            }
        }
        .ifLet(\.game, action: \.game) { GameReducer() }
        .ifLet(\.$alert, action: \.alert)
    }

    private func handle(_ event: RoomServerEvent, state: inout State) -> Effect<Action> {
        switch event {
        case .playerJoined(let playerID):
            if !state.players.contains(playerID) {
                state.players.append(playerID)
            }
            if playerID != state.myPlayerID, !state.opponentOrder.contains(playerID) {
                state.opponentOrder.append(playerID)
            }
            return .none

        case .playerLeft(let playerID):
            state.players.removeAll { $0 == playerID }
            return .none

        case .hostChanged(let playerID):
            state.hostID = playerID
            return .none

        case .commandFailed(let code):
            state.isStartRequesting = false
            state.alert = RoomCopy.commandFailedAlert(code)
            return .none

        case .gameStarted, .preloadSong, .game, .gameOver, .gameAborted:
            return handleGame(event, state: &state)
        }
    }

    private func handleGame(_ event: RoomServerEvent, state: inout State) -> Effect<Action> {
        switch event {
        case .gameStarted:
            // REQ-ROOM-09: 시작 응답으로 시작 요청 중을 푼다
            state.isStartRequesting = false
            // 게임·결과 중의 GAME_STARTED는 무시 (requirements 8). 나가는 중이면 그 상태를 유지한다 (EDGE-13)
            guard state.stage == .waiting else { return .none }
            state.stage = .playing
            state.game = GameReducer.State()
            return .none

        case .preloadSong(let isrc, let startTime, let roundNumber):
            guard state.stage == .playing else { return .none }
            return preload(isrc: isrc, startTime: startTime, roundNumber: roundNumber, roomID: state.roomID)

        case .game(let gameEvent):
            guard state.stage == .playing, state.game != nil else { return .none }
            return .send(.game(.serverEvent(gameEvent)))

        case .gameOver(let result):
            return endGame(.finished(result), state: &state)

        case .gameAborted(let reason):
            return endGame(.aborted(reason), state: &state)

        case .playerJoined, .playerLeft, .hostChanged, .commandFailed:
            return .none
        }
    }

    /// REQ-GAME-02: 준비가 끝나면 READY_TO_PLAY, 실패하면 보내지 않는다
    private func preload(isrc: String, startTime: Int, roundNumber: Int, roomID: String) -> Effect<Action> {
        .run { send in
            do {
                try await audioClient.preload(isrc, TimeInterval(startTime), Self.preloadTimeLimit)
            } catch is CancellationError {
                return
            } catch {
                await send(.preloadFailed(roundNumber: roundNumber))
                return
            }
            await send(.delegate(.send(.readyToPlay(roomID: roomID, roundNumber: roundNumber))))
        }
        .cancellable(id: CancelID.preload, cancelInFlight: true)
    }

    /// GAME_OVER, GAME_ABORTED: 게임 중일 때만 결과로 바꾼다. 게임 상태를 버리고(페널티 타이머 취소)
    /// 곡 준비를 취소하고 음악을 멈춘다 (design 12). 결과 화면에서 다시 오면 무시한다 (requirements 8).
    private func endGame(_ result: Stage, state: inout State) -> Effect<Action> {
        guard state.stage == .playing else { return .none }
        state.stage = result
        state.game = nil
        return .merge(.cancel(id: CancelID.preload), stopMusic())
    }

    /// REQ-ROOM-05: LEAVE_ROOM을 보내고 나가는 중이 된다. 화면 전환은 App이 ROOM_LEFT로 한다.
    private func leave(_ state: inout State) -> Effect<Action> {
        state.isLeaving = true
        return .send(.delegate(.send(.leaveRoom(roomID: state.roomID))))
    }

    private func stopMusic() -> Effect<Action> {
        .run { _ in
            do {
                try await audioClient.stop()
            } catch {
                Self.logger.error("음악 정지 실패: \(String(describing: error))")
            }
        }
    }

    private static let logger = Logger(subsystem: "M_GAME", category: "FeatureRoom")
}
