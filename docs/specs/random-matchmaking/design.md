# iOS 랜덤 매칭 설계

> **이 문서의 목표:** 안쪽을 어떻게 나누고 어떻게 만들지를, 어떤 에이전트가 읽어도 같은 구조가 나오게 정한다.
>
> **이 문서에 두지 않는 것:** 무엇을 왜 만드는지는 requirements.md, 작업 나누기는 tasks.md에 둔다. 서버와 주고받는 메시지 형식은 같은 폴더의 `protocol.md`(서버 v1 복사본)를 따르며 여기서 다시 정의하지 않는다.

- 상태: 확정
- 버전: v1.0
- 기준 요구사항 버전: v1.0
- 바깥 계약: 같은 폴더의 `protocol.md`와 `fixtures/` (서버 복사본, 출처는 `SOURCE.md`)
- 작성일: 2026-11-25

---

## 1. 기존 코드와 바꿀 부분

### 현재 동작
- `M_GAME/Sources/AppFeature.swift`, `ContentView.swift`: 방 ID를 입력받아 `roomSessionClient.connect(roomID)`로 연결하면 곧바로 `RoomReducer` 상태를 만든다. 연결이 곧 방 입장이다.
- `Clients/RoomSessionClient`: `ws://{host}/ws?room=...`로 연결한다. `protocolVersion`이 없어서 v1 서버는 HTTP 400으로 거절한다. `roomEvents()`를 호출할 때마다 같은 WebSocket 스트림을 새 Task로 순회한다. 코덱이 UUID를 `!`로 강제 변환한다. WELCOME을 `.serverConnectionChanged(.connected(...))`로 바꾼다.
- `Clients/WebSocketClient`: `WebSocketConnection` actor가 URLSessionWebSocketTask 하나를 관리한다. `connect(url:)`는 이전 연결을 먼저 끊으면서 이전 스트림에 `.disconnected(.normal)`을 넣고 끝낸다. 연결이 열리면 `.connected`, 수신 오류가 나면 `.disconnected(.networkError)`를 내고 스트림을 끝낸다.
- `Features/Room`: `RoomReducer`가 `onAppear`에서 직접 `roomEvents()`를 구독하고, `onDisappear`에서 소켓을 끊는다. 참가자는 `[UUID: Player]` 딕셔너리다. `GameReducer`는 라운드, 글자 카드, 제출, 오답 페널티(500ms), 카운트다운을 처리한다.
- `RoomView`: 디버그용 텍스트와 하드코딩된 구 Category로 START_GAME을 보내는 버튼이 있다.
- `Features/Lobby`, `Features/Login`: 파일만 있고 내용이 0줄이다.
- `Clients/RoomClient`: REST 인터페이스만 있고 쓰는 곳이 없다. `FeatureLobby` 타깃이 의존한다.
- CI(`fastlane ci`): `swiftlint lint --strict`, `tuist install`, `tuist generate`, `xcodebuild build`만 한다. 테스트를 실행하지 않는다.

### 유지할 것
- `WebSocketClient` 인터페이스와 `WebSocketConnection` 구현
- `GameReducer`의 라운드 진행 규칙과 페널티 동작 (입력 이벤트만 v1 메시지에서 오도록 바뀐다)
- `AudioClient`, `MusicEntitlementClient` 인터페이스와 구현
- `Login` Feature와 `AuthClient` (건드리지 않는다)
- Tuist 모듈 구조의 Interface / Live / Test 3분할 패턴

### 바꿀 것
- `RoomSessionClient` 모듈 3개를 삭제하고 `SessionClient` 모듈 3개로 대체한다.
- `RoomClient` 모듈 3개와 `Room`, `CreateRoomRequest`, `UpdateRoomRequest`를 삭제한다.
- 구 `Category`, `StartGamePayload`, 구 `WelcomePayload`, 구 payload DTO들을 v1 타입으로 대체한다.
- 연결 상태는 `SessionEvent`와 App 상태로 옮기고, 방 정보·재접속·강퇴를 담던 `ServerConnectionState`, `DisconnectReason`, `RoomConnectionInfo`, `RoomCloseReason`, `RoomSessionState`, 구 `RoomEvent`처럼 이번 변경으로 쓰이지 않게 된 타입을 삭제한다. 이번 변경과 무관한 빈 파일(예: `User.swift`)은 건드리지 않는다.
- `RoomReducer`는 직접 구독하지 않고, 소켓을 끊지 않으며, 서버 송신을 delegate로 App에 맡긴다.
- `ContentView`를 삭제하고 App 상태를 그리는 `RootView`로 대체한다.
- CI에 테스트 실행을 추가한다.

