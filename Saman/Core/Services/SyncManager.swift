import Foundation
import SwiftData
import Supabase

@MainActor
final class SyncManager {

    private let supabase: SupabaseClient
    private let tombstoneKey = "samaan.sync.tombstones"

    nonisolated init() {
        self.supabase = .shared
    }

    nonisolated init(supabase: SupabaseClient) {
        self.supabase = supabase
    }

    func queueTombstone(table: String, id: UUID) {
        var stones = loadTombstones()
        stones.append(Tombstone(table: table, id: id))
        saveTombstones(stones)
    }

    func clearTombstones() {
        saveTombstones([])
    }

    /// Snapshot of queued server deletes. Used by tests to prove `deleteRecord`
    /// tombstones the row (and shopping-list children) before the local drop.
    func queuedTombstones() -> [(table: String, id: UUID)] {
        loadTombstones().map { ($0.table, $0.id) }
    }

    func syncAll(context: ModelContext) async {
        guard let userID = try? await supabase.auth.session.user.id else { return }
        await flushTombstones()
        await syncItems(context: context, userID: userID)
        await syncPantries(context: context, userID: userID)
        await syncProducts(context: context, userID: userID)
        await syncStores(context: context, userID: userID)
        await syncShoppingLists(context: context, userID: userID)
        await syncShoppingListItems(context: context, userID: userID)
        await syncRecipes(context: context, userID: userID)
        await pullAll(context: context, userID: userID)
    }

    // MARK: - Deletes

    private struct Tombstone: Codable {
        let table: String
        let id: UUID
    }

    private func loadTombstones() -> [Tombstone] {
        guard let data = UserDefaults.standard.data(forKey: tombstoneKey) else { return [] }
        return (try? JSONDecoder().decode([Tombstone].self, from: data)) ?? []
    }

    private func saveTombstones(_ stones: [Tombstone]) {
        UserDefaults.standard.set(try? JSONEncoder().encode(stones), forKey: tombstoneKey)
    }

    private func flushTombstones() async {
        let stones = loadTombstones()
        guard !stones.isEmpty else { return }
        var remaining: [Tombstone] = []
        for stone in stones {
            do {
                try await supabase.from(stone.table).delete().eq("id", value: stone.id).execute()
            } catch {
                AppLogger.error("[Sync] delete \(stone.table): \(error)")
                remaining.append(stone)
            }
        }
        saveTombstones(remaining)
    }

    // MARK: - Upload dirty

    private func syncItems(context: ModelContext, userID: UUID) async {
        let dirty = fetchAll(Item.self, context: context).filter(\.isDirty)
        guard !dirty.isEmpty else { return }
        let payloads = dirty.map { ItemPayload($0, userID: userID) }
        do {
            try await supabase.from("items").upsert(payloads).execute()
            dirty.forEach { $0.isDirty = false }
            try? context.save()
        } catch { AppLogger.error("[Sync] items: \(error)") }
    }

    private func syncPantries(context: ModelContext, userID: UUID) async {
        let dirty = fetchAll(Pantry.self, context: context).filter(\.isDirty)
        guard !dirty.isEmpty else { return }
        let payloads = dirty.map { PantryPayload($0, userID: userID) }
        do {
            try await supabase.from("pantries").upsert(payloads).execute()
            dirty.forEach { $0.isDirty = false }
            try? context.save()
        } catch { AppLogger.error("[Sync] pantries: \(error)") }
    }

    private func syncProducts(context: ModelContext, userID: UUID) async {
        let dirty = fetchAll(Product.self, context: context).filter(\.isDirty)
        guard !dirty.isEmpty else { return }
        let payloads = dirty.map { ProductPayload($0, userID: userID) }
        do {
            try await supabase.from("products").upsert(payloads).execute()
            dirty.forEach { $0.isDirty = false }
            try? context.save()
        } catch { AppLogger.error("[Sync] products: \(error)") }
    }

