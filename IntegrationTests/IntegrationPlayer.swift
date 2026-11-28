import ClientSession
import ClientSessionLive
import Foundation
import Models

/// 로컬 v1 서버에 붙은 실제 연결 하나 (tasks.md 9번).
///
/// `SessionClient.live(host:)` 인스턴스 하나에 연결 하나를 둔다 (PR #42). 받은 이벤트는 순서대로 쌓아 두고
/// 테스트가 `nextMessage`로 하나씩 꺼낸다. 서버가 보내는 시간(매칭, 30초 준비 제한)은 실제 시간이라
/// 기다림은 모두 상한이 있는 실제 시간 대기다.
actor IntegrationPlayer {
    /// design 13번: 통합 테스트의 서버 주소.
    static let host = "127.0.0.1:8080"

    enum Failure: Error, CustomStringConvertible {
        case notConnected(String, SessionEvent?)
        case timedOut(String, waitingFor: String)
        case disconnected(String, SessionCloseReason?)

        var description: String {
            switch self {
            case let .notConnected(name, event):
                "\(name): 서버(\(IntegrationPlayer.host))에 연결하지 못함. 첫 이벤트: \(String(describing: event)). 서버를 먼저 띄웠는지 확인 (bundle exec fastlane integration)"
            case let .timedOut(name, waitingFor):
                "\(name): \(waitingFor)을(를) 기다리다 시간 초과"
            case let .disconnected(name, reason):
                "\(name): 연결이 끊김 (\(String(describing: reason)))"
            }
        }
    }

    let name: String
    private let client: SessionClient
    private let inbox = EventInbox()
    private var pump: Task<Void, Never>?

    /// 정리(`cleanUp`)에 쓰는 이 연결의 서버 쪽 상태. 받은 메시지와 보낸 요청으로만 갱신한다.
    private(set) var roomID: String?
    private var waitingRequestIDs: Set<String> = []

    private init(name: String) {
        self.name = name
        self.client = .live(host: Self.host)
    }

    /// 새 연결을 열고 `.connected`까지 기다린다.
    static func connect(_ name: String, timeout: Duration = .seconds(10)) async throws -> IntegrationPlayer {
        let player = IntegrationPlayer(name: name)
        try await player.open(timeout: timeout)
        return player
    }

    private func open(timeout: Duration) async throws {
        let stream = await client.connect()
        let inbox = inbox
        pump = Task {
            for await event in stream {
                await inbox.append(event)
            }
            await inbox.finish()
        }
        let first = await inbox.next(timeout: timeout)
        guard case .event(.connected) = first else {
            throw Failure.notConnected(name, first.event)
        }
    }

    // MARK: - 보내기

    func send(_ message: ClientMessage) async throws {
        if case let .matchRequest(payload) = message {
            waitingRequestIDs.insert(payload.requestID)
        }
        try await client.send(message)
    }

    /// 새 requestID로 MATCH_REQUEST를 보내고 그 ID를 돌려준다.
    @discardableResult
    func requestMatch(_ category: MatchCategory, catalogVersion: String) async throws -> String {
        let requestID = UUID().uuidString.lowercased()
        try await send(.matchRequest(.init(requestID: requestID, catalogVersion: catalogVersion, category: category)))
        return requestID
    }

    // MARK: - 받기

    /// 다음 서버 메시지. 시간 초과나 연결 끊김이면 throw한다.
    func nextMessage(timeout: Duration = .seconds(10), _ waitingFor: String = "다음 메시지") async throws -> ServerMessage {
        switch await inbox.next(timeout: timeout) {
        case let .event(.message(message)):
            track(message)
            return message
        case .event(.connected):
            return try await nextMessage(timeout: timeout, waitingFor)
        case let .event(.disconnected(reason)):
            throw Failure.disconnected(name, reason)
        case .finished:
            throw Failure.disconnected(name, nil)
        case .timedOut:
            throw Failure.timedOut(name, waitingFor: waitingFor)
        }
    }

    /// `duration` 동안 아무 메시지도 오지 않았으면 nil, 왔으면 그 메시지.
    func messageIfAny(within duration: Duration) async throws -> ServerMessage? {
        do {
            return try await nextMessage(timeout: duration)
        } catch Failure.timedOut {
            return nil
        }
    }

    /// 조건에 맞는 메시지가 올 때까지 다른 메시지는 건너뛴다. 건너뛴 메시지도 상태 추적에는 반영한다.
    func skip(
        until waitingFor: String,
        timeout: Duration = .seconds(10),
        _ matches: (ServerMessage) -> Bool
    ) async throws -> ServerMessage {
        let deadline = ContinuousClock.now.advanced(by: timeout)
        while true {
            let remaining = ContinuousClock.now.duration(to: deadline)
            guard remaining > .zero else { throw Failure.timedOut(name, waitingFor: waitingFor) }
            let message = try await nextMessage(timeout: remaining, waitingFor)
            if matches(message) { return message }
        }
    }

    // MARK: - 정리

    /// 다음 테스트의 매칭에 이 연결의 방이나 대기 요청이 섞이지 않도록 서버 쪽 상태를 비우고 연결을 닫는다.
    ///
    /// 방에 있으면 LEAVE_ROOM → ROOM_LEFT, 대기 요청이 있으면 MATCH_CANCEL → MATCH_CANCELLED를 확인한 뒤 닫는다.
    /// 실패한 테스트에서도 불리므로 오류는 삼키고, 확인하지 못하면 연결 끊김으로 서버가 정리하게 둔다.
    func cleanUp() async {
        for _ in 0..<4 {
            if let roomID {
                try? await send(.leaveRoom(roomID: roomID))
                _ = try? await skip(until: "정리 ROOM_LEFT", timeout: .seconds(5)) { _ in self.roomID == nil }
                // 응답이 없으면 같은 방을 다시 기다리지 않는다.
                if self.roomID == roomID { self.roomID = nil }
            } else if let requestID = waitingRequestIDs.first {
                try? await send(.matchCancel(requestID: requestID))
                _ = try? await skip(until: "정리 MATCH_CANCELLED", timeout: .seconds(5)) { _ in
                    !self.waitingRequestIDs.contains(requestID)
                }
                // 응답이 없으면 같은 ID를 다시 기다리지 않는다.
                waitingRequestIDs.remove(requestID)
            } else {
                break
            }
        }
        await client.disconnect()
        pump?.cancel()
    }

    private func track(_ message: ServerMessage) {
        switch message {
        case let .welcome(payload):
            waitingRequestIDs.remove(payload.requestID)
            roomID = payload.roomID
        case let .matchCancelled(payload):
            waitingRequestIDs.remove(payload.requestID)
        case let .matchFailed(payload):
            waitingRequestIDs.remove(payload.requestID)
        case let .roomLeft(payload) where payload.roomID == roomID,
             let .playerKicked(payload) where payload.roomID == roomID:
            roomID = nil
        default:
            break
        }
    }
}

