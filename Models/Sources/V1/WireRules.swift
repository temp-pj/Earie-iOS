import Foundation

/// protocol.md v1의 값 규칙. 문서와 `fixtures/`가 판정 기준이다.
enum WireRules {
    /// 소문자 canonical UUID v4 (`xxxxxxxx-xxxx-4xxx-[89ab]xxx-xxxxxxxxxxxx`).
    static func isCanonicalID(_ value: String) -> Bool {
        let bytes = Array(value.utf8)
        guard bytes.count == 36 else { return false }
        for (index, byte) in bytes.enumerated() {
            switch index {
            case 8, 13, 18, 23:
                guard byte == UInt8(ascii: "-") else { return false }
            case 14:
                guard byte == UInt8(ascii: "4") else { return false }
            case 19:
                guard "89ab".utf8.contains(byte) else { return false }
            default:
                guard isLowerHex(byte) else { return false }
            }
        }
        return true
    }

    /// 1~64자의 `[A-Za-z0-9._-]`.
    static func isCatalogVersion(_ value: String) -> Bool {
        let bytes = Array(value.utf8)
        guard (1...64).contains(bytes.count) else { return false }
        return bytes.allSatisfy { isASCIIAlphanumeric($0) || "._-".utf8.contains($0) }
    }

    /// 확정된 방 조건. 어느 축에도 any가 없고, all 또는 구체 값만 있다.
    static func isResolvedCategory(_ category: MatchCategory) -> Bool {
        isResolvedDecade(category.decade)
            && ["all", "solo", "group"].contains(category.artistType)
            && ["all", "male", "female"].contains(category.gender)
            && isResolvedGenre(category.genre)
    }

    private static func isResolvedDecade(_ value: String) -> Bool {
        if value == "all" { return true }
        let bytes = Array(value.utf8)
        guard bytes.count == 5, bytes[4] == UInt8(ascii: "s") else { return false }
        return bytes.prefix(4).allSatisfy(isDigit)
    }

    /// `all` 또는 `[a-z][a-z0-9_]*` 태그 (예약어 any 제외).
    private static func isResolvedGenre(_ value: String) -> Bool {
        if value == "all" { return true }
        guard value != "any", let first = value.utf8.first, isLowerAlpha(first) else { return false }
        return value.utf8.allSatisfy { isLowerAlpha($0) || isDigit($0) || $0 == UInt8(ascii: "_") }
    }

    private static func isDigit(_ byte: UInt8) -> Bool {
        (UInt8(ascii: "0")...UInt8(ascii: "9")).contains(byte)
    }

    private static func isLowerAlpha(_ byte: UInt8) -> Bool {
        (UInt8(ascii: "a")...UInt8(ascii: "z")).contains(byte)
    }

    private static func isLowerHex(_ byte: UInt8) -> Bool {
        isDigit(byte) || (UInt8(ascii: "a")...UInt8(ascii: "f")).contains(byte)
    }

    private static func isASCIIAlphanumeric(_ byte: UInt8) -> Bool {
        isDigit(byte) || isLowerAlpha(byte) || (UInt8(ascii: "A")...UInt8(ascii: "Z")).contains(byte)
    }
}
