import Foundation
import SwiftData
import Testing
@testable import Saman

// Main-actor isolated: previewModelContainerCanCreateAllPrimaryModels touches
// ModelContainer.mainContext, which is @MainActor.
@MainActor
struct SamanTests {

    @Test func configDoesNotExposePrivateAnthropicKey() {
        #expect(!Config.recipeExtractionEndpoint.isEmpty)
        #expect(Config.recipeExtractionEndpoint.hasPrefix(Config.supabaseURL))
        #expect(!Config.recipeExtractionEndpoint.contains("sk-" + "ant-api"))
        #expect(!Config.recipeExtractionEndpoint.lowercased().contains("anthropic"))
    }

    @Test func previewModelContainerCanCreateAllPrimaryModels() throws {
        let context = ModelContainer.preview.mainContext
        let pantry = Pantry(name: "Test Pantry")
        let item = Item(name: "Rice", quantity: 2, unit: "bag", minimumQuantity: 1, pantry: pantry)
        let product = Product(name: "Basmati Rice", barcode: "123456789012")
        let store = Store(name: "Test Store")
        let shoppingList = ShoppingList(name: "Weekly", store: store)
        let shoppingListItem = ShoppingListItem(quantity: 1, unit: "bag", product: product, shoppingList: shoppingList)
        let recipe = Recipe(title: "Test Recipe", rawTranscript: "Boil rice", extractedJSON: "{}")

        context.insert(pantry)
        context.insert(item)
        context.insert(product)
        context.insert(store)
        context.insert(shoppingList)
        context.insert(shoppingListItem)
        context.insert(recipe)

        try context.save()

        let items = try context.fetch(FetchDescriptor<Item>())
        #expect(items.contains { $0.name == "Rice" })
        #expect(item.isLow == false)
        #expect(recipe.updatedAt.timeIntervalSince1970 > 0)
    }
}

struct SyncReconcileTests {
    @Test func dirtyLocalWinsOverNewerServer() {
        let local = Date(timeIntervalSince1970: 1)
        let server = Date(timeIntervalSince1970: 100)
        #expect(SyncReconcile.shouldApplyServer(localUpdatedAt: local, localDirty: true, serverUpdatedAt: server) == false)
    }

    @Test func cleanLocalYieldsToNewerOrEqualServer() {
        let local = Date(timeIntervalSince1970: 50)
        let newer = Date(timeIntervalSince1970: 100)
        let equal = Date(timeIntervalSince1970: 50)
        let older = Date(timeIntervalSince1970: 1)
        #expect(SyncReconcile.shouldApplyServer(localUpdatedAt: local, localDirty: false, serverUpdatedAt: newer) == true)
        #expect(SyncReconcile.shouldApplyServer(localUpdatedAt: local, localDirty: false, serverUpdatedAt: equal) == true)
        #expect(SyncReconcile.shouldApplyServer(localUpdatedAt: local, localDirty: false, serverUpdatedAt: older) == false)
    }

    @Test func missingServerRowDeletesOnlyCleanLocal() {
        #expect(SyncReconcile.shouldDeleteLocal(localDirty: false, presentOnServer: false) == true)
        #expect(SyncReconcile.shouldDeleteLocal(localDirty: true, presentOnServer: false) == false)
        #expect(SyncReconcile.shouldDeleteLocal(localDirty: false, presentOnServer: true) == false)
    }

    @Test func flushKeepsTombstonesQueuedDuringNetworkWait() {
        let first = SyncReconcile.TombstoneID(table: "items", id: UUID())
        let second = SyncReconcile.TombstoneID(table: "shopping_list_items", id: UUID())
        let kept = SyncReconcile.remainingTombstones(
            current: [first, second],
            successfullyDeleted: [first]
        )
        #expect(kept == [second])
    }

    @Test func flushDropsOnlySuccessfulDeletes() {
        let failed = SyncReconcile.TombstoneID(table: "recipes", id: UUID())
        let kept = SyncReconcile.remainingTombstones(
            current: [failed],
            successfullyDeleted: []
        )
        #expect(kept == [failed])
    }

    @Test func pullSkipsTombstonedRows() {
        let deleted = UUID()
        let live = UUID()
        #expect(SyncReconcile.shouldInsertPulledRow(id: deleted, tombstonedIDs: [deleted]) == false)
        #expect(SyncReconcile.shouldInsertPulledRow(id: live, tombstonedIDs: [deleted]) == true)
    }

