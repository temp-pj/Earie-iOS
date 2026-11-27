import Foundation

/// v1 엔드포인트 `ws://{host}/ws?protocolVersion=1` (protocol.md "연결과 봉투").
/// `room` query는 붙이지 않는다. v1 서버는 room query가 있으면 HTTP 400으로 거절한다.
enum SessionURL {
    static let protocolVersion = "1"

    /// `host`는 `"127.0.0.1:8080"`처럼 호스트와 선택 포트만 담아야 한다. 그 밖의 형식이면 nil.
    static func make(host: String) -> URL? {
        let disallowed = CharacterSet(charactersIn: "/?#@").union(.whitespacesAndNewlines)
        guard !host.isEmpty, host.rangeOfCharacter(from: disallowed) == nil else { return nil }

        var components = URLComponents()
        components.scheme = "ws"
        components.path = "/ws"
        components.queryItems = [URLQueryItem(name: "protocolVersion", value: protocolVersion)]

        guard let authority = URLComponents(string: "ws://\(host)"),
              let hostName = authority.host, !hostName.isEmpty else { return nil }
        components.host = hostName
        components.port = authority.port
        return components.url
    }
}

/// Info.plist의 `SERVER_HOST` (Configs/Secrets.xcconfig에서 채워진다).
enum ServerHost {
    static let infoKey = "SERVER_HOST"

    static func value(in info: [String: Any]?) -> String? {
        guard let raw = info?[infoKey] as? String else { return nil }
        let host = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        return host.isEmpty ? nil : host
    }
}
