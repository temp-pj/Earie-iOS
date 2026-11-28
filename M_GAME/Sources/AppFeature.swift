//
//  AppFeature.swift
//  M_GAME
//
//  Created by 송지혁 on 4/28/26.
//

import ComposableArchitecture
import FeatureLogin
import FeatureRoom
import Foundation

// T5 임시 상태: v1 RoomReducer는 WELCOME으로만 만들어진다. 매칭과 연결 조립은 T6에서 다시 쓴다.
@Reducer
struct AppFeature {
    @ObservableState
    struct State {
        var room: RoomReducer.State?
    }

    enum Action {
        case room(RoomReducer.Action)
        case onAppear
    }

    @Dependency(\.musicEntitlementClient) var musicEntitlementClient

    var body: some ReducerOf<Self> {
        Reduce { _, action in
            switch action {
                case .onAppear:
                    return .run { _ in
                        await musicEntitlementClient.requestAuthorization()
                    }

                case .room: return .none
            }
        }
        .ifLet(\.room, action: \.room) {
            RoomReducer()
        }
    }
}
