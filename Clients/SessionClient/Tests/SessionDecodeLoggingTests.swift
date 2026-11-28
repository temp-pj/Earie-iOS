import ClientSession
@testable import ClientSessionLive
import Foundation
import Models
import XCTest

/// 디코딩 실패 로그 중 공개(`privacy: .public`)로 남는 분류에 받은 메시지의 값이 들어가지 않는지 확인한다.
/// 오류 전체와 원문은 private로 남긴다.
final class SessionDecodeLoggingTests: XCTestCase {
    func test_디코딩_실패_공개_로그_분류에는_받은_값이_들어가지_않는다() throws {
        let marker = "private-marker"
        let texts = [
            #"{"type":"\#(marker)","payload":{},"timestamp":0}"#,
            #"{"type":"WELCOME","payload":{"roomID":"\#(marker)"},"timestamp":0}"#,
            #"{"type":"PLAYER_JOINED","payload":{"roomID":"\#(marker)","playerID":"\#(marker)"},"timestamp":"\#(marker)"}"#,
            #"{"\#(marker)":"#
        ]

        for text in texts {
            var thrown: (any Error)?
            XCTAssertThrowsError(try MessageCodec.decodeServer(Data(text.utf8))) { thrown = $0 }
            let error = try XCTUnwrap(thrown)
            let category = SessionClient.decodeFailureCategory(error)
            XCTAssertFalse(category.contains(marker), "\(category) / \(text)")
            XCTAssertNotEqual(category, "other", "\(error)")
        }
        XCTAssertEqual(
            SessionClient.decodeFailureCategory(MessageCodecError.unknownType(marker)),
            "unknownType"
        )
        XCTAssertEqual(
            SessionClient.decodeFailureCategory(MessageCodecError.invalidField("roomID")),
            "invalidField(roomID)"
        )
    }
}
