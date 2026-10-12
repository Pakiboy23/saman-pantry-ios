import Foundation
import Testing
@testable import Saman

@MainActor
struct RecipeBookTests {
    @Test func transcriptSourcePublishesAndUrlDoesNot() {
        #expect(RecipeSourceKind.transcript.publishesToFamilyBook)
        #expect(!RecipeSourceKind.url.publishesToFamilyBook)
    }

    @Test func transcriptRecipeKeepsAndazaPhraseInExtractedJSON() throws {
        let turmeric = ExtractedIngredient(
            ingredient: "turmeric",
            originalPhrase: "haldi andaza se",
            amount: nil,
            unit: nil,
            vague: true
        )
        let extracted = ExtractedRecipe(
            title: "Chicken Karahi",
            attribution: "Mom",
            ingredients: [turmeric],
            steps: ["Add chicken and haldi"],
            notes: nil
        )
        let data = try JSONEncoder().encode(extracted)
        let json = try #require(String(data: data, encoding: .utf8))
        let recipe = Recipe(
            title: "Chicken Karahi",
            rawTranscript: "Beta listen, put in haldi andaza se",
            extractedJSON: json,
            attribution: "Mom",
            sourceKind: .transcript
        )
        #expect(recipe.sourceKindValue == .transcript)
        #expect(recipe.sourceKindValue.publishesToFamilyBook)
        #expect(json.contains("haldi andaza se"))
        let decoded = try JSONDecoder().decode(ExtractedRecipe.self, from: Data(json.utf8))
        #expect(decoded.ingredients.first?.originalPhrase == "haldi andaza se")
    }

    @Test func urlRecipeDoesNotPublishToFamilyBook() {
        let recipe = Recipe(
            title: "YouTube Karahi",
            rawTranscript: "https://www.youtube.com/watch?v=example",
            extractedJSON: nil,
            attribution: "youtube.com",
            sourceKind: .url
        )
        #expect(recipe.sourceKindValue == .url)
        #expect(!recipe.sourceKindValue.publishesToFamilyBook)
        #expect(!recipe.isInFamilyBook)
        #expect(recipe.myBookStatusLabel == "link")
    }

    @Test func urlRecipeOptsIntoFamilyBookAndCanLeaveAgain() {
        let recipe = Recipe(
            title: "YouTube Karahi",
            rawTranscript: "https://www.youtube.com/watch?v=example",
            attribution: "youtube.com",
            sourceKind: .url
        )
        recipe.setFamilyBookSharing(true)
        #expect(recipe.shareInFamilyBook)
        #expect(recipe.isInFamilyBook)
        #expect(recipe.isDirty)
        #expect(recipe.myBookStatusLabel == "link · in the family book")

        recipe.setFamilyBookSharing(false)
        #expect(!recipe.shareInFamilyBook)
        #expect(!recipe.isInFamilyBook)
        #expect(recipe.myBookStatusLabel == "link")
    }

    @Test func transcriptStaysInTheFamilyBookWhenTheFlagIsCleared() {
        let recipe = Recipe(
            title: "Chicken Karahi",
            rawTranscript: "Beta listen, put in haldi andaza se",
            attribution: "Ammi",
            sourceKind: .transcript
        )
        recipe.shareInFamilyBook = false
        #expect(recipe.isInFamilyBook)
        #expect(recipe.myBookStatusLabel == "in the family book")
        recipe.setFamilyBookSharing(false)
        #expect(!recipe.shareInFamilyBook)
        #expect(recipe.isInFamilyBook)
    }

