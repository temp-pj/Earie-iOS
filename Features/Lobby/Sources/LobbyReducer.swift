import ClientCatalog
import ComposableArchitecture
import Foundation
import Models

/// 로비: 조건 선택, 후보 활성 판정, 매칭 대기, 취소, 조합 저장·복원 (design 3, 5, 6, 8).
/// 연결과 송신은 하지 않는다. 매칭 시작과 취소는 delegate로 App에 맡긴다.
@Reducer
public struct LobbyReducer {
    public init() {}

    @ObservableState
    public struct State: Equatable {
        public var catalog: CatalogState
        public var selection: MatchCategory
        public var phase: Phase

        public init(
            catalog: CatalogState = .loading,
            selection: MatchCategory = LobbyReducer.defaultSelection,
            phase: Phase = .selecting
        ) {
            self.catalog = catalog
            self.selection = selection
            self.phase = phase
        }
    }

    public enum CatalogState: Equatable, Sendable {
        case loading
        case available(CatalogProjection)
        /// 읽기 실패, 빈 `allowedRequests`, 전부 상관없음 조합 없음 (REQ-CAT-06)
        case unavailable
    }

    public enum Phase: Equatable, Sendable {
        case selecting
        case matching(requestID: String)
    }

    /// 조건 축 (REQ-CAT-01)
    public enum Axis: CaseIterable, Equatable, Hashable, Sendable {
        case decade
        case artistType
        case gender
        case genre
    }

    /// 화면에 그릴 후보 하나
    public struct Candidate: Equatable, Identifiable, Sendable {
        /// wire 값
        public let value: String
        public let label: CandidateLabel
        public let isEnabled: Bool
        public let isSelected: Bool

        public var id: String { value }
    }

    /// 후보 표시 이름의 종류. 카탈로그가 주는 이름은 `catalog`에 그대로 담는다 (REQ-CAT-03).
    public enum CandidateLabel: Equatable, Sendable {
        /// 상관없음 (`any`)
        case any
        /// 모든 연대 (연대 축의 `all`)
        case allDecades
        /// 카탈로그의 연대 값 또는 장르 `label`
        case catalog(String)
        case solo
        case group
        case male
        case female
    }

    public enum Action: Equatable {
        /// 로비 진입. 카탈로그와 저장된 조합을 읽는다.
        case onAppear
        case candidateTapped(Axis, value: String)
        case matchButtonTapped
        case cancelButtonTapped
        /// App이 보낸다: 활성 요청이 실패·끊김으로 끝났다 (design 7).
        case matchEnded
        case delegate(Delegate)

        @CasePathable
        public enum Delegate: Equatable, Sendable {
            case requestMatch(requestID: String, category: MatchCategory, catalogVersion: String)
            case cancelMatch(requestID: String)
        }
    }

    @Dependency(\.catalogClient) var catalogClient
    @Dependency(\.categoryPreferenceClient) var categoryPreferenceClient
    @Dependency(\.uuid) var uuid

    public var body: some ReducerOf<Self> {
        Reduce { state, action in
            switch action {
            case .onAppear:
                guard state.catalog == .loading else { return .none }
                loadCatalog(into: &state)
                return .none

            case let .candidateTapped(axis, value):
                guard state.phase == .selecting,
                      state.candidates(for: axis).contains(where: { $0.value == value && $0.isEnabled })
                else { return .none }
                state.selection[axis] = value
                return .none

            case .matchButtonTapped:
                guard state.phase == .selecting,
                      state.isMatchButtonEnabled,
                      case let .available(catalog) = state.catalog
                else { return .none }
                let requestID = uuid().uuidString.lowercased()
                let category = state.selection
                state.phase = .matching(requestID: requestID)
                return .merge(
                    .send(.delegate(.requestMatch(
                        requestID: requestID,
                        category: category,
                        catalogVersion: catalog.version
                    ))),
                    .run { [save = categoryPreferenceClient.save] _ in
                        save(category)
                    }
                )

            case .cancelButtonTapped:
                guard case let .matching(requestID) = state.phase else { return .none }
                state.phase = .selecting
                return .send(.delegate(.cancelMatch(requestID: requestID)))

            case .matchEnded:
                state.phase = .selecting
                return .none

            case .delegate:
                return .none
            }
        }
    }

