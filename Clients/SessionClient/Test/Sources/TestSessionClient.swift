import ClientSession
import ConcurrencyExtras
import Foundation
import Models

/// 테스트용 `SessionClient`. 연결마다 테스트가 쥔 스트림을 돌려주고, `send`를 기록한다.
///
/// - `connect()`를 n번째(0부터)로 호출하면 n번째 연결 스트림을 돌려준다.
/// - `yield(_:connection:)`는 아직 열리지 않은 연결에도 이벤트를 미리 넣을 수 있다.
///   이벤트는 그 연결의 스트림에 쌓였다가 `connect()`가 그 스트림을 돌려준 뒤 소비된다.
///
/// ```swift
/// let session = TestSessionClient()
/// let store = TestStore(...) { $0.sessionClient = session.client }
/// session.yield(.connected, connection: 0)
/// session.yield(.message(.welcome(...)), connection: 0)
/// ```
public final class TestSessionClient: Sendable {
    private struct Connection: Sendable {
        let stream: AsyncStream<SessionEvent>
        let continuation: AsyncStream<SessionEvent>.Continuation
    }

    private let connections = LockIsolated<[Connection]>([])
    private let connectCalls = LockIsolated(0)
    private let sent = LockIsolated<[ClientMessage]>([])
    private let disconnectCalls = LockIsolated(0)
    private let sendError = LockIsolated<(any Error & Sendable)?>(nil)

    public init() {}

    public var client: SessionClient {
        SessionClient(
            connect: { [self] in
                let index = connectCalls.withValue { calls in
                    defer { calls += 1 }
                    return calls
                }
                return connection(at: index).stream
            },
            send: { [self] message in
                if let error = sendError.value { throw error }
                sent.withValue { $0.append(message) }
            },
            disconnect: { [self] in
                disconnectCalls.withValue { $0 += 1 }
            }
        )
    }

    /// `connect()`가 호출된 횟수
    public var connectCount: Int { connectCalls.value }

    /// `send`로 성공한 메시지 (보낸 순서)
    public var sentMessages: [ClientMessage] { sent.value }

    /// `disconnect()`가 호출된 횟수
    public var disconnectCount: Int { disconnectCalls.value }

    /// `index`번째 연결(0부터) 스트림에 이벤트를 넣는다.
    public func yield(_ event: SessionEvent, connection index: Int) {
        connection(at: index).continuation.yield(event)
    }

    /// 가장 최근에 열린 연결 스트림에 이벤트를 넣는다. 아직 연결이 없으면 0번째 연결에 넣는다.
    public func yield(_ event: SessionEvent) {
        yield(event, connection: max(connectCount - 1, 0))
    }

    /// `index`번째 연결 스트림을 끝낸다.
    public func finish(connection index: Int) {
        connection(at: index).continuation.finish()
    }

    /// 이후의 `send`가 `error`로 throw하게 한다. nil이면 다시 성공한다.
    public func setSendError(_ error: (any Error & Sendable)?) {
        sendError.setValue(error)
    }

    private func connection(at index: Int) -> Connection {
        connections.withValue { connections in
            while connections.count <= index {
                let (stream, continuation) = AsyncStream.makeStream(of: SessionEvent.self)
                connections.append(Connection(stream: stream, continuation: continuation))
            }
            return connections[index]
        }
    }
}

/// `TestSessionClient.setSendError`에 쓸 수 있는 기본 오류
public struct TestSessionSendError: Error, Equatable, Sendable {
    public init() {}
}
