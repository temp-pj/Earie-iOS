import ComposableArchitecture
import FeatureRoom
import SwiftUI

// T5 임시 화면: 구 방 ID 입장 경로를 뺐다. RootView로 대체하는 것은 T6이다.
struct ContentView: View {
    let store: StoreOf<AppFeature>

    var body: some View {
        VStack {
            if let roomStore = store.scope(state: \.room, action: \.room) {
                RoomView(store: roomStore)
            }
        }
        .padding()
        .onAppear { store.send(.onAppear) }
    }
}

#Preview {
    ContentView(store: Store(initialState: AppFeature.State(),
                             reducer: { AppFeature() },
                             withDependencies: { $0.authClient = .live })
    )
}
