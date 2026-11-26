import Foundation
import XCTest

/// `docs/specs/random-matchmaking/fixtures/`를 테스트 번들 리소스로 읽는다.
/// 형식은 fixtures/README.md "Fixture 형식과 실행"을 따른다.
enum ContractFixtures {
    struct ValidCase {
        let name: String
        let direction: String
        let message: Any
        let canonical: Any?
    }

    struct InvalidCase {
        let name: String
        let direction: String
        let data: Data
    }

    static func url(_ name: String) throws -> URL {
        let bundle = Bundle(for: BundleToken.self)
        return try XCTUnwrap(
            bundle.url(forResource: name, withExtension: "json"),
            "\(name).json이 ModelsTests 리소스에 없다"
        )
    }

    static func data(_ name: String) throws -> Data {
        try Data(contentsOf: url(name))
    }

    static func jsonArray(_ name: String) throws -> [[String: Any]] {
        let object = try JSONSerialization.jsonObject(with: data(name), options: [.fragmentsAllowed])
        return try XCTUnwrap(object as? [[String: Any]], "\(name).json은 객체 배열이어야 한다")
    }

    static func validCases() throws -> [ValidCase] {
        try jsonArray("messages-valid").map { entry in
            ValidCase(
                name: try XCTUnwrap(entry["name"] as? String),
                direction: try XCTUnwrap(entry["direction"] as? String),
                message: try XCTUnwrap(entry["message"]),
                canonical: entry["canonical"]
            )
        }
    }

    /// 레시피를 정상 fixture에 적용한 결과. raw 사례는 텍스트를 그대로 쓴다.
    static func invalidCases() throws -> [InvalidCase] {
        let valid = Dictionary(uniqueKeysWithValues: try validCases().map { ($0.name, $0) })
        return try jsonArray("messages-invalid").map { recipe in
            let name = try XCTUnwrap(recipe["name"] as? String)
            if let raw = recipe["raw"] as? String {
                return InvalidCase(
                    name: name,
                    direction: try XCTUnwrap(recipe["direction"] as? String),
                    data: Data(raw.utf8)
                )
            }
            let baseName = try XCTUnwrap(recipe["base"] as? String)
            let base = try XCTUnwrap(valid[baseName], "\(name)의 base \(baseName)가 없다")
            var message = base.message
            if let operation = recipe["op"] as? String {
                let path = try XCTUnwrap(recipe["path"] as? [String])
                message = try apply(operation: operation, path: path, value: recipe["value"] ?? NSNull(), to: message)
            }
            return InvalidCase(
                name: name,
                direction: recipe["direction"] as? String ?? base.direction,
                data: try JSONSerialization.data(withJSONObject: message, options: [.fragmentsAllowed])
            )
        }
    }

    /// `path`는 JSON 키 또는 0부터 시작하는 배열 인덱스 문자열 목록이다.
    private static func apply(operation: String, path: [String], value: Any, to node: Any) throws -> Any {
        let key = try XCTUnwrap(path.first)
        let rest = Array(path.dropFirst())
        if var array = node as? [Any] {
            let index = try XCTUnwrap(Int(key))
            if rest.isEmpty {
                if operation == "remove" { array.remove(at: index) } else { array[index] = value }
            } else {
                array[index] = try apply(operation: operation, path: rest, value: value, to: array[index])
            }
            return array
        }
        var object = try XCTUnwrap(node as? [String: Any], "경로 \(path)가 객체/배열을 가리키지 않는다")
        if rest.isEmpty {
            switch operation {
            case "remove": object.removeValue(forKey: key)
            case "set": object[key] = value
            default: XCTFail("모르는 op \(operation)")
            }
        } else {
            object[key] = try apply(operation: operation, path: rest, value: value, to: try XCTUnwrap(object[key]))
        }
        return object
    }

    private final class BundleToken {}
}
