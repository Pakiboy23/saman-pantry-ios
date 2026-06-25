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
                    Color.surfaceDoodh.ignoresSafeArea()
                    VStack(spacing: 8) {
                        Text("Saman")
                            .font(.pantryWordmark)
                            .foregroundStyle(Color.brandSaag)
                        Text("سامان")
                            .font(.custom("NotoNastaliqUrdu-Regular", size: 22))
                            .foregroundStyle(Color.inkKohlSoft)
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
            HomeView()
                .tabItem {
                    Label("Home", systemImage: "house.fill")
                }

            InventoryView()
                .tabItem {
                    Label("Pantry", systemImage: "cabinet.fill")
                }

            ShoppingListsView()
                .tabItem {
                    Label("Lists", systemImage: "list.bullet.rectangle.fill")
                }

            RecipesView()
                .tabItem {
                    Label("Recipes", systemImage: "fork.knife")
                }
        }
        .tint(Color.brandSaag)
    }
}

#Preview {
    RootView()
        .environment(\.appEnv, AppEnvironment(modelContainer: .preview))
}
