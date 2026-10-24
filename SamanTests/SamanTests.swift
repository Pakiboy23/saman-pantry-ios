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
        let suite = "samaan.tests.clear.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.set("Khan family recipes", forKey: "samaan.familyCookbook.name")
        defaults.set("a@example.com,b@example.com", forKey: "samaan.familyCookbook.members")
        defer { defaults.removePersistentDomain(forName: suite) }

        env.clearLocalStore(defaults: defaults)

        let remaining = try container.mainContext.fetch(FetchDescriptor<Item>())
        #expect(remaining.isEmpty)
        #expect(env.syncManager.queuedTombstones().isEmpty)
        #expect(defaults.string(forKey: "samaan.familyCookbook.name") == nil)
        #expect(defaults.string(forKey: "samaan.familyCookbook.members") == nil)
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
        defaults.set("Khan family recipes", forKey: "samaan.familyCookbook.name")
        defaults.set("a@example.com,b@example.com", forKey: "samaan.familyCookbook.members")

        env.reconcileLocalStore(currentUserID: nil, defaults: defaults)

        let remaining = try container.mainContext.fetch(FetchDescriptor<Item>())
        #expect(remaining.isEmpty)
        #expect(env.syncManager.queuedTombstones().isEmpty)
        #expect(defaults.string(forKey: AppEnvironment.lastAuthenticatedUserIDKey) == nil)
        #expect(defaults.string(forKey: "samaan.familyCookbook.name") == nil)
        #expect(defaults.string(forKey: "samaan.familyCookbook.members") == nil)
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
        defaults.set("Khan family recipes", forKey: "samaan.familyCookbook.name")
        defaults.set("a@example.com,b@example.com", forKey: "samaan.familyCookbook.members")

        env.reconcileLocalStore(
            currentUserID: "BBBBBBBB-CCCC-DDDD-EEEE-FFFFFFFFFFFF",
            defaults: defaults
        )

        let remaining = try container.mainContext.fetch(FetchDescriptor<Item>())
        #expect(remaining.isEmpty)
        #expect(defaults.string(forKey: AppEnvironment.lastAuthenticatedUserIDKey) == "BBBBBBBB-CCCC-DDDD-EEEE-FFFFFFFFFFFF")
        #expect(defaults.string(forKey: "samaan.familyCookbook.name") == nil)
        #expect(defaults.string(forKey: "samaan.familyCookbook.members") == nil)
    }
}

struct PurchaseSessionBindingTests {
    @Test func signedInAccountIdentifiesRevenueCat() {
        #expect(
            PurchaseSessionBinding.action(
                currentUserID: "user-a",
                revenueCatIsAnonymous: false,
                skipsAuth: false
            ) == .identify("user-a")
        )
        #expect(
            PurchaseSessionBinding.action(
                currentUserID: "user-a",
                revenueCatIsAnonymous: true,
                skipsAuth: false
            ) == .identify("user-a")
        )
    }

    @Test func leftoverIdentifiedUserLogsOutWhenSessionEnds() {
        #expect(
            PurchaseSessionBinding.action(
                currentUserID: nil,
                revenueCatIsAnonymous: false,
                skipsAuth: false
            ) == .logOut
        )
    }

    @Test func anonymousGuestKeepsOwnPurchases() {
        #expect(
            PurchaseSessionBinding.action(
                currentUserID: nil,
                revenueCatIsAnonymous: true,
                skipsAuth: false
            ) == .ignore
        )
    }

    @Test func screenshotAuthSkipDoesNotTouchRevenueCat() {
        #expect(
            PurchaseSessionBinding.action(
                currentUserID: nil,
                revenueCatIsAnonymous: false,
                skipsAuth: true
            ) == .ignore
        )
        #expect(
            PurchaseSessionBinding.action(
                currentUserID: "ui-testing",
                revenueCatIsAnonymous: false,
                skipsAuth: true
            ) == .ignore
        )
    }

    @Test func appBindsPurchasesOnSessionEndAndInitialCheck() throws {
        let app = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Saman/SamaanApp.swift")
        let text = try String(contentsOf: app, encoding: .utf8)
        #expect(text.contains("bindPurchases(to: userID)"))
        #expect(text.contains("bindPurchases(to: appEnv.auth.currentUserID)"))
        #expect(text.contains("appEnv.purchases.logOutAppUser()"))
        #expect(text.contains("PurchaseSessionBinding.action"))
    }
}

