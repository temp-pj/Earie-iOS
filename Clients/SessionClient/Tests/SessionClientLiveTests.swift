import ClientSession
@testable import ClientSessionLive
import Foundation
import Models
import XCTest

/// T2: `ClientSessionLive`를 테스트용 `WebSocketClient`로 검증한다 (tasks.md 8번 T2).
///
/// 모든 테스트는 소켓 스트림을 끝까지 흘린 뒤 결과 스트림을 끝까지 모아서 비교한다. 시간 대기는 쓰지 않는다.
final class SessionClientLiveTests: XCTestCase {
    private let host = "127.0.0.1:8080"

    // MARK: - URL (REQ-MATCH-02, design 7)

    func test_연결_URL은_protocolVersion_1이고_room_query가_없다() async throws {
        let socket = FakeWebSocketClient()
        let client = SessionClient.make(host: { [host] in host }, webSocketClient: socket.client)

        _ = await client.connect()

        let url = try XCTUnwrap(socket.connectedURLs.first)
        XCTAssertEqual(url.absoluteString, "ws://127.0.0.1:8080/ws?protocolVersion=1")
        let components = try XCTUnwrap(URLComponents(url: url, resolvingAgainstBaseURL: false))
        XCTAssertEqual(components.scheme, "ws")
        XCTAssertEqual(components.host, "127.0.0.1")
        XCTAssertEqual(components.port, 8080)
        XCTAssertEqual(components.path, "/ws")
        XCTAssertEqual(components.queryItems, [URLQueryItem(name: "protocolVersion", value: "1")])
        XCTAssertFalse(components.queryItems?.contains { $0.name == "room" } ?? false)
    }

    func test_포트_없는_호스트도_같은_경로와_query로_연결한다() {
        XCTAssertEqual(SessionURL.make(host: "example.com")?.absoluteString, "ws://example.com/ws?protocolVersion=1")
    }

    func test_서버_주소가_없거나_잘못되면_연결하지_않고_networkError로_끝난다() async {
        let invalidHosts: [String?] = [nil, "", "127.0.0.1:8080/ws", "host?room=x", "a b", "user@host", "host#x"]

        for invalid in invalidHosts {
            let socket = FakeWebSocketClient()
            let client = SessionClient.make(host: { invalid }, webSocketClient: socket.client)

            let events = await collect(client.connect())

            XCTAssertEqual(events, [.disconnected(.networkError)], "\(String(describing: invalid))")
            XCTAssertEqual(socket.connectionCount, 0, "\(String(describing: invalid))")
        }
    }

    func test_서버_주소는_Info_plist의_SERVER_HOST를_공백을_빼고_읽는다() {
        XCTAssertEqual(ServerHost.value(in: ["SERVER_HOST": " 127.0.0.1:8080\n"]), "127.0.0.1:8080")
        XCTAssertNil(ServerHost.value(in: ["SERVER_HOST": "  "]))
        XCTAssertNil(ServerHost.value(in: ["SERVER_HOST": 8080]))
        XCTAssertNil(ServerHost.value(in: [:]))
        XCTAssertNil(ServerHost.value(in: nil))
    }

    // MARK: - 연결마다 새 스트림 (design 7, 9)

    func test_연결마다_새_스트림을_돌려주고_이전_스트림은_끊김으로_끝난다() async throws {
        let socket = FakeWebSocketClient()
        let client = makeClient(socket)
        let welcome = try SessionFixtures.validServerCase(type: "WELCOME")

        let first = await client.connect()
        socket.yield(.connected, connection: 0)
        let second = await client.connect()
        socket.yield(.connected, connection: 1)
        socket.yield(text: try welcome.text, connection: 1)
        socket.yield(.disconnected(.normal), connection: 1)

        let firstEvents = await collect(first)
        let secondEvents = await collect(second)

        XCTAssertEqual(socket.connectionCount, 2)
        XCTAssertEqual(firstEvents, [.connected, .disconnected(.normal)])
        XCTAssertEqual(secondEvents, [.connected, .message(try decoded(welcome)), .disconnected(.normal)])
    }