    @Test func uploadLeavesDirtyWhenRowChangedInFlight() {
        let uploaded = Date(timeIntervalSince1970: 10)
        let edited = Date(timeIntervalSince1970: 20)
        #expect(SyncReconcile.shouldClearDirtyAfterUpload(uploadedUpdatedAt: uploaded, currentUpdatedAt: edited) == false)
        #expect(SyncReconcile.shouldClearDirtyAfterUpload(uploadedUpdatedAt: uploaded, currentUpdatedAt: uploaded) == true)
    }
}

@MainActor
@Suite(.serialized)
struct DeleteRecordTests {
    private func makeContainer() throws -> ModelContainer {
        let schema = Schema([
            Item.self,
            Pantry.self,
            Product.self,
            Store.self,
            ShoppingList.self,
            ShoppingListItem.self,
            Recipe.self,
        ])
        return try ModelContainer(
            for: schema,
            configurations: ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        )
    }

    @Test func deleteItemQueuesTombstoneAndDropsLocalRow() throws {
        let container = try makeContainer()
        let env = AppEnvironment(modelContainer: container)
        env.syncManager.clearTombstones()
        defer { env.syncManager.clearTombstones() }

        let item = Item(name: "Atta", quantity: 2, unit: "kg")
        container.mainContext.insert(item)
        try container.mainContext.save()
        let itemID = item.id

        env.deleteRecord(item, table: "items", id: itemID)

        let remaining = try container.mainContext.fetch(FetchDescriptor<Item>())
        #expect(remaining.isEmpty)
        #expect(env.syncManager.queuedTombstones().contains { $0.table == "items" && $0.id == itemID })
    }

    @Test func deleteRecipeQueuesTombstoneAndDropsLocalRow() throws {
        let container = try makeContainer()
        let env = AppEnvironment(modelContainer: container)
        env.syncManager.clearTombstones()
        defer { env.syncManager.clearTombstones() }

        let recipe = Recipe(title: "Karahi", rawTranscript: "chicken, tamatar")
        container.mainContext.insert(recipe)
        try container.mainContext.save()
        let recipeID = recipe.id

        env.deleteRecord(recipe, table: "recipes", id: recipeID)

        let remaining = try container.mainContext.fetch(FetchDescriptor<Recipe>())
        #expect(remaining.isEmpty)
        #expect(env.syncManager.queuedTombstones().contains { $0.table == "recipes" && $0.id == recipeID })
    }

    @Test func deleteShoppingListTombstonesListAndChildItems() throws {
        let container = try makeContainer()
        let env = AppEnvironment(modelContainer: container)
        env.syncManager.clearTombstones()
        defer { env.syncManager.clearTombstones() }

        let list = ShoppingList(name: "Sunday shop")
        let product = Product(name: "Atta")
        let listItem = ShoppingListItem(quantity: 1, unit: "bag", product: product, shoppingList: list)
        container.mainContext.insert(product)
        container.mainContext.insert(list)
        container.mainContext.insert(listItem)
        try container.mainContext.save()
        let listID = list.id
        let itemID = listItem.id

        env.deleteRecord(list, table: "shopping_lists", id: listID)

        let lists = try container.mainContext.fetch(FetchDescriptor<ShoppingList>())
        let items = try container.mainContext.fetch(FetchDescriptor<ShoppingListItem>())
        #expect(lists.isEmpty)
        #expect(items.isEmpty)
        let stones = env.syncManager.queuedTombstones()
        #expect(stones.contains { $0.table == "shopping_lists" && $0.id == listID })
        #expect(stones.contains { $0.table == "shopping_list_items" && $0.id == itemID })
    }

    @Test func clearLocalStoreInvalidatesSyncAndDropsTombstones() throws {
        let container = try makeContainer()
        let env = AppEnvironment(modelContainer: container)
        env.syncManager.clearTombstones()
        defer { env.syncManager.clearTombstones() }

        let item = Item(name: "Haldi", quantity: 1, unit: "jar")
        container.mainContext.insert(item)
        try container.mainContext.save()
        env.deleteRecord(item, table: "items", id: item.id)
        #expect(!env.syncManager.queuedTombstones().isEmpty)

        env.clearLocalStore()

        let remaining = try container.mainContext.fetch(FetchDescriptor<Item>())
        #expect(remaining.isEmpty)
        #expect(env.syncManager.queuedTombstones().isEmpty)
    }
}

