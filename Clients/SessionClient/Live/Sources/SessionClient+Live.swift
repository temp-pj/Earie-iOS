import ClientSession
import ClientWebSocket
import ClientWebSocketLive
import Foundation
import Models
import OSLog

public extension SessionClient {
    /// Info.plist `SERVER_HOST`의 서버에 `ws://{host}/ws?protocolVersion=1`로 연결한다.
    ///
    /// 주소는 `connect`할 때 읽는다. 주소가 없거나 잘못되면 그 연결 스트림이 `.disconnected(.networkError)`로 끝난다.
    static var live: SessionClient {
        make(host: { ServerHost.value(in: Bundle.main.infoDictionary) }, webSocketClient: .live)
    }

    /// 통합 테스트용. `host`는 `"127.0.0.1:8080"` 형식이다.
    ///
    /// 호출할 때마다 자기 `WebSocketClient.live`(연결 하나)를 갖는 독립 인스턴스를 만든다.
    static func live(host: String) -> SessionClient {
        make(host: { host }, webSocketClient: .live)
    }
}

enum SessionClientError: Error, Equatable {
    case encodingFailed
}

private let logger = Logger(subsystem: "io.tuist.MGAME.ClientSessionLive", category: "SessionClient")

extension SessionClient {
    /// `live`, `live(host:)`의 실제 구성. 테스트는 테스트용 `WebSocketClient`를 넣는다.
    static func make(
        host: @escaping @Sendable () -> String?,
        webSocketClient: WebSocketClient
    ) -> SessionClient {
        // connect(url) 직후의 receive()가 다른 connect의 스트림을 받지 않도록 연결 시작과 종료를 한 줄로 세운다.
        let queue = ConnectionQueue()

        return SessionClient(
            connect: {
                await queue.run {
                    await openStream(host: host(), webSocketClient: webSocketClient)
                }
            },
            send: { message in
                let data = try MessageCodec.encodeClient(message)
                guard let text = String(data: data, encoding: .utf8) else {
                    throw SessionClientError.encodingFailed
                }
                try await webSocketClient.send(text)
            },
            disconnect: {
                await queue.run {
                    do {
                        try await webSocketClient.disconnect()
                    } catch {
                        logger.error("disconnect 실패: \(String(describing: error), privacy: .public)")
                    }
                }
            }
        )
    }

    /// 연결 하나를 시작하고 그 연결의 이벤트만 담는 스트림을 돌려준다.
    /// 스트림은 `.disconnected`를 정확히 한 번 내고 끝난다.
    private static func openStream(host: String?, webSocketClient: WebSocketClient) async -> AsyncStream<SessionEvent> {
        guard let host, let url = SessionURL.make(host: host) else {
            logger.error("서버 주소가 없거나 잘못되어 연결하지 않는다")
            return .closed(.networkError)
        }

        do {
            try await webSocketClient.connect(url)
        } catch {
            logger.error("연결 시작 실패: \(String(describing: error), privacy: .public)")
            return .closed(.networkError)
        }
        let source = await webSocketClient.receive()

        return AsyncStream { continuation in
            let task = Task {
                for await event in source {
                    switch event {
                    case .connected:
                        continuation.yield(.connected)
                    case let .message(text):
                        if let message = decode(text) {
                            continuation.yield(.message(message))
                        }
                    case let .disconnected(reason):
                        continuation.yield(.disconnected(SessionCloseReason(reason)))
                        continuation.finish()
                        return
                    }
                }
                // 소켓 스트림이 끊김 이벤트 없이 끝나도 App이 연결 종료를 알 수 있게 한다.
                // 소비자가 스트림을 버려서 끝난 경우(취소)에는 보낼 곳이 없다.
                if !Task.isCancelled {
                    continuation.yield(.disconnected(.networkError))
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    /// 해석할 수 없는 메시지는 로그만 남기고 버린다 (REQ-FAIL-04).
    private static func decode(_ text: String) -> ServerMessage? {
        do {
            return try MessageCodec.decodeServer(Data(text.utf8))
        } catch {
            // 오류 값에도 받은 내용(모르는 type 문자열 등)이 들어갈 수 있어서, 공개 로그에는 분류만 남긴다.
            logger.error("수신 메시지 디코딩 실패, 버림: \(decodeFailureCategory(error), privacy: .public) / 오류: \(String(describing: error), privacy: .private) / 원문: \(text, privacy: .private)")
            return nil
        }
    }

    /// 받은 메시지의 값이 들어가지 않는 디코딩 실패 분류.
    /// `invalidField`의 필드 이름은 코덱 코드가 정한 상수라 그대로 둔다.
    static func decodeFailureCategory(_ error: any Error) -> String {
        switch error {
        case MessageCodecError.unknownType:
            return "unknownType"
        case let MessageCodecError.invalidField(field):
            return "invalidField(\(field))"
        case let decodingError as DecodingError:
            switch decodingError {
            case .typeMismatch: return "typeMismatch"
            case .valueNotFound: return "valueNotFound"
            case .keyNotFound: return "keyNotFound"
            case .dataCorrupted: return "dataCorrupted"
            @unknown default: return "decodingError"
            }
        default:
            return "other"
        }
    }
}

private extension SessionCloseReason {
    init(_ reason: WebSocketEvent.CloseReason) {
        switch reason {
        case .normal: self = .normal
        case .networkError: self = .networkError
        }
    }
}

private extension AsyncStream where Element == SessionEvent {
    static func closed(_ reason: SessionCloseReason) -> Self {
        AsyncStream { continuation in
            continuation.yield(.disconnected(reason))
            continuation.finish()
        }
    }
}

/// 넘겨받은 작업을 들어온 순서대로 하나씩 실행한다.
final class ConnectionQueue: @unchecked Sendable {
    private let lock = NSLock()
    private var tail: Task<Void, Never>?

    func run<T: Sendable>(_ operation: @escaping @Sendable () async -> T) async -> T {
        let task: Task<T, Never> = lock.withLock {
            let previous = tail
            let task = Task {
                await previous?.value
                return await operation()
            }
            tail = Task { _ = await task.value }
            return task
        }
        return await task.value
    }
}