    private func syncStores(context: ModelContext, userID: UUID) async {
        let dirty = fetchAll(Store.self, context: context).filter(\.isDirty)
        guard !dirty.isEmpty else { return }
        let payloads = dirty.map { StorePayload($0, userID: userID) }
        do {
            try await supabase.from("stores").upsert(payloads).execute()
            dirty.forEach { $0.isDirty = false }
            try? context.save()
        } catch { AppLogger.error("[Sync] stores: \(error)") }
    }

    private func syncShoppingLists(context: ModelContext, userID: UUID) async {
        let dirty = fetchAll(ShoppingList.self, context: context).filter(\.isDirty)
        guard !dirty.isEmpty else { return }
        let payloads = dirty.map { ShoppingListPayload($0, userID: userID) }
        do {
            try await supabase.from("shopping_lists").upsert(payloads).execute()
            dirty.forEach { $0.isDirty = false }
            try? context.save()
        } catch { AppLogger.error("[Sync] shopping_lists: \(error)") }
    }

    private func syncShoppingListItems(context: ModelContext, userID: UUID) async {
        let dirty = fetchAll(ShoppingListItem.self, context: context).filter(\.isDirty)
        guard !dirty.isEmpty else { return }
        let payloads = dirty.map { ShoppingListItemPayload($0, userID: userID) }
        do {
            try await supabase.from("shopping_list_items").upsert(payloads).execute()
            dirty.forEach { $0.isDirty = false }
            try? context.save()
        } catch { AppLogger.error("[Sync] shopping_list_items: \(error)") }
    }

    private func syncRecipes(context: ModelContext, userID: UUID) async {
        let dirty = fetchAll(Recipe.self, context: context).filter(\.isDirty)
        guard !dirty.isEmpty else { return }
        let payloads = dirty.map { RecipePayload($0, userID: userID) }
        do {
            try await supabase.from("recipes").upsert(payloads).execute()
            dirty.forEach { $0.isDirty = false }
            try? context.save()
        } catch { AppLogger.error("[Sync] recipes: \(error)") }
    }

    // MARK: - Pull

    private func pullAll(context: ModelContext, userID: UUID) async {
        await pullPantries(context: context, userID: userID)
        await pullProducts(context: context, userID: userID)
        await pullStores(context: context, userID: userID)
        await pullItems(context: context, userID: userID)
        await pullShoppingLists(context: context, userID: userID)
        await pullShoppingListItems(context: context, userID: userID)
        await pullRecipes(context: context, userID: userID)
        try? context.save()
    }

    private func pullPantries(context: ModelContext, userID: UUID) async {
        let rows: [PantryRow]
        do { rows = try await fetchRows("pantries", userID: userID) } catch { return }
        let local = fetchAll(Pantry.self, context: context)
        let byId = Dictionary(uniqueKeysWithValues: local.map { ($0.id, $0) })
        var seen = Set<UUID>()
        for row in rows {
            seen.insert(row.id)
            if let existing = byId[row.id] {
                if SyncReconcile.shouldApplyServer(localUpdatedAt: existing.updatedAt, localDirty: existing.isDirty, serverUpdatedAt: row.updatedAt) {
                    existing.name = row.name
                    existing.updatedAt = row.updatedAt
                    existing.isDirty = false
                }
            } else {
                let pantry = Pantry(id: row.id, name: row.name)
                pantry.isDirty = false
                pantry.updatedAt = row.updatedAt
                context.insert(pantry)
            }
        }
        for item in local where SyncReconcile.shouldDeleteLocal(localDirty: item.isDirty, presentOnServer: seen.contains(item.id)) {
            context.delete(item)
        }
    }