## 2. 기술 제약

- 언어 / 런타임: Swift (Tuist `Package.swift`의 swift-tools 6.0), iOS, SwiftUI
- 사용해야 하는 것:
  - TCA (`swift-composable-architecture` 1.25.5 이상, 기존 고정 버전)
  - 의존성은 `@Dependency`와 `DependencyKey`로 주입한다 (기존 Client 패턴)
  - 새 클라이언트는 Interface / Live / Test 세 타깃으로 나눈다
  - JSON은 Foundation `JSONEncoder` / `JSONDecoder`
  - 조합 저장은 `UserDefaults`
  - requestID는 `@Dependency(\.uuid)`로 만든다
  - 시간 대기는 `@Dependency(\.continuousClock)`을 쓴다
- 쓰면 안 되는 것:
  - 새 서드파티 패키지
  - 화면에서 `Task.sleep`이나 `DispatchQueue` 직접 사용
  - 강제 언래핑으로 서버 값을 변환하는 코드
  - MDS나 커스텀 디자인 (OUT-02)

## 3. 모듈 경계

| 모듈 (Tuist 타깃) | 맡는 일 | 맡지 않는 일 |
|---|---|---|
| `Models` | v1 wire 타입(`ClientMessage`, `ServerMessage`, payload DTO), `MessageCodec`, 도메인 타입(`MatchCategory`, `CatalogProjection`, `RoomServerEvent`, 기존 게임 타입) | 네트워크, 저장소, 상태 관리 |
| `ClientSession` (Interface) | `SessionClient`, `SessionEvent` 정의 | 구현 |
| `ClientSessionLive` | v1 URL 구성, `WebSocketClient`로 연결, 수신 문자열을 `MessageCodec`으로 디코딩해 `SessionEvent`로 내보내기, 디코딩 실패 로그와 폐기 | 요청·방 상태 판단, 거르기 |
| `ClientSessionTest` | 테스트용 `SessionClient` (스트림을 테스트가 제어) | |
| `ClientCatalog` (Interface) | `CatalogClient`, `CategoryPreferenceClient` 정의 | 구현 |
| `ClientCatalogLive` | 번들 `catalog-projection.json` 읽기, `UserDefaults` 저장·읽기 | 조합 활성 판정 |
| `ClientCatalogTest` | 테스트용 구현 (카탈로그 주입, 메모리 저장) | |
| `ClientWebSocket` / `Live` / `Test` | 기존 그대로 | |
| `FeatureLobby` | 조건 선택, 후보 활성 판정, 매칭 대기 단계, 취소, 조합 저장·복원 | 연결, 송신, 메시지 거르기 |
| `FeatureRoom` | 방 대기, 나가는 중, 게임(`GameReducer`), 결과, 곡 준비 | 연결, 송신, 메시지 거르기 |
| `M_GAME` (App) | `AppFeature`: 연결 수명, 스트림 단일 소비, 메시지 거르기와 라우팅, 송신, 화면 단계 전환, 알럿 / `RootView` | 각 화면 내부 규칙 |