    func test_이전_연결의_늦은_이벤트는_새_스트림에_섞이지_않는다() async throws {
        let socket = FakeWebSocketClient(closesPreviousOnConnect: false)
        let client = makeClient(socket)
        let oldMessage = try SessionFixtures.validServerCase(type: "PLAYER_JOINED")
        let newMessage = try SessionFixtures.validServerCase(type: "WELCOME")

        let first = await client.connect()
        let second = await client.connect()
        // 새 연결이 열린 뒤에 이전 연결로 메시지가 늦게 도착한다.
        socket.yield(text: try oldMessage.text, connection: 0)
        socket.yield(.disconnected(.normal), connection: 0)
        socket.yield(.connected, connection: 1)
        socket.yield(text: try newMessage.text, connection: 1)
        socket.yield(.disconnected(.networkError), connection: 1)

        let firstEvents = await collect(first)
        let secondEvents = await collect(second)

        XCTAssertEqual(firstEvents, [.message(try decoded(oldMessage)), .disconnected(.normal)])
        XCTAssertEqual(secondEvents, [.connected, .message(try decoded(newMessage)), .disconnected(.networkError)])
    }

    func test_동시에_연결해도_스트림마다_한_연결의_이벤트만_받는다() async throws {
        let socket = FakeWebSocketClient(closesPreviousOnConnect: false)
        let client = makeClient(socket)
        let messages = try SessionFixtures.validServerCases().prefix(2).map { try $0.text }

        async let streamA = client.connect()
        async let streamB = client.connect()
        let streams = await [streamA, streamB]

        XCTAssertEqual(socket.connectionCount, 2)
        for index in 0..<2 {
            socket.yield(text: messages[index], connection: index)
            socket.yield(.disconnected(.normal), connection: index)
        }
        var results: [[SessionEvent]] = []
        for stream in streams {
            results.append(await collect(stream))
        }

        let expected = try messages.map { text in
            [SessionEvent.message(try MessageCodec.decodeServer(Data(text.utf8))), .disconnected(.normal)]
        }
        XCTAssertEqual(results.count, 2)
        XCTAssertTrue(results.allSatisfy(expected.contains), "\(results)")
        XCTAssertNotEqual(results[0], results[1], "두 스트림이 같은 연결을 읽었다")
    }

    // MARK: - SessionEvent 변환

    func test_정상_서버_메시지_전체를_수신_순서대로_SessionEvent로_바꾼다() async throws {
        let socket = FakeWebSocketClient()
        let client = makeClient(socket)
        let cases = try SessionFixtures.validServerCases()
        XCTAssertEqual(cases.count, 28)

        let stream = await client.connect()
        socket.yield(.connected, connection: 0)
        for fixture in cases {
            socket.yield(text: try fixture.text, connection: 0)
        }
        socket.yield(.disconnected(.normal), connection: 0)
        let events = await collect(stream)

        let expected: [SessionEvent] = [.connected]
            + (try cases.map { .message(try decoded($0)) })
            + [.disconnected(.normal)]
        XCTAssertEqual(events, expected)
        let receivedTypes = events.compactMap { event -> String? in
            if case let .message(message) = event { return message.type }
            return nil
        }
        XCTAssertEqual(receivedTypes, cases.map(\.type))
    }

    func test_networkError_끊김을_전달하고_그_뒤로는_아무것도_내보내지_않는다() async throws {
        let socket = FakeWebSocketClient(closesPreviousOnConnect: false)
        let client = makeClient(socket)
        let late = try SessionFixtures.validServerCase(type: "PLAYER_LEFT")

        let stream = await client.connect()
        socket.yield(.connected, connection: 0)
        socket.yield(.disconnected(.networkError), connection: 0)
        socket.yield(text: try late.text, connection: 0)
        socket.finish(connection: 0)

        let events = await collect(stream)

        XCTAssertEqual(events, [.connected, .disconnected(.networkError)])
    }