struct FreeLimitsTests {
    @Test func pantryAndListsAreUnlimitedForEveryone() {
        #expect(FreeLimits.freePlanSummary.lowercased().contains("unlimited pantry"))
        #expect(FreeLimits.freePlanSummary.lowercased().contains("lists"))
        #expect(!FreeLimits.freePlanSummary.contains("30"))
    }

    @Test func extractQuotaIsFiveWithLifetimeAndDailyCopy() {
        #expect(FreeLimits.extractLimit == 5)
        #expect(FreeLimits.extractionCounterLabel(used: 2, grandfathered: false) == "2 of 5 extractions used")
        #expect(FreeLimits.extractionCounterLabel(used: 2, grandfathered: true) == "2 of 5 extractions used today")
        #expect(FreeLimits.freePlanSummary.contains("5 voice extractions"))
        #expect(FreeLimits.proActiveSummary.lowercased().contains("unlimited voice"))
        #expect(!FreeLimits.proActiveSummary.lowercased().contains("share"))
        #expect(!FreeLimits.proMarketingStrings.joined(separator: "\n").lowercased().contains("add family members"))
    }

    @Test func paywallTriggersCarryContextOnlyWhenNeeded() {
        #expect(PaywallTrigger.settings.contextLine == nil)
        #expect(PaywallTrigger.extractionLimit.contextLine == FreeLimits.paywallContextExtractionLimit)
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
        #expect(text.contains("voice"))
        #expect(text.contains("cookbook") || text.contains("Cookbook"))
        #expect(!text.lowercased().contains("lifetime"))
    }

    @Test func paywallBenefitsAreTheRealUnlocks() {
        #expect(FreeLimits.proBenefits.count == 3)
        #expect(FreeLimits.proBenefits.map(\.title) == [
            "Unlimited voice extractions",
            "Start family cookbooks",
            "Keep every rescued recipe",
        ])
        #expect(FreeLimits.paywallHeadline.contains("Don't lose the recipes"))
        #expect(FreeLimits.paywallSubheadline == "Samaan Pro turns voice notes and recordings into recipes you can keep.")
        #expect(!FreeLimits.paywallSubheadline.contains("Pantry Pro"))
        #expect(FreeLimits.monthlyPriceLabel.contains("7.99"))
        #expect(FreeLimits.yearlyPriceLabel.contains("59.99"))
        #expect(FreeLimits.yearlySavingsLabel.contains("38%"))
        for string in FreeLimits.proMarketingStrings {
            let lower = string.lowercased()
            for banned in Self.bannedProClaims {
                #expect(!lower.contains(banned), "Pro copy leaked \(banned): \(string)")
            }
            #expect(!string.contains("—"), "App-facing copy must not use em dashes: \(string)")
            #expect(!lower.contains("read and cook from it for free"))
            #expect(!lower.contains("add family members"))
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

    @Test func onboardingAndSourcePlaceholdersStayNeutral() throws {
        let onboarding = try String(
            contentsOf: samanRoot.appendingPathComponent("Features/Onboarding/OnboardingView.swift"),
            encoding: .utf8
        )
        #expect(onboarding.contains("Record whoever in your family cooks as they explain a dish, in any language."))
        #expect(onboarding.contains("New accounts get 5 recipe extractions for life. No credit card needed. Go Samaan Pro when you're ready for unlimited."))
        #expect(!onboarding.contains("voice note of them"))
        #expect(!onboarding.contains("Upgrade to Pro"))
        #expect(!onboarding.contains("—"))

        let capture = try String(
            contentsOf: samanRoot.appendingPathComponent("Features/Recipes/RecipeCaptureView.swift"),
            encoding: .utf8
        )
        let edit = try String(
            contentsOf: samanRoot.appendingPathComponent("Features/Recipes/RecipeEditView.swift"),
            encoding: .utf8
        )
        #expect(capture.contains("e.g. whoever taught you"))
        #expect(edit.contains("e.g. whoever taught you"))
        #expect(!capture.contains("e.g. Mom"))
        #expect(!edit.contains("e.g. Mom"))
        #expect(!edit.contains("From —"))
        #expect(!edit.contains("andaza —"))
    }

    @Test func paywallDoesNotRenderRemoteOfferingCopy() throws {
        let paywall = try String(contentsOf: samanRoot.appendingPathComponent("Features/Settings/PaywallView.swift"), encoding: .utf8)
        #expect(!paywall.contains("import RevenueCatUI"))
        #expect(!paywall.contains("PaywallView()"))
        #expect(paywall.contains("FreeLimits.proBenefits"))
        #expect(paywall.contains("FreeLimits.paywallHeadline"))
        #expect(paywall.contains("Lifetime is retired"))
        #expect(paywall.contains("localizedPriceString"))
        #expect(paywall.contains("loadFailed = true"))
        #expect(paywall.contains("usesScreenshotFixtures"))
        #expect(!paywall.contains("CreateFamilyCookbookView"))
    }

    @Test func familyCookbookCreateUIIsNotShipped() throws {
        let createPath = samanRoot.appendingPathComponent("Features/Recipes/CreateFamilyCookbookView.swift")
        #expect(!FileManager.default.fileExists(atPath: createPath.path))
        let familyBook = try String(
            contentsOf: samanRoot.appendingPathComponent("Features/Recipes/FamilyRecipeBookView.swift"),
            encoding: .utf8
        )
        #expect(!familyBook.contains("CreateFamilyCookbookView"))
        #expect(!familyBook.contains("cookbook.create"))
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

@MainActor
struct AnalyticsTests {
    @Test func eventNamesMatchEventsTableCheck() {
        #expect(AnalyticsEvent.allCases.map(\.rawValue).sorted() == [
            "app_open", "guest_start", "item_added", "list_item_bought",
            "pantry_restocked", "paywall_viewed", "purchase_started",
            "recipe_extracted", "recipe_saved", "recipe_shared", "signup",
        ])
    }

    @Test func payloadCarriesNoAccountData() {
        let id = UUID()
        let body = Analytics.payload(event: .itemAdded, installID: id, appVersion: "1.1 (94)")
        #expect(Set(body.keys) == ["install_id", "event", "app_version"])
        #expect(body["install_id"] == id.uuidString.lowercased())
        #expect(body["event"] == "item_added")
    }

    @Test func installIDIsStablePerDefaults() {
        let suite = "samaan.tests.analytics.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let first = Analytics.installID(defaults: defaults)
        #expect(Analytics.installID(defaults: defaults) == first)
    }

    @Test func analyticsIsOffUnderTests() {
        #expect(Analytics.isEnabled == false)
    }
}