struct AuthCopyTests {
    private struct DummyError: LocalizedError {
        let message: String
        var errorDescription: String? { message }
    }

    @Test func friendlyMapsProviderErrors() {
        #expect(AuthService.friendly(DummyError(message: "Invalid login credentials")) == "Email or password is wrong.")
        #expect(AuthService.friendly(DummyError(message: "User already registered")) == "That email already has an account. Try signing in.")
        #expect(AuthService.friendly(DummyError(message: "Rate limit exceeded")) == "Too many attempts. Wait a minute and try again.")
        #expect(AuthService.friendly(DummyError(message: "The Internet connection appears to be offline.")) == "Couldn't reach the server. Check your connection.")
        #expect(AuthService.friendly(DummyError(message: "Password should be at least 6 characters")) == "Use a password with at least 6 characters.")
        #expect(AuthService.friendly(DummyError(message: "unexpected blob")) == "Something went wrong. Please try again.")
    }
}

struct LegalURLTests {
    @Test func configExposesAppStoreLegalURLs() {
        #expect(Config.privacyPolicyURL == "https://samanpantry.com/privacy")
        #expect(Config.termsOfUseURL == "https://www.apple.com/legal/internet-services/itunes/dev/stdeula/")
        #expect(Config.supportURL == "https://samanpantry.com/support")
        #expect(URL(string: Config.privacyPolicyURL) != nil)
        #expect(URL(string: Config.termsOfUseURL) != nil)
        #expect(URL(string: Config.supportURL) != nil)
    }
}

@MainActor
struct GuestAccountGateTests {
    private func makeContainer() throws -> ModelContainer {
        let schema = Schema([
            Item.self,
            Pantry.self,
            Product.self,
            Store.self,
            ShoppingList.self,
            ShoppingListItem.self,
            Recipe.self,
        ])
        return try ModelContainer(
            for: schema,
            configurations: ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        )
    }

    @Test func requireAccountPresentsAuthWhenSignedOut() throws {
        let env = AppEnvironment(modelContainer: try makeContainer())
        guard !ScreenshotLaunchConfiguration.current.skipsAuth else { return }
        #expect(env.auth.isSignedIn == false)
        #expect(env.isAuthPresented == false)
        #expect(env.requireAccount() == false)
        #expect(env.isAuthPresented)
    }
}

struct LocalStoreAuthPolicyTests {
    @Test func trueGuestKeepsLocalKitchen() {
        #expect(LocalStoreAuthPolicy.shouldClearLocalStore(persistedUserID: nil, currentUserID: nil) == false)
        #expect(LocalStoreAuthPolicy.shouldClearLocalStore(persistedUserID: "  ", currentUserID: nil) == false)
    }

    @Test func firstSignInAfterGuestKeepsKitchenForUpload() {
        #expect(
            LocalStoreAuthPolicy.shouldClearLocalStore(
                persistedUserID: nil,
                currentUserID: "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE"
            ) == false
        )
    }

    @Test func sameAccountRestoreKeepsCache() {
        let userID = "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE"
        #expect(LocalStoreAuthPolicy.shouldClearLocalStore(persistedUserID: userID, currentUserID: userID) == false)
        #expect(
            LocalStoreAuthPolicy.shouldClearLocalStore(
                persistedUserID: userID.lowercased(),
                currentUserID: userID
            ) == false
        )
    }

    @Test func sessionLossAndAccountSwitchWipe() {
        let userA = "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE"
        let userB = "BBBBBBBB-CCCC-DDDD-EEEE-FFFFFFFFFFFF"
        #expect(LocalStoreAuthPolicy.shouldClearLocalStore(persistedUserID: userA, currentUserID: nil) == true)
        #expect(LocalStoreAuthPolicy.shouldClearLocalStore(persistedUserID: userA, currentUserID: userB) == true)
    }
}

@MainActor
struct LocalStoreReconcileTests {
    private func makeContainer() throws -> ModelContainer {
        let schema = Schema([
            Item.self,
            Pantry.self,
            Product.self,
            Store.self,
            ShoppingList.self,
            ShoppingListItem.self,
            Recipe.self,
        ])
        return try ModelContainer(
            for: schema,
            configurations: ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        )
    }

    private func makeDefaults() -> (UserDefaults, String) {
        let suite = "samaan.tests.localstore.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        return (defaults, suite)
    }

