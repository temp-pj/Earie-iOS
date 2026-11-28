//
//  RoomReducerTests.swift
//  FeatureRoom
//
//  Created by 송지혁 on 5/15/26.
//

@testable import FeatureRoom

import ComposableArchitecture
import Foundation
import Models
import XCTest

// swiftlint:disable file_length
@MainActor
final class RoomReducerTests: XCTestCase {
    // MARK: - WELCOME으로 만든 상태 (REQ-MATCH-07, REQ-ROOM-01)

    func test_WELCOME으로_방_상태를_만든다() {
        let welcome = WireV1.WelcomePayload.fixture(hostID: TestID.other, players: [TestID.other, TestID.myself])

        let state = RoomReducer.State(welcome: welcome)

        XCTAssertEqual(state.roomID, TestID.room)
        XCTAssertEqual(state.myPlayerID, TestID.myself)
        XCTAssertEqual(state.hostID, TestID.other)
        XCTAssertEqual(state.players, [TestID.other, TestID.myself])
        XCTAssertEqual(state.maxPlayers, 8)
        XCTAssertEqual(state.category, .roomFixture)
        XCTAssertEqual(state.stage, .waiting)
        XCTAssertFalse(state.isLeaving)
        XCTAssertFalse(state.isStartRequesting)
        XCTAssertNil(state.game)
        XCTAssertNil(state.alert)
        XCTAssertFalse(state.isHost)
    }

    // MARK: - 참가자·방장 갱신 (REQ-ROOM-02, EDGE-06)

    func test_PLAYER_JOINED는_서버_순서대로_뒤에_붙는다() async {
        let store = makeStore()

        await store.send(.server(.playerJoined(playerID: TestID.third))) {
            $0.players = [TestID.myself, TestID.other, TestID.third]
        }
        // 이미 있는 참가자는 다시 넣지 않는다
        await store.send(.server(.playerJoined(playerID: TestID.other)))
    }

    func test_PLAYER_LEFT는_목록에서_뺀다() async {
        let store = makeStore(RoomReducer.State(welcome: .fixture(players: [TestID.myself, TestID.other, TestID.third])))

        await store.send(.server(.playerLeft(playerID: TestID.other))) {
            $0.players = [TestID.myself, TestID.third]
        }
        // 없는 참가자는 변화 없음
        await store.send(.server(.playerLeft(playerID: TestID.other)))
    }

    func test_HOST_CHANGED는_방장을_바꾼다() async {
        let store = makeStore()

        await store.send(.server(.hostChanged(playerID: TestID.other))) {
            $0.hostID = TestID.other
        }
        XCTAssertFalse(store.state.isHost)
    }

    // MARK: - 시작 버튼 판정 (REQ-ROOM-03, EDGE-09, EDGE-10)

    func test_방장이고_2명_이상_대기_중이면_시작할_수_있다() async {
        let store = makeStore()
        XCTAssertTrue(store.state.canStart)

        await store.send(.startTapped) {
            $0.isStartRequesting = true
        }
        await store.receive(\.delegate.send, .startGame(roomID: TestID.room))
    }

    func test_방장_혼자면_시작할_수_없다() async {
        let store = makeStore(RoomReducer.State(welcome: .fixture(players: [TestID.myself])))
        XCTAssertFalse(store.state.canStart)

        await store.send(.startTapped)
    }

    func test_방장이_아니면_시작할_수_없다() async {
        let store = makeStore(RoomReducer.State(welcome: .fixture(hostID: TestID.other)))
        XCTAssertFalse(store.state.canStart)

        await store.send(.startTapped)
    }

    func test_나가는_중이거나_대기_상태가_아니면_시작할_수_없다() {
        var leaving = RoomReducer.State(welcome: .fixture())
        leaving.isLeaving = true
        XCTAssertFalse(leaving.canStart)

        XCTAssertFalse(playingState().canStart)

        var finished = RoomReducer.State(welcome: .fixture())
        finished.stage = .finished(GameResult(winner: "", scores: [:]))
        XCTAssertFalse(finished.canStart)

        var aborted = RoomReducer.State(welcome: .fixture())
        aborted.stage = .aborted(.internalError)
        XCTAssertFalse(aborted.canStart)
    }

    func test_혼자_남으면_시작_비활성_방에는_머문다() async {
        let store = makeStore()

        await store.send(.server(.playerLeft(playerID: TestID.other))) {
            $0.players = [TestID.myself]
        }
        XCTAssertFalse(store.state.canStart)
        XCTAssertEqual(store.state.stage, .waiting)
    }

