import Foundation
import SwiftData

@Model
final class Recipe {
    var id: UUID
    var title: String
    var rawTranscript: String
    var extractedJSON: String?
    var attribution: String?
    var isDirty: Bool
    var createdAt: Date
    var updatedAt: Date

    init(id: UUID = UUID(), title: String, rawTranscript: String, extractedJSON: String? = nil, attribution: String? = nil) {
        self.id = id
        self.title = title
        self.rawTranscript = rawTranscript
        self.extractedJSON = extractedJSON
        self.attribution = attribution
        self.isDirty = true
        self.createdAt = Date()
        self.updatedAt = Date()
    }

    func markDirty() {
        isDirty = true
        updatedAt = Date()
    }
}