struct HeyCatchOutboxTests {
    @Test func eventsStayQueuedUntilTheSessionBind() {
        var outbox = HeyCatchOutbox()
        #expect(outbox.screen("Splash") == [])
        #expect(outbox.screen("Home") == [])
        #expect(outbox.capture("app_open") == [])
        #expect(outbox.open() == [
            .screen("Splash"),
            .screen("Home"),
            .capture("app_open"),
        ])
        #expect(outbox.screens.isEmpty)
        #expect(outbox.captures.isEmpty)
    }

    @Test func automaticCaptureIsOffBeforeSetup() throws {
        let file = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Saman/Core/Services/HeyCatch.swift")
        let text = try String(contentsOf: file, encoding: .utf8)
        let setup = try #require(text.range(of: "PostHogSDK.shared.setup(config)"))
        for flag in [
            "config.captureApplicationLifecycleEvents = false",
            "config.captureScreenViews = false",
            "config.enableSwizzling = false",
            "config.errorTrackingConfig.autoCapture = false",
            "config.surveys = false",
            "config.sessionReplay = false",
        ] {
            let setting = try #require(text.range(of: flag), "missing \(flag)")
            #expect(setting.lowerBound < setup.lowerBound)
        }
    }

    @Test func eventsAfterOpenSendImmediately() {
        var outbox = HeyCatchOutbox()
        _ = outbox.open()
        #expect(outbox.screen("Pantry") == [.screen("Pantry")])
        #expect(outbox.capture("item_added") == [.capture("item_added")])
        #expect(outbox.open() == [])
    }
}

struct HeyCatchIdentityTests {
    @Test func freshGuestStaysAnonymous() {
        #expect(HeyCatchIdentity.action(currentUserID: nil, boundUserID: nil) == .none)
        #expect(HeyCatchIdentity.action(currentUserID: "  ", boundUserID: nil) == .none)
        #expect(HeyCatchIdentity.action(currentUserID: "ui-testing", boundUserID: nil) == .none)
    }

