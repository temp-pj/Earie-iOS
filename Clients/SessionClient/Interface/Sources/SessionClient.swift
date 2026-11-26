import Foundation
import Models

/// v1 서버와의 WebSocket 연결 하나를 다루는 클라이언트 (design 7).
public struct SessionClient: Sendable {
    /// 새 연결을 시작하고, 그 연결 전용 스트림을 돌려준다.
    /// 실패도 스트림의 `.disconnected`로 온다. 연결이 끊기면 스트림이 끝난다.
    public var connect: @Sendable () async -> AsyncStream<SessionEvent>
    /// 연결이 없거나 인코딩에 실패하면 throw한다.
    public var send: @Sendable (ClientMessage) async throws -> Void
    /// 현재 연결을 닫는다. 이번 기능에서는 앱 종료 외에 호출하지 않는다.
    public var disconnect: @Sendable () async -> Void

    public init(
        connect: @escaping @Sendable () async -> AsyncStream<SessionEvent>,
        send: @escaping @Sendable (ClientMessage) async throws -> Void,
        disconnect: @escaping @Sendable () async -> Void
    ) {
        self.connect = connect
        self.send = send
        self.disconnect = disconnect
    }
}

public enum SessionEvent: Equatable, Sendable {
    case connected
    case message(ServerMessage)
    case disconnected(SessionCloseReason)
}

public enum SessionCloseReason: Equatable, Sendable {
    case normal
    case networkError
}
