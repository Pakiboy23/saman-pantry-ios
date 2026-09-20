import Foundation
import SwiftData

/// Mark-bought restock: prefer the `Item.product` FK, then exact name.
/// Recipe extract maps phrases like *haldi* → grocery term *turmeric*; list-add
/// linking attaches the pantry Item so the FK exists before restock runs.
enum PantryRestock {
    static func apply(items: [Item], for listItem: ShoppingListItem, by delta: Int) {
        guard let pantryItem = matchingItem(in: items, for: listItem) else { return }
        pantryItem.quantity = max(0, pantryItem.quantity + delta)
        pantryItem.markDirty()
    }

    static func matchingItem(in items: [Item], for listItem: ShoppingListItem) -> Item? {
        if let productID = listItem.product?.id,
           let match = items.first(where: { $0.product?.id == productID }) {
            return match
        }
        guard let name = listItem.product?.name else { return nil }
        let key = PantryNameMatch.normalize(name)
        guard !key.isEmpty else { return nil }
        return items.first { PantryNameMatch.normalize($0.name) == key }
    }
}

/// Attach or reuse a pantry Item's Product when adding a shopping-list row.
enum PantryProductLink {
    static func product(
        groceryName: String,
        aliases: [String] = [],
        pantryItems: [Item],
        in context: ModelContext
    ) -> Product {
        let name = groceryName.trimmingCharacters(in: .whitespacesAndNewlines)
        if let pantryItem = matchingItem(groceryName: name, aliases: aliases, in: pantryItems) {
            if let existing = pantryItem.product {
                return existing
            }
            let created = Product(name: name.isEmpty ? pantryItem.name : name)
            context.insert(created)
            pantryItem.product = created
            pantryItem.markDirty()
            return created
        }
        let created = Product(name: name)
        context.insert(created)
        return created
    }

    static func matchingItem(groceryName: String, aliases: [String], in items: [Item]) -> Item? {
        let candidates = ([groceryName] + aliases)
            .map(PantryNameMatch.normalize)
            .filter { !$0.isEmpty }

        for candidate in candidates {
            if let item = items.first(where: { PantryNameMatch.normalize($0.name) == candidate }) {
                return item
            }
        }

        for item in items {
            let itemKey = PantryNameMatch.normalize(item.name)
            guard !itemKey.isEmpty else { continue }
            if candidates.contains(where: { PantryNameMatch.containsWordSequence($0, itemKey) }) {
                return item
            }
        }
        return nil
    }

    static func appendIngredients(
        _ ingredients: [ExtractedIngredient],
        to list: ShoppingList,
        in context: ModelContext
    ) {
        let pantryItems = (try? context.fetch(FetchDescriptor<Item>())) ?? []
        for ing in ingredients {
            let product = PantryProductLink.product(
                groceryName: ing.ingredient,
                aliases: [ing.originalPhrase],
                pantryItems: pantryItems,
                in: context
            )
            let qty = max(1, Int((ing.amount ?? 1.0).rounded(.up)))
            let unit = ing.unit ?? "unit"
            context.insert(ShoppingListItem(quantity: qty, unit: unit, product: product, shoppingList: list))
        }
    }
}

enum PantryNameMatch {
    static func normalize(_ raw: String) -> String {
        raw.lowercased()
            .map { character -> Character in
                character.isLetter || character.isNumber ? character : " "
            }
            .reduce(into: "") { partial, character in
                if character == " ", partial.last == " " { return }
                partial.append(character)
            }
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func containsWordSequence(_ haystack: String, _ needle: String) -> Bool {
        let hay = haystack.split(separator: " ")
        let need = needle.split(separator: " ")
        guard !need.isEmpty, hay.count >= need.count else { return false }
        let limit = hay.count - need.count
        for index in 0...limit {
            if hay[index..<(index + need.count)].elementsEqual(need) {
                return true
            }
        }
        return false
    }
}
