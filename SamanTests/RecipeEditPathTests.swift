import Foundation
import Testing
@testable import Saman

@MainActor
struct RecipeEditPathTests {
    @Test func editPathMarksRecipeDirtyAndBumpsUpdatedAt() throws {
        let repoRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let editSource = try String(
            contentsOf: repoRoot.appendingPathComponent("Saman/Features/Recipes/RecipeEditView.swift"),
            encoding: .utf8
        )
        let detailSource = try String(
            contentsOf: repoRoot.appendingPathComponent("Saman/Features/Recipes/RecipeDetailView.swift"),
            encoding: .utf8
        )

        let saveStart = try #require(editSource.range(of: "private func save()"))
        let saveBody = editSource[saveStart.lowerBound...]
        #expect(saveBody.contains("recipe.markDirty()"))
        #expect(saveBody.contains("appEnv.syncNow()"))
        #expect(!saveBody.contains("isDirty ="))

        #expect(detailSource.contains("Text(recipe.title)"))
        #expect(!detailSource.contains("$recipe.title"))
        #expect(!detailSource.contains("TextField(\"Recipe title\""))

        let recipe = Recipe(title: "Chicken Karahi", rawTranscript: "chicken, tamatar, haldi")
        recipe.isDirty = false
        let syncedAt = Date(timeIntervalSince1970: 1_700_000_000)
        recipe.updatedAt = syncedAt

        recipe.title = "Nihari"
        recipe.markDirty()

        #expect(recipe.title == "Nihari")
        #expect(recipe.isDirty)
        #expect(recipe.updatedAt > syncedAt)

        // After a push clears the flag, the edit's timestamp still beats the row we synced from.
        recipe.isDirty = false
        #expect(SyncReconcile.shouldApplyServer(
            localUpdatedAt: recipe.updatedAt,
            localDirty: recipe.isDirty,
            serverUpdatedAt: syncedAt
        ) == false)
    }
}
