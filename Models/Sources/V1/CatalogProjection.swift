import Foundation

/// iOS 번들에 넣는 카탈로그 projection (protocol.md "배포 카탈로그").
/// 배열 순서가 UI 표시 순서이고, 빈 배열은 서비스 이용 불가를 뜻한다.
public struct CatalogProjection: Codable, Equatable, Sendable {
    public let version: String
    public let decades: [String]
    public let genres: [CatalogGenre]
    public let allowedRequests: [MatchCategory]
    public let pools: [PoolProjection]

    public init(
        version: String,
        decades: [String],
        genres: [CatalogGenre],
        allowedRequests: [MatchCategory],
        pools: [PoolProjection]
    ) {
        self.version = version
        self.decades = decades
        self.genres = genres
        self.allowedRequests = allowedRequests
        self.pools = pools
    }
}

public struct CatalogGenre: Codable, Equatable, Sendable {
    public let id: String
    public let label: String

    public init(id: String, label: String) {
        self.id = id
        self.label = label
    }
}

public struct PoolProjection: Codable, Equatable, Sendable {
    public let category: MatchCategory
    public let songCount: Int

    public init(category: MatchCategory, songCount: Int) {
        self.category = category
        self.songCount = songCount
    }
}