    func test_소켓_스트림이_끊김_이벤트_없이_끝나도_networkError로_끝낸다() async {
        let socket = FakeWebSocketClient()
        let client = makeClient(socket)

        let stream = await client.connect()
        socket.yield(.connected, connection: 0)
        socket.finish(connection: 0)

        let events = await collect(stream)

        XCTAssertEqual(events, [.connected, .disconnected(.networkError)])
    }

    func test_연결_시작이_실패하면_networkError로_끝난다() async {
        let socket = FakeWebSocketClient()
        socket.failConnect()
        let client = makeClient(socket)

        let events = await collect(client.connect())

        XCTAssertEqual(events, [.disconnected(.networkError)])
    }

    // MARK: - 디코딩 실패 폐기 (REQ-FAIL-04)

    func test_디코딩에_실패한_메시지는_버리고_다음_메시지는_정상_전달한다() async throws {
        let socket = FakeWebSocketClient()
        let client = makeClient(socket)
        let welcome = try SessionFixtures.validServerCase(type: "WELCOME")
        let joined = try SessionFixtures.validServerCase(type: "PLAYER_JOINED")
        let invalidTexts = try invalidServerTexts(from: welcome)

        let stream = await client.connect()
        socket.yield(.connected, connection: 0)
        for text in invalidTexts {
            socket.yield(text: text, connection: 0)
        }
        socket.yield(text: try welcome.text, connection: 0)
        for text in invalidTexts {
            socket.yield(text: text, connection: 0)
        }
        socket.yield(text: try joined.text, connection: 0)
        socket.yield(.disconnected(.normal), connection: 0)
        let events = await collect(stream)

        XCTAssertEqual(events, [
            .connected,
            .message(try decoded(welcome)),
            .message(try decoded(joined)),
            .disconnected(.normal)
        ])
        XCTAssertEqual(socket.disconnectCount, 0, "디코딩 실패로 연결을 닫지 않는다")
    }

    // MARK: - 송신

    func test_send는_코덱으로_인코딩한_JSON_문자열을_보내고_ID는_소문자다() async throws {
        let socket = FakeWebSocketClient()
        let client = makeClient(socket)
        let message = ClientMessage.matchRequest(WireV1.MatchRequestPayload(
            requestID: "AAAAAAAA-AAAA-4AAA-8AAA-AAAAAAAAAAAA",
            catalogVersion: "test-v1",
            category: MatchCategory(decade: "2010s", artistType: "any", gender: "any", genre: "korean_ballad")
        ))

        _ = await client.connect()
        try await client.send(message)

        let text = try XCTUnwrap(socket.sentTexts.first)
        XCTAssertEqual(socket.sentTexts.count, 1)
        XCTAssertEqual(text, String(bytes: try MessageCodec.encodeClient(message), encoding: .utf8))
        XCTAssertTrue(text.contains("aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa"))
        XCTAssertFalse(text.contains("AAAAAAAA"))
        XCTAssertEqual(
            try MessageCodec.decodeClient(Data(text.utf8)),
            .matchRequest(WireV1.MatchRequestPayload(
                requestID: "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa",
                catalogVersion: "test-v1",
                category: MatchCategory(decade: "2010s", artistType: "any", gender: "any", genre: "korean_ballad")
            ))
        )
    }

    func test_send는_연결이_없으면_throw한다() async {
        let socket = FakeWebSocketClient()
        let client = makeClient(socket)

        do {
            try await client.send(.leaveRoom(roomID: "22222222-2222-4222-8222-222222222222"))
            XCTFail("연결 없이 send가 성공했다")
        } catch {
            XCTAssertEqual(error as? FakeWebSocketClient.FakeError, FakeWebSocketClient.FakeError())
        }
        XCTAssertEqual(socket.sentTexts, [])
    }

