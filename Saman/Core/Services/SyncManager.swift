import Foundation
import SwiftData
import Supabase

@MainActor
final class SyncManager {

    private let supabase: SupabaseClient

    init() {
        self.supabase = .shared
    }

    init(supabase: SupabaseClient) {
        self.supabase = supabase
    }

    // MARK: - Public

    func syncAll(context: ModelContext) async {
        guard let userID = try? await supabase.auth.session.user.id else { return }
        await syncItems(context: context, userID: userID)
        await syncPantries(context: context, userID: userID)
        await syncProducts(context: context, userID: userID)
        await syncStores(context: context, userID: userID)
        await syncShoppingLists(context: context, userID: userID)
        await syncShoppingListItems(context: context, userID: userID)
    }

    // MARK: - Per-model sync

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

    private func fetchAll<T: PersistentModel>(_ type: T.Type, context: ModelContext) -> [T] {
        (try? context.fetch(FetchDescriptor<T>())) ?? []
    }
}

// MARK: - Codable payloads

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