    @Test func failedFamilyBookUploadRestoresThePreviousFlag() {
        let recipe = Recipe(
            title: "YouTube Karahi",
            rawTranscript: "https://www.youtube.com/watch?v=example",
            attribution: "youtube.com",
            sourceKind: .url,
            shareInFamilyBook: true
        )
        recipe.isDirty = false
        let snapshot = FamilyBookShareSnapshot.capture(recipe)
        recipe.setFamilyBookSharing(false)
        let toggleUpdatedAt = recipe.updatedAt
        #expect(recipe.myBookStatusLabel == "link")
        #expect(FamilyBookShareCommit.uploadWasRejected(
            isDirty: recipe.isDirty,
            updatedAt: recipe.updatedAt,
            toggleUpdatedAt: toggleUpdatedAt
        ))
        snapshot.restore(to: recipe)
        #expect(recipe.shareInFamilyBook)
        #expect(!recipe.isDirty)
        #expect(recipe.updatedAt == snapshot.updatedAt)
        #expect(recipe.myBookStatusLabel == "link · in the family book")
    }

    @Test func acceptedFamilyBookUploadKeepsTheNewFlag() {
        let recipe = Recipe(
            title: "YouTube Karahi",
            rawTranscript: "https://www.youtube.com/watch?v=example",
            sourceKind: .url
        )
        recipe.setFamilyBookSharing(true)
        let toggleUpdatedAt = recipe.updatedAt
        recipe.isDirty = false
        #expect(!FamilyBookShareCommit.uploadWasRejected(
            isDirty: recipe.isDirty,
            updatedAt: recipe.updatedAt,
            toggleUpdatedAt: toggleUpdatedAt
        ))
        #expect(recipe.myBookStatusLabel == "link · in the family book")
    }

    @Test func canceledSignInDropsTheFamilyBookTapAndSuccessKeepsIt() {
        let recipeID = UUID()
        var intent = FamilyBookAuthIntent()
        intent.remember(recipeID)
        #expect(intent.resolve(signedIn: false) == nil)
        #expect(intent.recipeID == nil)

        intent.remember(recipeID)
        #expect(intent.resolve(signedIn: true) == recipeID)
        #expect(intent.recipeID == nil)
    }

    @Test func familyBookShareCopyIsSentenceCase() {
        for line in FamilyBookShareCopy.all {
            #expect(!line.contains("—"))
            #expect(line.first?.isUppercase == true)
        }
        #expect(FamilyBookShareCopy.addAction == "Add to family book")
        #expect(FamilyBookShareCopy.removeAction == "Remove from family book")
    }

    @Test func linkCardOpensOnlyHttpSource() {
        let link = FamilyRecipeBookCard(
            id: UUID(),
            ownerId: UUID(),
            title: "YouTube Karahi",
            attribution: "youtube.com",
            steps: ["Cook"],
            ingredientPhrases: ["haldi andaza se"],
            addedByLabel: "cousin.a",
            sourceUrl: "https://www.youtube.com/watch?v=example",
            createdAt: Date(),
            updatedAt: Date()
        )
        #expect(link.sourceLink?.scheme == "https")
        #expect(link.sourceLink?.host == "www.youtube.com")

        let spoken = FamilyRecipeBookCard(
            id: UUID(),
            ownerId: UUID(),
            title: "Karahi",
            attribution: "Ammi",
            steps: [],
            ingredientPhrases: [],
            addedByLabel: "cousin.a",
            sourceUrl: "Beta listen, private words",
            createdAt: Date(),
            updatedAt: Date()
        )
        #expect(spoken.sourceLink == nil)

        let script = FamilyRecipeBookCard(
            id: UUID(),
            ownerId: UUID(),
            title: "Karahi",
            attribution: nil,
            steps: [],
            ingredientPhrases: [],
            addedByLabel: "cousin.a",
            sourceUrl: "javascript:alert(1)",
            createdAt: Date(),
            updatedAt: Date()
        )
        #expect(script.sourceLink == nil)
    }

    @Test func publicCardKeysNeverIncludeRawTranscript() {
        #expect(!FamilyRecipeBookCard.publicFieldKeys.contains("raw_transcript"))
        #expect(FamilyRecipeBookCard.publicFieldKeys.contains("ingredient_phrases"))
        #expect(FamilyRecipeBookCard.publicFieldKeys.contains("added_by_label"))
        #expect(FamilyRecipeBookCard.publicFieldKeys.contains("source_url"))
    }

    @Test func captureSaveSetsSourceKindFromExtractPath() throws {
        let repoRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let capture = try String(
            contentsOf: repoRoot.appendingPathComponent("Saman/Features/Recipes/RecipeCaptureView.swift"),
            encoding: .utf8
        )
        #expect(capture.contains("capturedSourceKind = .url"))
        #expect(capture.contains("capturedSourceKind = .transcript"))
        #expect(capture.contains("sourceKind: capturedSourceKind"))
    }

    @Test func migrationKeepsOwnerRLSAndPublishesCardNotRawRow() throws {
        let repoRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let migration = try String(
            contentsOf: repoRoot.appendingPathComponent("supabase/migrations/008_recipe_book.sql"),
            encoding: .utf8
        )
        #expect(migration.contains("recipe_book_cards"))
        #expect(migration.contains("raw_transcript never appears on the card") || migration.contains("raw_transcript never"))
        #expect(migration.contains("source_kind"))
        #expect(migration.contains("recipe_book_notes"))
        #expect(migration.contains("for select to authenticated"))
        #expect(!migration.contains("drop policy if exists \"owner\" on recipes"))
    }

    @Test func urlOptInMigrationKeepsExistingCardsAndOwnerRLS() throws {
        let repoRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let migration = try String(
            contentsOf: repoRoot.appendingPathComponent("supabase/migrations/012_recipe_book_url_opt_in.sql"),
            encoding: .utf8
        )
        #expect(migration.contains("share_in_family_book boolean not null default false"))
        #expect(migration.contains("source_url"))
        #expect(migration.contains("add column if not exists"))
        #expect(migration.contains("new.source_kind = 'transcript'"))
        #expect(migration.contains("new.share_in_family_book"))
        #expect(migration.contains("jsonb_typeof(card_ingredients) <> 'array'"))
        #expect(migration.contains("auth.uid() = user_id"))
        #expect(migration.contains("raw_transcript"))
        #expect(migration.contains("^https?://"))
        let lowered = migration.lowercased()
        #expect(!lowered.contains("drop table"))
        #expect(!lowered.contains("delete from public.recipes"))
        #expect(!lowered.contains("truncate"))
    }
}