- 근거: 연결 수명은 로비, 방, 게임을 넘나들고, 서버의 순서 보장(WELCOME 선행)은 소켓 하나의 수신 순서를 한 곳에서 그대로 처리할 때만 유지된다. 그래서 연결과 수신은 App 한 곳에 둔다.
- 버린 대안: 매칭 전용 클라이언트와 방 클라이언트를 분리하고 WebSocket을 공유하는 방식. 소켓을 누가 읽는지 애매해지고, 스트림이 둘로 나뉘면 스트림 사이의 순서가 사라져 방 쪽이 WELCOME보다 PLAYER_JOINED를 먼저 처리할 수 있다.
- 버린 대안: 클라이언트 하나에 용도별 스트림을 여러 개 두는 방식. 서로 다른 Feature가 동시에 소비하면 위와 같은 순서 문제가 생긴다.
- 근거 (송신도 App 경유): 매칭 요청은 연결 상태에 따라 즉시 보내거나 연결 후 보내야 해서 App이 판단해야 한다. 나머지 송신도 같은 경로로 모으면 Feature 모듈이 `ClientSession`에 전혀 의존하지 않고, Feature 테스트는 delegate 액션만 확인하면 된다.
- 버린 대안: 방·게임 Feature가 `SessionClient.send`를 직접 호출하는 방식. 송신 경로가 둘이 되고, 연결이 끊긴 뒤 보낸 송신 실패를 어디서 처리할지가 갈린다.
- 근거 (코덱을 Models에): 순수 변환이라 네트워크 없이 fixture로 테스트할 수 있고, App 테스트와 통합 테스트가 같은 타입을 쓴다.

## 4. 의존 방향

- 허용:
  - `FeatureLobby` → `Models`, `ClientCatalog`, `ComposableArchitecture`
  - `FeatureRoom` → `Models`, `ClientAudio`, `ClientMusicEntitlement`, `ComposableArchitecture`
  - `ClientSession` → `Models`
  - `ClientSessionLive` → `ClientSession`, `ClientWebSocket`, `Models`
  - `ClientCatalog` → `Models` / `ClientCatalogLive` → `ClientCatalog`, `Models`
  - `M_GAME` → 모든 Feature, 모든 Client Interface와 Live
- 금지:
  - Feature → `ClientSession`, `ClientSessionLive`, `ClientWebSocket`
  - Feature ↔ Feature (`FeatureLobby`와 `FeatureRoom`은 서로 모른다)
  - `Models` → 다른 모든 모듈
  - Live 모듈 → Feature
- 모듈들을 조립하는 곳: `M_GAME/Sources/MGAMEApp.swift` (live 주입), `AppFeature` (Feature 조합)

- 근거: Feature가 연결을 모르게 해야 "스트림 소비자는 App 하나"가 구조적으로 강제된다.

## 5. 상태 소유권

| 상태 | 소유 모듈 | 바꿀 수 있는 경로 | 읽기만 하는 모듈 |
|---|---|---|---|
| 연결 상태와 연결 세대 | `AppFeature.State.connection` | App의 연결 시작, `SessionEvent` 처리 | - |
| 화면 단계 (로비 / 방) | `AppFeature.State.phase` | App의 WELCOME, ROOM_LEFT, 강퇴, MATCH_FAILED, 연결 끊김 처리 | - |
| 화면 전환을 동반하는 알럿 (매칭 실패, 연결 끊김, 강퇴) | `AppFeature.State.alert` | App | - |
| 방 안의 알럿 (명령 실패)과 게임 중 나가기 확인창 | `RoomReducer.State.alert` | Room | - |
| 카탈로그 | `LobbyReducer.State.catalog` | 로비 진입 시 `CatalogClient.load` | - |
| 현재 조합 | `LobbyReducer.State.selection` | 로비의 조건 선택 액션 | App (매칭 요청 송신 시) |
| 활성 requestID | `LobbyReducer.State.phase` (`.matching`) | 로비의 매칭 탭, 취소 탭, App이 보내는 매칭 종료 액션 | App (거르기) |
| 현재 roomID, 나가는 중 여부 | `RoomReducer.State` | WELCOME으로 생성, 로비 나가기 액션 | App (거르기) |
| 참가자, 방장, 방 단계, 결과 | `RoomReducer.State` | App이 전달한 `RoomServerEvent` | - |
| 라운드 진행 상태 | `GameReducer.State` | Room이 전달한 `GameEvent`, 사용자 입력 | - |
| 저장된 조합 | `CategoryPreferenceClient` (UserDefaults) | 로비 | - |