    private func pullProducts(context: ModelContext, userID: UUID) async {
        let rows: [ProductRow]
        do { rows = try await fetchRows("products", userID: userID) } catch { return }
        let local = fetchAll(Product.self, context: context)
        let byId = Dictionary(uniqueKeysWithValues: local.map { ($0.id, $0) })
        var seen = Set<UUID>()
        for row in rows {
            seen.insert(row.id)
            if let existing = byId[row.id] {
                if SyncReconcile.shouldApplyServer(localUpdatedAt: existing.updatedAt, localDirty: existing.isDirty, serverUpdatedAt: row.updatedAt) {
                    existing.name = row.name
                    existing.barcode = row.barcode
                    existing.brand = row.brand
                    existing.category = row.category
                    existing.updatedAt = row.updatedAt
                    existing.isDirty = false
                }
            } else {
                let product = Product(id: row.id, name: row.name, barcode: row.barcode, brand: row.brand, category: row.category)
                product.isDirty = false
                product.updatedAt = row.updatedAt
                context.insert(product)
            }
        }
        for item in local where SyncReconcile.shouldDeleteLocal(localDirty: item.isDirty, presentOnServer: seen.contains(item.id)) {
            context.delete(item)
        }
    }

    private func pullStores(context: ModelContext, userID: UUID) async {
        let rows: [StoreRow]
        do { rows = try await fetchRows("stores", userID: userID) } catch { return }
        let local = fetchAll(Store.self, context: context)
        let byId = Dictionary(uniqueKeysWithValues: local.map { ($0.id, $0) })
        var seen = Set<UUID>()
        for row in rows {
            seen.insert(row.id)
            if let existing = byId[row.id] {
                if SyncReconcile.shouldApplyServer(localUpdatedAt: existing.updatedAt, localDirty: existing.isDirty, serverUpdatedAt: row.updatedAt) {
                    existing.name = row.name
                    existing.address = row.address
                    existing.updatedAt = row.updatedAt
                    existing.isDirty = false
                }
            } else {
                let store = Store(id: row.id, name: row.name, address: row.address)
                store.isDirty = false
                store.updatedAt = row.updatedAt
                context.insert(store)
            }
        }
        for item in local where SyncReconcile.shouldDeleteLocal(localDirty: item.isDirty, presentOnServer: seen.contains(item.id)) {
            context.delete(item)
        }
    }

    private func pullItems(context: ModelContext, userID: UUID) async {
        let rows: [ItemRow]
        do { rows = try await fetchRows("items", userID: userID) } catch { return }
        let local = fetchAll(Item.self, context: context)
        let byId = Dictionary(uniqueKeysWithValues: local.map { ($0.id, $0) })
        let pantries = Dictionary(uniqueKeysWithValues: fetchAll(Pantry.self, context: context).map { ($0.id, $0) })
        let products = Dictionary(uniqueKeysWithValues: fetchAll(Product.self, context: context).map { ($0.id, $0) })
        var seen = Set<UUID>()
        for row in rows {
            seen.insert(row.id)
            if let existing = byId[row.id] {
                if SyncReconcile.shouldApplyServer(localUpdatedAt: existing.updatedAt, localDirty: existing.isDirty, serverUpdatedAt: row.updatedAt) {
                    apply(row, to: existing, pantries: pantries, products: products)
                }
            } else {
                let item = Item(id: row.id, name: row.name, quantity: row.quantity, unit: row.unit, minimumQuantity: row.minimumQuantity)
                apply(row, to: item, pantries: pantries, products: products)
                item.isDirty = false
                context.insert(item)
            }
        }
        for item in local where SyncReconcile.shouldDeleteLocal(localDirty: item.isDirty, presentOnServer: seen.contains(item.id)) {
            context.delete(item)
        }
    }

    private func apply(_ row: ItemRow, to item: Item, pantries: [UUID: Pantry], products: [UUID: Product]) {
        item.name = row.name
        item.quantity = row.quantity
        item.unit = row.unit
        item.minimumQuantity = row.minimumQuantity
        item.barcode = row.barcode
        item.expiryDate = row.expiryDate
        item.notes = row.notes
        item.imageUrl = row.imageUrl
        item.updatedAt = row.updatedAt
        item.pantry = row.pantryId.flatMap { pantries[$0] }
        item.product = row.productId.flatMap { products[$0] }
        item.isDirty = false
    }

