//
//  RoomTestMocks.swift
//  FeatureRoom
//
//  Created by 송지혁 on 5/15/26.
//

import ClientAudio
import ComposableArchitecture
@testable import FeatureRoom
import Foundation
import Models
import XCTest

extension RoundData {
    static func mock(roundNumber: Int, totalRounds: Int, wordCards: [String], answerLength: Int, timeLimit: TimeInterval) -> RoundData {
        return RoundData(roundNumber: roundNumber,
                         totalRounds: totalRounds,
                         letterCards: wordCards,
                         answerLength: answerLength)
    }
}

/// 테스트용 ID. 모두 소문자 canonical UUID v4.
enum TestID {
    static let request = "11111111-1111-4111-8111-111111111111"
    static let room = "22222222-2222-4222-8222-222222222222"
    static let myself = "33333333-3333-4333-8333-333333333333"
    static let other = "44444444-4444-4444-8444-444444444444"
    static let third = "55555555-5555-4555-8555-555555555555"
}

extension MatchCategory {
    static let roomFixture = MatchCategory(decade: "2010s", artistType: "any", gender: "any", genre: "korean_ballad")
}

/// `MatchCategory.roomFixture`의 표시용 이름. 실제 문구는 부모(App)가 카탈로그로 만든다.
extension RoomReducer.CategoryLabel {
    static let roomFixture = RoomReducer.CategoryLabel(decade: "2010년대", artistType: "상관없음", gender: "상관없음", genre: "발라드")
}

extension RoomReducer.State {
    static func fixture(_ welcome: WireV1.WelcomePayload = .fixture()) -> Self {
        Self(welcome: welcome, categoryLabel: .roomFixture)
    }
}

extension WireV1.WelcomePayload {
    static func fixture(
        hostID: String = TestID.myself,
        players: [String] = [TestID.myself, TestID.other]
    ) -> Self {
        WireV1.WelcomePayload(
            requestID: TestID.request,
            roomID: TestID.room,
            playerID: TestID.myself,
            hostID: hostID,
            players: players,
            roomState: "waiting",
            maxPlayers: 8,
            category: .roomFixture,
            catalogVersion: "test-v1"
        )
    }
}

/// AudioClient 호출 기록
final class AudioRecorder: Sendable {
    struct Preload: Equatable {
        let isrc: String
        let startTime: TimeInterval
        let timeLimit: TimeInterval
    }

    let preloads = LockIsolated<[Preload]>([])
    let playCount = LockIsolated(0)
    let stopCount = LockIsolated(0)

    /// `preloadError`가 있으면 곡 준비가 그 오류로 실패한다. `preloadWait`가 있으면 끝나기 전에 그만큼 기다린다.
    func client(
        preloadError: (any Error & Sendable)? = nil,
        preloadWait: (clock: TestClock<Duration>, duration: Duration)? = nil
    ) -> AudioClient {
        AudioClient(
            preload: { isrc, startTime, timeLimit in
                self.preloads.withValue { $0.append(Preload(isrc: isrc, startTime: startTime, timeLimit: timeLimit)) }
                if let preloadWait {
                    try await preloadWait.clock.sleep(for: preloadWait.duration)
                }
                if let preloadError { throw preloadError }
            },
            play: { self.playCount.withValue { $0 += 1 } },
            stop: { self.stopCount.withValue { $0 += 1 } },
            playbackState: { AsyncStream { $0.finish() } }
        )
    }
}

struct PreloadFailure: Error {}

/// 방 테스트 공통 준비
@MainActor
extension XCTestCase {
    func makeStore(
        _ state: RoomReducer.State = RoomReducer.State.fixture(),
        audio: AudioRecorder = AudioRecorder(),
        preloadError: (any Error & Sendable)? = nil,
        clock: TestClock<Duration> = TestClock()
    ) -> TestStoreOf<RoomReducer> {
        TestStore(initialState: state) {
            RoomReducer()
        } withDependencies: {
            $0.audioClient = audio.client(preloadError: preloadError)
            $0.continuousClock = clock
        }
    }

    func playingState(isLeaving: Bool = false) -> RoomReducer.State {
        var state = RoomReducer.State.fixture()
        state.stage = .playing
        state.game = GameReducer.State()
        state.isLeaving = isLeaving
        return state
    }

}
