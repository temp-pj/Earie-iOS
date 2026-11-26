import Foundation
import Models
import XCTest

/// 송신 규칙: ID 소문자(INV-03), timestamp 없음, 잘못된 ID는 보내지 않음.
final class MessageCodecEncodingTests: XCTestCase {
    private let upperRequestID = "AAAAAAAA-AAAA-4AAA-8AAA-AAAAAAAAAAAA"
    private let upperRoomID = "BBBBBBBB-BBBB-4BBB-9BBB-BBBBBBBBBBBB"
    private let upperPlayerID = "CCCCCCCC-CCCC-4CCC-ACCC-CCCCCCCCCCCC"

    func test_보내는_ID는_전부_소문자다() throws {
        let category = MatchCategory(decade: "any", artistType: "any", gender: "any", genre: "any")
        let messages: [ClientMessage] = [
            .matchRequest(WireV1.MatchRequestPayload(requestID: upperRequestID, catalogVersion: "test-v1", category: category)),
            .matchCancel(requestID: upperRequestID),
            .leaveRoom(roomID: upperRoomID),
            .startGame(roomID: upperRoomID),
            .readyToPlay(roomID: upperRoomID, roundNumber: 1),
            .submitAnswer(roomID: upperRoomID, answer: "ABC"),
            .kickPlayer(roomID: upperRoomID, targetPlayerID: upperPlayerID)
        ]

        for message in messages {
            let payload = try encodedPayload(message)
            for key in ["requestID", "roomID", "targetPlayerID"] {
                guard let id = payload[key] as? String else { continue }
                XCTAssertEqual(id, id.lowercased(), "\(message.type).\(key)")
            }
        }
    }

    func test_시스템_UUID_문자열도_소문자로_보낸다() throws {
        let uuid = UUID()
        let payload = try encodedPayload(.matchCancel(requestID: uuid.uuidString))
        XCTAssertEqual(payload["requestID"] as? String, uuid.uuidString.lowercased())
    }

    func test_ID가_아닌_값은_대소문자를_바꾸지_않는다() throws {
        let payload = try encodedPayload(.submitAnswer(roomID: upperRoomID, answer: "ABC 정답"))
        XCTAssertEqual(payload["answer"] as? String, "ABC 정답")
    }

    func test_timestamp를_넣지_않는다() throws {
        let data = try MessageCodec.encodeClient(.startGame(roomID: upperRoomID))
        let object = try XCTUnwrap(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(Set(object.keys), ["type", "payload"])
        XCTAssertEqual(object["type"] as? String, "START_GAME")
    }

    func test_UUID_v4가_아닌_ID는_인코딩하지_않는다() {
        XCTAssertThrowsError(try MessageCodec.encodeClient(.leaveRoom(roomID: "garbage")))
        XCTAssertThrowsError(try MessageCodec.encodeClient(.matchCancel(requestID: "00000000-0000-0000-0000-000000000000")))
        XCTAssertThrowsError(try MessageCodec.encodeClient(.kickPlayer(roomID: upperRoomID, targetPlayerID: "garbage")))
    }

    func test_roundNumber가_1보다_작으면_인코딩하지_않는다() {
        XCTAssertThrowsError(try MessageCodec.encodeClient(.readyToPlay(roomID: upperRoomID, roundNumber: 0)))
    }

    func test_카탈로그_버전과_조건값은_검사하지_않고_보낸다() throws {
        // 서버가 MATCH_FAILED(INVALID_CRITERIA)로 답할 대상이다 (protocol.md 멱등성과 순서).
        let category = MatchCategory(decade: "1990s", artistType: "band", gender: "any", genre: "not_in_catalog")
        let payload = try encodedPayload(.matchRequest(WireV1.MatchRequestPayload(
            requestID: upperRequestID,
            catalogVersion: "test-v2",
            category: category
        )))
        XCTAssertEqual(payload["catalogVersion"] as? String, "test-v2")
    }

    private func encodedPayload(_ message: ClientMessage) throws -> [String: Any] {
        let data = try MessageCodec.encodeClient(message)
        let object = try XCTUnwrap(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        return try XCTUnwrap(object["payload"] as? [String: Any])
    }
}
