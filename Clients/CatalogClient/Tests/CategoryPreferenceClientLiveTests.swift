import ClientCatalog
import ClientCatalogLive
import Foundation
import Models
import XCTest

final class CategoryPreferenceClientLiveTests: XCTestCase {
    private var suiteName: String!
    private var userDefaults: UserDefaults!

    override func setUpWithError() throws {
        suiteName = "CategoryPreferenceClientLiveTests-\(UUID().uuidString)"
        userDefaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
    }

    override func tearDownWithError() throws {
        userDefaults.removePersistentDomain(forName: suiteName)
    }

    func test_저장값이_없으면_nil을_돌려준다() {
        XCTAssertNil(CategoryPreferenceClient.live(userDefaults: userDefaults).load())
    }

    func test_저장한_조합을_읽는다() {
        let client = CategoryPreferenceClient.live(userDefaults: userDefaults)
        let category = MatchCategory(decade: "2010s", artistType: "any", gender: "any", genre: "korean_ballad")

        client.save(category)

        XCTAssertEqual(client.load(), category)
    }

    func test_다시_저장하면_마지막_조합을_읽는다() {
        let client = CategoryPreferenceClient.live(userDefaults: userDefaults)
        let first = MatchCategory(decade: "2010s", artistType: "solo", gender: "female", genre: "korean_ballad")
        let second = MatchCategory(decade: "2020s", artistType: "group", gender: "male", genre: "synthetic_pop")

        client.save(first)
        client.save(second)

        XCTAssertEqual(client.load(), second)
    }

    func test_새로_만든_클라이언트도_같은_저장소의_값을_읽는다() throws {
        // 앱 재실행 후 복원 (REQ-CAT-07): 값은 저장소에만 있고 클라이언트 인스턴스에 남지 않는다.
        let category = MatchCategory(decade: "all", artistType: "any", gender: "any", genre: "any")
        CategoryPreferenceClient.live(userDefaults: userDefaults).save(category)

        let reopened = try XCTUnwrap(UserDefaults(suiteName: suiteName))

        XCTAssertEqual(CategoryPreferenceClient.live(userDefaults: reopened).load(), category)
    }

    func test_카탈로그에_없는_값도_판정하지_않고_그대로_돌려준다() {
        // 복원 조합의 허용 여부는 로비가 판정한다 (REQ-CAT-08, tasks.md 7번).
        let client = CategoryPreferenceClient.live(userDefaults: userDefaults)
        let unknown = MatchCategory(decade: "2000s", artistType: "any", gender: "any", genre: "any")

        client.save(unknown)

        XCTAssertEqual(client.load(), unknown)
    }

    func test_JSON_형식으로_저장한다() throws {
        let category = MatchCategory(decade: "2010s", artistType: "solo", gender: "female", genre: "korean_ballad")
        CategoryPreferenceClient.live(userDefaults: userDefaults).save(category)

        let data = try XCTUnwrap(userDefaults.data(forKey: CategoryPreferenceClient.storageKey))
        let object = try XCTUnwrap(try JSONSerialization.jsonObject(with: data) as? [String: String])
        XCTAssertEqual(object, ["decade": "2010s", "artistType": "solo", "gender": "female", "genre": "korean_ballad"])
    }

    func test_저장값을_해석할_수_없으면_nil을_돌려준다() {
        let client = CategoryPreferenceClient.live(userDefaults: userDefaults)
        let cases: [(String, Any)] = [
            ("JSON이 아닌 데이터", Data("broken".utf8)),
            ("필드 누락", Data(#"{"decade":"2010s","artistType":"any","gender":"any"}"#.utf8)),
            ("null 필드", Data(#"{"decade":null,"artistType":"any","gender":"any","genre":"any"}"#.utf8)),
            ("Data가 아닌 값", "2010s")
        ]
        for (name, value) in cases {
            userDefaults.set(value, forKey: CategoryPreferenceClient.storageKey)
            XCTAssertNil(client.load(), name)
        }
    }

    func test_해석할_수_없는_저장값은_다음_저장으로_덮어쓴다() {
        let client = CategoryPreferenceClient.live(userDefaults: userDefaults)
        userDefaults.set(Data("broken".utf8), forKey: CategoryPreferenceClient.storageKey)
        let category = MatchCategory(decade: "any", artistType: "any", gender: "any", genre: "any")

        client.save(category)

        XCTAssertEqual(client.load(), category)
    }
}
