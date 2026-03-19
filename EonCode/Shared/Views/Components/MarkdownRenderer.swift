import SwiftUI

// MARK: - Color hex init

extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 3: (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6: (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8: (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default: (a, r, g, b) = (255, 255, 255, 255)  // fallback: opaque white
        }
        self.init(.sRGB, red: Double(r) / 255, green: Double(g) / 255, blue: Double(b) / 255, opacity: Double(a) / 255)
    }
}

// MARK: - SyntaxHighlighter

struct SyntaxHighlighter {
    // Color palette (ChatGPT-inspired dark theme)
    static let background  = Color(hex: "#1e1e2e")
    static let keyword     = Color(hex: "#c792ea")  // purple
    static let string      = Color(hex: "#c3e88d")  // green
    static let comment     = Color(hex: "#546e7a")  // grey
    static let number      = Color(hex: "#f78c6c")  // orange
    static let type_       = Color(hex: "#89ddff")  // cyan
    static let plain       = Color(hex: "#cdd6f4")  // light

    struct Token {
        let text: String
        let color: Color
    }

    static func tokenize(_ code: String, language: String) -> [Token] {
        let lang = language.lowercased()
        switch lang {
        case "swift":       return tokenizeSwift(code)
        case "js", "javascript", "ts", "typescript": return tokenizeJS(code)
        case "python", "py": return tokenizePython(code)
        case "bash", "sh", "shell": return tokenizeBash(code)
        case "json":        return tokenizeJSON(code)
        default:            return [Token(text: code, color: plain)]
        }
    }

    private static func tokenizeGeneric(_ code: String, keywords: [String]) -> [Token] {
        var tokens: [Token] = []
        let lines = code.components(separatedBy: "\n")
        for (i, line) in lines.enumerated() {
            if line.contains("\"") || line.contains("'") {
                tokens.append(contentsOf: tokenizeStrings(line))
            } else {
                let words = line.components(separatedBy: CharacterSet.whitespaces)
                for word in words {
                    let stripped = word.trimmingCharacters(in: CharacterSet.punctuationCharacters)
                    if keywords.contains(stripped) {
                        tokens.append(Token(text: word + " ", color: keyword))
                    } else if stripped.first?.isNumber == true {
                        tokens.append(Token(text: word + " ", color: number))
                    } else {
                        tokens.append(Token(text: word + " ", color: plain))
                    }
                }
            }
            if i < lines.count - 1 { tokens.append(Token(text: "\n", color: plain)) }
        }
        return tokens
    }

    private static func tokenizeStrings(_ line: String) -> [Token] {
        var tokens: [Token] = []
        var inString = false
        var current = ""
        for ch in line {
            if ch == "\"" || ch == "'" {
                if !current.isEmpty {
                    tokens.append(Token(text: current, color: inString ? string : plain))
                    current = ""
                }
                inString.toggle()
                current += String(ch)
            } else {
                current += String(ch)
            }
        }
        if !current.isEmpty { tokens.append(Token(text: current, color: inString ? string : plain)) }
        return tokens
    }

    static func tokenizeSwift(_ code: String) -> [Token] {
        let kw = ["func","var","let","class","struct","enum","protocol","extension",
                  "if","else","guard","return","import","switch","case","for","while",
                  "in","is","as","nil","true","false","self","super","init","deinit",
                  "@MainActor","@Published","@State","@StateObject","@ObservedObject",
                  "async","await","throws","try","some","any","override","final","static",
                  "private","public","internal","open","mutating","lazy","weak","unowned"]
        return tokenizeGeneric(code, keywords: kw)
    }

    static func tokenizeJS(_ code: String) -> [Token] {
        let kw = ["const","let","var","function","return","if","else","for","while",
                  "class","import","export","default","async","await","try","catch",
                  "new","this","typeof","instanceof","null","undefined","true","false",
                  "require","module","=>","from"]
        return tokenizeGeneric(code, keywords: kw)
    }

    static func tokenizePython(_ code: String) -> [Token] {
        let kw = ["def","class","return","if","elif","else","for","while","import",
                  "from","as","with","try","except","finally","raise","pass","None",
                  "True","False","and","or","not","in","is","lambda","yield","async","await"]
        return tokenizeGeneric(code, keywords: kw)
    }

    static func tokenizeBash(_ code: String) -> [Token] {
        let kw = ["if","then","else","fi","for","do","done","while","case","esac",
                  "function","return","export","local","echo","cd","ls","mkdir","rm",
                  "git","npm","pip","curl","ssh"]
        return tokenizeGeneric(code, keywords: kw)
    }

