import ClientCatalog
import Foundation
import Models

public extension CategoryPreferenceClient {
    /// 마지막으로 매칭한 조합을 저장하는 `UserDefaults` 키
    static let storageKey = "ClientCatalog.lastMatchCategory"

    /// `UserDefaults.standard`에 저장하고 읽는다.
    static var live: CategoryPreferenceClient {
        live(userDefaults: .standard)
    }

    /// `userDefaults`에 저장하고 읽는다.
    ///
    /// 조합은 `MatchCategory`의 JSON으로 저장한다. 저장값이 없거나 읽을 수 없는 형식이면 `load`는 nil을 돌려준다.
    /// 복원한 조합이 현재 카탈로그에 있는지는 판정하지 않는다. 그 판정은 로비가 한다 (REQ-CAT-08).
    static func live(userDefaults: UserDefaults) -> CategoryPreferenceClient {
        let storage = UserDefaultsBox(userDefaults)
        return CategoryPreferenceClient(
            load: {
                guard let data = storage.value.data(forKey: storageKey) else { return nil }
                return try? JSONDecoder().decode(MatchCategory.self, from: data)
            },
            save: { category in
                guard let data = try? JSONEncoder().encode(category) else { return }
                storage.value.set(data, forKey: storageKey)
            }
        )
    }
}

/// `UserDefaults`는 스레드 안전하다고 문서화돼 있지만 SDK에서 `Sendable`로 표시되지 않아 감싼다.
private struct UserDefaultsBox: @unchecked Sendable {
    let value: UserDefaults

    init(_ value: UserDefaults) {
        self.value = value
    }
}
