import Dependencies
import Models

extension CatalogClient: DependencyKey {
    /// 실제 구현은 `ClientCatalogLive`의 `CatalogClient.live`를 App에서 주입한다.
    public static let liveValue = CatalogClient.unimplementedValue
    public static let testValue = CatalogClient.unimplementedValue

    static let unimplementedValue = CatalogClient(
        load: unimplemented("CatalogClient.load")
    )
}

extension CategoryPreferenceClient: DependencyKey {
    /// 실제 구현은 `ClientCatalogLive`의 `CategoryPreferenceClient.live`를 App에서 주입한다.
    public static let liveValue = CategoryPreferenceClient.unimplementedValue
    public static let testValue = CategoryPreferenceClient.unimplementedValue

    static let unimplementedValue = CategoryPreferenceClient(
        load: unimplemented("CategoryPreferenceClient.load", placeholder: nil),
        save: unimplemented("CategoryPreferenceClient.save")
    )
}

extension DependencyValues {
    public var catalogClient: CatalogClient {
        get { self[CatalogClient.self] }
        set { self[CatalogClient.self] = newValue }
    }

    public var categoryPreferenceClient: CategoryPreferenceClient {
        get { self[CategoryPreferenceClient.self] }
        set { self[CategoryPreferenceClient.self] = newValue }
    }
}
