import SwiftUI
import SwiftData

struct HomeView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.appEnv)       private var appEnv

    @Query(sort: \Recipe.createdAt,       order: .reverse) private var recipes:  [Recipe]
    @Query(sort: \ShoppingList.createdAt, order: .reverse) private var allLists:  [ShoppingList]
    @Query(sort: \Item.name)                               private var allItems:  [Item]

    @State private var showCapture  = false
    @State private var showAdd      = false
    @State private var showPaywall  = false
    @State private var showScanner  = false
    @State private var showSettings = false

    // MARK: - Derived

    private var recentRecipes:  [Recipe]       { Array(recipes.prefix(3)) }
    private var activeLists:    [ShoppingList] { allLists.filter { !$0.isCompleted && $0.pendingCount > 0 }.prefix(3).map { $0 } }
    private var attentionItems: [Item]         { allItems.filter { $0.stockStatus.isAttention }.prefix(5).map { $0 } }

    private var isEmpty: Bool {
        recipes.isEmpty && activeLists.isEmpty && attentionItems.isEmpty
    }

    // MARK: - Body

    var body: some View {
        NavigationStack {
            Group {
                if isEmpty { emptyState } else { dashboard }
            }
            .background(Color.samanBg)
            .safeAreaInset(edge: .top, spacing: 0) {
                VStack(spacing: 0) {
                    topHeader
                    Rectangle().frame(height: 1).foregroundStyle(Color.samanBorder)
                }
                .background(Color.samanBg)
            }
            .toolbar(.hidden, for: .navigationBar)
            .sheet(isPresented: $showCapture)  { RecipeCaptureView() }
            .sheet(isPresented: $showAdd)       { AddItemView() }
            .sheet(isPresented: $showPaywall)   { SamanPaywallView() }
            .sheet(isPresented: $showScanner)   { ScannerView() }
            .sheet(isPresented: $showSettings)  { SettingsView() }
        }
    }

    // MARK: - Header

    private var topHeader: some View {
        HStack(alignment: .bottom) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Saman")
                    .font(.cormorant(28))
                    .foregroundStyle(Color.samanPrimary)
                Text(greeting)
                    .font(.system(size: 13))
                    .foregroundStyle(Color.samanMuted)
            }
            Spacer()
            Button { showSettings = true } label: {
                Image(systemName: "gearshape")
                    .font(.system(size: 16))
                    .foregroundStyle(Color.samanMuted)
                    .frame(width: 36, height: 36)
            }
            Button { showScanner = true } label: {
                Image(systemName: "barcode.viewfinder")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Color.samanPrimary)
                    .frame(width: 36, height: 36)
            }
            Button {
                if allItems.count >= 30 && !appEnv.purchases.isPro { showPaywall = true }
                else { showAdd = true }
            } label: {
                Image(systemName: "plus")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Color.samanBg)
                    .frame(width: 36, height: 36)
                    .background(Color.samanAccent, in: RoundedRectangle(cornerRadius: 10))
            }
        }
        .padding(.horizontal, Saman.Space.md)
        .padding(.vertical, 12)
    }

    // MARK: - Empty state

    private var emptyState: some View {
        VStack(spacing: 0) {
            Spacer()
            VStack(spacing: 16) {
                Text("نسخہ")
                    .font(.custom("NotoNastaliqUrdu-Regular", size: 56))
                    .foregroundStyle(Color.samanAccent)
                VStack(spacing: 8) {
                    Text("Your kitchen starts here.")
                        .font(.cormorant(28))
                        .foregroundStyle(Color.samanPrimary)
                    Text("Capture a parent's recipe — code-switched,\nandaza and all.")
                        .font(.system(size: 14))
                        .foregroundStyle(Color.samanMuted)
                        .multilineTextAlignment(.center)
                }
            }
            .padding(.bottom, 32)
            Button("Capture a Recipe") { showCapture = true }
                .buttonStyle(SamanPrimaryButtonStyle())
                .padding(.horizontal, Saman.Space.md)
            Spacer()
        }
    }

    // MARK: - Dashboard

    private var dashboard: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {

                // Capture card — always at top when there's other content
                captureCard
                    .padding(.horizontal, Saman.Space.md)
                    .padding(.top, Saman.Space.md)

                // Recent recipes
                if !recentRecipes.isEmpty {
                    SamanSectionHeader(title: "Recipes", color: .samanAccent)
                    ForEach(recentRecipes) { recipe in
                        NavigationLink(destination: RecipeDetailView(recipe: recipe)) {
                            HomeRecipeRow(recipe: recipe)
                        }
                        .buttonStyle(.plain)
                        .padding(.horizontal, Saman.Space.md)
                        .padding(.bottom, 6)
                    }
                }

                // Active shopping lists
                if !activeLists.isEmpty {
                    SamanSectionHeader(title: "Shopping", color: .samanAccent)
                    ForEach(activeLists) { list in
                        NavigationLink(destination: ShoppingListDetailView(list: list)) {
                            HomeListRow(list: list)
                        }
                        .buttonStyle(.plain)
                        .padding(.horizontal, Saman.Space.md)
                        .padding(.bottom, 6)
                    }
                }

                // Low stock / attention items
                if !attentionItems.isEmpty {
                    SamanSectionHeader(title: "Running low", color: .samanRed)
                    ForEach(attentionItems) { item in
                        HomeLowStockRow(item: item)
                            .padding(.horizontal, Saman.Space.md)
                            .padding(.bottom, 4)
                    }
                    NavigationLink(destination: InventoryView()) {
                        HStack {
                            Text("See all pantry items")
                                .font(.system(size: 13))
                                .foregroundStyle(Color.samanAccent)
                            Image(systemName: "chevron.right")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(Color.samanAccent.opacity(0.6))
                        }
                        .padding(.horizontal, Saman.Space.md)
                        .padding(.top, 4)
                    }
                }

                Spacer(minLength: 32)
            }
        }
    }

    // MARK: - Capture card

    private var captureCard: some View {
        Button { showCapture = true } label: {
            HStack(spacing: 14) {
                Text("نسخہ")
                    .font(.custom("NotoNastaliqUrdu-Regular", size: 26))
                    .foregroundStyle(.white)
                    .frame(width: 48, height: 48)
                    .background(Color.samanAccent, in: RoundedRectangle(cornerRadius: 10))

                VStack(alignment: .leading, spacing: 3) {
                    Text("Capture a recipe")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Color.samanPrimary)
                    Text("Paste a transcript to extract ingredients")
                        .font(.system(size: 13))
                        .foregroundStyle(Color.samanMuted)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Color.samanMuted.opacity(0.5))
            }
            .padding(14)
            .samanCard()
        }
        .buttonStyle(.plain)
    }

    // MARK: - Helpers

    private var greeting: String {
        switch Calendar.current.component(.hour, from: Date()) {
        case 5..<12:  return "Good morning"
        case 12..<17: return "Good afternoon"
        default:      return "Good evening"
        }
    }
}

