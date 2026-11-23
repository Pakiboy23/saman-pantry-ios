import Foundation
import Testing

/// Keeps PrivacyInfo.xcprivacy in step with the live App Privacy label
/// (docs/launch/app-store-metadata.md, "App Privacy label answers").
struct PrivacyManifestLabelTests {
    private func types() throws -> [[String: Any]] {
        let file = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Saman/PrivacyInfo.xcprivacy")
        let data = try Data(contentsOf: file)
        let plist = try #require(
            PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any]
        )
        return try #require(plist["NSPrivacyCollectedDataTypes"] as? [[String: Any]])
    }

    @Test func manifestListsExactlyTheLabelDataTypes() throws {
        let names = Set(try types().compactMap { $0["NSPrivacyCollectedDataType"] as? String })
        #expect(names == [
            "NSPrivacyCollectedDataTypeName",
            "NSPrivacyCollectedDataTypeEmailAddress",
            "NSPrivacyCollectedDataTypeUserID",
            "NSPrivacyCollectedDataTypeAudioData",
            "NSPrivacyCollectedDataTypeOtherUserContent",
            "NSPrivacyCollectedDataTypePurchaseHistory",
            "NSPrivacyCollectedDataTypeProductInteraction",
            "NSPrivacyCollectedDataTypeOtherUsageData",
        ])
    }

    @Test func everyTypeIsLinkedNotTrackedWithValidPurposes() throws {
        let allowed: Set<String> = [
            "NSPrivacyCollectedDataTypePurposeThirdPartyAdvertising",
            "NSPrivacyCollectedDataTypePurposeDeveloperAdvertising",
            "NSPrivacyCollectedDataTypePurposeAnalytics",
            "NSPrivacyCollectedDataTypePurposeProductPersonalization",
            "NSPrivacyCollectedDataTypePurposeAppFunctionality",
            "NSPrivacyCollectedDataTypePurposeOther",
        ]
        for entry in try types() {
            let name = entry["NSPrivacyCollectedDataType"] as? String ?? "?"
            #expect(entry["NSPrivacyCollectedDataTypeLinked"] as? Bool == true, "\(name)")
            #expect(entry["NSPrivacyCollectedDataTypeTracking"] as? Bool == false, "\(name)")
            let purposes = entry["NSPrivacyCollectedDataTypePurposes"] as? [String] ?? []
            #expect(!purposes.isEmpty, "\(name)")
            for purpose in purposes {
                #expect(allowed.contains(purpose), "\(name): \(purpose)")
            }
        }
    }
}
