import SwiftUI

struct RootView: View {
    @Environment(\.appEnv) private var appEnv
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        Group {
            if !appEnv.auth.hasCheckedInitialSession {
                // Splash — wait for Supabase to resolve the cached session
                // before committing to either screen (prevents tab-bar flash)
                ZStack {
                    Color.samanBg.ignoresSafeArea()
                    VStack(spacing: 8) {
                        Text("Saman")
                            .font(.cormorant(42))
                            .foregroundStyle(Color.samanPrimary)
                        Text("سامان")
                            .font(.custom("NotoNastaliqUrdu-Regular", size: 22))
                            .foregroundStyle(Color.samanAccent)
                    }
                }
            } else if appEnv.auth.isSignedIn {
                tabShell
            } else {
                AuthView()
            }
        }
        .task { await appEnv.auth.startListening() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active && appEnv.auth.isSignedIn { appEnv.syncNow() }
        }
    }

    private var tabShell: some View {
        TabView {
            Tab("Home", systemImage: "house.fill") {
                InventoryView()
            }
            Tab("Reorder", systemImage: "arrow.trianglehead.clockwise") {
                ReorderView()
            }
            Tab("Lists", systemImage: "list.bullet.rectangle.fill") {
                ShoppingListsView()
            }
        }
        .tint(Color.samanAccent)
    }
}

#Preview {
    RootView()
        .environment(\.appEnv, AppEnvironment(modelContainer: .preview))
}