- 근거: 비교할 ID의 원본을 Feature 상태 하나에 둔다. 취소하면 로비가 requestID를 지우고, 그 순간부터 늦은 WELCOME은 App의 거르기에서 자동으로 빠진다.
- 버린 대안: App이 `activeRequestID`, `currentRoomID`를 따로 들고 있는 방식. 값이 두 곳에 있어 동기화가 어긋나면(취소했는데 App 쪽 ID가 안 지워짐) 늦은 WELCOME이 통과한다.

## 6. 핵심 데이터 구조

| 데이터 | 키 | 필드 | 구분 기준 |
|---|---|---|---|
| `MatchCategory` (Models) | - | `decade`, `artistType`, `gender`, `genre`: 모두 `String` (wire 값 그대로) | 네 필드가 모두 같으면 같은 조합 (`Hashable`) |
| `CatalogProjection` (Models) | `version` | `version: String`, `decades: [String]`, `genres: [CatalogGenre]`(`id`, `label`), `allowedRequests: [MatchCategory]`, `pools: [PoolProjection]`(`category`, `songCount`) | `version` |
| `ClientMessage` (Models) | type | `matchRequest(MatchRequestPayload)`, `matchCancel(requestID)`, `leaveRoom(roomID)`, `startGame(roomID)`, `readyToPlay(roomID, roundNumber)`, `submitAnswer(roomID, answer)`, `kickPlayer(roomID, targetPlayerID)` | - |
| `ServerMessage` (Models) | type | protocol.md v1의 서버→클라이언트 type 전체를 case로 갖고, payload는 v1 DTO | - |
| `SessionEvent` (ClientSession) | - | `.connected`, `.message(ServerMessage)`, `.disconnected(SessionCloseReason)`. `SessionCloseReason`은 `.normal`, `.networkError` | - |
| `RoomServerEvent` (Models) | - | `.playerJoined(playerID)`, `.playerLeft(playerID)`, `.hostChanged(playerID)`, `.gameStarted`, `.preloadSong(isrc:startTime:roundNumber:)`, `.game(GameEvent)`, `.gameOver(GameResult)`, `.gameAborted(AbortReason)`, `.commandFailed(RoomFailureCode)`. ROOM_LEFT와 PLAYER_KICKED는 App이 직접 처리하므로 없다. `GameEvent`, `RoundData`, `RoundResult`, `GameResult`는 기존 타입을 그대로 쓰고, 승자가 빈 문자열이면 `RoundResult.winnerId`는 nil이다 | - |
| 연결 세대 (App) | `UUID` | App이 연결을 시작할 때마다 새로 만든다 | 값이 같으면 같은 연결 |
| `LobbyReducer.State` | - | `catalog: CatalogState`(`.loading`, `.available(CatalogProjection)`, `.unavailable`), `selection: MatchCategory`, `phase: Phase`(`.selecting`, `.matching(requestID: String)`) | - |
| `RoomReducer.State` | `roomID` | `roomID`, `myPlayerID`, `hostID`, `players: [String]`(서버 순서), `maxPlayers`, `category: MatchCategory`, `stage`(`.waiting`, `.playing`, `.finished(GameResult)`, `.aborted(AbortReason)`), `isLeaving: Bool`, `game: GameReducer.State?`, `alert` (`@Presents`, 명령 실패 알럿과 나가기 확인창) | `roomID` |

- v1 payload DTO는 `Models` 안의 `WireV1` 네임스페이스(`public enum WireV1`) 안에 둔다 (예: `WireV1.WelcomePayload`). `ClientMessage`, `ServerMessage`, `MessageCodec`은 이 DTO를 쓴다.
  - 근거: 구 DTO(`WelcomePayload`, `PreloadSongPayload` 등)와 이름이 같아서, T6에서 구 DTO를 지우기 전까지 공존하려면 네임스페이스가 필요하다.
- ID(requestID, roomID, playerID)는 도메인과 wire 모두 `String`이다. 코덱이 디코딩할 때 소문자 canonical UUID v4 형식을 검증하고, 보낼 때도 소문자로 만든다.
  - 근거: `UUID.uuidString`은 대문자를 만들어 계약(소문자 canonical)과 어긋난다. 문자열로 두면 비교와 인코딩이 계약 형식 그대로다.
