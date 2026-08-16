import SwiftUI

extension Color {
    /// Low-stock status color (brass / masala). Maps to accentMasala asset.
    static let samaanBrass = Color.accentMasala

    /// Hex initializer for backward compatibility
    init(hex: String) {
        var value: UInt64 = 0
        Scanner(string: hex.trimmingCharacters(in: .alphanumerics.inverted)).scanHexInt64(&value)
        self.init(
            red:   Double((value >> 16) & 0xFF) / 255,
            green: Double((value >>  8) & 0xFF) / 255,
            blue:  Double( value        & 0xFF) / 255
        )
    }
}

// MARK: - Typography

extension Font {
    /// Cormorant Garamond Bold — wordmark & display headings
    @available(*, deprecated, message: "Use Font.cormorant(size:weight:) or presets like .pantryWordmark")
    static func cormorant(_ size: CGFloat) -> Font {
        .custom("CormorantGaramond-Bold", size: size, relativeTo: .title)
    }
    /// Cormorant Garamond SemiBold — secondary display
    @available(*, deprecated, message: "Use Font.cormorant(size:weight:) with .semibold")
    static func cormorantSemiBold(_ size: CGFloat) -> Font {
        .custom("CormorantGaramond-SemiBold", size: size, relativeTo: .body)
    }
    /// SF Mono — quantities and numbers
    static func samaanMono(_ size: CGFloat) -> Font {
        .system(size: size, design: .monospaced)
    }
}

// MARK: - Spacing & Radii

enum Samaan {
    enum Space {
        static let xs: CGFloat = 4
        static let sm: CGFloat = 8
        static let md: CGFloat = 16
        static let lg: CGFloat = 24
        static let xl: CGFloat = 32
    }
    enum Radius {
        static let sm: CGFloat = 8
        static let md: CGFloat = 12
        static let lg: CGFloat = 16
        static let pill: CGFloat = 100
    }
}

// MARK: - Button Styles

struct SamaanPrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 14, weight: .semibold))
            .foregroundStyle(Color.surfaceDoodh)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 15)
            .background(
                configuration.isPressed ? Color.brandSaagDeep : Color.brandSaag,
                in: RoundedRectangle(cornerRadius: Samaan.Radius.md)
            )
    }
}

struct SamaanSecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 14, weight: .medium))
            .foregroundStyle(Color.brandSaag)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 15)
            .background(Color.brandSaagSoft.opacity(0.2), in: RoundedRectangle(cornerRadius: Samaan.Radius.md))
            .overlay(
                RoundedRectangle(cornerRadius: Samaan.Radius.md)
                    .stroke(Color.brandSaag.opacity(0.4), lineWidth: 1)
            )
    }
}

extension Button {
    func samaanPrimary() -> some View {
        self.buttonStyle(SamaanPrimaryButtonStyle())
    }
    func samaanSecondary() -> some View {
        self.buttonStyle(SamaanSecondaryButtonStyle())
    }
}

// MARK: - View Modifiers

extension View {
    /// Standard warm card background
    func samaanCard(radius: CGFloat = Samaan.Radius.md) -> some View {
        self
            .background(Color.surfaceMalai, in: RoundedRectangle(cornerRadius: radius))
            .overlay(RoundedRectangle(cornerRadius: radius).stroke(Color.borderAkhrotSoft.opacity(0.5), lineWidth: 1))
    }
}
