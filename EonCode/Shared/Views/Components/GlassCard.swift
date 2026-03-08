import SwiftUI

// MARK: - Glass Card

struct GlassCard<Content: View>: View {
    let content: Content
    var cornerRadius: CGFloat = 16
    var padding: CGFloat = 16

    init(cornerRadius: CGFloat = 16, padding: CGFloat = 16, @ViewBuilder content: () -> Content) {
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
                            .strokeBorder(
                                LinearGradient(
                                    colors: [.white.opacity(0.3), .white.opacity(0.05)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                ),
                                lineWidth: 0.5
                            )
                    )
            )
    }
}

// MARK: - Glass Button

struct GlassButton: View {
    let title: String
    let icon: String?
    let action: () -> Void
    var isDestructive = false
    var isPrimary = false

    init(_ title: String, icon: String? = nil, isDestructive: Bool = false, isPrimary: Bool = false, action: @escaping () -> Void) {
        self.title = title
        self.icon = icon
        self.action = action
        self.isDestructive = isDestructive
        self.isPrimary = isPrimary
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if let icon = icon {
                    Image(systemName: icon)
                        .font(.system(size: 13, weight: .medium))
                }
                Text(title)
                    .font(.system(size: 14, weight: .medium))
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(isPrimary ? Color.accentNavi.opacity(0.3) :
                          isDestructive ? Color.red.opacity(0.2) :
                          Color.white.opacity(0.1))
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .strokeBorder(
                                isPrimary ? Color.accentNavi.opacity(0.5) :
                                isDestructive ? Color.red.opacity(0.4) :
                                Color.white.opacity(0.2),
                                lineWidth: 0.5
                            )
                    )
            )
            .foregroundColor(isDestructive ? .red : isPrimary ? .accentNavi : .primary)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Glass TextField

struct GlassTextField: View {
    let placeholder: String
    @Binding var text: String
    var isSecure = false
    var onSubmit: (() -> Void)? = nil

    var body: some View {
        Group {
            if isSecure {
                SecureField(placeholder, text: $text)
                    .onSubmit { onSubmit?() }
            } else {
                TextField(placeholder, text: $text)
                    .onSubmit { onSubmit?() }
            }
        }
        .font(.system(size: 14, design: .monospaced))
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color.inputBackground)
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .strokeBorder(Color.inputBorder, lineWidth: 0.5)
                )
        )
    }
}

// MARK: - Syntax Highlighter

struct SyntaxHighlighter {
    static func highlight(_ code: String, language: String) -> AttributedString {
        var result = AttributedString(code)

        // Basic token colorization
        let patterns: [(String, Color)] = tokenPatterns(for: language)

        for (pattern, color) in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern) else { continue }
            let nsCode = code as NSString
            let matches = regex.matches(in: code, range: NSRange(location: 0, length: nsCode.length))