    static func tokenizeJSON(_ code: String) -> [Token] {
        var tokens: [Token] = []
        var i = code.startIndex
        while i < code.endIndex {
            let ch = code[i]
            if ch == "\"" {
                var j = code.index(after: i)
                while j < code.endIndex && code[j] != "\"" {
                    if code[j] == "\\" {
                        j = code.index(after: j)
                        guard j < code.endIndex else { break }
                    }
                    j = code.index(after: j)
                }
                if j < code.endIndex { j = code.index(after: j) }
                let s = String(code[i..<j])
                // A quoted string is a JSON key if the next non-whitespace character is ':'
                let isKey = code[j...].first(where: { !$0.isWhitespace }) == ":"
                tokens.append(Token(text: s, color: isKey ? type_ : string))
                i = j
            } else if ch.isNumber || ch == "-" {
                var j = code.index(after: i)
                while j < code.endIndex && (code[j].isNumber || code[j] == "." || code[j] == "e" || code[j] == "E") {
                    j = code.index(after: j)
                }
                tokens.append(Token(text: String(code[i..<j]), color: number))
                i = j
            } else {
                tokens.append(Token(text: String(ch), color: plain))
                i = code.index(after: i)
            }
        }
        return tokens
    }
}

// MARK: - StreamingMarkdownBuffer

@MainActor
final class StreamingMarkdownBuffer: ObservableObject {
    @Published private(set) var displayText: String = ""
    private var targetText: String = ""
    private var timer: Timer?

    // Dummy singleton for non-streaming callers — avoids creating a new instance on every render.
    static let dummy = StreamingMarkdownBuffer()

    func update(text: String, animated: Bool) {
        targetText = text
        if !animated {
            displayText = text
            timer?.invalidate()
            timer = nil
            return
        }
        if timer == nil { startTimer() }
    }

    func reset() {
        timer?.invalidate()
        timer = nil
        displayText = ""
        targetText = ""
    }

    private func startTimer() {
        // Use Task { @MainActor in ... } — safe even if timer fires off-main-thread
        timer = Timer.scheduledTimer(withTimeInterval: 0.008, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                if self.displayText.count < self.targetText.count {
                    let offset = self.displayText.count + 1
                    guard offset <= self.targetText.count else { return }
                    let idx = self.targetText.index(self.targetText.startIndex, offsetBy: offset)
                    self.displayText = String(self.targetText[..<idx])
                } else {
                    self.timer?.invalidate()
                    self.timer = nil
                }
            }
        }
    }
}

// MARK: - MarkdownCodeBlock

struct MarkdownCodeBlock: View {
    let language: String
    let code: String
    @State private var copied = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header bar
            HStack {
                if !language.isEmpty {
                    Text(language.lowercased())
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                        .foregroundColor(.secondary)
                }
                Spacer()
                Button(action: copyCode) {
                    HStack(spacing: 4) {
                        Image(systemName: copied ? "checkmark" : "doc.on.doc")
                            .font(.system(size: 11))
                        Text(copied ? "Kopierat" : "Kopiera")
                            .font(.system(size: 11))
                    }
                    .foregroundColor(.secondary)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(Color(hex: "#2a2a3a"))

            // Code content
            ScrollView(.horizontal, showsIndicators: false) {
                highlightedCode
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
            }
        }
        .background(SyntaxHighlighter.background)
        .cornerRadius(8)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.white.opacity(0.08), lineWidth: 1)
        )
    }

    @ViewBuilder
    private var highlightedCode: some View {
        let tokens = SyntaxHighlighter.tokenize(code, language: language)
        let lines = code.components(separatedBy: "\n")
        let showLineNumbers = lines.count > 10

        if showLineNumbers {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .trailing, spacing: 0) {
                    ForEach(Array(lines.enumerated()), id: \.offset) { i, _ in
                        Text("\(i + 1)")
                            .font(.system(size: 13, design: .monospaced))
                            .foregroundColor(Color(hex: "#546e7a"))
                            .frame(minWidth: 24, alignment: .trailing)
                    }
                }
                tokenText(tokens)
            }
        } else {
            tokenText(tokens)
        }
    }

    private func tokenText(_ tokens: [SyntaxHighlighter.Token]) -> some View {
        tokens.reduce(Text("")) { acc, token in
            acc + Text(token.text)
                .foregroundColor(token.color)
        }
        .font(.system(size: 13, design: .monospaced))
    }

    private func copyCode() {
        #if os(iOS)
        UIPasteboard.general.string = code
        let impact = UIImpactFeedbackGenerator(style: .light)
        impact.impactOccurred()
        #else
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(code, forType: .string)
        #endif
        withAnimation { copied = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            withAnimation { copied = false }
        }
    }
}

// MARK: - MarkdownTextView

