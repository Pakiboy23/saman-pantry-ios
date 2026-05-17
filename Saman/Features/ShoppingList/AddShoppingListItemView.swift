import SwiftUI
import SwiftData

struct AddShoppingListItemView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Environment(\.appEnv) private var appEnv

    let list: ShoppingList

    @Query(sort: \Product.name) private var products: [Product]

    @State private var searchText = ""
    @State private var selectedProduct: Product?
    @State private var quantity = 1
    @State private var unit = "unit"
    @State private var estimatedPrice = ""

    private let units = ["unit", "g", "kg", "ml", "L", "oz", "lb", "pack", "can", "bottle", "box"]

    private var filteredProducts: [Product] {
        searchText.isEmpty ? products : products.filter { $0.name.localizedCaseInsensitiveContains(searchText) }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Product") {
                    if let product = selectedProduct {
                        HStack {
                            Text(product.name)
                            Spacer()
                            Button("Change") { selectedProduct = nil }
                                .font(.caption)
                                .foregroundStyle(Color.brandSaag)
                        }
                    } else {
                        TextField("Search products…", text: $searchText)
                        ForEach(filteredProducts.prefix(5)) { product in
                            Button(product.name) { selectedProduct = product; searchText = "" }
                                .foregroundStyle(Color.inkKohl)
                        }
                        if !searchText.isEmpty && filteredProducts.isEmpty {
                            Button("Create \"\(searchText)\"") { createAndSelect() }
                                .foregroundStyle(Color.brandSaag)
                        }
                    }
                }

                Section("Quantity") {
                    Picker("Unit", selection: $unit) {
                        ForEach(units, id: \.self) { Text($0) }
                    }
                    Stepper("Quantity: \(quantity) \(unit)", value: $quantity, in: 1...999)
                }

                Section("Price (optional)") {
                    TextField("Estimated price", text: $estimatedPrice)
                        .keyboardType(.decimalPad)
                }
            }
            .navigationTitle("Add Item")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") { save() }.disabled(selectedProduct == nil)
                }
            }
        }
    }

    private func createAndSelect() {
        let product = Product(name: searchText.trimmingCharacters(in: .whitespaces))
        context.insert(product)
        selectedProduct = product
        searchText = ""
    }

    private func save() {
        guard let product = selectedProduct else { return }
        let price = Double(estimatedPrice.replacingOccurrences(of: ",", with: "."))
        let item = ShoppingListItem(
            quantity: quantity,
            unit: unit,
            estimatedPrice: price,
            product: product,
            shoppingList: list
        )
        context.insert(item)
        try? context.save()
        appEnv.syncNow()
        dismiss()
    }
}
