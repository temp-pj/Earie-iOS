import Dependencies

extension SessionClient: DependencyKey {
    /// 실제 구현은 `ClientSessionLive`의 `SessionClient.live`를 App에서 주입한다.
    public static let liveValue = SessionClient.unimplementedValue
    public static let testValue = SessionClient.unimplementedValue

    static let unimplementedValue = SessionClient(
        connect: unimplemented("SessionClient.connect", placeholder: AsyncStream { $0.finish() }),
        send: unimplemented("SessionClient.send"),
        disconnect: unimplemented("SessionClient.disconnect")
    )
}

extension DependencyValues {
    public var sessionClient: SessionClient {
        get { self[SessionClient.self] }
        set { self[SessionClient.self] = newValue }
    }
}
