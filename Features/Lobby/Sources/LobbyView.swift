import ComposableArchitecture
import SwiftUI

/// 로비 화면. 상태를 그리고 액션을 보내기만 한다. 기본 SwiftUI 컴포넌트만 쓴다 (OUT-02).
public struct LobbyView: View {
    let store: StoreOf<LobbyReducer>

    public init(store: StoreOf<LobbyReducer>) {
        self.store = store
    }

    public var body: some View {
        Group {
            switch store.phase {
            case .selecting:
                selectingView
            case .matching:
                matchingView
            }
        }
        .onAppear { store.send(.onAppear) }
    }

    private var selectingView: some View {
        Form {
            switch store.catalog {
            case .loading:
                Section { ProgressView() }
            case .unavailable:
                Section { Text("지금은 매칭을 이용할 수 없어요") }
            case .available:
                ForEach(LobbyReducer.Axis.allCases, id: \.self) { axis in
                    Section(axis.title) {
                        ForEach(store.state.candidates(for: axis)) { candidate in
                            candidateRow(candidate, axis: axis)
                        }
                    }
                }
            }
            Section {
                Button("매칭") { store.send(.matchButtonTapped) }
                    .disabled(!store.isMatchButtonEnabled)
            }
        }
    }

    private func candidateRow(_ candidate: LobbyReducer.Candidate, axis: LobbyReducer.Axis) -> some View {
        Button {
            store.send(.candidateTapped(axis, value: candidate.value))
        } label: {
            HStack {
                Text(candidate.label.title)
                Spacer()
                if candidate.isSelected {
                    Image(systemName: "checkmark")
                }
            }
        }
        .disabled(!candidate.isEnabled)
    }

    private var matchingView: some View {
        VStack(spacing: 16) {
            ProgressView()
            Text("매칭 대기 중")
            Button("취소") { store.send(.cancelButtonTapped) }
        }
    }
}

private extension LobbyReducer.Axis {
    /// 축 이름 (REQ-CAT-01)
    var title: String {
        switch self {
        case .decade: "연대"
        case .artistType: "구성"
        case .gender: "성별"
        case .genre: "장르"
        }
    }
}

private extension LobbyReducer.CandidateLabel {
    var title: String {
        switch self {
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
