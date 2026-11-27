import ComposableArchitecture
import Models

/// 방 화면 문구. 출처는 requirements.md의 각 규칙이다.
enum RoomCopy {
    /// REQ-ROOM-04
    static func commandFailedMessage(_ code: RoomFailureCode) -> String {
        switch code {
        case .notHost: "방장만 게임을 시작할 수 있어요."
        case .notEnoughPlayers: "2명 이상일 때 시작할 수 있어요."
        case .invalidState: "지금은 게임을 시작할 수 없어요."
        case .internalError: "게임을 시작하지 못했어요. 다시 시도해 주세요."
        }
    }

    /// REQ-GAME-05
    static func abortMessage(_ reason: AbortReason) -> String {
        switch reason {
        case .insufficientPlayers: "상대가 모두 퇴장했습니다"
        case .internalError: "문제가 생겨 게임이 중단됐어요."
        }
    }

    static func commandFailedAlert(_ code: RoomFailureCode) -> AlertState<RoomReducer.Action.Alert> {
        AlertState {
            TextState(commandFailedMessage(code))
        } actions: {
            ButtonState(role: .cancel) {
                TextState("확인")
            }
        }
    }

    /// REQ-ROOM-08
    static let confirmLeaveAlert = AlertState<RoomReducer.Action.Alert> {
        TextState("게임에서 나갈까요?")
    } actions: {
        ButtonState(role: .cancel) {
            TextState("취소")
        }
        ButtonState(action: .confirmLeave) {
            TextState("확인")
        }
    }
}