- 참가자는 `[String]` 배열이다.
  - 근거: 화면에 서버 접수 순서를 보여야 한다 (REQ-ROOM-01). 기존 딕셔너리는 순서가 없다.
- `MatchCategory`, `RoomServerEvent`, `SessionCloseReason`은 새 이름이다. 구 `Category`, `RoomEvent`, `ServerConnectionState`·`DisconnectReason`은 마지막 정리 작업에서 삭제한다.
  - 근거: 작업을 병렬로 나누는 동안 구 경로가 컴파일되어야 해서 같은 이름을 쓸 수 없다.

## 7. 모듈 간 내부 계약

| 보내는 모듈 → 받는 모듈 | 명령 / 값 | 입력 | 결과 (성공 / 실패) |
|---|---|---|---|
| App → `SessionClient` | `connect` | 없음 | 그 연결 전용 `AsyncStream<SessionEvent>`. 실패도 스트림의 `.disconnected`로 온다. 끊기면 스트림이 끝난다 |
| App → `SessionClient` | `send` | `ClientMessage` | 성공 / throw (연결 없음, 인코딩 실패) |
| App → `SessionClient` | `disconnect` | 없음 | 현재 연결을 닫는다. 이번 기능에서는 앱 종료 외에 호출하지 않는다 |
| `ClientSessionLive` → `MessageCodec` | `decodeServer` | `Data` | `ServerMessage` / throw |
| `ClientSessionLive` → `MessageCodec` | `encodeClient` | `ClientMessage` | `Data` / throw |
| Lobby → App | delegate `requestMatch` | `requestID: String`, `category: MatchCategory`, `catalogVersion: String` | 없음 (App이 송신) |
| Lobby → App | delegate `cancelMatch` | `requestID: String` | 없음 (App이 송신) |
| App → Lobby | `matchEnded` | 없음 | 로비가 `.selecting`으로 돌아간다 |
| App → Room | `server(RoomServerEvent)` | 거르기를 통과한 방·게임 이벤트 | Room 상태 갱신 |
| Room → App | delegate `send` | `ClientMessage` | 없음 (App이 송신) |
| Lobby → `CatalogClient` | `load` | 없음 | `CatalogProjection` / throw → `.unavailable` |
| Lobby → `CategoryPreferenceClient` | `load` / `save` | 없음 / `MatchCategory` | `MatchCategory?` / 없음 |

함수 이름과 시그니처는 다음으로 고정한다.

```swift
// ClientSession
public struct SessionClient: Sendable {
    public var connect: @Sendable () async -> AsyncStream<SessionEvent>
    public var send: @Sendable (ClientMessage) async throws -> Void
    public var disconnect: @Sendable () async -> Void
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

// ClientSessionLive
public extension SessionClient {
    static var live: SessionClient                       // Info.plist SERVER_HOST 사용
    static func live(host: String) -> SessionClient      // 통합 테스트용, "127.0.0.1:8080" 형식
}
// 두 구현 모두 ws://{host}/ws?protocolVersion=1 로 연결한다.

// ClientCatalog
public struct CatalogClient: Sendable {
    public var load: @Sendable () throws -> CatalogProjection
}
public struct CategoryPreferenceClient: Sendable {
    public var load: @Sendable () -> MatchCategory?
    public var save: @Sendable (MatchCategory) -> Void
}

// Models
public enum MessageCodec {
    public static func decodeServer(_ data: Data) throws -> ServerMessage
    public static func encodeClient(_ message: ClientMessage) throws -> Data
    public static func decodeClient(_ data: Data) throws -> ClientMessage   // fixture 재인코딩 검증용
}
```

- `decodeServer`의 판정 기준은 `protocol.md`와 `fixtures/`다: 필수 필드, null 금지, 타입, 소문자 canonical UUID v4, 오류 코드 enum, 서버 메시지의 `timestamp` 필수, 방향이 맞지 않는 type 거부, 모르는 type 거부, 모르는 필드 무시. 문서와 fixture가 어긋나 보이면 fixture를 따르고 보고한다.
- `encodeClient`는 `timestamp`를 넣지 않는다 (protocol.md에서 C→S timestamp는 선택).

