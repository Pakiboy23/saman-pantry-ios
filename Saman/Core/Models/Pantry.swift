import Foundation
import SwiftData

@Model
final class Pantry {
    var id: UUID
    var name: String

    @Relationship(deleteRule: .cascade)
    var items: [Item]

    var isDirty: Bool
    var createdAt: Date
    var updatedAt: Date

    init(id: UUID = UUID(), name: String) {
        self.id = id
        self.name = name
        self.items = []
        self.isDirty = true
        self.createdAt = Date()
        self.updatedAt = Date()
    }

    func markDirty() {
        isDirty = true
        updatedAt = Date()
    }
}
