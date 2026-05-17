import SwiftUI

extension Font {
    /// Returns Cormorant Garamond at the specified size and weight.
    /// Available weights: .semibold, .bold (others fall back to .bold)
    static func cormorant(size: CGFloat, weight: Font.Weight = .bold) -> Font {
        let name: String
        switch weight {
        case .semibold:
            name = "CormorantGaramond-SemiBold"
        case .bold, .heavy, .black:
            name = "CormorantGaramond-Bold"
        default:
            // Fall back to Bold for weights we don't have
            name = "CormorantGaramond-Bold"
        }
        return .custom(name, size: size)
    }

    // MARK: - Presets

    /// Brand wordmark — "Samaan Pantry" display (34pt Bold)
    static let pantryWordmark = Font.cormorant(size: 34, weight: .bold)

    /// Large display headings (28pt Bold)
    static let pantryDisplay = Font.cormorant(size: 28, weight: .bold)

    /// Section headers (22pt SemiBold)
    static let pantrySectionHead = Font.cormorant(size: 22, weight: .semibold)
}