- 근거 (연결마다 새 스트림): 서버 계약상 새 연결은 새 사용자라서, 연결 경계와 스트림 경계를 같게 두면 이전 연결의 메시지가 새 연결에 섞일 수 없다.
- 버린 대안: 앱 수명 동안 스트림 하나. 연결 세대를 메시지마다 붙여야 하고, 이전 연결 메시지가 새 연결 뒤에 오지 않도록 별도로 막아야 한다.
- 근거 (wire 타입 그대로): 클라이언트가 얇아지고 fixture로 바로 테스트된다. 거르기를 App이 해야 해서 App이 wire 필드를 볼 수 있어야 한다.
- 버린 대안: 클라이언트 안에서 도메인 이벤트로 변환. 변환 규칙이 숨고, fixture 테스트와 도메인 테스트가 둘로 갈린다.
- 버린 대안: broadcast(구독자마다 복제). 여러 소비자가 생기면 순서 보장이 소비자 책임이 된다.

## 8. 내부 처리 흐름

**매칭 요청**
LobbyView 매칭 탭 → Lobby: `uuid()`로 requestID를 만들어 소문자 문자열로 바꾸고 `phase = .matching(requestID)`, delegate `requestMatch` → App:
- 연결이 `.connected`면 즉시 `send(.matchRequest)`
- `.connecting`이면 아무것도 안 함 (연결되면 보냄)
- `.disconnected`면 새 연결 세대를 만들고 `connect()`를 시작, 상태 `.connecting`

**연결 완료**
`SessionEvent.connected`(현재 세대) → App: 상태 `.connected`. 로비가 `.matching(requestID)`이면 그 요청으로 `send(.matchRequest)`.

**취소**
Lobby 취소 탭 → Lobby: `phase = .selecting`, delegate `cancelMatch(requestID)` → App: 연결이 `.connected`면 `send(.matchCancel)`. `.connecting`이면 보내지 않는다 (요청도 안 나갔으므로).

**수신과 라우팅**
`SessionClient` 스트림 → App의 연결 효과 하나가 `for await`로 순서대로 `.session(generation, event)` 액션을 보낸다 → App:
1. `generation`이 현재 세대가 아니면 버린다.
2. `.message`면 9번 표와 아래 규칙으로 거른다.
   - 매칭 메시지: `phase`가 로비이고 `.matching(requestID)`와 같을 때만. WELCOME이면 `phase = .room(RoomReducer.State(welcome:))`. MATCH_FAILED면 Lobby에 `matchEnded`, 알럿. MATCH_WAITING, MATCH_CANCELLED는 아무것도 안 함.
   - ROOM_LEFT: `phase`가 방이고 `roomID`가 같고 `isLeaving`일 때만. 로비로 전환.
   - PLAYER_KICKED: `phase`가 방이고 `roomID`가 같을 때만. 로비로 전환.
   - 그 밖의 방·게임 메시지: `phase`가 방이고 `roomID`가 같을 때만 `RoomServerEvent`로 바꿔 `.room(.server(event))`.
   - 걸러진 메시지는 로그만 남긴다.
3. `.disconnected`면 연결 상태 `.disconnected`, 방이나 매칭 대기 중이면 로비로 전환하고 알럿.

**로비로 전환**
App이 `phase`를 방에서 로비로 바꿀 때는 같은 처리에서 `audioClient.stop()` 효과와 Room·Game 효과 취소를 함께 실행하고, 새 `LobbyReducer.State`를 만든다. 로비는 진입 시 카탈로그와 저장된 조합을 읽는다.

**방 안의 송신**
Room 시작 탭 / 나가기 확정 / 곡 준비 완료 / 제출 → Room delegate `send(ClientMessage)` → App `send`. 나가기는 Room이 먼저 `isLeaving = true`로 바꾼다. 게임 단계의 나가기 탭은 먼저 `alert`에 확인창을 띄우고, 확인 액션이 왔을 때 나가기를 확정한다. 방 대기와 결과 단계는 탭이 곧 확정이다.

