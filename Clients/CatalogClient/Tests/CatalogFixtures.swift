import Foundation
import XCTest

/// `docs/specs/random-matchmaking/fixtures/`를 테스트 번들 리소스로 읽는다.
/// 형식은 fixtures/README.md "Fixture 형식과 실행"을 따른다.
enum CatalogFixtures {
    /// fixture가 들어 있는 `ClientCatalogTests` 번들
    static var bundle: Bundle { Bundle(for: BundleToken.self) }

    static func url(_ name: String) throws -> URL {
        try XCTUnwrap(
            bundle.url(forResource: name, withExtension: "json"),
            "\(name).json이 ClientCatalogTests 리소스에 없다"
        )
    }

    static func data(_ name: String) throws -> Data {
        try Data(contentsOf: url(name))
    }

    /// `catalog-invalid.json`의 변형 레시피 하나
    struct Recipe {
        let name: String
        let file: String
        let path: [String]
        let operation: String
        let value: Any
    }

    static func invalidRecipes(file: String) throws -> [Recipe] {
        let object = try JSONSerialization.jsonObject(with: data("catalog-invalid"))
        let entries = try XCTUnwrap(object as? [[String: Any]], "catalog-invalid.json은 객체 배열이어야 한다")
        return try entries
            .map { entry in
                Recipe(
                    name: try XCTUnwrap(entry["name"] as? String),
                    file: try XCTUnwrap(entry["file"] as? String),
                    path: try XCTUnwrap(entry["path"] as? [String]),
                    operation: try XCTUnwrap(entry["op"] as? String),
                    value: entry["value"] ?? NSNull()
                )
            }
            .filter { $0.file == file }
    }

    /// 원본 파일을 새로 읽고 레시피 하나만 적용한 JSON
    static func applying(_ recipe: Recipe) throws -> Data {
        let baseName = (recipe.file as NSString).deletingPathExtension
        let base = try JSONSerialization.jsonObject(with: data(baseName))
        let mutated = try apply(operation: recipe.operation, path: recipe.path, value: recipe.value, to: base)
        return try JSONSerialization.data(withJSONObject: mutated)
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