    private func loadCatalog(into state: inout State) {
        guard let catalog = try? catalogClient.load(),
              catalog.allowedRequests.contains(Self.defaultSelection)
        else {
            state.catalog = .unavailable
            state.selection = Self.defaultSelection
            return
        }
        state.catalog = .available(catalog)
        if let saved = categoryPreferenceClient.load(), catalog.allowedRequests.contains(saved) {
            state.selection = saved
        } else {
            state.selection = Self.defaultSelection
        }
    }
}

// MARK: - 판정

public extension LobbyReducer {
    /// wire 값 `any` (상관없음)
    static let anyValue = "any"
    /// wire 값 `all` (모든 연대)
    static let allValue = "all"

    /// 모든 축이 상관없음인 기본 조합 (REQ-CAT-01)
    static let defaultSelection = MatchCategory(
        decade: anyValue,
        artistType: anyValue,
        gender: anyValue,
        genre: anyValue
    )

    /// REQ-CAT-04: 축 `axis`의 후보 `value`가 활성인지 판정한다.
    /// 허용 조합 중 `axis`가 `value`이고, 나머지 축은 현재 값이 상관없음이면 아무 값이든,
    /// 아니면 현재 값과 같은 조합이 하나라도 있으면 활성이다. 상관없음은 항상 활성이다.
    static func isCandidateEnabled(
        _ value: String,
        axis: Axis,
        selection: MatchCategory,
        allowedRequests: [MatchCategory]
    ) -> Bool {
        if value == anyValue { return true }
        let otherAxes = Axis.allCases.filter { $0 != axis }
        return allowedRequests.contains { request in
            request[axis] == value && otherAxes.allSatisfy { other in
                selection[other] == anyValue || request[other] == selection[other]
            }
        }
    }
}

public extension LobbyReducer.State {
    var activeRequestID: String? {
        guard case let .matching(requestID) = phase else { return nil }
        return requestID
    }

    /// REQ-CAT-06: 이용 불가 안내를 표시한다.
    var isUnavailable: Bool {
        catalog == .unavailable
    }

    /// REQ-CAT-05, 06: 카탈로그가 있고, 조건 선택 중이고, 현재 조합이 허용 조합일 때만 활성
    var isMatchButtonEnabled: Bool {
        guard case let .available(catalog) = catalog, phase == .selecting else { return false }
        return catalog.allowedRequests.contains(selection)
    }

    /// 축의 후보 목록. 순서는 상관없음이 처음이고, 연대·장르는 카탈로그 배열 순서를 따른다 (REQ-CAT-02, 03).
    func candidates(for axis: LobbyReducer.Axis) -> [LobbyReducer.Candidate] {
        guard case let .available(catalog) = catalog else { return [] }
        let options: [(String, LobbyReducer.CandidateLabel)]
        switch axis {
        case .decade:
            options = [(LobbyReducer.anyValue, .any), (LobbyReducer.allValue, .allDecades)]
                + catalog.decades.map { ($0, .catalog($0)) }
        case .artistType:
            options = [(LobbyReducer.anyValue, .any), ("solo", .solo), ("group", .group)]
        case .gender:
            options = [(LobbyReducer.anyValue, .any), ("male", .male), ("female", .female)]
        case .genre:
            options = [(LobbyReducer.anyValue, .any)]
                + catalog.genres.map { ($0.id, .catalog($0.label)) }
        }
        return options.map { value, label in
            LobbyReducer.Candidate(
                value: value,
                label: label,
                isEnabled: LobbyReducer.isCandidateEnabled(
                    value,
                    axis: axis,
                    selection: selection,
                    allowedRequests: catalog.allowedRequests
                ),
                isSelected: selection[axis] == value
            )
        }
    }
}

extension MatchCategory {
    subscript(axis: LobbyReducer.Axis) -> String {
        get {
            switch axis {
            case .decade: decade
            case .artistType: artistType
            case .gender: gender
            case .genre: genre
            }
        }
        set {
            switch axis {
            case .decade: decade = newValue
            case .artistType: artistType = newValue
            case .gender: gender = newValue
            case .genre: genre = newValue
            }
        }
    }
}
