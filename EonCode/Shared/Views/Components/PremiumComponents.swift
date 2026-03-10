import SwiftUI

// MARK: - Premium Visual Components
// Claude iOS-inspired: terra cotta accents, warm surfaces, glass effects

// MARK: - Gradient Orb

struct GradientOrb: View {
    var size: CGFloat = 120
    var colors: [Color] = [
        Color.accentNavi,
        Color(naviHex: "c85a3a"),
        Color(naviHex: "b04a2e")
    ]

    @State private var isAnimating = false

    var body: some View {
        ZStack {
            Circle()
                .fill(
                    RadialGradient(
                        colors: [colors[0].opacity(0.3), colors[0].opacity(0)],
                        center: .center,
                        startRadius: 0,
                        endRadius: size / 2
                    )
                )
                .frame(width: size * 1.5, height: size * 1.5)
                .scaleEffect(isAnimating ? 1.1 : 1.0)
                .opacity(isAnimating ? 0.6 : 0.4)

            Circle()
                .fill(
                    LinearGradient(
                        colors: colors,
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(width: size, height: size)
                .scaleEffect(isAnimating ? 1.05 : 1.0)

            Circle()
                .fill(
                    RadialGradient(
                        colors: [.white.opacity(0.3), .clear],
                        center: .topLeading,
                        startRadius: 0,
                        endRadius: size / 2
                    )
                )
                .frame(width: size * 0.6, height: size * 0.6)
                .offset(x: -size * 0.15, y: -size * 0.15)
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 2).repeatForever(autoreverses: true)) {
                isAnimating = true
            }
        }
    }
}

// MARK: - Premium Card

struct PremiumCard<Content: View>: View {
    let content: Content
    var cornerRadius: CGFloat = 20
    var padding: CGFloat = 20
    var hasGradient: Bool = false

    init(cornerRadius: CGFloat = 20, padding: CGFloat = 20, hasGradient: Bool = false, @ViewBuilder content: () -> Content) {
        self.cornerRadius = cornerRadius
        self.padding = padding
        self.hasGradient = hasGradient
        self.content = content()
    }

    var body: some View {
        content
            .padding(padding)
            .background(
                RoundedRectangle(cornerRadius: cornerRadius)
                    .fill(hasGradient ?
                        LinearGradient(
                            colors: [
                                Color.primary.opacity(0.05),
                                Color.primary.opacity(0.02)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ) :
                        Color.primary.opacity(0.04))
                    .overlay(
                        RoundedRectangle(cornerRadius: cornerRadius)
                            .strokeBorder(
                                LinearGradient(
                                    colors: [
                                        Color.primary.opacity(0.1),
                                        Color.primary.opacity(0.03)
                                    ],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                ),
                                lineWidth: 0.5
                            )
                    )
                    .shadow(color: .black.opacity(0.06), radius: 16, x: 0, y: 8)
            )
    }
}

// MARK: - Premium Button

struct PremiumButton: View {
    let title: String
    let icon: String?
    let action: () -> Void
    var style: PremiumButtonStyle = .primary

    enum PremiumButtonStyle {
        case primary, secondary, ghost, destructive
    }

    @State private var isPressed = false
    @State private var isHovered = false

