import Foundation
import SwiftData

@Model
final class ShoppingListItem {
    var id: UUID
    var quantity: Int
    var unit: String
    var isPurchased: Bool
    var estimatedPrice: Double?

    @Relationship(deleteRule: .nullify)
    var product: Product?

    var shoppingList: ShoppingList?

    var isDirty: Bool
    var createdAt: Date
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        quantity: Int = 1,
        unit: String = "unit",
        isPurchased: Bool = false,
        estimatedPrice: Double? = nil,
        product: Product? = nil,
        shoppingList: ShoppingList? = nil
    ) {
        self.id = id
        self.quantity = quantity
        self.unit = unit
        self.isPurchased = isPurchased
        self.estimatedPrice = estimatedPrice
        self.product = product
        self.shoppingList = shoppingList
        self.isDirty = true
        self.createdAt = Date()
        self.updatedAt = Date()
    }

    func markDirty() {
        isDirty = true
        updatedAt = Date()
    }
}
