import SwiftUI
import SwiftData

struct AddItemView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Environment(\.appEnv) private var appEnv

    @State private var name = ""
    @State private var quantity = 1
    @State private var unit = "unit"
    @State private var minimumQuantity = 1
    @State private var barcode: String?
    @State private var showScanner = false

    private let units = ["unit", "g", "kg", "ml", "L", "oz", "lb", "pack", "can", "bottle", "box"]

    var body: some View {
        NavigationStack {
            Form {
                Section("Details") {
                    TextField("Name", text: $name)
                    Picker("Unit", selection: $unit) {
                        ForEach(units, id: \.self) { Text($0) }
                    }
                    Button {
                        showScanner = true
                    } label: {
                        Label("Scan barcode", systemImage: "barcode.viewfinder")
                    }
                    .foregroundStyle(Color.brandSaag)
                    .accessibilityLabel("Scan barcode")
                    if let barcode, !barcode.isEmpty {
                        Text(barcode)
                            .font(.samaanMono(12))
                            .foregroundStyle(Color.inkKohlSoft)
                            .accessibilityLabel("Barcode \(barcode)")
                    }
                }
                Section("Quantity") {
                    Stepper("Current: \(quantity) \(unit)", value: $quantity, in: 0...9999)
                    Stepper("Minimum: \(minimumQuantity) \(unit)", value: $minimumQuantity, in: 0...9999)
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
            .sheet(isPresented: $showScanner) {
                ScannerView { scanned, scannedName in
                    applyScan(barcode: scanned, name: scannedName)
                }
            }
        }
    }

    private func applyScan(barcode scanned: String, name scannedName: String?) {
        barcode = scanned
        if let scannedName {
            let trimmed = scannedName.trimmingCharacters(in: .whitespaces)
            if !trimmed.isEmpty {
                name = trimmed
            }
        }
    }

    private func save() {
        let item = Item(
            name: name.trimmingCharacters(in: .whitespaces),
            quantity: quantity,
            unit: unit,
            minimumQuantity: minimumQuantity,
            barcode: barcode
        )
        context.insert(item)
        try? context.save()
        Analytics.track(.itemAdded)
        appEnv.syncNow()
        dismiss()
    }
}

#Preview { AddItemView().modelContainer(.preview) }
