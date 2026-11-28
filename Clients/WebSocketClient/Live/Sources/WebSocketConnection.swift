//
//  WebSocketDelegate.swift
//  M_GAME
//
//  Created by 송지혁 on 5/16/26.
//

import ClientWebSocket
import Foundation

private final class WebSocketDelegate: NSObject, URLSessionWebSocketDelegate, Sendable {
    let onOpen: @Sendable () -> Void
    
    init(onOpen: @escaping @Sendable () -> Void) {
        self.onOpen = onOpen
    }
    
    func urlSession(_ session: URLSession,
                    webSocketTask: URLSessionWebSocketTask,
                    didOpenWithProtocol protocol: String?) {
        onOpen()
    }
}

public actor WebSocketConnection {
    private var session: URLSession?
    private var task: URLSessionWebSocketTask?
    
    private var continuation: AsyncStream<WebSocketEvent>.Continuation?
    private var stream: AsyncStream<WebSocketEvent> = AsyncStream { $0.finish() }
    
    func connect(url: URL) {
        disconnect()
        
        let (stream, continuation) = AsyncStream<WebSocketEvent>.makeStream()
        self.stream = stream
        self.continuation = continuation
        
        let delegate = WebSocketDelegate(
            onOpen: { continuation.yield(.connected) }
        )
        
        let session = URLSession(configuration: .default, delegate: delegate, delegateQueue: nil)
        self.session = session
        
        task = session.webSocketTask(with: url)
        task?.resume()
        
        startListening()
    }
    
    func send(text: String) async throws {
        guard let task else { throw WebSocketConnectionError.notConnected }
        
        let message = URLSessionWebSocketTask.Message.string(text)
        try await task.send(message)
    }
    
    func receive() -> AsyncStream<WebSocketEvent> { stream }
    
    private func startListening() {
        guard let task, let continuation else { return }
        
        Task { [weak self, task, continuation] in
            while true {
                do {
                    let message = try await task.receive()
                    
                    switch message {
                        case .string(let text):
                            continuation.yield(.message(text))
                            
                        case .data:
                            continue
                            
                        default: break
                    }
                } catch {
                    let reason: WebSocketEvent.CloseReason
                    if let urlError = error as? URLError, urlError.code == .cancelled {
                        reason = .normal
                    } else {
                        reason = .networkError
                    }
                    continuation.yield(.disconnected(reason))
                    continuation.finish()
                    await self?.connectionEnded(task)
                    return
                }
            }
        }
    }
    
    func disconnect() {
        task?.cancel(with: .goingAway, reason: nil)
        continuation?.yield(.disconnected(.normal))
        continuation?.finish()
        continuation = nil
        closeSession()
    }
    
    /// 수신이 끝난 연결(서버 종료, 네트워크 오류)의 세션을 정리한다.
    /// 그사이 새 연결로 바뀌었으면 새 연결은 건드리지 않는다.
    private func connectionEnded(_ endedTask: URLSessionWebSocketTask) {
        guard task === endedTask else { return }
        continuation = nil
        closeSession()
    }
    
    /// URLSession은 invalidate될 때까지 delegate를 잡고 해제되지 않는다.
    /// 연결이 끝날 때마다 invalidate해서 재연결할 때 세션이 쌓이지 않게 한다.
    /// 취소한 태스크의 close frame이 나갈 수 있도록 `finishTasksAndInvalidate`를 쓴다.
    private func closeSession() {
        session?.finishTasksAndInvalidate()
        session = nil
        task = nil
    }
    
}
