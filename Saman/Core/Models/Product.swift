import Foundation
import SwiftData

@Model
final class Product {
    var id: UUID
    var name: String
    var barcode: String?
    var brand: String?
    var category: String?

    var isDirty: Bool
    var createdAt: Date
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        name: String,
        barcode: String? = nil,
        brand: String? = nil,
        category: String? = nil
    ) {
        self.id = id
        self.name = name
        self.barcode = barcode
        self.brand = brand
        self.category = category
        self.isDirty = true
        self.createdAt = Date()
        self.updatedAt = Date()
    }

    func markDirty() {
        isDirty = true
        updatedAt = Date()
    }
}