            for match in matches {
                guard let range = Range(match.range, in: code),
                      let attrRange = Range(range, in: result)
                else { continue }
                result[attrRange].foregroundColor = color
            }
        }

        return result
    }

    private static func tokenPatterns(for language: String) -> [(String, Color)] {
        let swiftKeywords = ["import", "struct", "class", "enum", "func", "var", "let",
                              "if", "else", "for", "while", "switch", "case", "return",
                              "guard", "defer", "try", "catch", "throws", "async", "await",
                              "final", "static", "private", "public", "internal", "override",
                              "protocol", "extension", "init", "deinit", "self", "super",
                              "true", "false", "nil", "in", "is", "as"]

        switch language {
        case "swift":
            return [
                ("//[^\n]*", Color(red: 0.4, green: 0.6, blue: 0.4)),                          // comments
                ("\"[^\"]*\"", Color(red: 0.9, green: 0.6, blue: 0.4)),                         // strings
                ("\\b(\(swiftKeywords.joined(separator: "|")))\\b", Color(red: 0.8, green: 0.4, blue: 0.8)), // keywords
                ("\\b[0-9]+\\.?[0-9]*\\b", Color(red: 0.6, green: 0.8, blue: 1.0)),             // numbers
                ("@\\w+", Color(red: 0.9, green: 0.7, blue: 0.3)),                              // attributes
            ]
        case "python":
            return [
                ("#[^\n]*", Color(red: 0.4, green: 0.6, blue: 0.4)),
                ("\"\"\"[\\s\\S]*?\"\"\"", Color(red: 0.9, green: 0.6, blue: 0.4)),
                ("\"[^\"]*\"", Color(red: 0.9, green: 0.6, blue: 0.4)),
                ("\\b(def|class|import|from|if|else|elif|for|while|return|True|False|None|in|is|not|and|or|with|as|try|except|raise|pass|break|continue|lambda|yield)\\b", Color(red: 0.8, green: 0.4, blue: 0.8)),
                ("\\b[0-9]+\\b", Color(red: 0.6, green: 0.8, blue: 1.0)),
            ]
        case "javascript", "typescript":
            return [
                ("//[^\n]*", Color(red: 0.4, green: 0.6, blue: 0.4)),
                ("`[^`]*`", Color(red: 0.9, green: 0.6, blue: 0.4)),
                ("\"[^\"]*\"", Color(red: 0.9, green: 0.6, blue: 0.4)),
                ("'[^']*'", Color(red: 0.9, green: 0.6, blue: 0.4)),
                ("\\b(const|let|var|function|class|if|else|for|while|return|import|export|from|default|async|await|try|catch|new|this|typeof|instanceof|true|false|null|undefined)\\b", Color(red: 0.8, green: 0.4, blue: 0.8)),
            ]
        default:
            return [
                ("//[^\n]*|#[^\n]*", Color(red: 0.4, green: 0.6, blue: 0.4)),
                ("\"[^\"]*\"", Color(red: 0.9, green: 0.6, blue: 0.4)),
            ]
        }
    }
}

// MARK: - Previews

#Preview("GlassCard") {
    GlassCard(cornerRadius: 16, padding: 16) {
        VStack(alignment: .leading, spacing: 8) {
            Text("Navi")
                .font(.system(size: 18, weight: .bold))
            Text("AI-driven kodningsagent")
                .font(.system(size: 14))
                .foregroundColor(.secondary)
        }
    }
    .padding()
    .background(Color.black)
}

#Preview("GlassButton") {
    VStack(spacing: 12) {
        GlassButton("Primär", icon: "plus", isPrimary: true) {}
        GlassButton("Vanlig", icon: "gearshape") {}
        GlassButton("Destruktiv", icon: "trash", isDestructive: true) {}
    }
    .padding()
    .background(Color.black)
}

#Preview("GlassTextField") {
    VStack(spacing: 12) {
        GlassTextField(placeholder: "Projektnamn", text: .constant(""))
        GlassTextField(placeholder: "sk-ant-…", text: .constant("sk-ant-abc123"), isSecure: false)
    }
    .padding()
    .background(Color.black)
}

// MARK: - Large Text View (chunked rendering)

struct LargeTextView: View {
    let text: String
    var fontSize: CGFloat = 13
    var fontDesign: Font.Design = .monospaced
    var chunkSize: Int = 100 // lines per chunk

    private var chunks: [String] {
        let lines = text.components(separatedBy: "\n")
        return stride(from: 0, to: lines.count, by: chunkSize).map { i in
            lines[i..<min(i + chunkSize, lines.count)].joined(separator: "\n")
        }
    }

    var body: some View {
        LazyVStack(alignment: .leading, spacing: 0) {
            ForEach(Array(chunks.enumerated()), id: \.offset) { _, chunk in
                Text(chunk)
                    .font(.system(size: fontSize, design: fontDesign))
                    .foregroundColor(.primary)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}
