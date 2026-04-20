import Foundation
import SwiftData

@Model
final class Store {
    var id: UUID
    var name: String
    var address: String?

    var isDirty: Bool
    var createdAt: Date
    var updatedAt: Date

    init(id: UUID = UUID(), name: String, address: String? = nil) {
        self.id = id
        self.name = name
        self.address = address
        self.isDirty = true
        self.createdAt = Date()
        self.updatedAt = Date()
    }

    func markDirty() {
        isDirty = true
        updatedAt = Date()
    }
}
