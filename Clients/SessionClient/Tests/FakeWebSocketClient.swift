import ClientWebSocket
import Foundation

/// 테스트용 `WebSocketClient`. 연결마다 스트림을 하나 만들고, 테스트가 그 스트림에 이벤트를 넣는다.
///
/// 기본 동작은 `WebSocketConnection`과 같다. `connect`가 이전 연결 스트림에 `.disconnected(.normal)`을 넣고 끝낸 뒤,
/// `receive()`는 가장 최근 연결의 스트림을 돌려준다.
/// `closesPreviousOnConnect: false`면 이전 연결 스트림을 열어 둔다. 늦게 온 이전 연결 이벤트를 흉내 낼 때 쓴다.
final class FakeWebSocketClient: @unchecked Sendable {
    struct FakeError: Error, Equatable {}

    private struct Connection {
        let stream: AsyncStream<WebSocketEvent>
        let continuation: AsyncStream<WebSocketEvent>.Continuation
    }

    private let lock = NSLock()
    private let closesPreviousOnConnect: Bool
    private var connections: [Connection] = []
    private var current: Connection?
    private var _connectedURLs: [URL] = []
    private var _sentTexts: [String] = []
    private var _disconnectCount = 0
    private var _connectError: FakeError?

    init(closesPreviousOnConnect: Bool = true) {
        self.closesPreviousOnConnect = closesPreviousOnConnect
    }

    var client: WebSocketClient {
        WebSocketClient(
            connect: { [self] url in
                // 실제 구현처럼 연결 시작과 receive() 사이에 다른 작업이 끼어들 틈을 만든다.
                await Task.yield()
                try lock.withLock {
                    if let error = _connectError { throw error }
                    if closesPreviousOnConnect, let previous = current {
                        previous.continuation.yield(.disconnected(.normal))
                        previous.continuation.finish()
                    }
                    let (stream, continuation) = AsyncStream.makeStream(of: WebSocketEvent.self)
                    let connection = Connection(stream: stream, continuation: continuation)
                    connections.append(connection)
                    current = connection
                    _connectedURLs.append(url)
                }
            },
            send: { [self] text in
                try lock.withLock {
                    guard current != nil else { throw FakeError() }
                    _sentTexts.append(text)
                }
            },
            receive: { [self] in
                lock.withLock { current?.stream ?? AsyncStream { $0.finish() } }
            },
            disconnect: { [self] in
                lock.withLock {
                    _disconnectCount += 1
                    current?.continuation.yield(.disconnected(.normal))
                    current?.continuation.finish()
                    current = nil
                }
            }
        )
    }

    var connectedURLs: [URL] { lock.withLock { _connectedURLs } }
    var sentTexts: [String] { lock.withLock { _sentTexts } }
    var disconnectCount: Int { lock.withLock { _disconnectCount } }
    var connectionCount: Int { lock.withLock { connections.count } }

    func failConnect() {
        lock.withLock { _connectError = FakeError() }
    }

    /// `index`번째(0부터) 연결 스트림에 이벤트를 넣는다.
    func yield(_ event: WebSocketEvent, connection index: Int) {
        lock.withLock { connections[index].continuation }.yield(event)
    }

    func yield(text: String, connection index: Int) {
        yield(.message(text), connection: index)
    }

    /// 끊김 이벤트 없이 `index`번째 연결 스트림을 끝낸다.
    func finish(connection index: Int) {
        lock.withLock { connections[index].continuation }.finish()
    }
}
