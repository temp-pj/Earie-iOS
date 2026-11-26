import ClientCatalog
import ConcurrencyExtras
import Foundation
import Models

public extension CatalogClient {
    /// 항상 `catalog`를 돌려준다.
    static func returning(_ catalog: CatalogProjection) -> Self {
        Self(load: { catalog })
    }

    /// 항상 `error`로 throw한다 (파일 없음, 형식 오류).
    static func failing(_ error: any Error & Sendable = CatalogClientTestError()) -> Self {
        Self(load: { throw error })
    }
}

/// `CatalogClient.failing`의 기본 오류
public struct CatalogClientTestError: Error, Equatable, Sendable {
    public init() {}
}

public extension CategoryPreferenceClient {
    /// 메모리에 저장한다. 테스트가 `storage`로 저장값을 확인하거나 미리 넣을 수 있다.
    static func inMemory(_ storage: LockIsolated<MatchCategory?> = LockIsolated(nil)) -> Self {
        Self(
            load: { storage.value },
            save: { category in storage.setValue(category) }
        )
    }
}