**곡 준비**
`RoomServerEvent.preloadSong` → Room: `audioClient.preload(isrc, startTime, 30)` → 성공하면 delegate `send(.readyToPlay(roomID, roundNumber))`. 실패하면 로그만 남긴다.

**송신 실패**
App의 `send`가 throw하면 연결 끊김과 같은 처리를 한다.

## 9. 내부 상황별 동작 표

App의 연결 상태 기준이다.

| 연결 상태 \ 일어난 일 | Lobby `requestMatch` | Lobby `cancelMatch` | 현재 세대 `.connected` | 현재 세대 `.message` | 현재 세대 `.disconnected` | 이전 세대 이벤트 | `send` 실패 |
|---|---|---|---|---|---|---|---|
| `.disconnected` | 새 세대로 `.connecting`, `connect()` 시작 | 아무것도 안 함 | 해당 없음 | 해당 없음 | 해당 없음 | 무시 | 해당 없음 |
| `.connecting` | 아무것도 안 함 (연결되면 보냄) | 아무것도 안 함 | `.connected`, 로비가 매칭 중이면 MATCH_REQUEST | 해당 없음 | `.disconnected`, 매칭 중이면 로비 `matchEnded`와 알럿 | 무시 | 해당 없음 |
| `.connected` | MATCH_REQUEST 송신 | MATCH_CANCEL 송신 | 무시 | 거르기 후 라우팅 | `.disconnected`, 매칭 중이거나 방이면 로비와 알럿 (아니면 알럿 없이 연결 상태만 바꿈) | 무시 | 현재 세대 `.disconnected`와 같게 처리 |

- 칸에 쓸 수 있는 값: 바뀌는 내부 상태와 하는 일 / 무시 / 해당 없음
- `WebSocketConnection.connect`는 이전 스트림에 `.disconnected(.normal)`을 넣는다. 세대 비교가 없으면 새 연결을 시작하자마자 끊긴 것으로 처리된다. 세대 비교는 그래서 필수다.

## 10. 불변식

- INV-01: `AppFeature.State.phase`는 로비와 방 중 정확히 하나다. 둘이 동시에 존재하지 않는다.
- INV-02: MATCH_REQUEST를 보낸 뒤 그 요청이 취소, 실패, 배정으로 끝나기 전에는 다른 MATCH_REQUEST를 보내지 않는다.
- INV-03: 보내는 모든 ID는 소문자 canonical UUID 문자열이다.
- INV-04: `roomID`가 현재 방과 다른 방·게임 메시지는 `RoomReducer`에 전달되지 않는다.
- INV-05: `requestID`가 활성 요청과 다른 매칭 메시지는 App과 Lobby 상태를 바꾸지 않는다.
- INV-06: `SessionClient.connect`가 돌려준 스트림을 소비하는 곳은 App의 연결 효과 하나뿐이다.
- INV-07: 같은 연결의 메시지는 수신 순서대로 App 액션이 된다.
- INV-08: 현재 세대가 아닌 연결의 이벤트는 상태를 바꾸지 않는다.
- INV-09: 앱은 취소, 퇴장, 강퇴로 `disconnect`를 호출하지 않는다.
- INV-10: Feature 모듈의 소스는 `ClientSession`을 import하지 않는다.
- INV-11: 서버 메시지를 해석하는 코드에 강제 언래핑이 없다.

## 11. 실패와 타임아웃 처리

| 실패 상황 | 기다리는 시간 | 처리 |
|---|---|---|
| 연결 시도 후 `.connected`가 오지 않음 | 10초 (`continuousClock`) | 연결 끊김과 같게 처리하고, 해당 세대 효과를 취소한 뒤 `disconnect` 호출 |
| 연결 중 수신 오류 | 없음 | `WebSocketConnection`이 `.disconnected(.networkError)`를 내고 스트림 종료 → 9번 표 |
| 송신 실패 | 없음 | 연결 끊김과 같게 처리 |
| 메시지 디코딩 실패 | 없음 | `ClientSessionLive`가 버리고 로그 |
| 곡 준비 실패 | 없음 | READY_TO_PLAY를 보내지 않음. 서버가 30초 뒤 GAME_ABORTED를 보낸다 |
| ROOM_LEFT가 오지 않음 | 없음 (타이머 두지 않음) | 서버가 반드시 응답한다 (protocol.md 멱등성). 연결이 죽으면 연결 끊김 처리로 빠져나온다 |
| MATCH_WAITING 뒤 배정 없음 | 없음 | 무기한 대기 (REQ-MATCH-05) |

