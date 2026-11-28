import ComposableArchitecture
import FeatureLobby
import FeatureRoom
import Models
import SwiftUI

/// App 상태를 그린다. 로비와 방 중 현재 단계 하나와 화면 전환 알럿 (design 1 "바꿀 것").
struct RootView: View {
    let store: StoreOf<AppFeature>

    var body: some View {
        Group {
            switch store.phase {
            case .lobby:
                if let lobbyStore = store.scope(state: \.phase.lobby, action: \.lobby) {
                    LobbyView(store: lobbyStore)
                }
            case .room:
                if let roomStore = store.scope(state: \.phase.room, action: \.room) {
                    RoomView(store: roomStore)
                }
            }
        }
        .alert(
            store.alert.map(AppCopy.alertTitle) ?? "",
            isPresented: Binding(
                get: { store.alert != nil },
                set: { isPresented in
                    if !isPresented { store.send(.alertDismissed) }
                }
            )
        ) {
            Button(AppCopy.alertConfirm, role: .cancel) {}
        }
        .onAppear { store.send(.onAppear) }
    }
}

/// App 화면 문구를 모으는 곳.
///
/// - 명세 문구: 알럿 본문 (REQ-FAIL-01, REQ-FAIL-02, REQ-ROOM-07)
/// - 로비와 맞춘 이름: 조건 값 이름은 `LobbyView`의 후보 이름과 같게 둔다
/// - 임시 문구 (명세에 없음, 사용자 허용에 따른 임시 문구): `alertConfirm`, `allValueTitle`
enum AppCopy {
    static func alertTitle(_ alert: AppFeature.AppAlert) -> String {
        switch alert {
        case let .matchFailed(code): matchFailedMessage(code)
        case .disconnected: "서버와 연결이 끊어졌어요."
        case .kicked: "방에서 내보내졌어요."
        }
    }

    /// REQ-FAIL-01
    static func matchFailedMessage(_ code: MatchFailureCode) -> String {
        switch code {
        case .invalidCriteria: "음악 조건 정보가 변경됐어요. 앱 업데이트를 확인해 주세요."
        case .internalError: "매칭 중 문제가 생겼어요. 잠시 후 다시 시도해 주세요."
        case .alreadyMatching: "이미 매칭 중이에요."
        case .alreadyInRoom: "이미 방에 참여 중이에요."
        }
    }

    /// 임시 문구: 알럿 닫기 버튼
    static let alertConfirm = "확인"

    /// 임시 문구: 확정 방 조건에서 구성·성별·장르 축의 `all` (양쪽 상관없음이 합쳐진 값, protocol.md "Category 공통 타입").
    /// 로비에는 이 값의 후보가 없어 이름이 없다.
    static let allValueTitle = "전체"

    /// WELCOME의 확정 조합을 방 화면용 이름으로 바꾼다. 값→후보 종류는 로비의 `candidates(for:)`를 그대로 쓴다.
    static func categoryLabel(_ category: MatchCategory, lobby: LobbyReducer.State) -> RoomReducer.CategoryLabel {
        func title(_ axis: LobbyReducer.Axis, _ value: String) -> String {
            if let candidate = lobby.candidates(for: axis).first(where: { $0.value == value }) {
                return candidateTitle(candidate.label)
            }
            if value == LobbyReducer.allValue { return allValueTitle }
            return value
        }
        return RoomReducer.CategoryLabel(
            decade: title(.decade, category.decade),
            artistType: title(.artistType, category.artistType),
            gender: title(.gender, category.gender),
            genre: title(.genre, category.genre)
        )
    }

    /// `LobbyView`의 후보 이름과 같다 (FeatureLobby의 `CandidateLabel.title`은 모듈 밖에 공개되지 않는다).
    static func candidateTitle(_ label: LobbyReducer.CandidateLabel) -> String {
        switch label {
        case .any: "상관없음"
        case .allDecades: "모든 연대"
        case let .catalog(text): text
        case .solo: "솔로"
        case .group: "그룹"
        case .male: "남성"
        case .female: "여성"
        }
    }
}
