import SwiftUI
import SwiftData

struct AddPantryView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Environment(\.appEnv) private var appEnv
    @State private var name = ""

    var body: some View {
        NavigationStack {
            Form {
                Section("Name") {
                    TextField("e.g. Kitchen, Fridge, Pantry", text: $name)
                }
            }
            .navigationTitle("New Pantry")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") { save() }
                        .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
    }

    private func save() {
        let pantry = Pantry(name: name.trimmingCharacters(in: .whitespaces))
        context.insert(pantry)
        try? context.save()
        appEnv.syncNow()
        dismiss()
    }
}
