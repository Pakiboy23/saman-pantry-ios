import Foundation
import Supabase

/// Private family books (migration 20261024000000_family_books).
/// Only members can read a family. Members see a snapshot of each recipe:
/// title, attribution, steps, ingredient phrases and a source link.
/// The spoken transcript never leaves the cook's own book.
struct Family: Identifiable, Hashable, Decodable, Sendable {
    let id: UUID
    let name: String
    let ownerId: UUID
    let createdAt: Date

    enum CodingKeys: String, CodingKey {
        case id, name
        case ownerId = "owner_id"
        case createdAt = "created_at"
    }
}

struct FamilyMember: Identifiable, Hashable, Decodable, Sendable {
    let familyId: UUID
    let userId: UUID
    let role: String
    let displayLabel: String
    let joinedAt: Date

    var id: UUID { userId }
    var isOwner: Bool { role == "owner" }

    enum CodingKeys: String, CodingKey {
        case role
        case familyId = "family_id"
        case userId = "user_id"
        case displayLabel = "display_label"
        case joinedAt = "joined_at"
    }
}

struct FamilyRecipe: Identifiable, Hashable, Decodable, Sendable {
    let familyId: UUID
    let recipeId: UUID
    let addedBy: UUID?
    let addedByLabel: String
    let title: String
    let attribution: String?
    let steps: [String]
    let ingredientPhrases: [String]
    let sourceUrl: String?
    let addedAt: Date

    var id: String { "\(familyId)-\(recipeId)" }

    enum CodingKeys: String, CodingKey {
        case title, attribution, steps
        case familyId = "family_id"
        case recipeId = "recipe_id"
        case addedBy = "added_by"
        case addedByLabel = "added_by_label"
        case ingredientPhrases = "ingredient_phrases"
        case sourceUrl = "source_url"
        case addedAt = "added_at"
    }

    /// Keys a member can read. raw_transcript is intentionally absent.
    static let memberFieldKeys: Set<String> = [
        "family_id", "recipe_id", "added_by", "added_by_label", "title", "attribution",
        "steps", "ingredient_phrases", "source_url", "added_at", "updated_at",
    ]
}

struct FamilyRecipeNote: Identifiable, Hashable, Decodable, Sendable {
    let id: UUID
    let authorId: UUID
    let body: String
    let createdAt: Date

    enum CodingKeys: String, CodingKey {
        case id, body
        case authorId = "author_id"
        case createdAt = "created_at"
    }
}

struct FamilyInvite: Hashable, Decodable, Sendable {
    let code: String
    let token: String
    let expiresAt: Date

    enum CodingKeys: String, CodingKey {
        case code, token
        case expiresAt = "expires_at"
    }

    var link: URL { FamilyInviteLink.url(token: token) }

    /// Share sheet text. Plain, no em dashes.
    var shareText: String {
        "Join our family cookbook on Samaan Pantry: \(link.absoluteString)\nOr enter code \(code) in the app. It works for 7 days. Joining is free."
    }
}

struct FamilyInvitePreview: Hashable, Decodable, Sendable {
    let familyId: UUID
    let name: String
    let ownerLabel: String
    let memberCount: Int
    let alreadyMember: Bool

    enum CodingKeys: String, CodingKey {
        case name
        case familyId = "family_id"
        case ownerLabel = "owner_label"
        case memberCount = "member_count"
        case alreadyMember = "already_member"
    }
}

/// `https://www.samanpantry.com/join/<token>` universal links (apex redirects to www, and AASA cannot redirect), plus the 8-character code.
enum FamilyInviteLink {
    static let host = "samanpantry.com"

    static func url(token: String) -> URL {
        URL(string: "https://www.\(host)/join/\(token)")!
    }

    /// Returns the token or code from a join link, or nil for any other URL.
    static func joinValue(from url: URL) -> String? {
        guard let scheme = url.scheme?.lowercased(), scheme == "https",
              let host = url.host?.lowercased(),
              host == Self.host || host == "www.\(Self.host)" else { return nil }
        let parts = url.pathComponents.filter { $0 != "/" }
        guard parts.count == 2, parts[0] == "join" else { return nil }
        let value = parts[1]
        guard (8...64).contains(value.count),
              value.allSatisfy({ $0.isLetter || $0.isNumber }) else { return nil }
        return value
    }

