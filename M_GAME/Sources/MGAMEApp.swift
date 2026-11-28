import ClientAudioLive
import ClientAuthLive
import ClientCatalogLive
import ClientMusicEntitlementLive
import ClientSessionLive
import ComposableArchitecture
import Foundation
import SwiftUI

@main
struct MGAMEApp: App {
    /// live 의존성은 여기서만 주입한다 (design 4, 13).
    /// `webSocketClient`는 주입하지 않는다. `SessionClient.live`가 자기 WebSocket 연결을 갖는다.
    let store = Store(initialState: AppFeature.State()) {
        AppFeature()
    } withDependencies: {
        $0.authClient = .live
        $0.musicEntitlementClient = .live
        $0.audioClient = .live
        $0.sessionClient = .live
        $0.catalogClient = .live
        $0.categoryPreferenceClient = .live
    }

    var body: some Scene {
        WindowGroup {
            RootView(store: store)
        }
    }
}