    func test_방장이_나가서_내가_방장이_되면_시작할_수_있다() async {
        let store = makeStore(RoomReducer.State(welcome: .fixture(hostID: TestID.other, players: [TestID.other, TestID.myself, TestID.third])))
        XCTAssertFalse(store.state.canStart)

        await store.send(.server(.playerLeft(playerID: TestID.other))) {
            $0.players = [TestID.myself, TestID.third]
        }
        await store.send(.server(.hostChanged(playerID: TestID.myself))) {
            $0.hostID = TestID.myself
        }
        XCTAssertTrue(store.state.isHost)
        XCTAssertTrue(store.state.canStart)
    }

    // MARK: - 시작 요청 중 (REQ-ROOM-09)

    func test_시작을_연타해도_START_GAME은_한_번만_보낸다() async {
        let store = makeStore()

        await store.send(.startTapped) {
            $0.isStartRequesting = true
        }
        await store.receive(\.delegate.send, .startGame(roomID: TestID.room))
        XCTAssertFalse(store.state.canStart)

        await store.send(.startTapped)
        await store.send(.startTapped)
    }

    func test_ROOM_COMMAND_FAILED를_받으면_시작_요청_중이_풀려_다시_누를_수_있다() async {
        let store = makeStore()

        await store.send(.startTapped) {
            $0.isStartRequesting = true
        }
        await store.receive(\.delegate.send, .startGame(roomID: TestID.room))

        await store.send(.server(.commandFailed(.internalError))) {
            $0.isStartRequesting = false
            $0.alert = RoomCopy.commandFailedAlert(.internalError)
        }
        XCTAssertTrue(store.state.canStart)
        await store.send(.alert(.dismiss)) {
            $0.alert = nil
        }

        await store.send(.startTapped) {
            $0.isStartRequesting = true
        }
        await store.receive(\.delegate.send, .startGame(roomID: TestID.room))
    }

    func test_GAME_STARTED를_받으면_시작_요청_중이_풀린다() async {
        let store = makeStore()

        await store.send(.startTapped) {
            $0.isStartRequesting = true
        }
        await store.receive(\.delegate.send, .startGame(roomID: TestID.room))

        await store.send(.server(.gameStarted)) {
            $0.isStartRequesting = false
            $0.stage = .playing
            $0.game = GameReducer.State()
        }
    }

    // MARK: - 나가기와 나가는 중 (REQ-ROOM-05, 06, 08)

    func test_방_대기의_나가기는_확인창_없이_LEAVE_ROOM() async {
        let store = makeStore()

        await store.send(.leaveTapped) {
            $0.isLeaving = true
        }
        await store.receive(\.delegate.send, .leaveRoom(roomID: TestID.room))
        XCTAssertFalse(store.state.canStart)
        XCTAssertFalse(store.state.canLeave)
    }

    func test_나가는_중에는_나가기와_시작을_다시_보내지_않고_방_이벤트는_반영한다() async {
        var state = RoomReducer.State(welcome: .fixture())
        state.isLeaving = true
        let store = makeStore(state)

        await store.send(.leaveTapped)
        await store.send(.startTapped)

        await store.send(.server(.playerJoined(playerID: TestID.third))) {
            $0.players = [TestID.myself, TestID.other, TestID.third]
        }
        await store.send(.server(.hostChanged(playerID: TestID.other))) {
            $0.hostID = TestID.other
        }
    }

    func test_나가는_중에_GAME_STARTED가_오면_게임으로_바뀌고_나가는_중을_유지한다() async {
        var state = RoomReducer.State(welcome: .fixture())
        state.isLeaving = true
        let audio = AudioRecorder()
        let store = makeStore(state, audio: audio)

        await store.send(.server(.gameStarted)) {
            $0.stage = .playing
            $0.game = GameReducer.State()
        }
        XCTAssertTrue(store.state.isLeaving)

        // 나가는 중 게임 화면의 나가기도 다시 보내지 않는다 (확인창도 없음)
        await store.send(.leaveTapped)

        let result = GameResult(winner: TestID.myself, scores: [TestID.myself: 1])
        await store.send(.server(.gameOver(result))) {
            $0.stage = .finished(result)
            $0.game = nil
        }
        XCTAssertTrue(store.state.isLeaving)
        await store.finish()
        XCTAssertEqual(audio.stopCount.value, 1)
    }

