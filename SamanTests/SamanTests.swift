import Foundation
import SwiftData
import Testing
@testable import Saman

// Main-actor isolated: previewModelContainerCanCreateAllPrimaryModels touches
// ModelContainer.mainContext, which is @MainActor.
@MainActor
struct SamanTests {

    @Test func configDoesNotExposePrivateAnthropicKey() {
        #expect(!Config.recipeExtractionEndpoint.isEmpty)
        #expect(Config.recipeExtractionEndpoint.hasPrefix(Config.supabaseURL))
        #expect(!Config.recipeExtractionEndpoint.contains("sk-" + "ant-api"))
        #expect(!Config.recipeExtractionEndpoint.lowercased().contains("anthropic"))
    }

    @Test func previewModelContainerCanCreateAllPrimaryModels() throws {
        let context = ModelContainer.preview.mainContext
        let pantry = Pantry(name: "Test Pantry")
        let item = Item(name: "Rice", quantity: 2, unit: "bag", minimumQuantity: 1, pantry: pantry)
        let product = Product(name: "Basmati Rice", barcode: "123456789012")
        let store = Store(name: "Test Store")
        let shoppingList = ShoppingList(name: "Weekly", store: store)
        let shoppingListItem = ShoppingListItem(quantity: 1, unit: "bag", product: product, shoppingList: shoppingList)
        let recipe = Recipe(title: "Test Recipe", rawTranscript: "Boil rice", extractedJSON: "{}")

        context.insert(pantry)
        context.insert(item)
        context.insert(product)
        context.insert(store)
        context.insert(shoppingList)
        context.insert(shoppingListItem)
        context.insert(recipe)

        try context.save()

        let items = try context.fetch(FetchDescriptor<Item>())
        #expect(items.contains { $0.name == "Rice" })
        #expect(item.isLow == false)
        #expect(recipe.updatedAt.timeIntervalSince1970 > 0)
    }
}

struct SyncReconcileTests {
    @Test func dirtyLocalWinsOverNewerServer() {
        let local = Date(timeIntervalSince1970: 1)
        let server = Date(timeIntervalSince1970: 100)
        #expect(SyncReconcile.shouldApplyServer(localUpdatedAt: local, localDirty: true, serverUpdatedAt: server) == false)
    }

    @Test func cleanLocalYieldsToNewerOrEqualServer() {
        let local = Date(timeIntervalSince1970: 50)
        let newer = Date(timeIntervalSince1970: 100)
        let equal = Date(timeIntervalSince1970: 50)
        let older = Date(timeIntervalSince1970: 1)
        #expect(SyncReconcile.shouldApplyServer(localUpdatedAt: local, localDirty: false, serverUpdatedAt: newer) == true)
        #expect(SyncReconcile.shouldApplyServer(localUpdatedAt: local, localDirty: false, serverUpdatedAt: equal) == true)
        #expect(SyncReconcile.shouldApplyServer(localUpdatedAt: local, localDirty: false, serverUpdatedAt: older) == false)
    }

    @Test func missingServerRowDeletesOnlyCleanLocal() {
        #expect(SyncReconcile.shouldDeleteLocal(localDirty: false, presentOnServer: false) == true)
        #expect(SyncReconcile.shouldDeleteLocal(localDirty: true, presentOnServer: false) == false)
        #expect(SyncReconcile.shouldDeleteLocal(localDirty: false, presentOnServer: true) == false)
    }
}

struct AuthCopyTests {
    private struct DummyError: LocalizedError {
        let message: String
        var errorDescription: String? { message }
    }

    @Test func friendlyMapsProviderErrors() {
        #expect(AuthService.friendly(DummyError(message: "Invalid login credentials")) == "Email or password is wrong.")
        #expect(AuthService.friendly(DummyError(message: "User already registered")) == "That email already has an account. Try signing in.")
        #expect(AuthService.friendly(DummyError(message: "Rate limit exceeded")) == "Too many attempts. Wait a minute and try again.")
        #expect(AuthService.friendly(DummyError(message: "The Internet connection appears to be offline.")) == "Couldn't reach the server. Check your connection.")
        #expect(AuthService.friendly(DummyError(message: "Password should be at least 6 characters")) == "Use a password with at least 6 characters.")
        #expect(AuthService.friendly(DummyError(message: "unexpected blob")) == "Something went wrong. Please try again.")
    }
}