    private func pullShoppingLists(context: ModelContext, userID: UUID) async {
        let rows: [ShoppingListRow]
        do { rows = try await fetchRows("shopping_lists", userID: userID) } catch { return }
        let local = fetchAll(ShoppingList.self, context: context)
        let byId = Dictionary(uniqueKeysWithValues: local.map { ($0.id, $0) })
        let stores = Dictionary(uniqueKeysWithValues: fetchAll(Store.self, context: context).map { ($0.id, $0) })
        var seen = Set<UUID>()
        for row in rows {
            seen.insert(row.id)
            if let existing = byId[row.id] {
                if SyncReconcile.shouldApplyServer(localUpdatedAt: existing.updatedAt, localDirty: existing.isDirty, serverUpdatedAt: row.updatedAt) {
                    existing.name = row.name
                    existing.isCompleted = row.isCompleted
                    existing.store = row.storeId.flatMap { stores[$0] }
                    existing.updatedAt = row.updatedAt
                    existing.isDirty = false
                }
            } else {
                let list = ShoppingList(id: row.id, name: row.name, store: row.storeId.flatMap { stores[$0] })
                list.isCompleted = row.isCompleted
                list.isDirty = false
                list.updatedAt = row.updatedAt
                context.insert(list)
            }
        }
        for item in local where SyncReconcile.shouldDeleteLocal(localDirty: item.isDirty, presentOnServer: seen.contains(item.id)) {
            context.delete(item)
        }
    }

    private func pullShoppingListItems(context: ModelContext, userID: UUID) async {
        let rows: [ShoppingListItemRow]
        do { rows = try await fetchRows("shopping_list_items", userID: userID) } catch { return }
        let local = fetchAll(ShoppingListItem.self, context: context)
        let byId = Dictionary(uniqueKeysWithValues: local.map { ($0.id, $0) })
        let lists = Dictionary(uniqueKeysWithValues: fetchAll(ShoppingList.self, context: context).map { ($0.id, $0) })
        let products = Dictionary(uniqueKeysWithValues: fetchAll(Product.self, context: context).map { ($0.id, $0) })
        var seen = Set<UUID>()
        for row in rows {
            seen.insert(row.id)
            if let existing = byId[row.id] {
                if SyncReconcile.shouldApplyServer(localUpdatedAt: existing.updatedAt, localDirty: existing.isDirty, serverUpdatedAt: row.updatedAt) {
                    existing.quantity = row.quantity
                    existing.unit = row.unit
                    existing.isPurchased = row.isPurchased
                    existing.estimatedPrice = row.estimatedPrice
                    existing.product = row.productId.flatMap { products[$0] }
                    existing.shoppingList = row.shoppingListId.flatMap { lists[$0] }
                    existing.updatedAt = row.updatedAt
                    existing.isDirty = false
                }
            } else {
                let item = ShoppingListItem(
                    id: row.id,
                    quantity: row.quantity,
                    unit: row.unit,
                    isPurchased: row.isPurchased,
                    estimatedPrice: row.estimatedPrice,
                    product: row.productId.flatMap { products[$0] },
                    shoppingList: row.shoppingListId.flatMap { lists[$0] }
                )
                item.isDirty = false
                item.updatedAt = row.updatedAt
                context.insert(item)
            }
        }
        for item in local where SyncReconcile.shouldDeleteLocal(localDirty: item.isDirty, presentOnServer: seen.contains(item.id)) {
            context.delete(item)
        }
    }