    func test_게임_중_나가기는_확인창을_띄우고_확인하면_LEAVE_ROOM() async {
        let store = makeStore(playingState())

        await store.send(.leaveTapped) {
            $0.alert = RoomCopy.confirmLeaveAlert
        }
        XCTAssertEqual(store.state.alert?.title, TextState("게임에서 나갈까요?"))

        await store.send(.alert(.presented(.confirmLeave))) {
            $0.alert = nil
            $0.isLeaving = true
        }
        await store.receive(\.delegate.send, .leaveRoom(roomID: TestID.room))
        XCTAssertEqual(store.state.stage, .playing)
    }

    func test_게임_중_나가기_확인창에서_취소하면_아무것도_보내지_않는다() async {
        let store = makeStore(playingState())

        await store.send(.leaveTapped) {
            $0.alert = RoomCopy.confirmLeaveAlert
        }
        await store.send(.alert(.dismiss)) {
            $0.alert = nil
        }
        XCTAssertFalse(store.state.isLeaving)
    }

    func test_결과_화면의_나가기는_확인창_없이_LEAVE_ROOM() async {
        for stage in [RoomReducer.Stage.finished(GameResult(winner: "", scores: [:])), .aborted(.insufficientPlayers)] {
            var state = RoomReducer.State(welcome: .fixture())
            state.stage = stage
            let store = makeStore(state)

            await store.send(.leaveTapped) {
                $0.isLeaving = true
            }
            await store.receive(\.delegate.send, .leaveRoom(roomID: TestID.room))
        }
    }

    // MARK: - ROOM_COMMAND_FAILED (REQ-ROOM-04)

    func test_ROOM_COMMAND_FAILED는_코드별_문구로_알럿을_띄우고_방에_머문다() async {
        let cases: [(RoomFailureCode, String)] = [
            (.notHost, "방장만 게임을 시작할 수 있어요."),
            (.notEnoughPlayers, "2명 이상일 때 시작할 수 있어요."),
            (.invalidState, "지금은 게임을 시작할 수 없어요."),
            (.internalError, "게임을 시작하지 못했어요. 다시 시도해 주세요.")
        ]
        for (code, message) in cases {
            let store = makeStore()

            await store.send(.server(.commandFailed(code))) {
                $0.alert = RoomCopy.commandFailedAlert(code)
            }
            XCTAssertEqual(store.state.alert?.title, TextState(message), "\(code)")
            XCTAssertEqual(store.state.stage, .waiting)

            await store.send(.alert(.dismiss)) {
                $0.alert = nil
            }
        }
    }
}

@MainActor
final class RoomGameTests: XCTestCase {
    // MARK: - 곡 준비 (REQ-GAME-02, 03, EDGE-12)

    func test_곡_준비가_끝나면_같은_roomID와_roundNumber로_READY_TO_PLAY() async {
        let audio = AudioRecorder()
        let store = makeStore(playingState(), audio: audio)

        await store.send(.server(.preloadSong(isrc: "KRA381234567", startTime: 42, roundNumber: 3)))
        await store.receive(\.delegate.send, .readyToPlay(roomID: TestID.room, roundNumber: 3))

        XCTAssertEqual(audio.preloads.value, [.init(isrc: "KRA381234567", startTime: 42, timeLimit: 30)])
    }

    func test_곡_준비에_실패하면_READY_TO_PLAY를_보내지_않는다() async {
        let store = makeStore(playingState(), preloadError: PreloadFailure())

        await store.send(.server(.preloadSong(isrc: "KRA381234567", startTime: 0, roundNumber: 1)))
        await store.receive(\.preloadFailed, 1)
        // 서버의 GAME_ABORTED(INTERNAL_ERROR)를 기다린다
        await store.send(.server(.gameAborted(.internalError))) {
            $0.stage = .aborted(.internalError)
            $0.game = nil
        }
    }

    func test_게임_중이_아니면_PRELOAD_SONG을_무시한다() async {
        let audio = AudioRecorder()
        let store = makeStore(audio: audio)

        await store.send(.server(.preloadSong(isrc: "KRA381234567", startTime: 0, roundNumber: 1)))
        XCTAssertEqual(audio.preloads.value, [])
    }

    // MARK: - 게임 한 사이클 (REQ-GAME-01, 03, 04)

