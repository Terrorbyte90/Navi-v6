import SwiftUI

// MARK: - NaviTheme
// Centralised design tokens. Inspired by Claude's clean, minimal aesthetic.
// Single source of truth for colors, typography, spacing, radii, animations.
// Usage: NaviTheme.accent, NaviTheme.Spacing.md, NaviTheme.Spring.responsive

enum NaviTheme {

    // MARK: - Accent

    /// Deep purple — Claude-inspired primary accent (#7C5CBF)
    static let accent      = Color(naviHex: "#7C5CBF")
    static let accentLight = Color(naviHex: "#9B7FD4")
    static let accentBg    = Color(naviHex: "#7C5CBF").opacity(0.08)
    static let accentBorder = Color(naviHex: "#7C5CBF").opacity(0.20)

    // MARK: - Surfaces (adaptive light/dark)

    static var surface: Color { Color.chatBackground }
    static var surfaceSecondary: Color { Color.sidebarBackground }
    static var surfaceTertiary: Color {
        #if os(macOS)
        Color(NSColor.quaternaryLabelColor).opacity(0.2)
        #else
        Color(UIColor.tertiarySystemBackground)
        #endif
    }

    // MARK: - Text

    static var textPrimary: Color   { .primary }
    static var textSecondary: Color { .secondary }
    static var textMuted: Color     { Color.secondary.opacity(0.55) }

    // MARK: - Chat bubbles

    static var userBubble: Color  { Color.userBubble }
    static var assistantBubble: Color { .clear }

    // MARK: - Code blocks

    /// Dark code block background — always dark regardless of app theme
    static let codeBG     = Color(red: 0.11, green: 0.11, blue: 0.12)
    static let codeHeader = Color(red: 0.07, green: 0.07, blue: 0.07)
    static let codeBorder = Color.white.opacity(0.06)

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

    // Flat aliases for common values
    static let messagePaddingH: CGFloat = 16
    static let messagePaddingV: CGFloat = 8
    static let messageSpacing:  CGFloat = 6
    static let sidebarItemPaddingH: CGFloat = 12
    static let sidebarItemPaddingV: CGFloat = 7

    // MARK: - Corner Radii

    enum Radius {
        static let xs:     CGFloat = 6
        static let sm:     CGFloat = 8
        static let md:     CGFloat = 12
        static let lg:     CGFloat = 16
        static let bubble: CGFloat = 18
        static let pill:   CGFloat = 22
    }

    // Flat aliases
    static let cornerRadiusSmall:  CGFloat = 8
    static let cornerRadiusMedium: CGFloat = 12
    static let cornerRadiusLarge:  CGFloat = 18

    // MARK: - Typography

    static func body(_ size: CGFloat = 15.5) -> Font {
        .system(size: size)
    }
    static func bodyRounded(_ size: CGFloat = 15.5) -> Font {
        .system(size: size, design: .rounded)
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
        .system(size: size, weight: weight, design: .rounded)
    }

    // MARK: - Spring Animations

    enum Spring {
        /// Fast, snappy — for small UI elements (badges, toggles)
        static let quick      = Animation.spring(response: 0.25, dampingFraction: 0.90)
        /// Responsive — for modals, sheets, sidebar slides
        static let responsive = Animation.spring(response: 0.30, dampingFraction: 0.85)
        /// Bouncy — for cards, orbs, live activity elements
        static let bouncy     = Animation.spring(response: 0.40, dampingFraction: 0.70)
        /// Smooth — for content fade transitions
        static let smooth     = Animation.easeInOut(duration: 0.25)
    }
}

// MARK: - Color(naviHex:) init
// Separate named init to avoid ambiguity with any future Color(hex:) extensions.

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