    private func pullRecipes(context: ModelContext, userID: UUID) async {
        let rows: [RecipeRow]
        do { rows = try await fetchRows("recipes", userID: userID) } catch { return }
        let local = fetchAll(Recipe.self, context: context)
        let byId = Dictionary(uniqueKeysWithValues: local.map { ($0.id, $0) })
        var seen = Set<UUID>()
        for row in rows {
            seen.insert(row.id)
            if let existing = byId[row.id] {
                if SyncReconcile.shouldApplyServer(localUpdatedAt: existing.updatedAt, localDirty: existing.isDirty, serverUpdatedAt: row.updatedAt) {
                    existing.title = row.title
                    existing.rawTranscript = row.rawTranscript
                    existing.extractedJSON = row.extractedJson
                    existing.attribution = row.attribution
                    existing.updatedAt = row.updatedAt
                    existing.isDirty = false
                }
            } else {
                let recipe = Recipe(id: row.id, title: row.title, rawTranscript: row.rawTranscript, extractedJSON: row.extractedJson, attribution: row.attribution)
                recipe.isDirty = false
                recipe.updatedAt = row.updatedAt
                context.insert(recipe)
            }
        }
        for item in local where SyncReconcile.shouldDeleteLocal(localDirty: item.isDirty, presentOnServer: seen.contains(item.id)) {
            context.delete(item)
        }
    }

    private func fetchRows<T: Decodable>(_ table: String, userID: UUID) async throws -> [T] {
        let response: [T] = try await supabase
            .from(table)
            .select()
            .eq("user_id", value: userID)
            .execute()
            .value
        return response
    }

    private func fetchAll<T: PersistentModel>(_ type: T.Type, context: ModelContext) -> [T] {
        (try? context.fetch(FetchDescriptor<T>())) ?? []
    }
}

// MARK: - Codable payloads / rows

private struct ItemPayload: Encodable {
    let id, userId: UUID; let pantryId, productId: UUID?
    let name: String; let quantity, minimumQuantity: Int
    let unit: String; let barcode: String?
    let expiryDate: Date?; let notes: String?; let imageUrl: String?
    let updatedAt: Date

    init(_ i: Item, userID: UUID) {
        id = i.id; userId = userID; pantryId = i.pantry?.id; productId = i.product?.id
        name = i.name; quantity = i.quantity; unit = i.unit
        minimumQuantity = i.minimumQuantity; barcode = i.barcode
        expiryDate = i.expiryDate; notes = i.notes; imageUrl = i.imageUrl
        updatedAt = i.updatedAt
    }
    enum CodingKeys: String, CodingKey {
        case id, name, quantity, unit, barcode, notes
        case userId = "user_id"; case pantryId = "pantry_id"; case productId = "product_id"
        case minimumQuantity = "minimum_quantity"; case updatedAt = "updated_at"
        case expiryDate = "expiry_date"; case imageUrl = "image_url"
    }
}

private struct PantryPayload: Encodable {
    let id, userId: UUID; let name: String; let updatedAt: Date
    init(_ p: Pantry, userID: UUID) { id = p.id; userId = userID; name = p.name; updatedAt = p.updatedAt }
    enum CodingKeys: String, CodingKey { case id, name; case userId = "user_id"; case updatedAt = "updated_at" }
}

private struct ProductPayload: Encodable {
    let id, userId: UUID; let name: String; let barcode, brand, category: String?; let updatedAt: Date
    init(_ p: Product, userID: UUID) { id = p.id; userId = userID; name = p.name; barcode = p.barcode; brand = p.brand; category = p.category; updatedAt = p.updatedAt }
    enum CodingKeys: String, CodingKey { case id, name, barcode, brand, category; case userId = "user_id"; case updatedAt = "updated_at" }
}

private struct StorePayload: Encodable {
    let id, userId: UUID; let name: String; let address: String?; let updatedAt: Date
    init(_ s: Store, userID: UUID) { id = s.id; userId = userID; name = s.name; address = s.address; updatedAt = s.updatedAt }
    enum CodingKeys: String, CodingKey { case id, name, address; case userId = "user_id"; case updatedAt = "updated_at" }
}

private struct ShoppingListPayload: Encodable {
    let id, userId: UUID; let storeId: UUID?; let name: String; let isCompleted: Bool; let updatedAt: Date
    init(_ l: ShoppingList, userID: UUID) { id = l.id; userId = userID; storeId = l.store?.id; name = l.name; isCompleted = l.isCompleted; updatedAt = l.updatedAt }
    enum CodingKeys: String, CodingKey { case id, name; case userId = "user_id"; case storeId = "store_id"; case isCompleted = "is_completed"; case updatedAt = "updated_at" }
}

