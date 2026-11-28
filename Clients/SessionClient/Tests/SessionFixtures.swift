import Foundation
import XCTest

/// `docs/specs/random-matchmaking/fixtures/messages-valid.json`을 테스트 번들 리소스로 읽는다.
enum SessionFixtures {
    struct ServerCase {
        let name: String
        let type: String
        let object: [String: Any]

        var text: String {
            get throws {
                let data = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
                return try XCTUnwrap(String(data: data, encoding: .utf8))
            }
        }
    }

    /// 서버→클라이언트 방향의 정상 메시지 전체 (fixture 순서)
    static func validServerCases() throws -> [ServerCase] {
        let bundle = Bundle(for: BundleToken.self)
        let url = try XCTUnwrap(
            bundle.url(forResource: "messages-valid", withExtension: "json"),
            "messages-valid.json이 ClientSessionTests 리소스에 없다"
        )
        let entries = try XCTUnwrap(
            try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [[String: Any]]
        )
        return try entries
            .filter { $0["direction"] as? String == "server" }
            .map { entry in
                let object = try XCTUnwrap(entry["message"] as? [String: Any])
                return ServerCase(
                    name: try XCTUnwrap(entry["name"] as? String),
                    type: try XCTUnwrap(object["type"] as? String),
                    object: object
                )
            }
    }

    static func validServerCase(type: String) throws -> ServerCase {
        try XCTUnwrap(try validServerCases().first { $0.type == type }, "\(type) fixture가 없다")
    }

    private final class BundleToken {}
}