struct MarkdownTextView: View {
    let text: String
    var isStreaming: Bool = false
    // Call site owns the buffer as @StateObject and passes it in.
    // For non-streaming (historical) messages, pass nil — falls back to dummy singleton.
    @ObservedObject var buffer: StreamingMarkdownBuffer

    init(text: String, isStreaming: Bool = false, buffer: StreamingMarkdownBuffer? = nil) {
        self.text = text
        self.isStreaming = isStreaming
        self.buffer = buffer ?? .dummy
    }

    private var blocks: [MarkdownBlock] {
        MarkdownBlock.parse(isStreaming ? buffer.displayText : text)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            ForEach(Array(blocks.enumerated()), id: \.offset) { i, block in
                blockView(block, isFirst: i == 0)
            }
        }
        .onAppear {
            if isStreaming { buffer.update(text: text, animated: true) }
        }
        .onChange(of: text) { _, newText in
            if isStreaming { buffer.update(text: newText, animated: true) }
        }
    }

    @ViewBuilder
    private func blockView(_ block: MarkdownBlock, isFirst: Bool) -> some View {
        switch block {
        case .paragraph(let t):
            inlineText(t)
                .fixedSize(horizontal: false, vertical: true)
        case .header(let level, let t):
            headerView(level: level, text: t)
                .padding(.top, isFirst ? 0 : (level <= 2 ? 12 : 6))
        case .code(let lang, let code):
            MarkdownCodeBlock(language: lang, code: code)
        case .bulletList(let items):
            bulletListView(items)
        case .numberedList(let items):
            numberedListView(items)
        case .blockquote(let t):
            blockquoteView(t)
        case .table(let headers, let rows):
            tableView(headers: headers, rows: rows)
        case .divider:
            Divider().opacity(0.15).padding(.vertical, 4)
        }
    }

    @ViewBuilder
    private func inlineText(_ raw: String) -> some View {
        if let attributed = try? AttributedString(
            markdown: raw,
            options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        ) {
            Text(attributed)
                .font(.system(size: 16, weight: .regular, design: .default))
                .lineSpacing(6)
                .tracking(-0.1)
        } else {
            Text(raw)
                .font(.system(size: 16, weight: .regular, design: .default))
                .lineSpacing(6)
                .tracking(-0.1)
        }
    }

    @ViewBuilder
    private func headerView(level: Int, text: String) -> some View {
        let config: (size: CGFloat, weight: Font.Weight) = {
            switch level {
            case 1:  return (22, .bold)
            case 2:  return (19, .semibold)
            default: return (16, .semibold)
            }
        }()
        Group {
            if let attributed = try? AttributedString(
                markdown: text,
                options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)
            ) {
                Text(attributed)
                    .font(.system(size: config.size, weight: config.weight))
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                Text(text)
                    .font(.system(size: config.size, weight: config.weight))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    @ViewBuilder
    private func bulletListView(_ items: [(level: Int, text: String)]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                HStack(alignment: .top, spacing: 8) {
                    Text("·")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundColor(.secondary)
                        .frame(width: 16, alignment: .center)
                        .padding(.leading, CGFloat(item.level) * 16)
                    inlineText(item.text)
                }
            }
        }
    }

    @ViewBuilder
    private func numberedListView(_ items: [(number: Int, text: String)]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                HStack(alignment: .top, spacing: 8) {
                    Text("\(item.number).")
                        .font(.system(size: 16, weight: .medium, design: .monospaced))
                        .foregroundColor(.secondary)
                        .frame(minWidth: 24, alignment: .trailing)
                    inlineText(item.text)
                }
            }
        }
    }

    @ViewBuilder
    private func blockquoteView(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 0) {
            Rectangle()
                .fill(Color.accentColor)
                .frame(width: 3)
            inlineText(text)
                .italic()
                .opacity(0.8)
                .padding(.leading, 12)
        }
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private func tableView(headers: [String], rows: [[String]]) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                ForEach(Array(headers.enumerated()), id: \.offset) { _, h in
                    Text(h)
                        .font(.system(size: 14, weight: .semibold))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 8)
                }
            }
            .background(Color.white.opacity(0.06))
            Divider().opacity(0.15)
            ForEach(Array(rows.enumerated()), id: \.offset) { rowIdx, row in
                HStack(spacing: 0) {
                    ForEach(Array(row.enumerated()), id: \.offset) { _, cell in
                        Text(cell)
                            .font(.system(size: 14))
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 7)
                    }
                }
                .background(rowIdx % 2 == 0 ? Color.clear : Color.white.opacity(0.03))
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.white.opacity(0.1), lineWidth: 1)
        )
    }
}

