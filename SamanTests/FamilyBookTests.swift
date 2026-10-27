import Foundation
import Testing
@testable import Saman

struct FamilyBookTests {
    @Test func joinLinkParsesOnlySamanpantryJoinPaths() {
        let token = String(repeating: "a1", count: 32)
        #expect(FamilyInviteLink.joinValue(from: URL(string: "https://samanpantry.com/join/\(token)")!) == token)
        #expect(FamilyInviteLink.joinValue(from: URL(string: "https://www.samanpantry.com/join/ABCD2345")!) == "ABCD2345")
        #expect(FamilyInviteLink.joinValue(from: URL(string: "https://evil.com/join/ABCD2345")!) == nil)
        #expect(FamilyInviteLink.joinValue(from: URL(string: "http://samanpantry.com/join/ABCD2345")!) == nil)
        #expect(FamilyInviteLink.joinValue(from: URL(string: "https://samanpantry.com/privacy")!) == nil)
        #expect(FamilyInviteLink.joinValue(from: URL(string: "samaan://auth-callback")!) == nil)
    }

    @Test func displayNameIsTrimmedAndCollapsed() {
        #expect(FamilyDisplayName.normalized("   Sam    Rivera  ") == "Sam Rivera")
        #expect(FamilyDisplayName.normalized("   ").isEmpty)
        #expect(FamilyNameSection.isValid(String(repeating: "x", count: 40)))
        #expect(!FamilyNameSection.isValid(String(repeating: "x", count: 41)))
        struct Fake: Error, CustomStringConvertible { let description: String }
        #expect(FamilyError.from(Fake(description: "hint: name_too_long")) == .nameTooLong)
    }

    @Test func codeEntryIsNormalized() {
        #expect(FamilyInviteLink.normalizedCode(" abcd-2345 ") == "ABCD2345")
    }

    @Test func memberFieldsNeverIncludeTranscript() {
        #expect(!FamilyRecipe.memberFieldKeys.contains("raw_transcript"))
    }

    @Test func serverHintsMapToPlainErrors() {
        struct Fake: Error, CustomStringConvertible { let description: String }
        #expect(FamilyError.from(Fake(description: "hint: pro_required")) == .proRequired)
        #expect(FamilyError.from(Fake(description: "hint: pro_required"), isProOnDevice: true) == .proSyncing)
        #expect(FamilyError.from(Fake(description: "family_full")) == .familyFull)
    }

    @Test func familyCopyFollowsBrandRules() {
        let all = FamilyCopy.all + [FamilyInvite(code: "ABCD2345", token: "t", expiresAt: .now).shareText]
        for line in all {
            #expect(!line.contains("\u{2014}"), "em dash in: \(line)")
            #expect(!line.contains("Pantry Pro"))
            for word in [" his ", " her ", " he ", " she "] {
                #expect(!" \(line.lowercased()) ".contains(word), "gendered: \(line)")
            }
        }
        #expect(FamilyCopy.paywallContext.contains("Samaan Pro"))
    }

    @Test func joinLinkSelectsRecipesTabOnRootView() throws {
        let file = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Saman/App/RootView.swift")
        let text = try String(contentsOf: file, encoding: .utf8)
        let rootChange = try #require(text.range(of: ".onChange(of: appEnv.familyJoinRequest)"))
        let tabShell = try #require(text.range(of: "private var tabShell: some View"))
        #expect(rootChange.lowerBound < tabShell.lowerBound)
        #expect(!text[tabShell.lowerBound...].contains("familyJoinRequest"))
    }

    @Test func savedCopyUsesPrivateCopiedSource() throws {
        let file = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Saman/Features/Recipes/FamilyViews.swift")
        let text = try String(contentsOf: file, encoding: .utf8)
        #expect(text.contains("sourceKind: .copied"))
        #expect(!text.contains("sourceKind: recipe.sourceUrl == nil ? .transcript : .url"))
        #expect(text.contains("presentPendingJoin"))
        #expect(text.contains("try await nameModel.saveIfChanged()"))
        #expect(!text.contains("try? await nameModel.saveIfChanged()"))
    }

    @Test func familyBooksMigrationKeepsCopiedSourcePrivateAndSurvivesAccountDelete() throws {
        let file = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("supabase/migrations/20261024000000_family_books.sql")
        let text = try String(contentsOf: file, encoding: .utf8)
        #expect(text.contains("check (source_kind in ('transcript', 'url', 'copied'))"))
        #expect(text.contains("if exists (select 1 from auth.users where id = old.user_id)"))
    }

    @Test func savedCopyDecodesAsExtractedRecipe() throws {
        let recipe = FamilyRecipe(
            familyId: UUID(), recipeId: UUID(), addedBy: nil, addedByLabel: "a cook",
            title: "Aloo keema", attribution: "Nani", steps: ["Fry onions"],
            ingredientPhrases: ["andaza namak"], sourceUrl: nil, addedAt: .now
        )
        let decoded = try JSONDecoder().decode(ExtractedRecipe.self, from: Data(recipe.copyExtractedJSON.utf8))
        #expect(decoded.title == "Aloo keema")
        #expect(decoded.ingredients.first?.originalPhrase == "andaza namak")
    }
}