    @Test func coldLaunchGuestDropsThePreviousAccount() {
        #expect(HeyCatchIdentity.action(currentUserID: nil, boundUserID: "user-a") == .reset)
        #expect(HeyCatchIdentity.action(currentUserID: "ui-testing", boundUserID: "user-a") == .reset)
    }

    @Test func sameAccountDoesNotReidentify() {
        #expect(HeyCatchIdentity.action(currentUserID: "user-a", boundUserID: "user-a") == .none)
        #expect(HeyCatchIdentity.action(currentUserID: "  user-a  ", boundUserID: "user-a") == .none)
    }

    @Test func firstSignInIdentifies() {
        #expect(HeyCatchIdentity.action(currentUserID: "user-a", boundUserID: nil) == .identify("user-a"))
    }

    @Test func accountSwapResetsBeforeIdentify() {
        #expect(
            HeyCatchIdentity.action(currentUserID: "user-b", boundUserID: "user-a")
                == .resetThenIdentify("user-b")
        )
    }

    @Test func coldLaunchGuestGroupsOnlyAfterReset() {
        let effects = HeyCatchBind.effects(for: .reset, alreadyGrouped: false)
        #expect(effects == [.resetSDK, .forgetBoundUser, .registerAndGroup])
    }

    @Test func accountSwapGroupsAfterTheNewIdentity() {
        let effects = HeyCatchBind.effects(
            for: .resetThenIdentify("user-b"),
            alreadyGrouped: true
        )
        #expect(effects == [
            .resetSDK,
            .identify("user-b"),
            .remember("user-b"),
            .registerAndGroup,
        ])
    }

    @Test func firstSignInGroupsAfterIdentify() {
        #expect(
            HeyCatchBind.effects(for: .identify("user-a"), alreadyGrouped: false)
                == [.identify("user-a"), .remember("user-a"), .registerAndGroup]
        )
    }

    @Test func sameAccountDoesNotGroupAgain() {
        #expect(HeyCatchBind.effects(for: .none, alreadyGrouped: true).isEmpty)
    }

    @Test func firstGuestStillGroupsOnce() {
        #expect(HeyCatchBind.effects(for: .none, alreadyGrouped: false) == [.registerAndGroup])
    }

    @Test func startupDoesNotQueueGroupIdentify() throws {
        let file = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Saman/Core/Services/HeyCatch.swift")
        let text = try String(contentsOf: file, encoding: .utf8)
        let start = try #require(text.range(of: "static func start()"))
        let registerProject = try #require(text.range(of: "private static func registerProject()"))
        let startup = text[start.lowerBound..<registerProject.lowerBound]
        #expect(!startup.contains(".group("))
        #expect(!startup.contains("registerProject()"))
        #expect(text.components(separatedBy: "PostHogSDK.shared.group(").count == 2)
    }

    @Test func appRebindsBeforeAppOpenAndOnUserChange() throws {
        let app = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Saman/SamaanApp.swift")
        let text = try String(contentsOf: app, encoding: .utf8)
        let bindOnCheck = try #require(text.range(of: "HeyCatch.bind(userID: appEnv.auth.currentUserID)"))
        let release = try #require(text.range(of: "HeyCatch.releaseQueuedEvents()"))
        let appOpen = try #require(text.range(of: "Analytics.track(.appOpen)"))
        #expect(bindOnCheck.lowerBound < release.lowerBound)
        #expect(release.lowerBound < appOpen.lowerBound)
        #expect(text.contains("HeyCatch.bind(userID: userID)"))
        #expect(!text.contains("HeyCatch.identify("))
        #expect(!text.contains("HeyCatch.reset()"))
    }

    @Test func recipesScreenViewIsOnTheYoursShelf() throws {
        let file = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Saman/Features/Recipes/RecipesView.swift")
        let text = try String(contentsOf: file, encoding: .utf8)
        let yours = try #require(text.range(of: "case .yours:"))
        let screen = try #require(text.range(of: ".heycatchScreen(\"Recipes\")"))
        let family = try #require(text.range(of: "case .familyBook:"))
        #expect(yours.lowerBound < screen.lowerBound)
        #expect(screen.lowerBound < family.lowerBound)
        let stackClose = try #require(text.range(of: "        }\n    }\n\n    private var headerSubtitle"))
        #expect(screen.lowerBound < stackClose.lowerBound)
        #expect(!text[stackClose.lowerBound...].contains(".heycatchScreen(\"Recipes\")"))
    }

    @Test func productInteractionIsLinkedAndUserIDIncludesAnalytics() throws {
        let file = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Saman/PrivacyInfo.xcprivacy")
        let data = try Data(contentsOf: file)
        let plist = try #require(
            PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any]
        )
        #expect(plist["NSPrivacyTracking"] as? Bool == false)
        let types = try #require(plist["NSPrivacyCollectedDataTypes"] as? [[String: Any]])
        func entry(_ name: String) throws -> [String: Any] {
            try #require(types.first { $0["NSPrivacyCollectedDataType"] as? String == name })
        }
        let userID = try entry("NSPrivacyCollectedDataTypeUserID")
        #expect(userID["NSPrivacyCollectedDataTypeLinked"] as? Bool == true)
        #expect(userID["NSPrivacyCollectedDataTypeTracking"] as? Bool == false)
        let userPurposes = try #require(userID["NSPrivacyCollectedDataTypePurposes"] as? [String])
        #expect(userPurposes.contains("NSPrivacyCollectedDataTypePurposeAppFunctionality"))
        #expect(userPurposes.contains("NSPrivacyCollectedDataTypePurposeAnalytics"))
        let interaction = try entry("NSPrivacyCollectedDataTypeProductInteraction")
        #expect(interaction["NSPrivacyCollectedDataTypeLinked"] as? Bool == true)
        #expect(interaction["NSPrivacyCollectedDataTypeTracking"] as? Bool == false)
        let email = try entry("NSPrivacyCollectedDataTypeEmailAddress")
        let emailPurposes = try #require(email["NSPrivacyCollectedDataTypePurposes"] as? [String])
        #expect(!emailPurposes.contains("NSPrivacyCollectedDataTypePurposeAnalytics"))
    }

    @Test func heycatchCallSitesCarryNoUserContent() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Saman")
        let files = try FileManager.default.subpathsOfDirectory(atPath: root.path)
            .filter { $0.hasSuffix(".swift") }
        for relative in files {
            let text = try String(contentsOf: root.appendingPathComponent(relative), encoding: .utf8)
            for rawLine in text.split(separator: "\n", omittingEmptySubsequences: false) {
                let line = String(rawLine)
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                if trimmed.hasPrefix("//") || trimmed.hasPrefix("///") { continue }
                if line.contains("heycatchScreen(") && !line.contains("func heycatchScreen(") {
                    #expect(line.contains("heycatchScreen(\""), "\(relative): \(line)")
                    #expect(!line.contains("\\("), "\(relative): \(line)")
                    #expect(!line.contains("properties"), "\(relative): \(line)")
                }
                if line.contains("postHogScreenView(") {
                    #expect(Bool(false), "\(relative) still calls postHogScreenView")
                }
                if line.contains("PostHogSDK.shared.screen(") || line.contains("PostHogSDK.shared.capture(") {
                    #expect(relative.hasSuffix("HeyCatch.swift"), "\(relative): \(line)")
                }
                if line.contains("HeyCatch.capture(") {
                    let allowed = line.contains("HeyCatch.capture(\"")
                        || line.contains("HeyCatch.capture(event.rawValue)")
                    #expect(allowed, "\(relative): \(line)")
                    #expect(!line.contains("\\("), "\(relative): \(line)")
                    #expect(!line.contains("properties"), "\(relative): \(line)")
                }
                if line.contains("identify(userID:") {
                    let lowered = line.lowercased()
                    #expect(!lowered.contains("email"), "\(relative): \(line)")
                    #expect(!lowered.contains("transcript"), "\(relative): \(line)")
                    #expect(!lowered.contains("name"), "\(relative): \(line)")
                }
            }
        }
    }
}

@MainActor
struct AIProcessingConsentTests {
    @Test func consentCopyNamesAnthropic() {
        #expect(AIProcessingConsent.message.contains("Anthropic"))
        #expect(AIProcessingConsent.title.contains("Anthropic"))
    }

    @Test func captureViewGatesExtractionOnConsent() throws {
        let file = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Saman/Features/Recipes/RecipeCaptureView.swift")
        let text = try String(contentsOf: file, encoding: .utf8)
        let gate = try #require(text.range(of: "if !hasAIConsent {"))
        let call = try #require(text.range(of: "RecipeExtractionService.shared.extract("))
        #expect(gate.lowerBound < call.lowerBound)
    }
}
