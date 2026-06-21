import Foundation
import SwiftData
import SwiftUI

@Model
final class Item {
    var id: UUID
    var name: String
    var quantity: Int
    var unit: String
    var minimumQuantity: Int
    var barcode: String?
    var expiryDate: Date?
    var notes: String?
    var imageUrl: String?

    @Relationship(deleteRule: .nullify, inverse: \Pantry.items)
    var pantry: Pantry?

    @Relationship(deleteRule: .nullify)
    var product: Product?

    var isDirty: Bool
    var createdAt: Date
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        name: String,
        quantity: Int = 0,
        unit: String = "unit",
        minimumQuantity: Int = 1,
        barcode: String? = nil,
        expiryDate: Date? = nil,
        notes: String? = nil,
        imageUrl: String? = nil,
        pantry: Pantry? = nil,
        product: Product? = nil
    ) {
        self.id = id
        self.name = name
        self.quantity = quantity
        self.unit = unit
        self.minimumQuantity = minimumQuantity
        self.barcode = barcode
        self.expiryDate = expiryDate
        self.notes = notes
        self.imageUrl = imageUrl
        self.pantry = pantry
        self.product = product
        self.isDirty = true
        self.createdAt = Date()
        self.updatedAt = Date()
    }

    func markDirty() {
        isDirty = true
        updatedAt = Date()
    }

    var isLow: Bool { quantity <= minimumQuantity }

    var isExpiringSoon: Bool {
        guard let expiry = expiryDate else { return false }
        return expiry.timeIntervalSinceNow < 7 * 24 * 60 * 60
    }

    var isExpired: Bool {
        guard let expiry = expiryDate else { return false }
        return expiry < Date()
    }

    var stockStatus: StockStatus {
        if quantity == 0            { return .out      }
        if isExpired || isExpiringSoon { return .expiring }
        if isLow                    { return .low      }
        return .inStock
    }
}

enum StockStatus {
    case inStock, low, expiring, out

    var dot: String {
        switch self {
        case .inStock:  return "●"
        case .low:      return "◐"
        case .expiring: return "◑"
        case .out:      return "○"
        }
    }

    var color: Color {
        switch self {
        case .inStock:  return .brandSaag
        case .low:      return .samanBrass
        case .expiring: return .accentAnaar
        case .out:      return .inkKohlSoft
        }
    }

    var isAttention: Bool { self != .inStock }
}
