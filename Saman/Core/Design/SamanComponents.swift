import SwiftUI

// MARK: - Wordmark Header

struct SamanHeader: View {
    var subtitle: String = "Your pantry, organised"
    var trailingAction: (() -> Void)? = nil
    var trailingIcon: String = "plus"

    var body: some View {
        HStack(alignment: .bottom) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Saman")
                    .font(.pantryDisplay)
                    .foregroundStyle(Color.inkKohl)
                Text(subtitle)
                    .font(.system(size: 13))
                    .foregroundStyle(Color.inkKohlSoft)
            }
            Spacer()
            if let action = trailingAction {
                Button(action: action) {
                    Image(systemName: trailingIcon)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(Color.surfaceDoodh)
                        .frame(width: 36, height: 36)
                        .background(Color.brandSaag, in: RoundedRectangle(cornerRadius: 10))
                }
            }
        }
        .padding(.horizontal, Saman.Space.md)
        .padding(.vertical, 12)
    }
}

// MARK: - Low Stock Alert Banner

struct LowStockBanner: View {
    let count: Int
    var action: (() -> Void)? = nil

    var body: some View {
        Button {
            action?()
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(Color.accentAnaar)
                    .font(.system(size: 14))
                Text("\(count) item\(count == 1 ? "" : "s") \(count == 1 ? "needs" : "need") restocking. Tap to see what to order.")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Color.accentAnaar)
                    .multilineTextAlignment(.leading)
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Color.accentAnaar.opacity(0.6))
            }
            .padding(12)
            .background(Color.accentAnaar.opacity(0.08), in: RoundedRectangle(cornerRadius: Saman.Radius.md))
            .overlay(RoundedRectangle(cornerRadius: Saman.Radius.md).stroke(Color.accentAnaar.opacity(0.25), lineWidth: 1))
        }
        .buttonStyle(.plain)
        .padding(.horizontal, Saman.Space.md)
    }
}

// MARK: - Pill Tab Bar

struct PillTabBar: View {
    let tabs: [(id: String, label: String)]
    @Binding var selection: String

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(tabs, id: \.id) { tab in
                    Button {
                        withAnimation(.easeInOut(duration: 0.18)) { selection = tab.id }
                    } label: {
                        let isActive = selection == tab.id
                        Text(tab.label)
                            .font(.system(size: 13, weight: isActive ? .semibold : .regular))
                            .foregroundStyle(isActive ? Color.brandSaag : Color.inkKohlSoft)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 7)
                            .background(
                                isActive ? Color.brandSaag.opacity(0.10) : Color.clear,
                                in: Capsule()
                            )
                            .overlay(
                                Capsule().stroke(
                                    isActive ? Color.brandSaag : Color.clear,
                                    lineWidth: 1
                                )
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, Saman.Space.md)
            .padding(.vertical, 4)
        }
    }
}

// MARK: - Section Header (Running low / Well stocked)

struct SamanSectionHeader: View {
    let title: String
    let color: Color

    var body: some View {
        HStack(spacing: 8) {
            Text(title.uppercased())
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(color)
                .kerning(0.8)
                .fixedSize()
            Rectangle()
                .frame(height: 1)
                .foregroundStyle(color.opacity(0.2))
        }
        .padding(.horizontal, Saman.Space.md)
        .padding(.top, 12)
        .padding(.bottom, 4)
    }
}

// MARK: - Item Card

struct ItemCard: View {
    let item: Item

