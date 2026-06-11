import Foundation
import SwiftData

@Model
final class Recipe {
    var id: UUID
    var title: String
    var rawTranscript: String
    var isDirty: Bool
    var createdAt: Date

    init(id: UUID = UUID(), title: String, rawTranscript: String) {
        self.id = id
        self.title = title
        self.rawTranscript = rawTranscript
        self.isDirty = true
        self.createdAt = Date()
    }
}