    @Test func sessionLossWipesPriorKitchenAndTombstones() throws {
        guard !ScreenshotLaunchConfiguration.current.skipsAuth else { return }
        let container = try makeContainer()
        let env = AppEnvironment(modelContainer: container)
        env.syncManager.clearTombstones()
        defer { env.syncManager.clearTombstones() }

        let item = Item(name: "Atta", quantity: 1, unit: "bag")
        container.mainContext.insert(item)
        try container.mainContext.save()
        env.syncManager.queueTombstone(table: "items", id: item.id)

        let (defaults, suite) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set("AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE", forKey: AppEnvironment.lastAuthenticatedUserIDKey)

        env.reconcileLocalStore(currentUserID: nil, defaults: defaults)

        let remaining = try container.mainContext.fetch(FetchDescriptor<Item>())
        #expect(remaining.isEmpty)
        #expect(env.syncManager.queuedTombstones().isEmpty)
        #expect(defaults.string(forKey: AppEnvironment.lastAuthenticatedUserIDKey) == nil)
    }

    @Test func guestKitchenSurvivesFirstSignIn() throws {
        guard !ScreenshotLaunchConfiguration.current.skipsAuth else { return }
        let container = try makeContainer()
        let env = AppEnvironment(modelContainer: container)

        let item = Item(name: "Chawal", quantity: 2, unit: "kg")
        container.mainContext.insert(item)
        try container.mainContext.save()

        let (defaults, suite) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }

        env.reconcileLocalStore(
            currentUserID: "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE",
            defaults: defaults
        )

        let remaining = try container.mainContext.fetch(FetchDescriptor<Item>())
        #expect(remaining.contains { $0.name == "Chawal" })
        #expect(defaults.string(forKey: AppEnvironment.lastAuthenticatedUserIDKey) == "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE")
    }

    @Test func accountSwitchWipesPriorKitchen() throws {
        guard !ScreenshotLaunchConfiguration.current.skipsAuth else { return }
        let container = try makeContainer()
        let env = AppEnvironment(modelContainer: container)

        let item = Item(name: "Masoor", quantity: 1, unit: "bag")
        container.mainContext.insert(item)
        try container.mainContext.save()

        let (defaults, suite) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set("AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE", forKey: AppEnvironment.lastAuthenticatedUserIDKey)

        env.reconcileLocalStore(
            currentUserID: "BBBBBBBB-CCCC-DDDD-EEEE-FFFFFFFFFFFF",
            defaults: defaults
        )

        let remaining = try container.mainContext.fetch(FetchDescriptor<Item>())
        #expect(remaining.isEmpty)
        #expect(defaults.string(forKey: AppEnvironment.lastAuthenticatedUserIDKey) == "BBBBBBBB-CCCC-DDDD-EEEE-FFFFFFFFFFFF")
    }
}

struct FreeLimitsTests {
    @Test func pantryCapBlocksFreeUserAtLimit() {
        #expect(FreeLimits.canAddPantryItem(existingCount: 29, isPro: false) == true)
        #expect(FreeLimits.canAddPantryItem(existingCount: 30, isPro: false) == false)
        #expect(FreeLimits.canAddPantryItem(existingCount: 30, isPro: true) == true)
        #expect(FreeLimits.pantryItemCap == 30)
    }

    @Test func listsTabCapBlocksFreeUserAtOneList() {
        #expect(FreeLimits.canAddShoppingListFromListsTab(existingCount: 0, isPro: false) == true)
        #expect(FreeLimits.canAddShoppingListFromListsTab(existingCount: 1, isPro: false) == false)
        #expect(FreeLimits.canAddShoppingListFromListsTab(existingCount: 1, isPro: true) == true)
        #expect(FreeLimits.shoppingListCap == 1)
    }

    @Test func extractQuotaIsNotAProUnlock() {
        #expect(FreeLimits.extractPerDay == 5)
        #expect(FreeLimits.quotaExceededMessage.contains("tomorrow"))
        #expect(FreeLimits.quotaExceededMessage.contains("\(FreeLimits.extractPerDay)"))
        #expect(RecipeExtractionService.ExtractionError.quotaExceeded.localizedDescription == FreeLimits.quotaExceededMessage)
        #expect(FreeLimits.proUnlocksSummary.contains("everyone"))
        #expect(FreeLimits.freePlanSummary.contains("Extract stays"))
    }
}

