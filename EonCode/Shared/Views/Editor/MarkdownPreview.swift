import SwiftUI

struct MarkdownPreview: View {
    let markdown: String

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                ForEach(Array(parseBlocks(markdown).enumerated()), id: \.offset) { _, block in
                    renderBlock(block)
                }
            }
            .padding()
        }
        .background(Color.chatBackground)
    }

    @ViewBuilder
    private func renderBlock(_ block: MarkdownBlock) -> some View {
        switch block {
        case .heading(let text, let level):
            Text(text)
                .font(headingFont(level))
                .fontWeight(.bold)
                .padding(.top, level == 1 ? 8 : 4)

        case .paragraph(let text):
            Text(parseInline(text))
                .font(.system(size: 14))
                .fixedSize(horizontal: false, vertical: true)

        case .code(let code, let lang):
            CodeBlockView(code: code, language: lang)

        case .bullet(let text):
            HStack(alignment: .top, spacing: 8) {
                Text("•")
                    .foregroundColor(.accentEon)
                Text(parseInline(text))
                    .font(.system(size: 14))
                    .fixedSize(horizontal: false, vertical: true)
            }

        case .divider:
            Divider().opacity(0.3)

        case .quote(let text):
            HStack(spacing: 0) {
                Rectangle()
                    .fill(Color.accentEon.opacity(0.5))
                    .frame(width: 3)
                Text(text)
                    .font(.system(size: 13))
                    .foregroundColor(.secondary)
                    .padding(.leading, 12)
            }
            .padding(.vertical, 4)
        }
    }

    private func headingFont(_ level: Int) -> Font {
        switch level {
        case 1: return .system(size: 24, weight: .bold)
        case 2: return .system(size: 20, weight: .bold)
        case 3: return .system(size: 17, weight: .semibold)
        default: return .system(size: 15, weight: .medium)
        }
    }

    private func parseInline(_ text: String) -> AttributedString {
        var result = AttributedString(text)

        // Bold **text**
        if let regex = try? NSRegularExpression(pattern: "\\*\\*(.+?)\\*\\*") {
            let matches = regex.matches(in: text, range: NSRange(text.startIndex..., in: text))
            for match in matches.reversed() {
                if let range = Range(match.range(at: 1), in: text),
                   let attrRange = Range(range, in: result) {
                    result[attrRange].font = .system(size: 14).bold()
                }
            }
        }

        // Inline code `code`
        if let regex = try? NSRegularExpression(pattern: "`(.+?)`") {
            let matches = regex.matches(in: text, range: NSRange(text.startIndex..., in: text))
            for match in matches.reversed() {
                if let range = Range(match.range(at: 1), in: text),
                   let attrRange = Range(range, in: result) {
                    result[attrRange].font = .system(size: 13, design: .monospaced)
                    result[attrRange].backgroundColor = .init(.codeBackground)
                }
            }
        }

        return result
    }

    private func parseBlocks(_ text: String) -> [MarkdownBlock] {
        var blocks: [MarkdownBlock] = []
        var lines = text.components(separatedBy: "\n")
        var i = 0

        while i < lines.count {
            let line = lines[i]

            if line.hasPrefix("---") || line.hasPrefix("===") {
                blocks.append(.divider)
            } else if line.hasPrefix("### ") {
                blocks.append(.heading(String(line.dropFirst(4)), level: 3))
            } else if line.hasPrefix("## ") {
                blocks.append(.heading(String(line.dropFirst(3)), level: 2))
            } else if line.hasPrefix("# ") {
                blocks.append(.heading(String(line.dropFirst(2)), level: 1))
            } else if line.hasPrefix("```") {
                let lang = String(line.dropFirst(3)).trimmed
                var code = ""
                i += 1
                while i < lines.count && !lines[i].hasPrefix("```") {
                    code += lines[i] + "\n"
                    i += 1
                }
                blocks.append(.code(code.trimmed, lang.isEmpty ? nil : lang))
            } else if line.hasPrefix("- ") || line.hasPrefix("* ") {
                blocks.append(.bullet(String(line.dropFirst(2))))
            } else if line.hasPrefix("> ") {
                blocks.append(.quote(String(line.dropFirst(2))))
            } else if !line.trimmed.isEmpty {
                blocks.append(.paragraph(line))
            }

            i += 1
        }

        return blocks
    }
}

enum MarkdownBlock {
    case heading(String, level: Int)
    case paragraph(String)
    case code(String, String?)
    case bullet(String)
    case divider
    case quote(String)
}

// MARK: - Previews

#Preview("MarkdownPreview") {
    MarkdownPreview(markdown: """
# Välkommen till Navi

Ett stycke med **fet text** och lite `inline-kod`.

## Funktioner

- Stödjer Swift, Python, JS och fler
- Parallella AI-workers
- iCloud-synk i realtid

```swift
struct HelloView: View {
    var body: some View {
        Text("Hej!")
    }
}
```

> "Koda smartare, inte hårdare."

---

Mer text efter avdelare.
""")
    .frame(width: 420, height: 600)
}
