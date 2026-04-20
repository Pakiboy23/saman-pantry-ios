import SwiftUI
import SwiftData

struct AddItemView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Environment(\.appEnv) private var appEnv

    @Query(sort: \Pantry.name) private var pantries: [Pantry]

    var defaultPantry: Pantry? = nil
    var prefillBarcode: String? = nil
    var prefillName: String? = nil

    @State private var name = ""
    @State private var quantity = 1
    @State private var unit = "unit"
    @State private var minimumQuantity = 1
    @State private var selectedPantry: Pantry?

    private let units = ["unit", "g", "kg", "ml", "L", "oz", "lb", "pack", "can", "bottle", "box"]

    var body: some View {
        NavigationStack {
            Form {
                Section("Details") {
                    TextField("Name", text: $name)
                    Picker("Unit", selection: $unit) {
                        ForEach(units, id: \.self) { Text($0) }
                    }
                }
                Section("Quantity") {
                    Stepper("Current: \(quantity) \(unit)", value: $quantity, in: 0...9999)
                    Stepper("Minimum: \(minimumQuantity) \(unit)", value: $minimumQuantity, in: 0...9999)
                }
                if !pantries.isEmpty {
                    Section("Pantry") {
                        Picker("Pantry", selection: $selectedPantry) {
                            Text("None").tag(Optional<Pantry>.none)
                            ForEach(pantries) { p in Text(p.name).tag(Optional(p)) }
                        }
                    }
                }
            }
            .navigationTitle("New Item")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") { save() }
                        .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .onAppear {
                selectedPantry = defaultPantry
                if let prefillName { name = prefillName }
            }
        }
    }

    private func save() {
        let item = Item(
            name: name.trimmingCharacters(in: .whitespaces),
            quantity: quantity,
            unit: unit,
            minimumQuantity: minimumQuantity,
            barcode: prefillBarcode,
            pantry: selectedPantry
        )
        context.insert(item)
        try? context.save()
        appEnv.syncNow()
        dismiss()
    }
}

#Preview { AddItemView().modelContainer(.preview) }