    static func normalizedCode(_ raw: String) -> String {
        raw.uppercased().filter { $0.isLetter || $0.isNumber }
    }
}

enum FamilyError: LocalizedError, Equatable {
    case signInRequired
    case proRequired
    case proSyncing
    case familyLimit
    case inviteInvalid
    case familyFull
    case membershipLimit
    case rateLimited
    case ownerMustTransfer
    case recipeNotSynced
    case failed

    var errorDescription: String? {
        switch self {
        case .signInRequired: return "Sign in to use family cookbooks."
        case .proRequired: return "Starting a family cookbook needs Samaan Pro."
        case .proSyncing: return "Your Samaan Pro is still syncing. Try again in a minute."
        case .familyLimit: return "You can start up to 5 families."
        case .inviteInvalid: return "That code didn't work. It may have expired. Ask for a new one."
        case .familyFull: return "This family has 50 members, the most a family can have."
        case .membershipLimit: return "You're in 20 families, the most you can join."
        case .rateLimited: return "Too many tries. Wait an hour and try again."
        case .ownerMustTransfer: return "Hand the family to another member first, or delete it."
        case .recipeNotSynced: return "This recipe hasn't synced yet. Check your connection and try again."
        case .failed: return "Something went wrong. Check your connection and try again."
        }
    }

    /// Maps the `hint` the SQL functions raise.
    static func from(_ error: Error, isProOnDevice: Bool = false) -> FamilyError {
        if let e = error as? FamilyError { return e }
        let text = String(describing: error)
        if text.contains("pro_required") { return isProOnDevice ? .proSyncing : .proRequired }
        if text.contains("family_limit") { return .familyLimit }
        if text.contains("family_full") { return .familyFull }
        if text.contains("membership_limit") { return .membershipLimit }
        if text.contains("rate_limited") { return .rateLimited }
        if text.contains("owner_must_transfer") { return .ownerMustTransfer }
        if text.contains("Recipe not found") { return .recipeNotSynced }
        return .failed
    }
}

final class FamilyService {
    static let shared = FamilyService()
    private init() {}

    private var client: SupabaseClient { .shared }

    @discardableResult
    func requireSignedIn() async throws -> UUID {
        do { return try await client.auth.session.user.id } catch { throw FamilyError.signInRequired }
    }

    /// Pro or grandfathered, as the server sees it.
    func serverCanCreateFamily() async -> Bool {
        struct Row: Decodable { let is_pro: Bool?; let grandfathered: Bool? }
        guard let uid = try? await requireSignedIn(),
              let rows: [Row] = try? await client.from("user_accounts")
                .select("is_pro, grandfathered").eq("id", value: uid).execute().value,
              let row = rows.first else { return false }
        return (row.is_pro ?? false) || (row.grandfathered ?? false)
    }

    func myFamilies() async throws -> [Family] {
        try await requireSignedIn()
        do {
            return try await client.from("families").select()
                .order("created_at", ascending: true).execute().value
        } catch { throw FamilyError.failed }
    }

    func createFamily(name: String, isProOnDevice: Bool) async throws -> Family {
        try await requireSignedIn()
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        do {
            return try await client.rpc("create_family", params: ["p_name": trimmed]).execute().value
        } catch { throw FamilyError.from(error, isProOnDevice: isProOnDevice) }
    }

    func rename(familyID: UUID, to name: String) async throws {
        do {
            try await client.from("families").update(["name": name]).eq("id", value: familyID).execute()
        } catch { throw FamilyError.failed }
    }

    func members(familyID: UUID) async throws -> [FamilyMember] {
        do {
            return try await client.from("family_members").select()
                .eq("family_id", value: familyID).order("joined_at", ascending: true).execute().value
        } catch { throw FamilyError.failed }
    }

    func recipes(familyID: UUID) async throws -> [FamilyRecipe] {
        do {
            return try await client.from("family_recipes").select()
                .eq("family_id", value: familyID).order("added_at", ascending: false).execute().value
        } catch { throw FamilyError.failed }
    }

    /// Families that already hold this recipe.
    func familyIDs(containing recipeID: UUID) async throws -> Set<UUID> {
        struct Row: Decodable { let family_id: UUID }
        let rows: [Row] = (try? await client.from("family_recipes").select("family_id")
            .eq("recipe_id", value: recipeID).execute().value) ?? []
        return Set(rows.map(\.family_id))
    }

