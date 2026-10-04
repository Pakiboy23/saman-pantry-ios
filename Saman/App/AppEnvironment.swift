import SwiftUI
import SwiftData
import Supabase

@Observable
final class AppEnvironment {
    let modelContainer: ModelContainer
    let supabase: SupabaseClient
    let syncManager: SyncManager
    let auth: AuthService
    let purchases: PurchaseService

    /// Presents `AuthView` from Settings or recipe capture (nested cover)
    /// when a guest hits Sync, AI extract, or account deletion.
    var isAuthPresented = false

    init(
        modelContainer: ModelContainer = .shared,
        supabase: SupabaseClient = .shared
    ) {
        self.modelContainer = modelContainer
        self.supabase = supabase
        self.syncManager = SyncManager(supabase: supabase)
        self.auth = AuthService(supabase: supabase)
        self.purchases = PurchaseService()
    }

    /// Returns `true` when a session already exists. Otherwise presents
    /// `AuthView` and returns `false` so the caller can wait or abort.
    @discardableResult
    func requireAccount() -> Bool {
        if auth.isSignedIn { return true }
        isAuthPresented = true
        return false
    }

    func syncNow() {
        // Screenshot / UI-test seeds are local-only. Pulling would race the
        // canned kitchen, and a fake "ui-testing" user must not push to prod.
        if ScreenshotLaunchConfiguration.current.shouldSeedDemoKitchen { return }
        // Guests can edit locally. Background sync is a no-op without a
        // session (`SyncManager` returns early). Do not prompt here — only
        // the explicit Settings "Sync now" control should demand an account.
        let container = modelContainer
        let manager = syncManager
        Task { @MainActor in
            await manager.syncAll(context: container.mainContext)
        }
    }

    /// Wait until dirty uploads and tombstone deletes have had a chance to
    /// reach the server. Sign-out must call this *before* dropping the
    /// session; `clearLocalStore()` wipes SwiftData and the delete queue.
    func flushPendingSync() async {
        if ScreenshotLaunchConfiguration.current.shouldSeedDemoKitchen { return }
        await syncManager.syncAll(context: modelContainer.mainContext)
    }

    /// Queue a server delete, then drop the local row. Without the tombstone,
    /// pull-sync would resurrect the row from Supabase on the next launch.
    /// Shopping lists also tombstone their items — cascade-delete is local-only.
    @MainActor
    func deleteRecord<T: PersistentModel>(_ model: T, table: String, id: UUID) {
        if let list = model as? ShoppingList {
            for item in Array(list.items) {
                syncManager.queueTombstone(table: "shopping_list_items", id: item.id)
            }
        }
        syncManager.queueTombstone(table: table, id: id)
        modelContainer.mainContext.delete(model)
        try? modelContainer.mainContext.save()
        syncNow()
    }

    static let lastAuthenticatedUserIDKey = "samaan.lastAuthenticatedUserID"

    /// Wipe all locally-cached SwiftData. Called on sign-out, session loss,
    /// account switch, and account deletion so guest browse never inherits the
    /// prior user's pantry (and so push-sync cannot re-upload it under a new user).
    @MainActor
    func clearLocalStore() {
        syncManager.invalidateInFlightSync()
        let context = modelContainer.mainContext
        try? context.delete(model: Item.self)
        try? context.delete(model: Pantry.self)
        try? context.delete(model: Product.self)
        try? context.delete(model: Store.self)
        try? context.delete(model: ShoppingList.self)
        try? context.delete(model: ShoppingListItem.self)
        try? context.delete(model: Recipe.self)
        try? context.save()
        syncManager.clearTombstones()
    }

    /// Align the on-disk kitchen with the current auth user.
    /// Screenshot / UI-test launches keep their seeded kitchen.
    @MainActor
    func reconcileLocalStore(
        currentUserID: String?,
        defaults: UserDefaults = .standard
    ) {
        if ScreenshotLaunchConfiguration.current.skipsAuth {
            return
        }
        let persisted = defaults.string(forKey: Self.lastAuthenticatedUserIDKey)
        if LocalStoreAuthPolicy.shouldClearLocalStore(
            persistedUserID: persisted,
            currentUserID: currentUserID
        ) {
            clearLocalStore()
        }
        let trimmed = currentUserID?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if trimmed.isEmpty {
            defaults.removeObject(forKey: Self.lastAuthenticatedUserIDKey)
        } else {
            defaults.set(trimmed, forKey: Self.lastAuthenticatedUserIDKey)
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
