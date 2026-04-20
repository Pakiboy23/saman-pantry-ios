import SwiftUI
import SwiftData

struct ShoppingListDetailView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.appEnv) private var appEnv
    @Bindable var list: ShoppingList
    @State private var showAddItem = false

    private var pending: [ShoppingListItem] { list.items.filter { !$0.isPurchased }.sorted { ($0.product?.name ?? "") < ($1.product?.name ?? "") } }
    private var purchased: [ShoppingListItem] { list.items.filter { $0.isPurchased }.sorted { ($0.product?.name ?? "") < ($1.product?.name ?? "") } }

    var body: some View {
        List {
            if !pending.isEmpty {
                Section("To Buy (\(pending.count))") {
                    ForEach(pending) { item in ShoppingItemRow(item: item, onToggle: { toggle(item) }) }
                        .onDelete { delete(from: pending, at: $0) }
                }
            }
            if !purchased.isEmpty {
                Section("In Cart (\(purchased.count))") {
                    ForEach(purchased) { item in ShoppingItemRow(item: item, onToggle: { toggle(item) }) }
                        .onDelete { delete(from: purchased, at: $0) }
                }
            }
        }
        .navigationTitle(list.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("Add Item", systemImage: "plus") { showAddItem = true }
            }
            ToolbarItem(placement: .secondaryAction) {
                Button(list.isCompleted ? "Reopen" : "Mark Complete") {
                    list.isCompleted.toggle()
                    list.markDirty()
                    try? context.save()
                    appEnv.syncNow()
                }
            }
        }
        .sheet(isPresented: $showAddItem) { AddShoppingListItemView(list: list) }
        .overlay {
            if list.items.isEmpty {
                ContentUnavailableView("Empty List", systemImage: "cart",
                    description: Text("Tap + to add items."))
            }
        }
    }

    private func toggle(_ item: ShoppingListItem) {
        item.isPurchased.toggle()
        item.markDirty()
        // Auto-complete list when all items are purchased
        if list.items.allSatisfy(\.isPurchased) { list.isCompleted = true; list.markDirty() }
        try? context.save()
        appEnv.syncNow()
    }

    private func delete(from items: [ShoppingListItem], at offsets: IndexSet) {
        for i in offsets { context.delete(items[i]) }
        try? context.save()
        appEnv.syncNow()
    }
}

// MARK: - Row

private struct ShoppingItemRow: View {
    let item: ShoppingListItem
    let onToggle: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Button(action: onToggle) {
                Image(systemName: item.isPurchased ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(item.isPurchased ? .green : .secondary)
                    .font(.title3)
            }
            .buttonStyle(.plain)

            VStack(alignment: .leading, spacing: 2) {
                Text(item.product?.name ?? "Unknown")
                    .strikethrough(item.isPurchased)
                    .foregroundStyle(item.isPurchased ? .secondary : .primary)
                HStack {
                    Text("\(item.quantity) \(item.unit)").font(.caption)
                    if let price = item.estimatedPrice {
                        Text("·").font(.caption)
                        Text(price, format: .currency(code: Locale.current.currency?.identifier ?? "USD"))
                            .font(.caption)
                    }
                }
                .foregroundStyle(.secondary)
            }
        }
    }
}
