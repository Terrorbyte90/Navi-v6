import SwiftUI

// MARK: - NaviTheme
// Centralised design tokens. Claude iOS-inspired: warm, minimal, sophisticated.
// Terra cotta accent, cream backgrounds, clean typography.

enum NaviTheme {

    // MARK: - Claude iOS Accent Colors

    /// Terra cotta — Claude iOS primary accent (#da7756)
    static let accent      = Color(naviHex: "da7756")
    static let accentLight = Color(naviHex: "e8a08a")
    static let accentBg    = Color(naviHex: "da7756").opacity(0.10)
    static let accentBorder = Color(naviHex: "da7756").opacity(0.25)

    /// Dark mode accent — slightly lighter terra cotta for contrast
    static let accentDark  = Color(naviHex: "e8a08a")
    static let accentDarkBg = Color(naviHex: "da7756").opacity(0.12)

    // MARK: - Surfaces (Claude iOS style)

    static var surface: Color { Color.chatBackground }
    static var surfaceSecondary: Color { Color.sidebarBackground }
    static var surfaceTertiary: Color {
        #if os(macOS)
        Color(NSColor.quaternaryLabelColor).opacity(0.2)
        #else
        Color(UIColor.tertiarySystemBackground)
        #endif
    }

    static var surfaceElevated: Color {
        Color.primary.opacity(0.04)
    }

    static var surfaceCard: Color {
        #if os(iOS)
        Color(UIColor.secondarySystemBackground)
        #else
        Color(NSColor.controlBackgroundColor)
        #endif
    }

    // MARK: - Text

    static var textPrimary: Color   { .primary }
    static var textSecondary: Color { .secondary }
    static var textMuted: Color     { Color.secondary.opacity(0.55) }
    static var textTertiary: Color  { Color.secondary.opacity(0.4) }

    // MARK: - Chat bubbles — Claude iOS style

    /// User bubble: warm gray pill
    static var userBubble: Color  { Color.userBubble }
    /// Assistant: no bubble background (Claude style)
    static var assistantBubble: Color { .clear }
    static var assistantMessageBg: Color { .clear }

    // MARK: - Code blocks — always dark

    static let codeBG     = Color(red: 0.10, green: 0.10, blue: 0.11)
    static let codeHeader = Color(red: 0.06, green: 0.06, blue: 0.07)
    static let codeBorder = Color.white.opacity(0.06)

    // MARK: - Semantic Colors

    static let success   = Color(naviHex: "4CAF50")
    static let successBg = Color(naviHex: "4CAF50").opacity(0.10)
    static let warning   = Color(naviHex: "FF9800")
    static let warningBg = Color(naviHex: "FF9800").opacity(0.10)
    static let error     = Color(naviHex: "E53935")
    static let errorBg   = Color(naviHex: "E53935").opacity(0.10)

    // MARK: - Glass

    /// Adaptive glass tint for iOS 26+ liquid glass effects
    static var glassTint: Color {
        #if os(iOS)
        Color(UIColor { $0.userInterfaceStyle == .dark
            ? UIColor(white: 1, alpha: 0.06)
            : UIColor(white: 0, alpha: 0.03)
        })
        #else
        Color.white.opacity(0.04)
        #endif
    }

    // MARK: - Spacing

    enum Spacing {
        static let xxs: CGFloat = 2
        static let xs:  CGFloat = 4
        static let sm:  CGFloat = 8
        static let md:  CGFloat = 16
        static let lg:  CGFloat = 24
        static let xl:  CGFloat = 32
        static let xxl: CGFloat = 48
    }

    static let messagePaddingH: CGFloat = 16
    static let messagePaddingV: CGFloat = 8
    static let messageSpacing:  CGFloat = 6
    static let sidebarItemPaddingH: CGFloat = 12
    static let sidebarItemPaddingV: CGFloat = 7

    // MARK: - Corner Radii

    enum Radius {
        static let xs:     CGFloat = 4
        static let sm:     CGFloat = 8
        static let md:     CGFloat = 12
        static let lg:     CGFloat = 16
        static let xl:     CGFloat = 20
        static let bubble: CGFloat = 20
        static let pill:   CGFloat = 24
    }

    static let cornerRadiusSmall:  CGFloat = 8
    static let cornerRadiusMedium: CGFloat = 12
    static let cornerRadiusLarge:  CGFloat = 18

    // MARK: - Typography — Claude iOS: clean system fonts

    static func body(_ size: CGFloat = 15.5) -> Font {
        .system(size: size, weight: .regular)
    }
    static func bodyRounded(_ size: CGFloat = 15) -> Font {
        .system(size: size, weight: .regular, design: .rounded)
    }
    static func label(_ size: CGFloat = 13, weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight)
    }
    static func caption(_ size: CGFloat = 11, weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight)
    }
    static func mono(_ size: CGFloat = 13, weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight, design: .monospaced)
    }
    static func heading(_ size: CGFloat = 17, weight: Font.Weight = .semibold) -> Font {
        .system(size: size, weight: weight)
    }
    static func display(_ size: CGFloat = 28, weight: Font.Weight = .bold) -> Font {
        .system(size: size, weight: weight)
    }

    // MARK: - Spring Animations

    enum Spring {
        static let quick      = Animation.spring(response: 0.2, dampingFraction: 0.85)
        static let responsive = Animation.spring(response: 0.3, dampingFraction: 0.8)
        static let bouncy     = Animation.spring(response: 0.35, dampingFraction: 0.7)
        static let smooth     = Animation.easeInOut(duration: 0.2)
        static let instant    = Animation.linear(duration: 0.1)
    }

    // MARK: - Shadows

    enum Shadow {
        static let small  = NaviShadow(color: .black.opacity(0.05), radius: 4, x: 0, y: 2)
        static let medium = NaviShadow(color: .black.opacity(0.08), radius: 8, x: 0, y: 4)
        static let large  = NaviShadow(color: .black.opacity(0.12), radius: 16, x: 0, y: 8)
    }
}

// MARK: - Shadow helper

struct NaviShadow {
    let color: Color
    let radius: CGFloat
    let x: CGFloat
    let y: CGFloat

    var modifier: some ViewModifier {
        NaviShadowModifier(shadow: self)
    }
}

struct NaviShadowModifier: ViewModifier {
    let shadow: NaviShadow

    func body(content: Content) -> some View {
        content
            .shadow(
                color: shadow.color,
                radius: shadow.radius,
                x: shadow.x,
                y: shadow.y
            )
    }
}

extension View {
    func navyShadow(_ shadow: NaviShadow) -> some View {
        modifier(NaviShadowModifier(shadow: shadow))
    }
}

// MARK: - Color(naviHex:) init

extension Color {
    /// Initialize a Color from a hex string such as "#7C5CBF" or "7C5CBF".
    init(naviHex hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 3:  (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6:  (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8:  (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default: (a, r, g, b) = (255, 200, 200, 200)
        }
        self.init(
            .sRGB,
            red:     Double(r) / 255,
            green:   Double(g) / 255,
            blue:    Double(b) / 255,
            opacity: Double(a) / 255
        )
    }
}
