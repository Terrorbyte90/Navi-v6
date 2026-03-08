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
                    .foregroundColor(.accentNavi)
                Text(parseInline(text))
                    .font(.system(size: 14))
                    .fixedSize(horizontal: false, vertical: true)
            }

        case .divider:
            Divider().opacity(0.3)

        case .numbered(let text, let number):
            HStack(alignment: .top, spacing: 8) {
                Text("\(number).")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.accentNavi)
                    .frame(width: 22, alignment: .trailing)
                Text(parseInline(text))
                    .font(.system(size: 14))
                    .fixedSize(horizontal: false, vertical: true)
            }

        case .quote(let text):
            HStack(spacing: 0) {
                Rectangle()
                    .fill(Color.accentNavi.opacity(0.5))
                    .frame(width: 3)
                Text(text)
                    .font(.system(size: 13))
                    .foregroundColor(.secondary)
                    .padding(.leading, 12)
            }
            .padding(.vertical, 4)

        case .table(let headers, let rows):
            VStack(spacing: 0) {
                HStack(spacing: 0) {
                    ForEach(headers.indices, id: \.self) { col in
                        Text(headers[col])
                            .font(.system(size: 12, weight: .semibold))
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 6)
                    }
                }
                .background(Color.codeBackground)
                Divider().opacity(0.3)
                ForEach(rows.indices, id: \.self) { row in
                    HStack(spacing: 0) {
                        ForEach(rows[row].indices, id: \.self) { col in
                            Text(rows[row][col])
                                .font(.system(size: 12))
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                        }
                    }
                    if row < rows.count - 1 {
                        Divider().opacity(0.1)
                    }
                }
            }
            .background(RoundedRectangle(cornerRadius: 8).fill(Color.white.opacity(0.03)))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.dividerColor.opacity(0.2)))
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
        let lines = text.components(separatedBy: "\n")
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
            } else if let match = line.range(of: #"^(\d+)\.\s+"#, options: .regularExpression) {
                let numStr = line[line.startIndex..<line.index(before: match.upperBound)]
                    .filter(\.isNumber)
                let num = Int(numStr) ?? 1
                let text = String(line[match.upperBound...])
                blocks.append(.numbered(text, number: num))
            } else if line.contains("|") && line.trimmingCharacters(in: .whitespaces).hasPrefix("|") {
                var tableLines: [String] = [line]
                var j = i + 1
                while j < lines.count && lines[j].trimmingCharacters(in: .whitespaces).hasPrefix("|") {
                    tableLines.append(lines[j])
                    j += 1
                }
                i = j - 1
                let parsed = parseTable(tableLines)
                if let parsed = parsed {
                    blocks.append(.table(parsed.headers, parsed.rows))
                }
            } else if line.hasPrefix("> ") {
                blocks.append(.quote(String(line.dropFirst(2))))
            } else if !line.trimmed.isEmpty {
                blocks.append(.paragraph(line))
            }

            i += 1
        }

        return blocks
    }

    private func parseTable(_ lines: [String]) -> (headers: [String], rows: [[String]])? {
        guard lines.count >= 2 else { return nil }
        func splitRow(_ line: String) -> [String] {
            line.split(separator: "|", omittingEmptySubsequences: false)
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }
        }
        let headers = splitRow(lines[0])
        guard !headers.isEmpty else { return nil }
        let startRow = lines.count > 1 && lines[1].contains("-") ? 2 : 1
        let rows = lines[startRow...].map { splitRow($0) }
        return (headers, Array(rows))
    }
}

enum MarkdownBlock {
    case heading(String, level: Int)
    case paragraph(String)
    case code(String, String?)
    case bullet(String)
    case numbered(String, number: Int)
    case divider
    case quote(String)
    case table([String], [[String]])
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
