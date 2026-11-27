//
//  RoomView.swift
//  FeatureRoom
//
//  Created by 송지혁 on 6/4/26.
//

import ComposableArchitecture
import Models
import SwiftUI

/// 방 대기, 게임, 결과 화면. 상태를 그리고 액션을 보내기만 한다.
public struct RoomView: View {
    @Bindable public var store: StoreOf<RoomReducer>

    public init(store: StoreOf<RoomReducer>) {
        self.store = store
    }

    public var body: some View {
        VStack(spacing: 16) {
            switch store.stage {
            case .waiting:
                RoomWaitingView(store: store)
            case .playing:
                if let gameStore = store.scope(state: \.game, action: \.game) {
                    GameView(store: gameStore)
                }
            case .finished, .aborted:
                RoomResultView(store: store)
            }

            if store.isLeaving {
                ProgressView("나가는 중")
            }

            Button("나가기") {
                store.send(.leaveTapped)
            }
            .disabled(!store.canLeave)
        }
        .padding()
        .alert($store.scope(state: \.alert, action: \.alert))
    }
}

/// REQ-ROOM-01: 참가자 목록(서버 순서), 방장, 나, 인원, 확정 조합
private struct RoomWaitingView: View {
    let store: StoreOf<RoomReducer>

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("참가자 \(store.players.count)/\(store.maxPlayers)")
                .font(.headline)

            ForEach(store.players, id: \.self) { playerID in
                HStack {
                    Text(playerID.prefix(8))
                        .monospaced()
                    if playerID == store.hostID {
                        Text("방장").foregroundStyle(.orange)
                    }
                    if playerID == store.myPlayerID {
                        Text("나").foregroundStyle(.blue)
                    }
                }
            }

            CategoryView(category: store.category)

            Button("시작") {
                store.send(.startTapped)
            }
            .buttonStyle(.borderedProminent)
            .disabled(!store.canStart)
        }
    }
}

private struct CategoryView: View {
    let category: MatchCategory

    var body: some View {
        VStack(alignment: .leading) {
            Text("연대: \(category.decade)")
            Text("구성: \(category.artistType)")
            Text("성별: \(category.gender)")
            Text("장르: \(category.genre)")
        }
        .font(.subheadline)
        .foregroundStyle(.secondary)
    }
}

/// REQ-GAME-04, 05: 승자와 점수, 또는 중단 사유
private struct RoomResultView: View {
    let store: StoreOf<RoomReducer>

    var body: some View {
        VStack(spacing: 12) {
            if let abortMessage = store.abortMessage {
                Text(abortMessage)
                    .font(.headline)
            } else {
                if let winnerID = store.winnerID {
                    Text("승자: \(winnerID.prefix(8))")
                        .font(.headline)
                } else {
                    Text("승자 없음")
                        .font(.headline)
                }
                ForEach(store.scoreboard) { score in
                    HStack {
                        Text(score.playerID.prefix(8))
                            .monospaced()
                        if score.playerID == store.myPlayerID {
                            Text("나").foregroundStyle(.blue)
                        }
                        Spacer()
                        Text("\(score.score)")
                    }
                }
            }
        }
    }
}

/// 기존 게임 화면 (REQ-GAME-01)
private struct GameView: View {
    let store: StoreOf<GameReducer>
    private let columns = [GridItem(.adaptive(minimum: 56), spacing: 10)]

    var body: some View {
        VStack(spacing: 12) {
            HStack {
                Image(systemName: "clock.fill")
                    .foregroundColor(store.remainingTime <= 5 ? .red : .orange)

                Text("\(store.remainingTime)초")
                    .font(.title)
                    .monospacedDigit()
                    .fontWeight(.bold)
                    .foregroundColor(store.remainingTime <= 5 ? .red : .primary)
            }
            .animation(.default, value: store.remainingTime)

            Text(store.selectedLetters.joined())
                .bold()

            let cards = store.roundData?.letterCards ?? []

            if cards.isEmpty {
                Text("카드를 불러오는 중이거나 없습니다... 👾")
                    .foregroundColor(.gray)
                    .padding()
            } else {
                LazyVGrid(columns: columns, spacing: 10) {
                    ForEach(Array(cards.enumerated()), id: \.offset) { index, letter in
                        Button {
                            store.send(.selectLetter(index))
                        } label: {
                            Text(letter)
                                .font(.title2)
                                .fontWeight(.bold)
                                .frame(width: 48, height: 48)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 12)
                                        .stroke(Color.orange, lineWidth: 2)
                                )
                        }
                    }
                }
                .padding(.horizontal)
                .id(cards.joined())
            }

            Button("SUBMIT") {
                store.send(.submit(store.selectedLetters.joined()))
            }
        }
    }
}
