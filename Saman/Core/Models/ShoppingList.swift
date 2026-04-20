import Foundation
import SwiftData

@Model
final class ShoppingList {
    var id: UUID
    var name: String

    @Relationship(deleteRule: .nullify)
    var store: Store?

    @Relationship(deleteRule: .cascade, inverse: \ShoppingListItem.shoppingList)
    var items: [ShoppingListItem]

    var isCompleted: Bool
    var isDirty: Bool
    var createdAt: Date
    var updatedAt: Date

    init(id: UUID = UUID(), name: String, store: Store? = nil) {
        self.id = id
        self.name = name
        self.store = store
        self.items = []
        self.isCompleted = false
        self.isDirty = true
        self.createdAt = Date()
        self.updatedAt = Date()
    }

    func markDirty() {
        isDirty = true
        updatedAt = Date()
    }

    var pendingCount: Int { items.filter { !$0.isPurchased }.count }
}
