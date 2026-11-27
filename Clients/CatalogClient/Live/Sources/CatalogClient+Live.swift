import ClientCatalog
import Foundation
import Models

/// `CatalogClient.load`가 던지는 오류
public enum CatalogLoadError: Error, Equatable, Sendable {
    /// 파일이 없다
    case fileNotFound
    /// 파일은 있지만 읽을 수 없다
    case unreadable
    /// JSON이 아니거나 `CatalogProjection` 형식(필수 필드, null, 타입)에 맞지 않는다
    case invalidFormat
}

public extension CatalogClient {
    /// 앱 번들에 들어 있는 카탈로그 파일 이름 (`M_GAME/Resources/catalog-projection.json`)
    static let bundledResourceName = "catalog-projection"

    /// 앱 번들(`Bundle.main`)의 `catalog-projection.json`을 읽는다.
    static var live: CatalogClient {
        live(bundle: .main)
    }

    /// `bundle`의 `catalog-projection.json`을 읽는다.
    static func live(bundle: Bundle) -> CatalogClient {
        CatalogClient {
            guard let url = bundle.url(forResource: bundledResourceName, withExtension: "json") else {
                throw CatalogLoadError.fileNotFound
            }
            return try loadProjection(at: url)
        }
    }

    /// `fileURL`의 파일을 읽는다.
    static func live(fileURL: URL) -> CatalogClient {
        CatalogClient {
            try loadProjection(at: fileURL)
        }
    }
}

/// 카탈로그 내용(버전, 연대, 장르, 조합)은 파일에서만 읽고 코드에 두지 않는다 (requirements 4번).
/// 허용 조합이 비었는지 등 이용 가능 여부는 판정하지 않는다. 그 판정은 로비가 한다 (REQ-CAT-06).
private func loadProjection(at url: URL) throws -> CatalogProjection {
    let data: Data
    do {
        data = try Data(contentsOf: url)
    } catch let error as CocoaError where error.code == .fileReadNoSuchFile {
        throw CatalogLoadError.fileNotFound
    } catch {
        throw CatalogLoadError.unreadable
    }
    do {
        return try JSONDecoder().decode(CatalogProjection.self, from: data)
    } catch {
        throw CatalogLoadError.invalidFormat
    }
}