    func test_게임_한_사이클() async {
        let clock = TestClock()
        let audio = AudioRecorder()
        let store = makeStore(audio: audio, clock: clock)

        // 시작
        await store.send(.startTapped) {
            $0.isStartRequesting = true
        }
        await store.receive(\.delegate.send, .startGame(roomID: TestID.room))
        await store.send(.server(.gameStarted)) {
            $0.isStartRequesting = false
            $0.stage = .playing
            $0.game = GameReducer.State()
        }

        // 곡 준비
        await store.send(.server(.preloadSong(isrc: "KRA381234567", startTime: 10, roundNumber: 1)))
        await store.receive(\.delegate.send, .readyToPlay(roomID: TestID.room, roundNumber: 1))

        // 라운드 시작
        let roundData = RoundData(roundNumber: 1, totalRounds: 10, letterCards: ["그", "대", "만", "있", "다", "면"], answerLength: 3)
        await store.send(.server(.game(.roundStarted(roundData))))
        await store.receive(\.game.serverEvent) {
            $0.game?.roundData = roundData
            $0.game?.roundState = .playing
            $0.game?.inputState = .enabled
        }
        await store.receive(\.game.delegate.playMusic)
        await store.finish()
        XCTAssertEqual(audio.playCount.value, 1)

        // 카운트다운
        await store.send(.server(.game(.countDown(9))))
        await store.receive(\.game.serverEvent) {
            $0.game?.remainingTime = 9
        }

        // 제출 → SUBMIT_ANSWER(roomID)
        await store.send(.game(.selectLetter(3))) { $0.game?.selectedLetters = ["있"] }
        await store.send(.game(.selectLetter(4))) { $0.game?.selectedLetters = ["있", "다"] }
        await store.send(.game(.selectLetter(5))) { $0.game?.selectedLetters = ["있", "다", "면"] }
        await store.receive(\.game.submit) { $0.game?.inputState = .submitting }
        await store.receive(\.game.delegate.submitAnswer)
        await store.receive(\.delegate.send, .submitAnswer(roomID: TestID.room, answer: "있다면"))

        // 오답 페널티 500ms (TestClock)
        await store.send(.server(.game(.wrongAnswer(playerID: TestID.myself, wrongAnswer: "있다면"))))
        await store.receive(\.game.serverEvent) { $0.game?.inputState = .penalized }
        await clock.advance(by: .milliseconds(499))
        await clock.advance(by: .milliseconds(1))
        await store.receive(\.game.penaltyFinished) {
            $0.game?.selectedLetters = []
            $0.game?.inputState = .enabled
        }

        // 라운드 결과
        let roundResult = RoundResult(winnerId: TestID.other, correctAnswer: "그대만", scores: [TestID.other: 1])
        await store.send(.server(.game(.roundEnded(roundResult))))
        await store.receive(\.game.serverEvent) {
            $0.game?.roundState = .result
            $0.game?.roundResult = roundResult
        }
        await store.receive(\.game.delegate.stopMusic)
        await store.finish()
        XCTAssertEqual(audio.stopCount.value, 1)

        // 게임 종료
        let result = GameResult(winner: TestID.other, scores: [TestID.myself: 0, TestID.other: 1])
        await store.send(.server(.gameOver(result))) {
            $0.stage = .finished(result)
            $0.game = nil
        }
        await store.finish()
        XCTAssertEqual(audio.stopCount.value, 2)
        XCTAssertEqual(store.state.winnerID, TestID.other)
        XCTAssertEqual(store.state.scoreboard, [
            .init(playerID: TestID.myself, score: 0),
            .init(playerID: TestID.other, score: 1)
        ])
        XCTAssertNil(store.state.abortMessage)
    }

    // MARK: - GAME_OVER (REQ-GAME-04)

    func test_GAME_OVER_승자가_빈_문자열이면_승자_없음() async {
        let audio = AudioRecorder()
        let store = makeStore(playingState(), audio: audio)
        let result = GameResult(winner: "", scores: [TestID.other: 0, TestID.myself: 0, TestID.third: 2])

        await store.send(.server(.gameOver(result))) {
            $0.stage = .finished(result)
            $0.game = nil
        }
        XCTAssertNil(store.state.winnerID)
        await store.finish()
        XCTAssertEqual(audio.stopCount.value, 1)
        // 서버 참가자 순서, 이미 나간 참가자는 뒤에
        XCTAssertEqual(store.state.scoreboard.map(\.playerID), [TestID.myself, TestID.other, TestID.third])
    }

    func test_결과_화면에서는_GAME_STARTED_GAME_OVER_GAME_ABORTED를_무시한다() async {
        let first = GameResult(winner: TestID.myself, scores: [TestID.myself: 3])
        var state = RoomReducer.State(welcome: .fixture())
        state.stage = .finished(first)
        let audio = AudioRecorder()
        let store = makeStore(state, audio: audio)

        await store.send(.server(.gameStarted))
        await store.send(.server(.gameOver(GameResult(winner: "", scores: [:]))))
        await store.send(.server(.gameAborted(.internalError)))
        await store.send(.server(.game(.countDown(3))))
        await store.finish()
        XCTAssertEqual(audio.stopCount.value, 0)
    }