struct MonetizationCopyTests {
    private static let bannedProClaims = [
        "instacart",
        "one-tap reorder",
        "one-tap instacart",
        "restock essentials before you run out",
    ]

    @Test func storeKitNamesRealUnlocks() throws {
        let text = try String(contentsOf: storeKitURL, encoding: .utf8)
        #expect(!text.contains("premium pantry and recipe features"))
        #expect(!text.contains("support development"))
        #expect(text.contains("\(FreeLimits.pantryItemCap) pantry"))
        #expect(text.contains("Lists"))
        #expect(text.contains("\(FreeLimits.extractPerDay) per day") || text.contains("\(FreeLimits.extractPerDay)/day"))
    }

    @Test func paywallBenefitsAreTheRealUnlocks() {
        #expect(FreeLimits.proBenefits.count == 2)
        #expect(FreeLimits.proBenefits.map(\.title) == [
            "Unlimited pantry items",
            "Unlimited shopping lists",
        ])
        #expect(!FreeLimits.proMarketingStrings.joined(separator: "\n").lowercased().contains("unlimited pantries"))
        #expect(FreeLimits.proUnlocksSummary.contains("\(FreeLimits.pantryItemCap) pantry"))
        #expect(FreeLimits.proUnlocksSummary.contains("everyone"))
        for string in FreeLimits.proMarketingStrings {
            let lower = string.lowercased()
            for banned in Self.bannedProClaims {
                #expect(!lower.contains(banned), "Pro copy leaked \(banned): \(string)")
            }
        }
    }

    @Test func shippedSourcesOmitRetiredGroceryDeliveryClaims() throws {
        let samanRoot = repoRoot.appendingPathComponent("Saman")
        for (file, text) in try sourceFiles(under: samanRoot) {
            let lower = text.lowercased()
            for banned in Self.bannedProClaims {
                #expect(!lower.contains(banned), "\(file.path) still contains \(banned)")
            }
        }
    }

    @Test func paywallDoesNotRenderRemoteOfferingCopy() throws {
        let paywall = try String(contentsOf: samanRoot.appendingPathComponent("Features/Settings/PaywallView.swift"), encoding: .utf8)
        #expect(!paywall.contains("import RevenueCatUI"))
        #expect(!paywall.contains("PaywallView()"))
        #expect(paywall.contains("FreeLimits.proBenefits"))
        #expect(paywall.contains("FreeLimits.proUnlocksSummary"))
    }

    private var repoRoot: URL {
        URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
    }

    private var samanRoot: URL { repoRoot.appendingPathComponent("Saman") }

    private var storeKitURL: URL { samanRoot.appendingPathComponent("Saman.storekit") }

    private func sourceFiles(under root: URL) throws -> [(URL, String)] {
        var files: [(URL, String)] = []
        let enumerator = FileManager.default.enumerator(at: root, includingPropertiesForKeys: [.isRegularFileKey])
        while let url = enumerator?.nextObject() as? URL {
            guard url.pathExtension == "swift" || url.pathExtension == "storekit" else { continue }
            files.append((url, try String(contentsOf: url, encoding: .utf8)))
        }
        return files
    }
}

struct ScanEntryTests {
    @Test func scanLivesInsideAddItemNotHomeOrPantry() throws {
        let saman = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Saman")
        let home = try String(contentsOf: saman.appendingPathComponent("Features/Home/HomeView.swift"), encoding: .utf8)
        let pantry = try String(contentsOf: saman.appendingPathComponent("Features/Inventory/InventoryView.swift"), encoding: .utf8)
        let addItem = try String(contentsOf: saman.appendingPathComponent("Features/Inventory/AddItemView.swift"), encoding: .utf8)
        let scanner = try String(contentsOf: saman.appendingPathComponent("Features/Scanner/ScannerView.swift"), encoding: .utf8)

        #expect(!home.contains("ScannerView"))
        #expect(!home.contains("barcode.viewfinder"))
        #expect(!home.contains("See all pantry items"))
        #expect(!home.contains("InventoryView()"))
        #expect(!pantry.contains("ScannerView"))
        #expect(!pantry.contains("barcode.viewfinder"))
        #expect(addItem.contains("ScannerView"))
        #expect(addItem.contains("barcode.viewfinder"))
        #expect(!scanner.contains("AddItemView"))
        #expect(!scanner.contains("showAddItem"))
    }
}
