import Foundation
import SwiftData

enum RecipeSourceKind: String, Codable, CaseIterable {
    case transcript
    case url

    /// Transcript saves publish to the family book. URL extracts stay private.
    var publishesToFamilyBook: Bool { self == .transcript }
}

@Model
final class Recipe {
    var id: UUID
    var title: String
    var rawTranscript: String
    var extractedJSON: String?
    var attribution: String?
    /// `transcript` or `url`. Transcript saves become public family-book cards.
    var sourceKind: String = RecipeSourceKind.transcript.rawValue
    var isDirty: Bool
    var createdAt: Date
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        title: String,
        rawTranscript: String,
        extractedJSON: String? = nil,
        attribution: String? = nil,
        sourceKind: RecipeSourceKind = .transcript
    ) {
        self.id = id
        self.title = title
        self.rawTranscript = rawTranscript
        self.extractedJSON = extractedJSON
        self.attribution = attribution
        self.sourceKind = sourceKind.rawValue
        self.isDirty = true
        self.createdAt = Date()
        self.updatedAt = Date()
    }

    var sourceKindValue: RecipeSourceKind {
        get { RecipeSourceKind(rawValue: sourceKind) ?? .transcript }
        set { sourceKind = newValue.rawValue }
    }

    func markDirty() {
        isDirty = true
        updatedAt = Date()
    }
}
