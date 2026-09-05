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

    func syncNow() {
        let container = modelContainer
        let manager = syncManager
        Task { @MainActor in
            await manager.syncAll(context: container.mainContext)
        }
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

    /// Wipe all locally-cached SwiftData. Called on sign-out and account deletion
    /// so the next account on a shared device never inherits the prior user's
    /// pantry (push-only sync would otherwise re-upload it under the new user).
    @MainActor
    func clearLocalStore() {
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