    func add(recipeID: UUID, to familyID: UUID) async throws {
        do {
            try await client.rpc("add_recipe_to_family",
                                 params: ["p_family_id": familyID, "p_recipe_id": recipeID]).execute()
        } catch { throw FamilyError.from(error) }
    }

    func remove(recipeID: UUID, from familyID: UUID) async throws {
        do {
            try await client.from("family_recipes").delete()
                .eq("family_id", value: familyID).eq("recipe_id", value: recipeID).execute()
        } catch { throw FamilyError.failed }
    }

    func createInvite(familyID: UUID) async throws -> FamilyInvite {
        do {
            return try await client.rpc("create_family_invite", params: ["p_family_id": familyID]).execute().value
        } catch { throw FamilyError.from(error) }
    }

    func preview(codeOrToken: String) async throws -> FamilyInvitePreview {
        try await requireSignedIn()
        do {
            let preview: FamilyInvitePreview? = try await client
                .rpc("preview_family_invite", params: ["p_code_or_token": codeOrToken]).execute().value
            guard let preview else { throw FamilyError.inviteInvalid }
            return preview
        } catch { throw FamilyError.from(error) }
    }

    func join(codeOrToken: String) async throws -> UUID {
        try await requireSignedIn()
        do {
            let id: UUID? = try await client
                .rpc("redeem_family_invite", params: ["p_code_or_token": codeOrToken]).execute().value
            guard let id else { throw FamilyError.inviteInvalid }
            return id
        } catch { throw FamilyError.from(error) }
    }

    func removeMember(familyID: UUID, userID: UUID) async throws {
        do {
            try await client.rpc("remove_family_member",
                                 params: ["p_family_id": familyID, "p_user_id": userID]).execute()
        } catch { throw FamilyError.from(error) }
    }

    func leave(familyID: UUID) async throws {
        let uid = try await requireSignedIn()
        try await removeMember(familyID: familyID, userID: uid)
    }

    func transferOwnership(familyID: UUID, to userID: UUID) async throws {
        do {
            try await client.rpc("transfer_family_ownership",
                                 params: ["p_family_id": familyID, "p_new_owner": userID]).execute()
        } catch { throw FamilyError.from(error) }
    }

    func deleteFamily(familyID: UUID) async throws {
        do {
            try await client.rpc("delete_family", params: ["p_family_id": familyID]).execute()
        } catch { throw FamilyError.from(error) }
    }

    func notes(familyID: UUID, recipeID: UUID) async throws -> [FamilyRecipeNote] {
        do {
            return try await client.from("family_recipe_notes").select("id, author_id, body, created_at")
                .eq("family_id", value: familyID).eq("recipe_id", value: recipeID)
                .order("created_at", ascending: true).execute().value
        } catch { throw FamilyError.failed }
    }

    func addNote(familyID: UUID, recipeID: UUID, body: String) async throws -> FamilyRecipeNote {
        let uid = try await requireSignedIn()
        let trimmed = body.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw FamilyError.failed }
        struct Insert: Encodable { let family_id: UUID; let recipe_id: UUID; let author_id: UUID; let body: String }
        do {
            let rows: [FamilyRecipeNote] = try await client.from("family_recipe_notes")
                .insert(Insert(family_id: familyID, recipe_id: recipeID, author_id: uid, body: trimmed))
                .select("id, author_id, body, created_at").execute().value
            guard let note = rows.first else { throw FamilyError.failed }
            return note
        } catch { throw FamilyError.failed }
    }
}

extension FamilyRecipe {
    /// extracted_json for "Save a copy", in the shape RecipeDetailView already reads.
    /// Amounts stay as the cook said them, so every ingredient is marked vague.
    var copyExtractedJSON: String {
        let recipe = ExtractedRecipe(
            title: title,
            attribution: attribution,
            ingredients: ingredientPhrases.map {
                ExtractedIngredient(ingredient: $0, originalPhrase: $0, amount: nil, unit: nil, vague: true)
            },
            steps: steps,
            notes: nil
        )
        let data = (try? JSONEncoder().encode(recipe)) ?? Data("{}".utf8)
        return String(decoding: data, as: UTF8.self)
    }
}
