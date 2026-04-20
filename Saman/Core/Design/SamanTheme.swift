import SwiftUI

// MARK: - Colors

extension Color {
    static let samanBg           = Color(hex: "FAF6EF")
    static let samanCard         = Color(hex: "F2EBE0")
    static let samanDeep         = Color(hex: "E8DDD0")
    static let samanPrimary      = Color(hex: "1C0F00")
    static let samanSecondary    = Color(hex: "5C4A35")
    static let samanMuted        = Color(hex: "9A8472")
    static let samanAccent       = Color(hex: "C67E2A")
    static let samanAccentLight  = Color(hex: "F5E6CC")
    static let samanBorder       = Color(red: 28/255, green: 15/255, blue: 0, opacity: 0.12)
    static let samanRed          = Color(hex: "C0392B")
    static let samanGreen        = Color(hex: "27795A")

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
    static func cormorant(_ size: CGFloat) -> Font {
        .custom("CormorantGaramond-Bold", size: size, relativeTo: .title)
    }
    /// Cormorant Garamond SemiBold — secondary display
    static func cormorantSemiBold(_ size: CGFloat) -> Font {
        .custom("CormorantGaramond-SemiBold", size: size, relativeTo: .body)
    }
    /// SF Mono — quantities and numbers
    static func samanMono(_ size: CGFloat) -> Font {
        .system(size: size, design: .monospaced)
    }
}

// MARK: - Spacing & Radii

enum Saman {
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

struct SamanPrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 14, weight: .semibold))
            .foregroundStyle(Color.samanPrimary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 15)
            .background(
                configuration.isPressed ? Color.samanAccent.opacity(0.75) : Color.samanAccent,
                in: RoundedRectangle(cornerRadius: Saman.Radius.md)
            )
    }
}

struct SamanSecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 14, weight: .medium))
            .foregroundStyle(Color.samanAccent)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 15)
            .background(Color.samanAccentLight, in: RoundedRectangle(cornerRadius: Saman.Radius.md))
            .overlay(
                RoundedRectangle(cornerRadius: Saman.Radius.md)
                    .stroke(Color.samanAccent.opacity(0.4), lineWidth: 1)
            )
    }
}

extension Button {
    func samanPrimary() -> some View {
        self.buttonStyle(SamanPrimaryButtonStyle())
    }
    func samanSecondary() -> some View {
        self.buttonStyle(SamanSecondaryButtonStyle())
    }
}

// MARK: - View Modifiers

extension View {
    /// Standard warm card background
    func samanCard(radius: CGFloat = Saman.Radius.md) -> some View {
        self
            .background(Color.samanCard, in: RoundedRectangle(cornerRadius: radius))
            .overlay(RoundedRectangle(cornerRadius: radius).stroke(Color.samanBorder, lineWidth: 1))
    }
}
