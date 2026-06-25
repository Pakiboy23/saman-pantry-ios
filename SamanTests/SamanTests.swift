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
    }
}