    var body: some View {
        HStack(spacing: 12) {
            // Emoji icon
            Text(item.emoji)
                .font(.system(size: 22))
                .frame(width: 46, height: 46)
                .background(Color.surfaceAtta, in: RoundedRectangle(cornerRadius: 10))

            // Name + detail
            VStack(alignment: .leading, spacing: 3) {
                Text(item.name)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(Color.inkKohl)
                    .lineLimit(1)
                HStack(spacing: 4) {
                    if let pantry = item.pantry {
                        Text(pantry.name)
                            .font(.system(size: 12))
                            .foregroundStyle(Color.inkKohlSoft)
                    }
                    if item.isExpired {
                        Text("· Expired")
                            .font(.system(size: 12))
                            .foregroundStyle(Color.accentAnaar)
                    } else if item.isExpiringSoon {
                        Text("· Expires soon")
                            .font(.system(size: 12))
                            .foregroundStyle(Color.accentMasala)
                    }
                }
            }

            Spacer()

            // Quantity
            VStack(alignment: .trailing, spacing: 2) {
                Text("\(item.quantity)")
                    .font(.samanMono(18).weight(.semibold))
                    .foregroundStyle(item.isLow ? Color.accentAnaar : Color.brandSaag)
                Text(item.unit)
                    .font(.system(size: 11))
                    .foregroundStyle(Color.inkKohlSoft)
            }
        }
        .padding(12)
        .samanCard()
    }
}

// MARK: - Reorder Item Row

struct ReorderItemRow: View {
    let item: Item
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 12) {
                Image(systemName: "plus.circle.fill")
                    .font(.system(size: 22))
                    .foregroundStyle(Color.brandSaag)

                Text(item.emoji)
                    .font(.system(size: 18))
                    .frame(width: 36, height: 36)
                    .background(Color.surfaceAtta, in: RoundedRectangle(cornerRadius: 8))

                VStack(alignment: .leading, spacing: 2) {
                    Text(item.name)
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(Color.inkKohl)
                    Text("Have \(item.quantity), need ≥ \(item.minimumQuantity)")
                        .font(.system(size: 12))
                        .foregroundStyle(Color.inkKohlSoft)
                }

                Spacer()

                Text("\(item.quantity)/\(item.minimumQuantity)")
                    .font(.samanMono(13))
                    .foregroundStyle(Color.accentAnaar)
            }
            .padding(12)
            .background(Color.surfaceMalai, in: RoundedRectangle(cornerRadius: Saman.Radius.md))
            .overlay(
                RoundedRectangle(cornerRadius: Saman.Radius.md)
                    .stroke(Color.accentAnaar.opacity(0.2), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Scanner Corner Brackets

struct ScannerCornerBrackets: View {
    var color: Color = .brandSaag
    var bracketSize: CGFloat = 28
    var strokeWidth: CGFloat = 3
    var inset: CGFloat = 72

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height
            let s = bracketSize

            ZStack {
                // Top-left
                cornerPath(from: CGPoint(x: inset, y: inset + s),
                           corner: CGPoint(x: inset, y: inset),
                           to: CGPoint(x: inset + s, y: inset))
                // Top-right
                cornerPath(from: CGPoint(x: w - inset - s, y: inset),
                           corner: CGPoint(x: w - inset, y: inset),
                           to: CGPoint(x: w - inset, y: inset + s))
                // Bottom-left
                cornerPath(from: CGPoint(x: inset, y: h - inset - s),
                           corner: CGPoint(x: inset, y: h - inset),
                           to: CGPoint(x: inset + s, y: h - inset))
                // Bottom-right
                cornerPath(from: CGPoint(x: w - inset - s, y: h - inset),
                           corner: CGPoint(x: w - inset, y: h - inset),
                           to: CGPoint(x: w - inset, y: h - inset - s))
            }
        }
    }

    private func cornerPath(from: CGPoint, corner: CGPoint, to: CGPoint) -> some View {
        Path { p in
            p.move(to: from)
            p.addLine(to: corner)
            p.addLine(to: to)
        }
        .stroke(color, style: StrokeStyle(lineWidth: strokeWidth, lineCap: .round, lineJoin: .round))
    }
}

// MARK: - Empty State

struct SamanEmptyState: View {
    let emoji: String
    let title: String
    let message: String

    var body: some View {
        VStack(spacing: 12) {
            Text(emoji).font(.system(size: 48))
            Text(title)
                .font(.pantrySectionHead)
                .foregroundStyle(Color.inkKohl)
            Text(message)
                .font(.system(size: 14))
                .foregroundStyle(Color.inkKohlSoft)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 80)
        .padding(.horizontal, 32)
    }
}
