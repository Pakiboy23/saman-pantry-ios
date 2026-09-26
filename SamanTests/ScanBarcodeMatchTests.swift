import Foundation
import SwiftData
import Testing
@testable import Saman

@MainActor
struct ScanBarcodeMatchTests {
    private func makeContainer() throws -> ModelContainer {
        let schema = Schema([
            Item.self,
            Pantry.self,
            Product.self,
            Store.self,
            ShoppingList.self,
            ShoppingListItem.self,
            Recipe.self,
        ])
        return try ModelContainer(
            for: schema,
            configurations: ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        )
    }

    private func saved(
        items: [Item] = [],
        products: [Product] = []
    ) throws -> (container: ModelContainer, items: [Item], products: [Product]) {
        let container = try makeContainer()
        let context = container.mainContext
        for product in products { context.insert(product) }
        for item in items { context.insert(item) }
        try context.save()
        return (
            container,
            try context.fetch(FetchDescriptor<Item>()),
            try context.fetch(FetchDescriptor<Product>())
        )
    }

    @Test func itemBarcodeResolvesLocalNameWithoutAProduct() throws {
        let item = Item(name: "Shan Biryani Masala", barcode: "8964000123456")
        let stored = try saved(items: [item])

        let name = localName(
            forScannedBarcode: "8964000123456",
            items: stored.items,
            products: stored.products
        )
        #expect(name == "Shan Biryani Masala")
    }

    @Test func itemNameWinsOverProductWithTheSameBarcode() throws {
        let item = Item(name: "Haldi", barcode: "111")
        let product = Product(name: "Turmeric Powder", barcode: "111")
        let stored = try saved(items: [item], products: [product])

        let name = localName(forScannedBarcode: "111", items: stored.items, products: stored.products)
        #expect(name == "Haldi")
    }

    @Test func newerItemNameWinsWhenBarcodesRepeat() throws {
        let older = Item(name: "Old Masala", barcode: "555")
        older.updatedAt = Date(timeIntervalSince1970: 10)
        let newer = Item(name: "Shan Masala", barcode: "555")
        newer.updatedAt = Date(timeIntervalSince1970: 20)
        let stored = try saved(items: [older, newer])

        let name = localName(forScannedBarcode: "555", items: stored.items, products: stored.products)
        #expect(name == "Shan Masala")
    }

    @Test func blankItemNameFallsThroughToProduct() throws {
        let item = Item(name: "   ", barcode: "555")
        let product = Product(name: "Shan", barcode: "555")
        let stored = try saved(items: [item], products: [product])

        let name = localName(forScannedBarcode: "555", items: stored.items, products: stored.products)
        #expect(name == "Shan")
    }

    @Test func productBarcodeStillResolvesWhenNoItemHasIt() throws {
        let product = Product(name: "Basmati Rice", barcode: "123456789012")
        let stored = try saved(products: [product])

        let name = localName(forScannedBarcode: "123456789012", items: stored.items, products: stored.products)
        #expect(name == "Basmati Rice")
    }

    @Test func unknownOrEmptyBarcodeHasNoLocalName() throws {
        let item = Item(name: "Atta", barcode: "111")
        let stored = try saved(items: [item])

        #expect(localName(forScannedBarcode: "999", items: stored.items, products: stored.products) == nil)
        #expect(localName(forScannedBarcode: "", items: stored.items, products: stored.products) == nil)
    }

    @Test func desiNameTableStillMapsStaples() {
        #expect(Item(name: "Atta").emoji == "🌾")
        #expect(Item(name: "Aata").emoji == "🌾")
        #expect(Item(name: "Daal").emoji == "🫘")
        #expect(Item(name: "Ghee").emoji == "🧈")
        #expect(Item(name: "Haldi").emoji == "🟡")
        #expect(Item(name: "Jeera").emoji == "🌿")
        #expect(Item(name: "Dhaniya").emoji == "🌿")
        #expect(Item(name: "Mirch").emoji == "🌶️")
        #expect(Item(name: "Chai").emoji == "🍵")
        #expect(Item(name: "Masala").emoji == "🌶️")
        #expect(Item(name: "Paneer").emoji == "🧀")
        #expect(Item(name: "Adrak").emoji == "🫚")
    }

    @Test func productCategoryDoesNotPickEmoji() {
        let dairy = Product(name: "Widget", category: "dairy")
        let widget = Item(name: "Widget", product: dairy)
        #expect(widget.emoji == "🛒")

        let cleaning = Product(name: "Atta", category: "cleaning")
        let atta = Item(name: "Atta", product: cleaning)
        #expect(atta.emoji == "🌾")

        #expect(Item(name: "Milk").emoji == "🥛")
    }

    @Test func lookupKeepsBrandAndDropsCategoryParse() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Saman")
        let lookup = try String(
            contentsOf: root.appendingPathComponent("Features/Scanner/ProductLookupService.swift"),
            encoding: .utf8
        )
        let scanner = try String(
            contentsOf: root.appendingPathComponent("Features/Scanner/ScannerView.swift"),
            encoding: .utf8
        )
        let emoji = try String(
            contentsOf: root.appendingPathComponent("Core/Design/Item+Emoji.swift"),
            encoding: .utf8
        )

        #expect(lookup.contains("let brand"))
        #expect(lookup.contains("case brands"))
        #expect(!lookup.contains("categories_tags"))
        #expect(!lookup.contains("categoriesTags"))
        #expect(!lookup.contains("category"))
        #expect(scanner.contains("foundProduct?.brand"))
        #expect(scanner.contains("localName(forScannedBarcode:"))
        #expect(!emoji.contains("product?.category"))
        #expect(!emoji.contains("Category fallback"))
        #expect(emoji.contains("(\"atta\", \"🌾\")"))
        #expect(emoji.contains("(\"haldi\", \"🟡\")"))
        #expect(emoji.contains("(\"adrak\", \"🫚\")"))
    }
}
