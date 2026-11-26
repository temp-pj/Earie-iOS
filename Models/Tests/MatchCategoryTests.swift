import Foundation
import Models
import XCTest

final class MatchCategoryTests: XCTestCase {
    func test_JSON_키는_protocol의_Category_필드와_같다() throws {
        let category = MatchCategory(decade: "2010s", artistType: "solo", gender: "female", genre: "korean_ballad")
        let data = try JSONEncoder().encode(category)
        let object = try XCTUnwrap(try JSONSerialization.jsonObject(with: data) as? [String: String])
        XCTAssertEqual(object, [
            "decade": "2010s",
            "artistType": "solo",
            "gender": "female",
            "genre": "korean_ballad"
        ])
    }

    func test_네_필드가_같으면_같은_조합이다() {
        let lhs = MatchCategory(decade: "all", artistType: "any", gender: "any", genre: "any")
        let rhs = MatchCategory(decade: "all", artistType: "any", gender: "any", genre: "any")
        let other = MatchCategory(decade: "any", artistType: "any", gender: "any", genre: "any")
        XCTAssertEqual(lhs, rhs)
        XCTAssertEqual(Set([lhs, rhs, other]).count, 2)
    }

    func test_카탈로그_projection_fixture를_읽는다() throws {
        let catalog = try JSONDecoder().decode(CatalogProjection.self, from: ContractFixtures.data("catalog-projection"))
        XCTAssertEqual(catalog.version, "test-v1")
        XCTAssertEqual(catalog.decades, ["2010s", "2020s"])
        XCTAssertEqual(catalog.genres.map(\.id), ["korean_ballad", "synthetic_pop"])
        XCTAssertEqual(catalog.allowedRequests.first, MatchCategory(decade: "any", artistType: "any", gender: "any", genre: "any"))
        XCTAssertEqual(catalog.allowedRequests.count, 5)
        XCTAssertEqual(catalog.pools.count, 4)
    }

    func test_이용_불가_카탈로그_fixture는_빈_배열로_읽힌다() throws {
        let catalog = try JSONDecoder().decode(CatalogProjection.self, from: ContractFixtures.data("catalog-unavailable"))
        XCTAssertEqual(catalog.allowedRequests, [])
        XCTAssertEqual(catalog.decades, [])
    }
}
