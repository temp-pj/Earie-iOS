import Foundation

/// 매칭 요청과 방 조건에 쓰는 음악 조건. 값은 wire 문자열 그대로다 (protocol.md "Category 공통 타입").
/// 네 필드가 모두 같으면 같은 조합이다.
public struct MatchCategory: Codable, Hashable, Sendable {
    public var decade: String
    public var artistType: String
    public var gender: String
    public var genre: String

    public init(decade: String, artistType: String, gender: String, genre: String) {
        self.decade = decade
        self.artistType = artistType
        self.gender = gender
        self.genre = genre
    }
}
