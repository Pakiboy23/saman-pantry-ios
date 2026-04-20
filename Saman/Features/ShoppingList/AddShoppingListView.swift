import SwiftUI
import SwiftData

struct AddShoppingListView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Environment(\.appEnv) private var appEnv
    @Query(sort: \Store.name) private var stores: [Store]

    @State private var name = ""
    @State private var selectedStore: Store?

    var body: some View {
        NavigationStack {
            Form {
                Section("Name") {
                    TextField("e.g. Weekly Shop", text: $name)
                }
                if !stores.isEmpty {
                    Section("Store") {
                        Picker("Store", selection: $selectedStore) {
                            Text("None").tag(Optional<Store>.none)
                            ForEach(stores) { s in Text(s.name).tag(Optional(s)) }
                        }
                    }
                }
            }
            .navigationTitle("New List")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Create") { save() }
                        .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
    }

    private func save() {
        let list = ShoppingList(name: name.trimmingCharacters(in: .whitespaces), store: selectedStore)
        context.insert(list)
        try? context.save()
        appEnv.syncNow()
        dismiss()
    }
}
