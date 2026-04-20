import SwiftUI
import SwiftData

struct ItemDetailView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.appEnv) private var appEnv
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \Pantry.name) private var pantries: [Pantry]

    @Bindable var item: Item
    @State private var hasExpiry: Bool = false

    private let units = ["unit", "g", "kg", "ml", "L", "oz", "lb", "pack", "can", "bottle", "box"]

    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                // Hero emoji card
                VStack(spacing: 6) {
                    Text(item.emoji)
                        .font(.system(size: 52))
                    Text(item.name)
                        .font(.cormorant(26))
                        .foregroundStyle(Color.samanPrimary)
                    if let pantry = item.pantry {
                        Text(pantry.name)
                            .font(.system(size: 13))
                            .foregroundStyle(Color.samanMuted)
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 24)
                .samanCard(radius: Saman.Radius.lg)
                .padding(.horizontal, Saman.Space.md)
                .padding(.top, 8)

                // Quantity card
                detailCard {
                    VStack(alignment: .leading, spacing: 16) {
                        sectionLabel("QUANTITY")
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("How many do you have?")
                                    .font(.system(size: 14))
                                    .foregroundStyle(Color.samanSecondary)
                                Stepper(
                                    value: $item.quantity, in: 0...9999,
                                    label: {
                                        Text("\(item.quantity) \(item.unit)")
                                            .font(.samanMono(22).weight(.semibold))
                                            .foregroundStyle(item.isLow ? Color.samanRed : Color.samanGreen)
                                    }
                                )
                                .onChange(of: item.quantity) { _, _ in persist() }
                            }
                        }

                        Divider().overlay(Color.samanBorder)

                        VStack(alignment: .leading, spacing: 4) {
                            Text("Alert me when below")
                                .font(.system(size: 14))
                                .foregroundStyle(Color.samanSecondary)
                            Stepper(
                                value: $item.minimumQuantity, in: 0...9999,
                                label: {
                                    Text("\(item.minimumQuantity) \(item.unit)")
                                        .font(.samanMono(18))
                                        .foregroundStyle(Color.samanPrimary)
                                }
                            )
                            .onChange(of: item.minimumQuantity) { _, _ in persist() }
                        }

                        Divider().overlay(Color.samanBorder)

                        // Unit
                        HStack {
                            Text("Unit")
                                .font(.system(size: 14))
                                .foregroundStyle(Color.samanSecondary)
                            Spacer()
                            Picker("Unit", selection: $item.unit) {
                                ForEach(units, id: \.self) { Text($0) }
                            }
                            .pickerStyle(.menu)
                            .tint(Color.samanAccent)
                            .onChange(of: item.unit) { _, _ in persist() }
                        }
                    }
                }

                // Expiry card
                detailCard {
                    VStack(alignment: .leading, spacing: 12) {
                        sectionLabel("EXPIRY")
                        Toggle("Track expiry date", isOn: $hasExpiry)
                            .tint(Color.samanAccent)
                            .font(.system(size: 14))
                            .foregroundStyle(Color.samanPrimary)
                            .onChange(of: hasExpiry) { _, on in
                                item.expiryDate = on ? (item.expiryDate ?? Date()) : nil
                                persist()
                            }

                        if hasExpiry {
                            Divider().overlay(Color.samanBorder)
                            DatePicker(
                                "Expiry date",
                                selection: Binding(
                                    get: { item.expiryDate ?? Date() },
                                    set: { item.expiryDate = $0; persist() }
                                ),
                                displayedComponents: .date
                            )
                            .tint(Color.samanAccent)
                            .font(.system(size: 14))

                            if item.isExpired {
                                Label("This item has expired", systemImage: "exclamationmark.circle.fill")
                                    .font(.system(size: 13, weight: .medium))
                                    .foregroundStyle(Color.samanRed)
                            } else if item.isExpiringSoon {
                                Label("Expires within 7 days", systemImage: "clock.fill")
                                    .font(.system(size: 13, weight: .medium))
                                    .foregroundStyle(Color.samanAccent)
                            }
                        }
                    }
                }

                // Notes card
                detailCard {
                    VStack(alignment: .leading, spacing: 10) {
                        sectionLabel("NOTES")
                        TextField(
                            "Any notes about this item…",
                            text: Binding(
                                get: { item.notes ?? "" },
                                set: { item.notes = $0.isEmpty ? nil : $0; persist() }
                            ),
                            axis: .vertical
                        )
                        .font(.system(size: 14))
                        .foregroundStyle(Color.samanPrimary)
                        .lineLimit(3...8)
                    }
                }

                // Pantry picker card
                if !pantries.isEmpty {
                    detailCard {
                        VStack(alignment: .leading, spacing: 10) {
                            sectionLabel("PANTRY")
                            Picker("Pantry", selection: $item.pantry) {
                                Text("None").tag(Optional<Pantry>.none)
                                ForEach(pantries) { p in Text(p.name).tag(Optional(p)) }
                            }
                            .pickerStyle(.menu)
                            .tint(Color.samanAccent)
                            .onChange(of: item.pantry?.id) { _, _ in persist() }
                        }
                    }
                }

                // Metadata
                detailCard {
                    VStack(alignment: .leading, spacing: 8) {
                        sectionLabel("INFO")
                        metaRow("Last updated", value: item.updatedAt.formatted(date: .abbreviated, time: .shortened))
                        Divider().overlay(Color.samanBorder)
                        metaRow("Added", value: item.createdAt.formatted(date: .abbreviated, time: .omitted))
                        if let barcode = item.barcode {
                            Divider().overlay(Color.samanBorder)
                            metaRow("Barcode", value: barcode)
                        }
                    }
                }
            }
            .padding(.bottom, 32)
        }
        .background(Color.samanBg)
        .scrollContentBackground(.hidden)
        .toolbar(.hidden, for: .navigationBar)
        .safeAreaInset(edge: .top, spacing: 0) {
            VStack(spacing: 0) {
                HStack(spacing: 12) {
                    Button { dismiss() } label: {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundStyle(Color.samanAccent)
                    }
                    Text(item.name)
                        .font(.cormorant(22))
                        .foregroundStyle(Color.samanPrimary)
                        .lineLimit(1)
                    Spacer()
                }
                .padding(.horizontal, Saman.Space.md)
                .padding(.vertical, 12)
                Rectangle().frame(height: 1).foregroundStyle(Color.samanBorder)
            }
            .background(Color.samanBg)
        }
        .onAppear { hasExpiry = item.expiryDate != nil }
        .onChange(of: item.name) { _, _ in persist() }
    }

    // MARK: - Helpers

    @ViewBuilder
    private func detailCard<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 0) { content() }
            .padding(16)
            .samanCard()
            .padding(.horizontal, Saman.Space.md)
    }

    private func sectionLabel(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(Color.samanMuted)
            .kerning(0.8)
    }

    private func metaRow(_ label: String, value: String) -> some View {
        HStack {
            Text(label).font(.system(size: 13)).foregroundStyle(Color.samanMuted)
            Spacer()
            Text(value).font(.samanMono(12)).foregroundStyle(Color.samanSecondary)
        }
    }

    private func persist() {
        item.markDirty()
        try? context.save()
        appEnv.syncNow()
    }
}