- 서버 ping(20초 간격)에는 URLSessionWebSocketTask가 자동으로 pong한다. 앱이 따로 ping을 보내지 않는다.

## 12. 자원 정리

| 자원 | 정리하는 시점 | 상한 |
|---|---|---|
| 연결 스트림 소비 효과 | 현재 세대 `.disconnected` 처리 시, 새 연결 시작 시 (`cancelInFlight`) | 동시에 1개 |
| 음악 재생 | 방에서 로비로 전환할 때, GAME_ABORTED, GAME_OVER | - |
| Room·Game 효과 (곡 준비, 페널티 타이머) | 방에서 로비로 전환할 때 취소 | - |
| 연결 시도 타이머 | `.connected`, `.disconnected` 처리 시 취소 | 동시에 1개 |

## 13. 주입 지점

| 의존성 | 실제 구현 | 테스트용 구현 | 주입하는 곳 |
|---|---|---|---|
| `SessionClient` | `ClientSessionLive` (`WebSocketClient` 사용) | `ClientSessionTest`: `connect`가 테스트가 쥔 `AsyncStream`을 돌려주고 `send`를 기록 | `MGAMEApp` / 테스트 `withDependencies` |
| `CatalogClient` | 번들 `catalog-projection.json` | fixture의 정상, 빈, 잘못된 카탈로그 | 동일 |
| `CategoryPreferenceClient` | `UserDefaults.standard` | 메모리 저장 | 동일 |
| `AudioClient` | 기존 MusicKit 구현 | 기존 Test 구현 | 동일 |
| `uuid` | 시스템 | `.incrementing` | 동일 |
| `continuousClock` | 시스템 | `TestClock` | 동일 |
| 서버 주소 | Info.plist `SERVER_HOST` | 통합 테스트는 `127.0.0.1:8080` | `ClientSessionLive` / 통합 테스트 |

## 14. 요구사항 연결

| 요구사항 ID | 다루는 설계 섹션 |
|---|---|
| REQ-CAT-01~08 | 3 (FeatureLobby, ClientCatalog), 5, 6 |
| REQ-MATCH-01~07 | 7, 8 (매칭 요청, 연결 완료), 9 |
| REQ-CANCEL-01~04 | 8 (취소), 9 |
| REQ-FAIL-01~05 | 8 (수신과 라우팅), 9, 11 |
| REQ-ROOM-01~08 | 5, 6, 8 (방 안의 송신, 로비로 전환) |
| REQ-GAME-01~07 | 8 (곡 준비), 11, 12 |
| REQ-FILTER-01~03 | 5, 8 (수신과 라우팅), 10 (INV-04, INV-05, INV-08) |
| SCOPE-09 | 1 (바꿀 것) |
| SCOPE-10 | tasks.md |

## 15. 고정할 것과 구현자 재량

### 고정할 것
- 3번 모듈 경계와 4번 의존 방향
- 5번 상태 소유권
- 6번 데이터 구조의 필드와 ID를 문자열로 두는 것
- 7번 함수 이름과 시그니처, delegate 이름
- 8번 처리 순서와 9번 표
- 10번 불변식

### 구현자 재량
- 비공개 헬퍼 함수의 구조와 이름
- View 레이아웃 (기본 SwiftUI 컴포넌트 안에서)
- `WireV1` 안의 payload DTO 이름 (protocol.md 필드명과 JSON 키만 일치하면 됨)
- 로그 문구와 출력 방식

## 16. 미결정

- 없음 (v0.1의 OPEN-01은 v0.2에서 11번 표의 10초로 확정)
