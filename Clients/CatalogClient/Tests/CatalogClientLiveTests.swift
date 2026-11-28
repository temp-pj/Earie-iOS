import ClientCatalog
import ClientCatalogLive
import Foundation
import Models
import XCTest

final class CatalogClientLiveTests: XCTestCase {
    private var temporaryDirectory: URL!

    override func setUpWithError() throws {
        temporaryDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("CatalogClientLiveTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: temporaryDirectory)
    }

    // MARK: - 번들 파일 읽기

    func test_번들의_catalog_projection_json을_읽는다() throws {
        let catalog = try CatalogClient.live(bundle: CatalogFixtures.bundle).load()

        XCTAssertEqual(catalog, Self.testV1)
    }

    func test_앱_번들_카탈로그는_fixture와_바이트가_같다() throws {
        let repositoryRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent() // Tests
            .deletingLastPathComponent() // CatalogClient
            .deletingLastPathComponent() // Clients
            .deletingLastPathComponent()
        let appResource = repositoryRoot.appendingPathComponent("M_GAME/Resources/catalog-projection.json")

        XCTAssertEqual(try Data(contentsOf: appResource), try CatalogFixtures.data("catalog-projection"))
    }

    func test_앱_번들_파일_이름은_catalog_projection이다() {
        XCTAssertEqual(CatalogClient.bundledResourceName, "catalog-projection")
    }

    func test_이용_불가_카탈로그도_형식이_맞으면_그대로_읽는다() throws {
        // 빈 배열의 이용 불가 판정은 로비가 한다 (REQ-CAT-06, tasks.md 7번).
        let catalog = try CatalogClient.live(fileURL: CatalogFixtures.url("catalog-unavailable")).load()

        XCTAssertEqual(catalog, CatalogProjection(version: "test-v1", decades: [], genres: [], allowedRequests: [], pools: []))
    }

    func test_알_수_없는_필드는_무시한다() throws {
        var object = try XCTUnwrap(
            try JSONSerialization.jsonObject(with: CatalogFixtures.data("catalog-projection")) as? [String: Any]
        )
        object["futureField"] = ["anything": true]
        let url = try write(try JSONSerialization.data(withJSONObject: object))

        XCTAssertEqual(try CatalogClient.live(fileURL: url).load(), Self.testV1)
    }

    // MARK: - 파일 없음

    func test_번들에_파일이_없으면_fileNotFound를_던진다() throws {
        let emptyBundle = try XCTUnwrap(Bundle(url: temporaryDirectory))

        XCTAssertThrowsError(try CatalogClient.live(bundle: emptyBundle).load()) { error in
            XCTAssertEqual(error as? CatalogLoadError, .fileNotFound)
        }
    }

    func test_경로에_파일이_없으면_fileNotFound를_던진다() {
        let missing = temporaryDirectory.appendingPathComponent("missing.json")

        XCTAssertThrowsError(try CatalogClient.live(fileURL: missing).load()) { error in
            XCTAssertEqual(error as? CatalogLoadError, .fileNotFound)
        }
    }

    func test_파일이_아닌_경로는_unreadable을_던진다() {
        XCTAssertThrowsError(try CatalogClient.live(fileURL: temporaryDirectory).load()) { error in
            XCTAssertEqual(error as? CatalogLoadError, .unreadable)
        }
    }

    // MARK: - 형식 오류

    func test_JSON이_아니면_invalidFormat을_던진다() throws {
        let cases: [(String, Data)] = [
            ("빈 파일", Data()),
            ("잘린 JSON", Data(#"{"version":"test-v1","decades":["#.utf8)),
            ("JSON 배열", Data("[]".utf8)),
            ("JSON null", Data("null".utf8)),
            ("텍스트", Data("catalog".utf8))
        ]
        for (name, data) in cases {
            let url = try write(data)
            XCTAssertThrowsError(try CatalogClient.live(fileURL: url).load(), name) { error in
                XCTAssertEqual(error as? CatalogLoadError, .invalidFormat, name)
            }
        }
    }

    /// `catalog-invalid.json`에서 `catalog-projection.json`의 필수 필드 누락, null, 타입 오류 레시피 전체
    func test_projection의_필수_null_타입_오류_레시피는_전부_invalidFormat을_던진다() throws {
        let recipes = try CatalogFixtures.invalidRecipes(file: "catalog-projection.json")
            .filter { $0.name.hasPrefix("catalog-projection.json-") }
        XCTAssertEqual(recipes.count, 51)

        for recipe in recipes {
            let url = try write(try CatalogFixtures.applying(recipe))
            XCTAssertThrowsError(try CatalogClient.live(fileURL: url).load(), recipe.name) { error in
                XCTAssertEqual(error as? CatalogLoadError, .invalidFormat, recipe.name)
            }
        }
    }

    /// 알려진 차이: 형식(필수, null, 타입)은 맞고 값만 서버 카탈로그 감사 기준에 어긋나는 레시피.
    /// iOS는 읽기 실패와 형식 오류만 처리하고 값 규칙은 카탈로그 파일을 만드는 쪽에서 검사하기로 결정했으므로 읽기에 성공한다 (PR #41 결정 사항).
    func test_알려진_차이_형식은_맞고_값만_어긋난_projection_레시피는_읽는다() throws {
        let recipes = try CatalogFixtures.invalidRecipes(file: "catalog-projection.json")
            .filter { !$0.name.hasPrefix("catalog-projection.json-") }
        XCTAssertEqual(recipes.map(\.name).sorted(), ["projection-leak", "projection-short-count", "projection-wrong-count"])

        for recipe in recipes {
            let url = try write(try CatalogFixtures.applying(recipe))
            XCTAssertNoThrow(try CatalogClient.live(fileURL: url).load(), recipe.name)
        }
    }

    // MARK: - Helpers

    private func write(_ data: Data) throws -> URL {
        let url = temporaryDirectory.appendingPathComponent("\(UUID().uuidString).json")
        try data.write(to: url)
        return url
    }

    private static let testV1 = CatalogProjection(
        version: "test-v1",
        decades: ["2010s", "2020s"],
        genres: [
            CatalogGenre(id: "korean_ballad", label: "Synthetic ballad (test only)"),
            CatalogGenre(id: "synthetic_pop", label: "Synthetic pop (test only)")
        ],
        allowedRequests: [
            MatchCategory(decade: "any", artistType: "any", gender: "any", genre: "any"),
            MatchCategory(decade: "all", artistType: "any", gender: "any", genre: "any"),
            MatchCategory(decade: "2010s", artistType: "any", gender: "any", genre: "korean_ballad"),
            MatchCategory(decade: "2010s", artistType: "solo", gender: "female", genre: "korean_ballad"),
            MatchCategory(decade: "2020s", artistType: "group", gender: "male", genre: "synthetic_pop")
        ],
        pools: [
            PoolProjection(category: MatchCategory(decade: "all", artistType: "all", gender: "all", genre: "all"), songCount: 20),
            PoolProjection(category: MatchCategory(decade: "2010s", artistType: "all", gender: "all", genre: "korean_ballad"), songCount: 10),
            PoolProjection(category: MatchCategory(decade: "2010s", artistType: "solo", gender: "female", genre: "korean_ballad"), songCount: 10),
            PoolProjection(category: MatchCategory(decade: "2020s", artistType: "group", gender: "male", genre: "synthetic_pop"), songCount: 10)
        ]
    )
}
