import SwiftUI

// MARK: - NaviTheme
// Centralised design tokens. Claude iOS-inspired design: clean, minimal, sophisticated.
// Single source of truth for colors, typography, spacing, radii, animations.

enum NaviTheme {

    // MARK: - Claude-inspired Accent Colors

    /// Claude purple — sophisticated AI accent (#D4A373 warm beige, #2D2D2D dark)
    static let accent      = Color(red: 0.83, green: 0.64, blue: 0.45) // Warm beige/gold
    static let accentLight = Color(red: 0.90, green: 0.78, blue: 0.62)
    static let accentBg    = Color(red: 0.83, green: 0.64, blue: 0.45).opacity(0.08)
    static let accentBorder = Color(red: 0.83, green: 0.64, blue: 0.45).opacity(0.20)

    /// Dark mode accent (black/charcoal for dark theme)
    static let accentDark  = Color(red: 0.95, green: 0.95, blue: 0.95)
    static let accentDarkBg = Color.white.opacity(0.08)

    // MARK: - Surfaces (adaptive light/dark) - Claude style

    static var surface: Color { Color.chatBackground }
    static var surfaceSecondary: Color { Color.sidebarBackground }
    static var surfaceTertiary: Color {
        #if os(macOS)
        Color(NSColor.quaternaryLabelColor).opacity(0.2)
        #else
        Color(UIColor.tertiarySystemBackground)
        #endif
    }

    /// Claude-inspired: subtle surface tints
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

    /// Claude style: softer text hierarchy
    static var textTertiary: Color { Color.secondary.opacity(0.4) }

    // MARK: - Chat bubbles - Minimalist Claude style

    static var userBubble: Color  { Color.userBubble }
    static var assistantBubble: Color { .clear }

    /// Claude uses no bubbles for assistant - just clean text
    static var assistantMessageBg: Color { .clear }

    // MARK: - Code blocks

    /// Dark code block background — always dark regardless of app theme
    static let codeBG     = Color(red: 0.11, green: 0.11, blue: 0.12)
    static let codeHeader = Color(red: 0.07, green: 0.07, blue: 0.07)
    static let codeBorder = Color.white.opacity(0.06)

    // MARK: - Semantic Colors - Claude palette

    /// Success - muted green
    static let success = Color(red: 0.30, green: 0.69, blue: 0.31)
    static let successBg = Color(red: 0.30, green: 0.69, blue: 0.31).opacity(0.10)

    /// Warning - muted amber
    static let warning = Color(red: 1.0, green: 0.76, blue: 0.0)
    static let warningBg = Color(red: 1.0, green: 0.76, blue: 0.0).opacity(0.10)

    /// Error - muted red
    static let error = Color(red: 0.91, green: 0.30, blue: 0.24)
    static let errorBg = Color(red: 0.91, green: 0.30, blue: 0.24).opacity(0.10)

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

    // MARK: - Corner Radii - Softer, more sophisticated

    enum Radius {
        static let xs:     CGFloat = 4
        static let sm:     CGFloat = 8
        static let md:     CGFloat = 12
        static let lg:     CGFloat = 16
        static let xl:     CGFloat = 20
        static let bubble: CGFloat = 20
        static let pill:   CGFloat = 24
    }

    // Flat aliases
    static let cornerRadiusSmall:  CGFloat = 8
    static let cornerRadiusMedium: CGFloat = 12
    static let cornerRadiusLarge:  CGFloat = 18

    // MARK: - Typography - Clean, readable, Claude-style

    static func body(_ size: CGFloat = 15) -> Font {
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
        .system(size: size, weight: weight, design: .rounded)
    }

    /// Display - large titles
    static func display(_ size: CGFloat = 28, weight: Font.Weight = .bold) -> Font {
        .system(size: size, weight: weight)
    }

    // MARK: - Spring Animations - Smooth, subtle

    enum Spring {
        /// Fast, snappy — for small UI elements
        static let quick      = Animation.spring(response: 0.2, dampingFraction: 0.85)
        /// Responsive — for modals, sheets, sidebar slides
        static let responsive = Animation.spring(response: 0.3, dampingFraction: 0.8)
        /// Bouncy — for cards, animations
        static let bouncy     = Animation.spring(response: 0.35, dampingFraction: 0.7)
        /// Smooth — for content fade transitions
        static let smooth     = Animation.easeInOut(duration: 0.2)
        /// Instant - for immediate feedback
        static let instant    = Animation.linear(duration: 0.1)
    }

    // MARK: - Shadows - Subtle, sophisticated

    enum Shadow {
        static let small = NaviShadow(color: .black.opacity(0.05), radius: 4, x: 0, y: 2)
        static let medium = NaviShadow(color: .black.opacity(0.08), radius: 8, x: 0, y: 4)
        static let large = NaviShadow(color: .black.opacity(0.12), radius: 16, x: 0, y: 8)
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