private struct ShoppingListItemPayload: Encodable {
    let id, userId: UUID; let shoppingListId, productId: UUID?; let quantity: Int; let unit: String; let isPurchased: Bool; let estimatedPrice: Double?; let updatedAt: Date
    init(_ i: ShoppingListItem, userID: UUID) { id = i.id; userId = userID; shoppingListId = i.shoppingList?.id; productId = i.product?.id; quantity = i.quantity; unit = i.unit; isPurchased = i.isPurchased; estimatedPrice = i.estimatedPrice; updatedAt = i.updatedAt }
    enum CodingKeys: String, CodingKey { case id, quantity, unit; case userId = "user_id"; case shoppingListId = "shopping_list_id"; case productId = "product_id"; case isPurchased = "is_purchased"; case estimatedPrice = "estimated_price"; case updatedAt = "updated_at" }
}

private struct RecipePayload: Encodable {
    let id, userId: UUID; let title: String; let rawTranscript: String; let extractedJson: String?; let attribution: String?; let updatedAt: Date
    init(_ r: Recipe, userID: UUID) {
        id = r.id; userId = userID; title = r.title; rawTranscript = r.rawTranscript
        extractedJson = r.extractedJSON; attribution = r.attribution; updatedAt = r.updatedAt
    }
    enum CodingKeys: String, CodingKey {
        case id, title, attribution
        case userId = "user_id"; case rawTranscript = "raw_transcript"
        case extractedJson = "extracted_json"; case updatedAt = "updated_at"
    }
}

private struct PantryRow: Decodable {
    let id: UUID; let name: String; let updatedAt: Date
    enum CodingKeys: String, CodingKey { case id, name; case updatedAt = "updated_at" }
}

private struct ProductRow: Decodable {
    let id: UUID; let name: String; let barcode, brand, category: String?; let updatedAt: Date
    enum CodingKeys: String, CodingKey { case id, name, barcode, brand, category; case updatedAt = "updated_at" }
}

private struct StoreRow: Decodable {
    let id: UUID; let name: String; let address: String?; let updatedAt: Date
    enum CodingKeys: String, CodingKey { case id, name, address; case updatedAt = "updated_at" }
}

private struct ItemRow: Decodable {
    let id: UUID; let pantryId, productId: UUID?
    let name: String; let quantity, minimumQuantity: Int
    let unit: String; let barcode: String?
    let expiryDate: Date?; let notes: String?; let imageUrl: String?
    let updatedAt: Date
    enum CodingKeys: String, CodingKey {
        case id, name, quantity, unit, barcode, notes
        case pantryId = "pantry_id"; case productId = "product_id"
        case minimumQuantity = "minimum_quantity"; case updatedAt = "updated_at"
        case expiryDate = "expiry_date"; case imageUrl = "image_url"
    }
}

private struct ShoppingListRow: Decodable {
    let id: UUID; let storeId: UUID?; let name: String; let isCompleted: Bool; let updatedAt: Date
    enum CodingKeys: String, CodingKey { case id, name; case storeId = "store_id"; case isCompleted = "is_completed"; case updatedAt = "updated_at" }
}

private struct ShoppingListItemRow: Decodable {
    let id: UUID; let shoppingListId, productId: UUID?; let quantity: Int; let unit: String; let isPurchased: Bool; let estimatedPrice: Double?; let updatedAt: Date
    enum CodingKeys: String, CodingKey { case id, quantity, unit; case shoppingListId = "shopping_list_id"; case productId = "product_id"; case isPurchased = "is_purchased"; case estimatedPrice = "estimated_price"; case updatedAt = "updated_at" }
}

private struct RecipeRow: Decodable {
    let id: UUID; let title: String; let rawTranscript: String; let extractedJson: String?; let attribution: String?; let updatedAt: Date
    enum CodingKeys: String, CodingKey {
        case id, title, attribution
        case rawTranscript = "raw_transcript"; case extractedJson = "extracted_json"; case updatedAt = "updated_at"
    }
}