/// 연결 이벤트를 받은 순서대로 보관하고, 기다리는 쪽에 상한 시간 안에 하나씩 넘긴다.
actor EventInbox {
    enum Next {
        case event(SessionEvent)
        case finished
        case timedOut

        var event: SessionEvent? {
            if case let .event(event) = self { return event }
            return nil
        }
    }

    private var pending: [SessionEvent] = []
    private var finished = false
    private var waiter: (id: UUID, continuation: CheckedContinuation<Next, Never>)?

    func append(_ event: SessionEvent) {
        if let waiter {
            self.waiter = nil
            waiter.continuation.resume(returning: .event(event))
        } else {
            pending.append(event)
        }
    }

    func finish() {
        finished = true
        if let waiter {
            self.waiter = nil
            waiter.continuation.resume(returning: .finished)
        }
    }

    func next(timeout: Duration) async -> Next {
        if !pending.isEmpty { return .event(pending.removeFirst()) }
        if finished { return .finished }

        let id = UUID()
        let timer = Task { [weak self] in
            try? await Task.sleep(for: timeout)
            await self?.expire(id)
        }
        defer { timer.cancel() }
        return await withCheckedContinuation { continuation in
            waiter = (id, continuation)
        }
    }

    private func expire(_ id: UUID) {
        guard let waiter, waiter.id == id else { return }
        self.waiter = nil
        waiter.continuation.resume(returning: .timedOut)
    }
}
