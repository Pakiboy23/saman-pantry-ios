import Foundation
import Supabase

/// Public family recipe book. Cards are projections of transcript recipes.
/// URL extracts never appear here. Reading does not consume extract quota.
struct FamilyRecipeBookCard: Identifiable, Hashable, Decodable, Sendable {
    let id: UUID
    let ownerId: UUID
    let title: String
    let attribution: String?
    let steps: [String]
    let ingredientPhrases: [String]
    let addedByLabel: String
    let createdAt: Date
    let updatedAt: Date

    enum CodingKeys: String, CodingKey {
        case id, title, attribution, steps
        case ownerId = "owner_id"
        case ingredientPhrases = "ingredient_phrases"
        case addedByLabel = "added_by_label"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }

    init(
        id: UUID,
        ownerId: UUID,
        title: String,
        attribution: String?,
        steps: [String],
        ingredientPhrases: [String],
        addedByLabel: String,
        createdAt: Date,
        updatedAt: Date
    ) {
        self.id = id
        self.ownerId = ownerId
        self.title = title
        self.attribution = attribution
        self.steps = steps
        self.ingredientPhrases = ingredientPhrases
        self.addedByLabel = addedByLabel
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    /// Keys exposed on a public card. raw_transcript is intentionally absent.
    static let publicFieldKeys: Set<String> = [
        "id", "owner_id", "title", "attribution", "steps",
        "ingredient_phrases", "added_by_label", "created_at", "updated_at",
    ]
}

struct FamilyRecipeBookNote: Identifiable, Hashable, Decodable, Sendable {
    let id: UUID
    let cardId: UUID
    let authorId: UUID
    let body: String
    let createdAt: Date

    enum CodingKeys: String, CodingKey {
        case id, body
        case cardId = "card_id"
        case authorId = "author_id"
        case createdAt = "created_at"
    }
}

enum FamilyRecipeBookError: LocalizedError {
    case unauthorized
    case loadFailed
    case noteFailed

    var errorDescription: String? {
        switch self {
        case .unauthorized:
            return "Sign in to open the family recipe book."
        case .loadFailed:
            return "Couldn't load the family recipe book. Check your connection and try again."
        case .noteFailed:
            return "Couldn't save that note. Try again."
        }
    }
}

final class FamilyRecipeBookService {
    static let shared = FamilyRecipeBookService()
    private init() {}

    private var client: SupabaseClient { .shared }

    func fetchCards() async throws -> [FamilyRecipeBookCard] {
        try await requireSignedIn()
        do {
            let rows: [FamilyRecipeBookCard] = try await client
                .from("recipe_book_cards")
                .select()
                .order("created_at", ascending: false)
                .execute()
                .value
            return rows
        } catch {
            throw FamilyRecipeBookError.loadFailed
        }
    }

    func fetchNotes(cardId: UUID) async throws -> [FamilyRecipeBookNote] {
        try await requireSignedIn()
        do {
            let rows: [FamilyRecipeBookNote] = try await client
                .from("recipe_book_notes")
                .select()
                .eq("card_id", value: cardId)
                .order("created_at", ascending: true)
                .execute()
                .value
            return rows
        } catch {
            throw FamilyRecipeBookError.loadFailed
        }
    }

    func addNote(cardId: UUID, body: String) async throws -> FamilyRecipeBookNote {
        let userId = try await requireSignedIn()
        let trimmed = body.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw FamilyRecipeBookError.noteFailed }
        struct Insert: Encodable {
            let cardId: UUID
            let authorId: UUID
            let body: String
            enum CodingKeys: String, CodingKey {
                case body
                case cardId = "card_id"
                case authorId = "author_id"
            }
        }
        do {
            let rows: [FamilyRecipeBookNote] = try await client
                .from("recipe_book_notes")
                .insert(Insert(cardId: cardId, authorId: userId, body: trimmed))
                .select()
                .execute()
                .value
            guard let note = rows.first else { throw FamilyRecipeBookError.noteFailed }
            return note
        } catch let error as FamilyRecipeBookError {
            throw error
        } catch {
            throw FamilyRecipeBookError.noteFailed
        }
    }

    @discardableResult
    private func requireSignedIn() async throws -> UUID {
        do {
            return try await client.auth.session.user.id
        } catch {
            throw FamilyRecipeBookError.unauthorized
        }
    }
}
