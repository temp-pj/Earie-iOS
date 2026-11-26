import Foundation
import Models

/// 앱 번들의 카탈로그 projection을 읽는다 (design 7).
public struct CatalogClient: Sendable {
    /// 파일이 없거나 형식이 잘못되면 throw한다.
    public var load: @Sendable () throws -> CatalogProjection

    public init(load: @escaping @Sendable () throws -> CatalogProjection) {
        self.load = load
    }
}

/// 마지막으로 매칭한 조합을 저장하고 읽는다 (design 7).
public struct CategoryPreferenceClient: Sendable {
    /// 저장된 조합이 없으면 nil
    public var load: @Sendable () -> MatchCategory?
    public var save: @Sendable (MatchCategory) -> Void

    public init(
        load: @escaping @Sendable () -> MatchCategory?,
        save: @escaping @Sendable (MatchCategory) -> Void
    ) {
        self.load = load
        self.save = save
    }
}