    var body: some View {
        Button(action: {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) {
                isPressed = true
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                isPressed = false
                action()
            }
        }) {
            HStack(spacing: 8) {
                if let icon = icon {
                    Image(systemName: icon)
                        .font(.system(size: 14, weight: .semibold))
                }
                Text(title)
                    .font(.system(size: 14, weight: .semibold))
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 12)
            .background(backgroundGradient)
            .foregroundColor(foregroundColor)
            .cornerRadius(14)
            .scaleEffect(isPressed ? 0.96 : 1.0)
            .shadow(color: shadowColor, radius: isHovered ? 12 : 6, x: 0, y: isHovered ? 6 : 3)
            .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isHovered)
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            isHovered = hovering
        }
    }

    private var backgroundGradient: some ShapeStyle {
        switch style {
        case .primary:
            return LinearGradient(
                colors: [Color.accentNavi, Color(naviHex: "c85a3a")],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        case .secondary:
            return LinearGradient(
                colors: [Color.primary.opacity(0.1), Color.primary.opacity(0.05)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        case .ghost:
            return Color.clear
        case .destructive:
            return LinearGradient(
                colors: [NaviTheme.error.opacity(0.8), NaviTheme.error.opacity(0.6)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }
    }

    private var foregroundColor: Color {
        switch style {
        case .primary, .destructive: return .white
        case .secondary, .ghost: return .primary
        }
    }

    private var shadowColor: Color {
        switch style {
        case .primary: return Color.accentNavi.opacity(0.3)
        case .secondary: return Color.black.opacity(0.05)
        case .ghost: return Color.clear
        case .destructive: return NaviTheme.error.opacity(0.3)
        }
    }
}

// MARK: - Floating Action Button

struct FloatingActionButton: View {
    let icon: String
    let action: () -> Void
    var size: CGFloat = 56
    var style: PremiumButton.PremiumButtonStyle = .primary

    @State private var isPressed = false

    var body: some View {
        Button(action: {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.5)) {
                isPressed = true
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                isPressed = false
                action()
            }
        }) {
            ZStack {
                Circle()
                    .fill(backgroundGradient)
                    .frame(width: size, height: size)
                    .shadow(color: shadowColor, radius: 16, x: 0, y: 8)

                Image(systemName: icon)
                    .font(.system(size: size * 0.4, weight: .semibold))
                    .foregroundColor(foregroundColor)
            }
            .scaleEffect(isPressed ? 0.9 : 1.0)
        }
        .buttonStyle(.plain)
    }

    private var backgroundGradient: some ShapeStyle {
        switch style {
        case .primary:
            return LinearGradient(
                colors: [Color.accentNavi, Color(naviHex: "c85a3a")],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        default:
            return Color.primary.opacity(0.08)
        }
    }

    private var foregroundColor: Color {
        switch style {
        case .primary: return .white
        default: return .primary
        }
    }

    private var shadowColor: Color {
        switch style {
        case .primary: return Color.accentNavi.opacity(0.4)
        default: return Color.black.opacity(0.1)
        }
    }
}

// MARK: - Modern TextField

struct ModernTextField: View {
    let placeholder: String
    @Binding var text: String
    var icon: String? = nil
    var isSecure: Bool = false
    var onSubmit: (() -> Void)? = nil

    @FocusState private var isFocused: Bool

    var body: some View {
        HStack(spacing: 12) {
            if let icon = icon {
                Image(systemName: icon)
                    .font(.system(size: 14))
                    .foregroundColor(isFocused ? .accentNavi : .secondary.opacity(0.5))
            }

            Group {
                if isSecure {
                    SecureField(placeholder, text: $text)
                        .onSubmit { onSubmit?() }
                } else {
                    TextField(placeholder, text: $text)
                        .onSubmit { onSubmit?() }
                }
            }
            .font(.system(size: 15))
            .focused($isFocused)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(Color.primary.opacity(0.03))
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
                        .strokeBorder(
                            isFocused ?
                            LinearGradient(
                                colors: [Color.accentNavi, Color(naviHex: "c85a3a")],
                                startPoint: .leading,
                                endPoint: .trailing
                            ) :
                            Color.primary.opacity(0.08),
                            lineWidth: isFocused ? 1.5 : 0.5
                        )
                )
        )
        .animation(.spring(response: 0.3), value: isFocused)
    }
}

// MARK: - Badge

struct PremiumBadge: View {
    let text: String
    var style: BadgeStyle = .default

    enum BadgeStyle {
        case `default`, success, warning, error, accent

        var colors: (bg: Color, text: Color) {
            switch self {
            case .default: return (Color.primary.opacity(0.08), Color.primary.opacity(0.7))
            case .success: return (NaviTheme.successBg, NaviTheme.success)
            case .warning: return (NaviTheme.warningBg, NaviTheme.warning)
            case .error: return (NaviTheme.errorBg, NaviTheme.error)
            case .accent: return (NaviTheme.accentBg, NaviTheme.accent)
            }
        }
    }

    var body: some View {
        Text(text)
            .font(.system(size: 11, weight: .medium))
            .foregroundColor(style.colors.text)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(
                Capsule()
                    .fill(style.colors.bg)
            )
    }
}

// MARK: - Shimmer Effect

struct ShimmerModifier: ViewModifier {
    @State private var phase: CGFloat = 0

    func body(content: Content) -> some View {
        content
            .overlay(
                GeometryReader { geometry in
                    LinearGradient(
                        colors: [
                            .clear,
                            .white.opacity(0.3),
                            .clear
                        ],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                    .frame(width: geometry.size.width * 2)
                    .offset(x: -geometry.size.width + (phase * geometry.size.width * 3))
                }
            )
            .mask(content)
            .onAppear {
                withAnimation(.linear(duration: 1.5).repeatForever(autoreverses: false)) {
                    phase = 1
                }
            }
    }
}

extension View {
    func shimmer() -> some View {
        modifier(ShimmerModifier())
    }
}

// MARK: - Loading Dots

struct LoadingDots: View {
    var count: Int = 3
    var size: CGFloat = 8
    var color: Color = .accentNavi

    @State private var animating = false

    var body: some View {
        HStack(spacing: 4) {
            ForEach(0..<count, id: \.self) { index in
                Circle()
                    .fill(color)
                    .frame(width: size, height: size)
                    .scaleEffect(animating ? 1.0 : 0.5)
                    .animation(
                        .easeInOut(duration: 0.6)
                        .repeatForever()
                        .delay(Double(index) * 0.15),
                        value: animating
                    )
            }
        }
        .onAppear {
            animating = true
        }
    }
}

// MARK: - Animated Gradient Background

struct AnimatedGradientBackground: View {
    var colors: [Color] = [
        Color(naviHex: "F5F5F0"),
        Color(naviHex: "EBE9E4"),
        Color(naviHex: "E0DDD7")
    ]

    @State private var animate = false

    var body: some View {
        LinearGradient(
            colors: animate ? colors : colors.reversed(),
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        .onAppear {
            withAnimation(.easeInOut(duration: 5).repeatForever(autoreverses: true)) {
                animate = true
            }
        }
    }
}

// MARK: - Parallax Card

struct ParallaxCard<Content: View>: View {
    let content: Content
    var height: CGFloat = 200

    @State private var offset: CGSize = .zero

    var body: some View {
        content
            .frame(height: height)
            .clipped()
            .offset(y: offset.height * 0.1)
            .scaleEffect(1 + (abs(offset.width) + abs(offset.height)) * 0.001)
            .gesture(
                DragGesture()
                    .onChanged { value in
                        offset = value.translation
                    }
                    .onEnded { _ in
                        withAnimation(.spring()) {
                            offset = .zero
                        }
                    }
            )
    }
}

// MARK: - Glass Morphism Container

struct GlassMorphismContainer<Content: View>: View {
    let content: Content
    var cornerRadius: CGFloat = 24
    var padding: CGFloat = 24

    init(cornerRadius: CGFloat = 24, padding: CGFloat = 24, @ViewBuilder content: () -> Content) {
        self.cornerRadius = cornerRadius
        self.padding = padding
        self.content = content()
    }

    var body: some View {
        content
            .padding(padding)
            .background(
                RoundedRectangle(cornerRadius: cornerRadius)
                    .fill(.ultraThinMaterial)
                    .overlay(
                        RoundedRectangle(cornerRadius: cornerRadius)
                            .fill(
                                LinearGradient(
                                    colors: [.white.opacity(0.3), .clear],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: cornerRadius)
                            .strokeBorder(.white.opacity(0.2), lineWidth: 0.5)
                    )
            )
    }
}

// MARK: - Separator with Gradient

struct GradientSeparator: View {
    var height: CGFloat = 0.5

    var body: some View {
        LinearGradient(
            colors: [.clear, Color.primary.opacity(0.1), .clear],
            startPoint: .leading,
            endPoint: .trailing
        )
        .frame(height: height)
    }
}

// MARK: - Animated Icon Button

struct AnimatedIconButton: View {
    let icon: String
    let action: () -> Void
    var size: CGFloat = 40
    var style: PremiumButton.PremiumButtonStyle = .ghost

    @State private var isPressed = false
    @State private var isHovered = false

    var body: some View {
        Button(action: {
            withAnimation(.spring(response: 0.2, dampingFraction: 0.5)) {
                isPressed = true
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                isPressed = false
                action()
            }
        }) {
            ZStack {
                Circle()
                    .fill(style == .primary ?
                          LinearGradient(
                            colors: [Color.accentNavi, Color(naviHex: "c85a3a")],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                          ) :
                          Color.primary.opacity(isHovered ? 0.08 : 0.04))
                    .frame(width: size, height: size)

                Image(systemName: icon)
                    .font(.system(size: size * 0.4, weight: .medium))
                    .foregroundColor(style == .primary ? .white : Color.primary.opacity(0.7))
            }
            .scaleEffect(isPressed ? 0.9 : 1.0)
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            isHovered = hovering
        }
    }
}

// MARK: - Avatar View

struct PremiumAvatar: View {
    let name: String
    var size: CGFloat = 40
    var style: AvatarStyle = .gradient

    enum AvatarStyle {
        case gradient, solid, minimal
    }

    var body: some View {
        ZStack {
            switch style {
            case .gradient:
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [Color.accentNavi, Color(naviHex: "c85a3a")],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: size, height: size)
                    .shadow(color: Color.accentNavi.opacity(0.3), radius: 8, x: 0, y: 4)

            case .solid:
                Circle()
                    .fill(Color.primary.opacity(0.1))
                    .frame(width: size, height: size)

            case .minimal:
                Circle()
                    .fill(Color.primary.opacity(0.06))
                    .frame(width: size, height: size)
            }

            Text(initials)
                .font(.system(size: size * 0.4, weight: .semibold))
                .foregroundColor(style == .gradient ? .white : Color.primary.opacity(0.6))
        }
    }

    private var initials: String {
        let components = name.components(separatedBy: " ")
        let first = components.first?.prefix(1) ?? ""
        let last = components.count > 1 ? components.last?.prefix(1) ?? "" : ""
        return "\(first)\(last)".uppercased()
    }
}

// MARK: - Skeleton Loader

struct SkeletonLoader: View {
    var width: CGFloat? = nil
    var height: CGFloat = 20

    var body: some View {
        RoundedRectangle(cornerRadius: 6)
            .fill(Color.primary.opacity(0.08))
            .frame(width: width, height: height)
            .shimmer()
    }
}

// MARK: - Previews

#Preview("Gradient Orb") {
    GradientOrb(size: 120)
        .padding()
        .background(Color.chatBackground)
}

#Preview("Premium Card") {
    PremiumCard(hasGradient: true) {
        VStack(alignment: .leading, spacing: 8) {
            Text("Välkommen till Navi")
                .font(.system(size: 20, weight: .bold))
            Text("Din AI-kodningsassistent")
                .font(.system(size: 14))
                .foregroundColor(.secondary)
        }
    }
    .padding()
}

#Preview("Premium Buttons") {
    VStack(spacing: 16) {
        PremiumButton(title: "Kom igång", icon: "arrow.right", action: {})
        PremiumButton(title: "Läs mer", icon: "book", style: .secondary, action: {})
        PremiumButton(title: "Avbryt", style: .ghost, action: {})
        PremiumButton(title: "Ta bort", icon: "trash", style: .destructive, action: {})
    }
    .padding()
}

#Preview("Floating Action Button") {
    ZStack {
        Color.chatBackground
        FloatingActionButton(icon: "plus", action: {})
    }
}

#Preview("Modern TextField") {
    VStack(spacing: 16) {
        ModernTextField(placeholder: "Enter your name", text: .constant(""), icon: "person")
        ModernTextField(placeholder: "Password", text: .constant(""), icon: "lock", isSecure: true)
    }
    .padding()
}

#Preview("Badges") {
    HStack(spacing: 8) {
        PremiumBadge(text: "New")
        PremiumBadge(text: "Success", style: .success)
        PremiumBadge(text: "Warning", style: .warning)
        PremiumBadge(text: "Error", style: .error)
        PremiumBadge(text: "Featured", style: .accent)
    }
    .padding()
}

#Preview("Loading Dots") {
    LoadingDots()
        .padding()
}

#Preview("Avatar") {
    HStack(spacing: 16) {
        PremiumAvatar(name: "Ted Svärd", size: 48, style: .gradient)
        PremiumAvatar(name: "Ted Svärd", size: 48, style: .solid)
        PremiumAvatar(name: "Ted Svärd", size: 48, style: .minimal)
    }
    .padding()
}
