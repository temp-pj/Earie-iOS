import Foundation
import Models
import XCTest

/// `docs/specs/random-matchmaking/fixtures/`의 카탈로그를 FeatureLobbyTests 리소스로 읽는다.
enum LobbyFixtures {
    /// `catalog-projection.json` (test-v1)
    static func testV1() throws -> CatalogProjection {
        try catalog("catalog-projection")
    }

    /// `catalog-unavailable.json` (빈 배열)
    static func unavailable() throws -> CatalogProjection {
        try catalog("catalog-unavailable")
    }

    static func catalog(_ name: String) throws -> CatalogProjection {
        let bundle = Bundle(for: BundleToken.self)
        let url = try XCTUnwrap(
            bundle.url(forResource: name, withExtension: "json"),
            "\(name).json이 FeatureLobbyTests 리소스에 없다"
        )
        return try JSONDecoder().decode(CatalogProjection.self, from: Data(contentsOf: url))
    }

    private final class BundleToken {}
}

extension MatchCategory {
    static func make(_ decade: String, _ artistType: String, _ gender: String, _ genre: String) -> Self {
        Self(decade: decade, artistType: artistType, gender: gender, genre: genre)
    }
}
