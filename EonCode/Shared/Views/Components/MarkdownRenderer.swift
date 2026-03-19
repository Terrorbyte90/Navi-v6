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
        default: (a, r, g, b) = (1, 1, 1, 0)
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

    // Generic keyword tokenizer helper
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
        let kw = ["func", "var", "let", "class", "struct", "enum", "protocol", "extension",
                  "if", "else", "guard", "return", "import", "switch", "case", "for", "while",
                  "in", "is", "as", "nil", "true", "false", "self", "super", "init", "deinit",
                  "@MainActor", "@Published", "@State", "@StateObject", "@ObservedObject",
                  "async", "await", "throws", "try", "some", "any", "override", "final", "static",
                  "private", "public", "internal", "open", "mutating", "lazy", "weak", "unowned"]
        return tokenizeGeneric(code, keywords: kw)
    }

    static func tokenizeJS(_ code: String) -> [Token] {
        let kw = ["const", "let", "var", "function", "return", "if", "else", "for", "while",
                  "class", "import", "export", "default", "async", "await", "try", "catch",
                  "new", "this", "typeof", "instanceof", "null", "undefined", "true", "false",
                  "require", "module", "=>", "from"]
        return tokenizeGeneric(code, keywords: kw)
    }

    static func tokenizePython(_ code: String) -> [Token] {
        let kw = ["def", "class", "return", "if", "elif", "else", "for", "while", "import",
                  "from", "as", "with", "try", "except", "finally", "raise", "pass", "None",
                  "True", "False", "and", "or", "not", "in", "is", "lambda", "yield", "async", "await"]
        return tokenizeGeneric(code, keywords: kw)
    }

    static func tokenizeBash(_ code: String) -> [Token] {
        let kw = ["if", "then", "else", "fi", "for", "do", "done", "while", "case", "esac",
                  "function", "return", "export", "local", "echo", "cd", "ls", "mkdir", "rm",
                  "git", "npm", "pip", "curl", "ssh"]
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
                    if code[j] == "\\" { j = code.index(after: j) }
                    if j < code.endIndex { j = code.index(after: j) }
                }
                if j < code.endIndex { j = code.index(after: j) }
                let s = String(code[i..<j])
                let afterJ = j < code.endIndex ? code[j...].first : nil
                let isKey = afterJ == ":" || code[i..<code.endIndex].dropFirst(s.count).first(where: { !$0.isWhitespace }) == ":"
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