// MARK: - Row components

private struct HomeRecipeRow: View {
    let recipe: Recipe

    var body: some View {
        HStack(spacing: 12) {
            Text("🍲")
                .font(.system(size: 20))
                .frame(width: 42, height: 42)
                .background(Color.samanAccentLight, in: RoundedRectangle(cornerRadius: 9))
            VStack(alignment: .leading, spacing: 2) {
                Text(recipe.title)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(Color.samanPrimary)
                    .lineLimit(1)
                Text(recipe.createdAt, format: .dateTime.day().month(.abbreviated).year())
                    .font(.system(size: 12))
                    .foregroundStyle(Color.samanMuted)
            }
            Spacer()
            Image(systemName: "chevron.right")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Color.samanMuted.opacity(0.5))
        }
        .padding(12)
        .samanCard()
    }
}

private struct HomeListRow: View {
    let list: ShoppingList

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "cart")
                .font(.system(size: 17))
                .foregroundStyle(Color.samanAccent)
                .frame(width: 42, height: 42)
                .background(Color.samanAccentLight, in: RoundedRectangle(cornerRadius: 9))
            VStack(alignment: .leading, spacing: 2) {
                Text(list.name)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(Color.samanPrimary)
                    .lineLimit(1)
                Text("\(list.pendingCount) item\(list.pendingCount == 1 ? "" : "s") left")
                    .font(.system(size: 12))
                    .foregroundStyle(Color.samanMuted)
            }
            Spacer()
            Image(systemName: "chevron.right")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Color.samanMuted.opacity(0.5))
        }
        .padding(12)
        .samanCard()
    }
}

private struct HomeLowStockRow: View {
    let item: Item

    var body: some View {
        HStack(spacing: 10) {
            Text(item.stockStatus.dot)
                .font(.system(size: 12))
                .foregroundStyle(item.stockStatus.color)
                .frame(width: 18)
            Text(item.emoji)
                .font(.system(size: 16))
                .frame(width: 36, height: 36)
                .background(Color.samanDeep, in: RoundedRectangle(cornerRadius: 8))
            Text(item.name)
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(Color.samanPrimary)
                .lineLimit(1)
            Spacer()
            Text(statusLabel(item.stockStatus))
                .font(.samanMono(11))
                .foregroundStyle(item.stockStatus.color)
        }
        .padding(10)
        .background(item.stockStatus.color.opacity(0.06), in: RoundedRectangle(cornerRadius: Saman.Radius.sm))
        .overlay(RoundedRectangle(cornerRadius: Saman.Radius.sm).stroke(item.stockStatus.color.opacity(0.2), lineWidth: 1))
    }

    private func statusLabel(_ s: StockStatus) -> String {
        switch s {
        case .out:      return "out"
        case .expiring: return "expiring"
        case .low:      return "low"
        case .inStock:  return ""
        }
    }
}

#Preview { HomeView().modelContainer(.preview) }
