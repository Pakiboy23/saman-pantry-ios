import SwiftUI
import SwiftData
import Supabase

@Observable
final class AppEnvironment {
    let modelContainer: ModelContainer
    let supabase: SupabaseClient
    let syncManager: SyncManager
    let auth: AuthService

    init(
        modelContainer: ModelContainer = .shared,
        supabase: SupabaseClient = .shared
    ) {
        self.modelContainer = modelContainer
        self.supabase = supabase
        self.syncManager = SyncManager(supabase: supabase)
        self.auth = AuthService(supabase: supabase)
    }

    func syncNow() {
        let context = modelContainer.mainContext
        Task {
            await syncManager.syncAll(context: context)
        }
    }
}

// MARK: - Environment key

private struct AppEnvironmentKey: EnvironmentKey {
    static let defaultValue = AppEnvironment()
}

extension EnvironmentValues {
    var appEnv: AppEnvironment {
        get { self[AppEnvironmentKey.self] }
        set { self[AppEnvironmentKey.self] = newValue }
    }
}