    func test_게임_중의_GAME_STARTED는_무시한다() async {
        var state = playingState()
        state.game?.remainingTime = 7
        let store = makeStore(state)

        await store.send(.server(.gameStarted))
    }

    // MARK: - GAME_ABORTED (REQ-GAME-05, EDGE-11)

    func test_GAME_ABORTED_INSUFFICIENT_PLAYERS() async {
        let audio = AudioRecorder()
        let store = makeStore(playingState(), audio: audio)

        await store.send(.server(.gameAborted(.insufficientPlayers))) {
            $0.stage = .aborted(.insufficientPlayers)
            $0.game = nil
        }
        XCTAssertEqual(store.state.abortMessage, "상대가 모두 퇴장했습니다")
        XCTAssertNil(store.state.winnerID)
        XCTAssertEqual(store.state.scoreboard, [])
        await store.finish()
        XCTAssertEqual(audio.stopCount.value, 1)
    }

    func test_GAME_ABORTED_INTERNAL_ERROR() async {
        let audio = AudioRecorder()
        let store = makeStore(playingState(), audio: audio)

        await store.send(.server(.gameAborted(.internalError))) {
            $0.stage = .aborted(.internalError)
            $0.game = nil
        }
        XCTAssertEqual(store.state.abortMessage, "문제가 생겨 게임이 중단됐어요.")
        await store.finish()
        XCTAssertEqual(audio.stopCount.value, 1)
    }

    func test_곡_준비_중_GAME_ABORTED가_오면_준비를_취소하고_READY_TO_PLAY를_보내지_않는다() async {
        let clock = TestClock()
        let audio = AudioRecorder()
        let store = TestStore(initialState: playingState()) {
            RoomReducer()
        } withDependencies: {
            $0.audioClient = audio.client(preloadWait: (clock, .seconds(5)))
        }

        await store.send(.server(.preloadSong(isrc: "KRA381234567", startTime: 0, roundNumber: 1)))
        await store.send(.server(.gameAborted(.insufficientPlayers))) {
            $0.stage = .aborted(.insufficientPlayers)
            $0.game = nil
        }
        await clock.advance(by: .seconds(5))
        await store.finish()
        XCTAssertEqual(audio.stopCount.value, 1)
    }

    func test_게임이_끝나면_오답_페널티_타이머도_취소된다() async {
        let clock = TestClock()
        let store = makeStore(playingState(), clock: clock)

        await store.send(.server(.game(.wrongAnswer(playerID: TestID.myself, wrongAnswer: "x"))))
        await store.receive(\.game.serverEvent) { $0.game?.inputState = .penalized }
        let result = GameResult(winner: "", scores: [:])
        await store.send(.server(.gameOver(result))) {
            $0.stage = .finished(result)
            $0.game = nil
        }
        await clock.advance(by: .seconds(1))
    }
}

// MARK: - App 쪽에서 방을 없앨 때의 효과 정리 (design 12, T6 인계 확인)

@Reducer
struct RoomHost {
    @ObservableState
    struct State: Equatable {
        var room: RoomReducer.State?
    }

    enum Action {
        case room(RoomReducer.Action)
        case backToLobby
    }

    var body: some ReducerOf<Self> {
        Reduce { state, action in
            switch action {
            case .backToLobby:
                state.room = nil
                return .none
            case .room:
                return .none
            }
        }
        .ifLet(\.room, action: \.room) { RoomReducer() }
    }
}

@MainActor
final class RoomEffectCleanupTests: XCTestCase {
    func test_부모가_방_상태를_없애면_곡_준비와_페널티_타이머가_취소된다() async {
        let clock = TestClock()
        var room = RoomReducer.State(welcome: .fixture())
        room.stage = .playing
        room.game = GameReducer.State()
        let audio = AudioRecorder()
        let store = TestStore(initialState: RoomHost.State(room: room)) {
            RoomHost()
        } withDependencies: {
            $0.audioClient = audio.client(preloadWait: (clock, .seconds(5)))
            $0.continuousClock = clock
        }

        await store.send(.room(.server(.preloadSong(isrc: "KRA381234567", startTime: 0, roundNumber: 1))))
        await store.send(.room(.server(.game(.wrongAnswer(playerID: TestID.myself, wrongAnswer: "x")))))
        await store.receive(\.room.game.serverEvent) { $0.room?.game?.inputState = .penalized }

        await store.send(.backToLobby) {
            $0.room = nil
        }
        // READY_TO_PLAY와 penaltyFinished가 오지 않는다
        await clock.advance(by: .seconds(10))
    }
}
