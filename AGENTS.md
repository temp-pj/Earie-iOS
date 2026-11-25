# Earie iOS 작업 지침

## 프로젝트

Tuist로 생성하는 iOS 앱이다. 프로젝트 이름은 `M_GAME`, 정의는 `Project.swift`, 외부 의존성은 `Tuist/Package.swift`(TCA)다. 생성된 `.xcodeproj`와 `.xcworkspace`는 커밋하지 않는다.

- `M_GAME/`: 앱 진입점(`MGAMEApp`), 최상위 Reducer와 루트 화면, live 의존성 주입.
- `Features/<이름>/`: 화면 단위 TCA Feature. `Sources`와 `Tests`로 나눈다.
- `Clients/<이름>Client/`: 외부 시스템 경계. `Interface`(타입과 `DependencyKey`), `Live`(실제 구현), `Test`(테스트용 구현) 세 타깃으로 나눈다.
- `Models/`: 모듈 공통 값 타입. 다른 모듈에 의존하지 않는다.
- `Shared/MDS/`: 디자인 시스템 자리. 지금은 비어 있다.
- `docs/specs/<기능>/`: 기능별 requirements.md, design.md, tasks.md.

## 작업 시작

1. `git status`로 저장소 상태를 확인한다. 사용자의 untracked 파일, 빌드 산출물, `Configs/Secrets.xcconfig`를 삭제하거나 커밋하지 않는다.
2. 해당 기능의 `docs/specs/<기능>/` 문서와 할당된 tasks 항목을 먼저 읽는다. 문서 상태가 "초안"이거나 걸리는 OPEN 항목이 남아 있으면 구현을 시작하지 않고 보고한다.
3. 작업별 전용 worktree를 쓰고, 기능 통합 브랜치의 최신 커밋에서 브랜치를 만든다. 브랜치 접두사는 작업하는 에이전트 자신의 이름을 소문자로 쓴다 (Claude는 `claude/`, Codex는 `codex/`, 그 밖의 에이전트도 같은 방식). 예: `claude/matchmaking-lobby`.
4. tasks.md의 선행 작업이 통합 브랜치에 병합된 것을 커밋 SHA로 확인한 뒤 시작한다. 이슈가 닫혔다는 사실만으로 판단하지 않는다.
5. 하나의 worktree에는 코드를 쓰는 에이전트를 하나만 둔다.

## 로컬 환경

- `Configs/Secrets.xcconfig`가 있어야 빌드된다. 내용은 `SERVER_HOST = <host:port>` 한 줄이다. 이 파일은 gitignore 대상이라 새 worktree에 자동으로 생기지 않는다. 없으면 만들되 값을 문서, 로그, 커밋, 응답에 쓰지 않는다.
- Tuist는 `mise`로 설치한다(`mise install tuist`). fastlane은 `bundle install` 후 `bundle exec fastlane`으로 실행한다.

## 구현 원칙

- 상태 변경은 Reducer에서만 한다. View는 상태를 그리고 액션을 보내기만 한다.
- 외부 의존성은 `@Dependency`로 주입한다. 시간은 `continuousClock`, UUID는 `uuid`를 쓴다.
- Feature는 Client의 `Live` 모듈을 import하지 않는다. Live 주입은 `M_GAME`에서만 한다.
- 새 서드파티 패키지를 추가하지 않는다.
- 서버나 파일에서 온 값을 강제 언래핑(`!`, `try!`)으로 변환하지 않는다.
- 문서에 없는 제품 정책(문구, 타이머 값, 화면 흐름)을 구현 편의로 정하지 않는다. 필요하면 멈추고 보고한다.
- 다른 작업이 소유한 파일과 공유 계약(tasks.md의 파일 소유권, 공유 계약 선행 작업)을 고치지 않는다. 필요하면 근거와 영향 파일을 보고한다.

## 검증

저장소 루트에서 실행한다.

- `swiftlint lint --strict`
- `tuist install && tuist generate --no-open`
- `bundle exec fastlane ci`: 린트와 빌드
- 테스트 실행 명령은 기능 tasks.md의 작업별 검증을 따른다

규칙:
- Reducer 테스트는 `TestStore`로 쓰고, 시간은 `TestClock`으로 제어한다. 실제 sleep에 기대지 않는다.
- CI 성공을 테스트 실행 증거로 쓰지 않는다. CI에 테스트 단계가 있는지 먼저 확인한다.
- 환경 문제로 실행하지 못한 검증은 통과로 기록하지 않는다. 무엇을 왜 못 했는지 적는다.

## 서버

- 서버 저장소는 https://github.com/temp-pj/Earie-ws 이고, iOS 작업에서는 읽기만 한다.
- 서버와 주고받는 형식은 기능 명세 폴더의 `protocol.md`와 `fixtures/`를 따른다. 서버 저장소에서 복사한 읽기 전용 사본이며 출처는 같은 폴더의 `SOURCE.md`에 있다. 사본을 고치지 않고, iOS 쪽에서 형식을 새로 정하지 않는다.
- 로컬 서버 실행에는 `CATALOG_PATH`, `SONG_MANIFEST_PATH`가 필요하다. 서버가 DB 연결 필수 조건을 없애기 전 버전이면 `DATABASE_URL`도 필요하다. DB 접속 정보는 문서, 로그, 커밋에 쓰지 않는다.

## PR

- 제목 접두사: `[Feat]`, `[Fix]`, `[Refactor]`, `[Test]`, `[Chore]`
- 대상 브랜치: 기능 tasks.md가 정한 통합 브랜치
- 본문: 관련 이슈, 작업 ID, 대응한 요구사항 ID, 변경 이유, 실행한 검증 명령과 결과, 검증하지 못한 것, 다음 작업에 넘겨줄 것(tasks.md 5번)
- 작업 완료는 구현과 검증을 뜻하며 병합이나 배포를 뜻하지 않는다.

## 작업자 입력 형식

```text
작업: [T-ID / 이슈 URL]
저장소와 worktree: [절대 경로]
기준: [통합 브랜치]의 [SHA]
명세: docs/specs/[기능]/ (requirements vN / design vN / tasks vN)
선행 PR과 병합 SHA: [목록]

AGENTS.md와 명세의 해당 작업을 읽어라. 할당된 파일 범위 안에서 완료 기준을 구현하고 검증하라.
공유 계약이나 제품 정책을 임의로 바꾸지 마라. OPEN 항목에 걸리면 멈추고 보고하라.
```

## 작업자 보고 형식

- 변경 파일 목록
- 대응한 요구사항·완료 조건 ID
- 실행한 검증 명령과 결과
- 검증하지 못한 것과 이유
- 멈춘 지점과 질문 (있다면)
- PR URL과 HEAD SHA
