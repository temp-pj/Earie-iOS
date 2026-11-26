import Foundation
@testable import Models
import XCTest

/// DONE-01, DONE-02: `fixtures/messages-valid.json`, `fixtures/messages-invalid.json` 기준 코덱 검증.
final class MessageCodecFixtureTests: XCTestCase {
    /// JSONDecoder는 정수 자리의 `1e0`을 1로 읽는다. design 2번이 JSONDecoder 사용을 고정하므로
    /// 클라이언트 방향(`decodeClient`, fixture 재인코딩 검증용)에서만 남는 차이로 기록한다.
    /// 서버 방향 fixture에는 해당 사례가 없다.
    private let knownClientDecodeGaps: Set<String> = ["integer-exponent"]

    // MARK: DONE-01

    func test_정상_서버_메시지_전체를_디코딩한다() throws {
        let cases = try ContractFixtures.validCases().filter { $0.direction == "server" }
        XCTAssertEqual(cases.count, 28)

        for fixture in cases {
            let data = try JSONSerialization.data(withJSONObject: fixture.message)
            do {
                let decoded = try MessageCodec.decodeServer(data)
                let type = (fixture.message as? [String: Any])?["type"] as? String
                XCTAssertEqual(decoded.type, type, fixture.name)
            } catch {
                XCTFail("\(fixture.name): \(error)")
            }
        }
    }

    func test_정상_클라이언트_메시지_전체를_디코딩_후_재인코딩하면_canonical과_같다() throws {
        let cases = try ContractFixtures.validCases().filter { $0.direction == "client" }
        XCTAssertEqual(cases.count, 13)

        for fixture in cases {
            let data = try JSONSerialization.data(withJSONObject: fixture.message)
            do {
                let reencoded = try MessageCodec.encodeClient(MessageCodec.decodeClient(data))
                let actual = try JSONSerialization.jsonObject(with: reencoded) as? NSDictionary
                XCTAssertEqual(actual, try expectedClientEncoding(fixture), fixture.name)
            } catch {
                XCTFail("\(fixture.name): \(error)")
            }
        }
    }

    func test_모든_fixture가_서버나_클라이언트_방향이다() throws {
        let directions = Set(try ContractFixtures.validCases().map(\.direction))
        XCTAssertEqual(directions, ["server", "client"])
    }

    // MARK: DONE-02

    func test_잘못된_서버_방향_메시지는_전부_거부한다() throws {
        let cases = try ContractFixtures.invalidCases().filter { $0.direction == "server" }
        XCTAssertEqual(cases.count, 349)

        let accepted = cases.filter { (try? MessageCodec.decodeServer($0.data)) != nil }.map(\.name)
        XCTAssertEqual(accepted, [], "거부해야 하는데 디코딩된 사례")
    }

    func test_잘못된_클라이언트_방향_메시지는_알려진_차이_외에_전부_거부한다() throws {
        let cases = try ContractFixtures.invalidCases().filter { $0.direction == "client" }
        XCTAssertEqual(cases.count, 115)

        let accepted = cases.filter { (try? MessageCodec.decodeClient($0.data)) != nil }.map(\.name)
        XCTAssertEqual(Set(accepted), knownClientDecodeGaps, "거부 여부가 기록과 다르다")
    }

    func test_서버_방향_코덱은_클라이언트_type을_거부한다() throws {
        let data = Data(#"{"type":"MATCH_REQUEST","payload":{"requestID":"11111111-1111-4111-8111-111111111111","catalogVersion":"test-v1","category":{"decade":"any","artistType":"any","gender":"any","genre":"any"}},"timestamp":1}"#.utf8)
        XCTAssertThrowsError(try MessageCodec.decodeServer(data)) { error in
            XCTAssertEqual(error as? MessageCodecError, .unknownType("MATCH_REQUEST"))
        }
    }

    func test_조건값이나_버전이_틀린_매칭_요청은_형식_오류가_아니다() throws {
        for entry in try ContractFixtures.jsonArray("criteria-invalid") {
            let name = entry["name"] as? String ?? "?"
            let data = try JSONSerialization.data(withJSONObject: try XCTUnwrap(entry["message"]))
            XCTAssertNoThrow(try MessageCodec.decodeClient(data), name)
        }
    }

    // MARK: 값 규칙

    func test_WELCOME의_방_조건은_categories_fixture의_resolvedValid를_따른다() throws {
        for entry in try ContractFixtures.jsonArray("categories") {
            let name = entry["name"] as? String ?? "?"
            let category = try XCTUnwrap(entry["category"])
            let resolvedValid = try XCTUnwrap(entry["resolvedValid"] as? Bool)
            let data = try welcome(replacing: "category", with: category)
            XCTAssertEqual((try? MessageCodec.decodeServer(data)) != nil, resolvedValid, name)
        }
    }

    func test_WELCOME의_catalogVersion은_versions_fixture를_따른다() throws {
        for entry in try ContractFixtures.jsonArray("versions") {
            let value = try XCTUnwrap(entry["value"] as? String)
            let valid = try XCTUnwrap(entry["valid"] as? Bool)
            let data = try welcome(replacing: "catalogVersion", with: value)
            XCTAssertEqual((try? MessageCodec.decodeServer(data)) != nil, valid, value.debugDescription)
        }
    }

    func test_WELCOME_디코딩_값() throws {
        let decoded = try MessageCodec.decodeServer(try welcome(replacing: nil, with: nil))
        XCTAssertEqual(decoded, .welcome(WireV1.WelcomePayload(
            requestID: "11111111-1111-4111-8111-111111111111",
            roomID: "22222222-2222-4222-8222-222222222222",
            playerID: "33333333-3333-4333-8333-333333333333",
            hostID: "33333333-3333-4333-8333-333333333333",
            players: ["33333333-3333-4333-8333-333333333333", "44444444-4444-4444-8444-444444444444"],
            roomState: "waiting",
            maxPlayers: 8,
            category: MatchCategory(decade: "2010s", artistType: "all", gender: "all", genre: "korean_ballad"),
            catalogVersion: "test-v1"
        )))
    }

    func test_승자가_없는_결과는_빈_문자열로_디코딩한다() throws {
        let fixture = try XCTUnwrap(try ContractFixtures.validCases().first { $0.name == "game-over-no-winner" })
        let decoded = try MessageCodec.decodeServer(try JSONSerialization.data(withJSONObject: fixture.message))
        guard case let .gameOver(payload) = decoded else { return XCTFail("\(decoded)") }
        XCTAssertEqual(payload.winner, "")
    }

    // MARK: Helpers

    /// canonical이 있으면 canonical, 없으면 원본에서 `timestamp`를 뺀 것.
    /// `encodeClient`는 timestamp를 넣지 않는다 (design 7).
    private func expectedClientEncoding(_ fixture: ContractFixtures.ValidCase) throws -> NSDictionary {
        var expected = try XCTUnwrap((fixture.canonical ?? fixture.message) as? [String: Any])
        expected.removeValue(forKey: "timestamp")
        return expected as NSDictionary
    }

    private func welcome(replacing key: String?, with value: Any?) throws -> Data {
        let fixture = try XCTUnwrap(try ContractFixtures.validCases().first { $0.name == "welcome" })
        var message = try XCTUnwrap(fixture.message as? [String: Any])
        if let key {
            var payload = try XCTUnwrap(message["payload"] as? [String: Any])
            payload[key] = value
            message["payload"] = payload
        }
        return try JSONSerialization.data(withJSONObject: message)
    }
}