    func test_send는_인코딩에_실패하면_throw하고_보내지_않는다() async {
        let socket = FakeWebSocketClient()
        let client = makeClient(socket)
        _ = await client.connect()

        do {
            try await client.send(.matchCancel(requestID: "not-a-uuid"))
            XCTFail("잘못된 ID로 send가 성공했다")
        } catch {
            XCTAssertTrue(error is MessageCodecError, "\(error)")
        }
        XCTAssertEqual(socket.sentTexts, [])
    }

    // MARK: - 연결 종료 (REQ-FAIL-03)

    func test_disconnect는_소켓을_닫고_현재_스트림은_끊김으로_끝난다() async {
        let socket = FakeWebSocketClient()
        let client = makeClient(socket)

        let stream = await client.connect()
        socket.yield(.connected, connection: 0)
        await client.disconnect()
        let events = await collect(stream)

        XCTAssertEqual(socket.disconnectCount, 1)
        XCTAssertEqual(events, [.connected, .disconnected(.normal)])
    }

    func test_방_나가기_강퇴_매칭_취소_메시지를_받아도_스스로_연결을_닫지_않는다() async throws {
        let socket = FakeWebSocketClient()
        let client = makeClient(socket)
        let types = ["MATCH_CANCELLED", "ROOM_LEFT", "PLAYER_KICKED"]

        let stream = await client.connect()
        socket.yield(.connected, connection: 0)
        for type in types {
            socket.yield(text: try SessionFixtures.validServerCase(type: type).text, connection: 0)
        }
        try await client.send(.leaveRoom(roomID: "22222222-2222-4222-8222-222222222222"))
        socket.yield(.disconnected(.normal), connection: 0)
        let events = await collect(stream)

        XCTAssertEqual(events.count, types.count + 2)
        XCTAssertEqual(socket.disconnectCount, 0)
        XCTAssertEqual(socket.connectionCount, 1)
    }

    // MARK: - Helpers

    private func makeClient(_ socket: FakeWebSocketClient) -> SessionClient {
        SessionClient.make(host: { [host] in host }, webSocketClient: socket.client)
    }

    private func collect(_ stream: AsyncStream<SessionEvent>) async -> [SessionEvent] {
        var events: [SessionEvent] = []
        for await event in stream {
            events.append(event)
        }
        return events
    }

    private func decoded(_ fixture: SessionFixtures.ServerCase) throws -> ServerMessage {
        try MessageCodec.decodeServer(Data(try fixture.text.utf8))
    }

    /// 형식 오류, 모르는 type, 방향이 틀린 type, 필수 필드 누락, 대문자 UUID
    private func invalidServerTexts(from base: SessionFixtures.ServerCase) throws -> [String] {
        func text(_ object: [String: Any]) throws -> String {
            let data = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
            return try XCTUnwrap(String(bytes: data, encoding: .utf8))
        }
        var unknownType = base.object
        unknownType["type"] = "NOT_A_TYPE"
        var clientType = base.object
        clientType["type"] = "MATCH_REQUEST"
        var missingTimestamp = base.object
        missingTimestamp.removeValue(forKey: "timestamp")
        var missingPayload = base.object
        missingPayload.removeValue(forKey: "payload")
        // fixture의 ID는 숫자뿐이라 대문자로 바꿔도 같다. 영문자가 든 대문자 UUID를 넣는다.
        var uppercaseID = base.object
        var payload = try XCTUnwrap(uppercaseID["payload"] as? [String: Any])
        payload["roomID"] = "AAAAAAAA-AAAA-4AAA-8AAA-AAAAAAAAAAAA"
        uppercaseID["payload"] = payload

        let texts = [
            "{",
            "",
            "[]",
            "null",
            #"{"type":"WELCOME"}"#,
            try text(unknownType),
            try text(clientType),
            try text(missingTimestamp),
            try text(missingPayload),
            try text(uppercaseID)
        ]
        for text in texts {
            XCTAssertThrowsError(try MessageCodec.decodeServer(Data(text.utf8)), "디코딩되면 안 되는 사례: \(text)")
        }
        return texts
    }
}
