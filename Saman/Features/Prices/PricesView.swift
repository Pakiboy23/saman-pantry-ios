import SwiftUI
import SwiftData

struct PricesView: View {
    @Query(sort: \ShoppingListItem.updatedAt, order: .reverse) private var items: [ShoppingListItem]

    var body: some View {
        NavigationStack {
            List(items) { item in
                HStack {
                    Text(item.product?.name ?? "Unknown product")
                    Spacer()
                    if let price = item.estimatedPrice {
                        Text(price, format: .currency(code: Locale.current.currency?.identifier ?? "USD"))
                            .foregroundStyle(.secondary)
                    } else {
                        Text("—").foregroundStyle(.tertiary)
                    }
                }
            }
            .navigationTitle("Prices")
            .overlay {
                if items.isEmpty {
                    ContentUnavailableView(
                        "No Price Data",
                        systemImage: "tag",
                        description: Text("Add estimated prices to shopping list items.")
                    )
                }
            }
        }
    }
}

#Preview {
    PricesView()
        .modelContainer(.preview)
}
