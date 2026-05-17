import SwiftUI
import SwiftData

struct ReorderView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.appEnv) private var appEnv
    @Query(sort: \Item.name) private var allItems: [Item]
    @State private var restockingItem: Item?

    private var lowItems: [Item] { allItems.filter(\.isLow) }

    var body: some View {
        NavigationStack {
            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 12) {
                    if lowItems.isEmpty {
                        SamanEmptyState(
                            emoji: "✅",
                            title: "All stocked up",
                            message: "Nothing needs reordering right now. Come back when something runs low."
                        )
                    } else {
                        summaryCard
                            .padding(.horizontal, Saman.Space.md)
                            .padding(.top, 8)

                        SamanSectionHeader(title: "To reorder", color: .accentAnaar)
                        ForEach(lowItems) { item in
                            ReorderItemRow(item: item) {
                                restockingItem = item
                            }
                            .padding(.horizontal, Saman.Space.md)
                            .padding(.top, 6)
                        }

                        Spacer(minLength: 32)
                    }
                }
                .padding(.bottom, 24)
            }
            .background(Color.surfaceDoodh)
            .scrollContentBackground(.hidden)
            .safeAreaInset(edge: .top, spacing: 0) {
                VStack(spacing: 0) {
                    SamanHeader(subtitle: "\(lowItems.count) item\(lowItems.count == 1 ? "" : "s") to restock")
                    Rectangle().frame(height: 1).foregroundStyle(Color.borderAkhrotSoft.opacity(0.5))
                }
                .background(Color.surfaceDoodh)
            }
            .toolbar(.hidden, for: .navigationBar)
            .sheet(item: $restockingItem) { item in
                RestockSheet(item: item) { amount in
                    commit(item: item, amount: amount)
                }
            }
        }
    }

    // MARK: - Summary card

    private var summaryCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "exclamationmark.circle.fill")
                    .foregroundStyle(Color.accentAnaar)
                Text("\(lowItems.count) item\(lowItems.count == 1 ? "" : "s") need restocking.")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Color.inkKohl)
            }
            Text("Tap an item to record how much you added.")
                .font(.system(size: 13))
                .foregroundStyle(Color.inkKohlSoft)
        }
        .padding(14)
        .background(Color.accentAnaar.opacity(0.06))
        .overlay(RoundedRectangle(cornerRadius: Saman.Radius.md).stroke(Color.accentAnaar.opacity(0.3), lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: Saman.Radius.md))
    }

    // MARK: - Writeback

    private func commit(item: Item, amount: Int) {
        item.quantity += amount
        item.markDirty()
        try? context.save()
        appEnv.syncNow()
    }
}

// MARK: - Restock sheet

private struct RestockSheet: View {
    @Environment(\.dismiss) private var dismiss
    let item: Item
    let onConfirm: (Int) -> Void

    @State private var amount: Int

    init(item: Item, onConfirm: @escaping (Int) -> Void) {
        self.item = item
        self.onConfirm = onConfirm
        _amount = State(initialValue: max(item.minimumQuantity - item.quantity + 1, 1))
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Item header
                VStack(spacing: 6) {
                    Text(item.emoji)
                        .font(.system(size: 44))
                    Text(item.name)
                        .font(.pantrySectionHead)
                        .foregroundStyle(Color.inkKohl)
                    Text("Have \(item.quantity) · Need at least \(item.minimumQuantity)")
                        .font(.system(size: 13))
                        .foregroundStyle(Color.inkKohlSoft)
                }
                .frame(maxWidth: .infinity)
                .padding(.top, 32)
                .padding(.bottom, 28)

                Divider().overlay(Color.borderAkhrotSoft.opacity(0.5))

                // Stepper card
                VStack(alignment: .leading, spacing: 16) {
                    Text("HOW MANY DID YOU ADD?")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Color.inkKohlSoft)
                        .kerning(0.8)

                    Stepper(
                        value: $amount,
                        in: 1...999,
                        label: {
                            Text("\(amount) \(item.unit)")
                                .font(.samanMono(28).weight(.semibold))
                                .foregroundStyle(Color.brandSaag)
                        }
                    )

                    Text("New total: \(item.quantity + amount) \(item.unit)")
                        .font(.system(size: 13))
                        .foregroundStyle(Color.inkKohl)
                }
                .padding(Saman.Space.md)
                .samanCard()
                .padding(.horizontal, Saman.Space.md)
                .padding(.top, 24)

                Spacer()

                Button("Confirm restock") {
                    onConfirm(amount)
                    dismiss()
                }
                .buttonStyle(SamanPrimaryButtonStyle())
                .padding(.horizontal, Saman.Space.md)
                .padding(.bottom, 32)
            }
            .background(Color.surfaceDoodh)
            .navigationTitle("Restock")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .foregroundStyle(Color.brandSaag)
                }
            }
        }
    }
}

#Preview { ReorderView().modelContainer(.preview) }
