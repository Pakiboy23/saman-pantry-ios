import SwiftData

extension ModelContainer {
    /// Shared container with all app schemas.
    static let shared: ModelContainer = {
        let schema = Schema([
            Item.self,
            Pantry.self,
            Product.self,
            Store.self,
            ShoppingList.self,
            ShoppingListItem.self,
            Recipe.self,
        ])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)
        do {
            return try ModelContainer(for: schema, configurations: config)
        } catch {
            fatalError("Failed to create ModelContainer: \(error)")
        }
    }()

    /// In-memory container for SwiftUI previews and unit tests.
    static let preview: ModelContainer = {
        let schema = Schema([
            Item.self,
            Pantry.self,
            Product.self,
            Store.self,
            ShoppingList.self,
            ShoppingListItem.self,
            Recipe.self,
        ])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        do {
            return try ModelContainer(for: schema, configurations: config)
        } catch {
            fatalError("Failed to create preview ModelContainer: \(error)")
        }
    }()
}