// MARK: - MarkdownBlock parser

enum MarkdownBlock {
    case paragraph(String)
    case header(Int, String)
    case code(String, String)
    case bulletList([(level: Int, text: String)])
    case numberedList([(number: Int, text: String)])
    case blockquote(String)
    case table([String], [[String]])
    case divider

    static func parse(_ text: String) -> [MarkdownBlock] {
        var blocks: [MarkdownBlock] = []
        let lines = text.components(separatedBy: "\n")
        var i = 0

        while i < lines.count {
            let line = lines[i]

            // Fenced code block
            if line.hasPrefix("```") {
                let lang = String(line.dropFirst(3)).trimmingCharacters(in: .whitespaces)
                var codeLines: [String] = []
                i += 1
                while i < lines.count && !lines[i].hasPrefix("```") {
                    codeLines.append(lines[i])
                    i += 1
                }
                blocks.append(.code(lang, codeLines.joined(separator: "\n")))
                i += 1
                continue
            }

            // Divider
            if line.hasPrefix("---") || line.hasPrefix("***") || line.hasPrefix("___") {
                blocks.append(.divider)
                i += 1
                continue
            }

            // Header
            if line.hasPrefix("#") {
                var level = 0
                var rest = line
                while rest.hasPrefix("#") { level += 1; rest = String(rest.dropFirst()) }
                level = min(level, 3)
                let title = rest.trimmingCharacters(in: .whitespaces)
                blocks.append(.header(level, title))
                i += 1
                continue
            }

            // Bullet list
            if line.hasPrefix("- ") || line.hasPrefix("* ") || line.hasPrefix("• ") {
                var items: [(level: Int, text: String)] = []
                while i < lines.count && (lines[i].hasPrefix("- ") || lines[i].hasPrefix("* ") || lines[i].hasPrefix("  ")) {
                    let l = lines[i]
                    let indent = l.prefix(while: { $0 == " " }).count / 2
                    let text = l.drop(while: { $0 == " " || $0 == "-" || $0 == "*" })
                        .trimmingCharacters(in: .whitespaces)
                    if !text.isEmpty { items.append((level: indent, text: text)) }
                    i += 1
                }
                if !items.isEmpty { blocks.append(.bulletList(items)) }
                continue
            }

            // Numbered list
            if line.range(of: #"^\d+\. "#, options: .regularExpression) != nil {
                var items: [(number: Int, text: String)] = []
                var num = 1
                while i < lines.count,
                      let r = lines[i].range(of: #"^\d+\. "#, options: .regularExpression) {
                    let text = String(lines[i][r.upperBound...]).trimmingCharacters(in: .whitespaces)
                    items.append((number: num, text: text))
                    num += 1
                    i += 1
                }
                if !items.isEmpty { blocks.append(.numberedList(items)) }
                continue
            }

            // Blockquote
            if line.hasPrefix("> ") {
                let text = String(line.dropFirst(2))
                blocks.append(.blockquote(text))
                i += 1
                continue
            }

            // Table
            if line.contains("|") && i + 1 < lines.count && lines[i + 1].contains("---") {
                let headers = line.split(separator: "|")
                    .map { $0.trimmingCharacters(in: .whitespaces) }
                    .filter { !$0.isEmpty }
                i += 2
                var rows: [[String]] = []
                while i < lines.count && lines[i].contains("|") {
                    let row = lines[i].split(separator: "|")
                        .map { $0.trimmingCharacters(in: .whitespaces) }
                        .filter { !$0.isEmpty }
                    if !row.isEmpty { rows.append(row) }
                    i += 1
                }
                blocks.append(.table(headers, rows))
                continue
            }

            // Paragraph
            if !line.isEmpty {
                var paraLines = [line]
                i += 1
                while i < lines.count && !lines[i].isEmpty
                    && !lines[i].hasPrefix("#")
                    && !lines[i].hasPrefix("```")
                    && !lines[i].hasPrefix("- ")
                    && !lines[i].hasPrefix("* ")
                    && !lines[i].hasPrefix("> ") {
                    paraLines.append(lines[i])
                    i += 1
                }
                blocks.append(.paragraph(paraLines.joined(separator: "\n")))
            } else {
                i += 1
            }
        }

        return blocks
    }
}

// MARK: - StreamingCursor

struct StreamingCursor: View {
    @State private var visible = true

    var body: some View {
        Rectangle()
            .fill(Color.accentColor)
            .frame(width: 6, height: 14)  // spec: 6×14pt
            .opacity(visible ? 1 : 0)
            .animation(.easeInOut(duration: 0.6).repeatForever(autoreverses: true), value: visible)
            .onAppear { visible = false }
    }
}
