# iOS Markdown & UI Improvements — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Rewrite markdown rendering to ChatGPT quality with smooth streaming + syntax highlighting, redesign chat bubbles, polish Code view UI, improve navigation, and add cost tracking.

**Architecture:** New `MarkdownRenderer.swift` centralizes all markdown rendering (replaces `MarkdownTextView` + `MarkdownCodeBlock` currently scattered in `PureChatView.swift`). Chat bubble layout changes happen in `ChatView.swift` and `PureChatView.swift`. Cost tracking requires changes to `CostTracker.swift`, `CostCalculator.swift`, and `ServerCodeSession.swift`. UI polish touches `CodeView.swift`, `SidebarView.swift`, and `SettingsView.swift`.

**Tech Stack:** Swift 6, SwiftUI, `@MainActor`, `Timer.scheduledTimer`, `AttributedString`, `NSRegularExpression`.

**Agent to use:** `navi-ios-dev` for implementation, `navi-ui-reviewer` after each UI task.

**Spec:** `docs/superpowers/specs/2026-03-19-navi-improvements-design.md` — Sektioner 2 och 3

---

## File Map

| File | Action | Responsibility |
|---|---|---|
| `EonCode/Shared/Views/Components/MarkdownRenderer.swift` | **Create** | All markdown: `MarkdownTextView`, `MarkdownCodeBlock`, `SyntaxHighlighter`, `StreamingMarkdownBuffer` |
| `EonCode/Shared/Views/Chat/PureChatView.swift` | Modify | Remove old `MarkdownTextView`+`MarkdownCodeBlock` (lines 804–end), redesign assistant bubbles |
| `EonCode/Shared/Views/Chat/ChatView.swift` | Modify | Use new `MarkdownTextView` with `isStreaming`, redesign message bubbles |
| `EonCode/Shared/Views/Code/CodeView.swift` | Modify | Tool pill compression, progress bar, git diff expansion, `"reviewing"` phase label |
| `EonCode/Shared/Views/Server/ServerView.swift` | Modify | Use new `MarkdownTextView` |
| `EonCode/Shared/Services/Code/ServerCodeSession.swift` | Modify | Handle `RUN_FINISHED` usage field, snapshot fetch, new `reviewing` phase |
| `EonCode/Shared/Services/ClaudeAPI/CostTracker.swift` | Modify | Re-enable `record()`, add monthly fields, add `recordOpenRouter()` |
| `EonCode/Shared/Services/ClaudeAPI/CostCalculator.swift` | Modify | Add `calculateOpenRouter(inputTokens:outputTokens:model:)` |
| `EonCode/Shared/Services/Persistence/SettingsStore.swift` | Modify | Add `chatModel`, `codeModel` per-view model selection |
| `EonCode/Shared/Views/Settings/SettingsView.swift` | Modify | Cost dashboard, per-view model selector, API key status |
| `EonCode/Shared/Views/Main/SidebarView.swift` | Modify | Recent code sessions section (iOS + macOS) |

---

## Task 1: Create `MarkdownRenderer.swift` — SyntaxHighlighter

**Files:**
- Create: `EonCode/Shared/Views/Components/MarkdownRenderer.swift`

This is the largest single file. Build it in parts, starting with `SyntaxHighlighter`.

- [ ] **Step 1: Create file with SyntaxHighlighter**

⚠️ **Add `Color(hex:)` extension first** — SyntaxHighlighter and MarkdownCodeBlock both use `Color(hex:)`. Add it at the top of the new file before the SyntaxHighlighter struct (and also add to `EonCode/Shared/Utilities/Extensions.swift` if not already there so other files can use it):
```swift
import SwiftUI

// MARK: - Color hex init (add to Extensions.swift if not already present)
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
```

```swift
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
        // Simple line-by-line approach
        let lines = code.components(separatedBy: "\n")
        for (i, line) in lines.enumerated() {
            // String literals
            if line.contains("\"") || line.contains("'") {
                // Simplified: colorize whole line segments between quotes
                tokens.append(contentsOf: tokenizeStrings(line))
            } else {
                var words = line.components(separatedBy: CharacterSet.whitespaces)
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
        // Simplified string detection — alternates between plain and string color
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
        // JSON: keys are cyan, strings are green, numbers are orange, booleans/null are purple
        var tokens: [Token] = []
        var i = code.startIndex
        while i < code.endIndex {
            let ch = code[i]
            if ch == "\"" {
                // Find closing quote
                var j = code.index(after: i)
                while j < code.endIndex && code[j] != "\"" {
                    if code[j] == "\\" { j = code.index(after: j) }
                    if j < code.endIndex { j = code.index(after: j) }
                }
                if j < code.endIndex { j = code.index(after: j) }
                let s = String(code[i..<j])
                // If followed by ":", it's a key (cyan), else value (green)
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
```

- [ ] **Step 2: Verify compilation**
```bash
# Open Xcode and check for errors, or:
xcodebuild -scheme Navi -destination 'generic/platform=iOS' -quiet 2>&1 | grep -E "error:|Build succeeded"
```

- [ ] **Step 3: Commit**
```bash
git add "EonCode/Shared/Views/Components/MarkdownRenderer.swift"
git commit -m "feat(markdown): add SyntaxHighlighter to MarkdownRenderer.swift"
```

---

## Task 2: Add `StreamingMarkdownBuffer` and `MarkdownCodeBlock` to `MarkdownRenderer.swift`

**Files:**
- Modify: `EonCode/Shared/Views/Components/MarkdownRenderer.swift`

- [ ] **Step 1: Add StreamingMarkdownBuffer**

Append to `MarkdownRenderer.swift`:

```swift
// MARK: - StreamingMarkdownBuffer

@MainActor
class StreamingMarkdownBuffer: ObservableObject {
    @Published private(set) var displayText: String = ""
    private var targetText: String = ""
    private var timer: Timer?

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

    // Dummy singleton for non-streaming callers — avoids creating a new instance on every render.
    static let dummy = StreamingMarkdownBuffer()

    private func startTimer() {
        // ⚠️ MainActor.assumeIsolated is a precondition crash if fired off-main.
        // Use Task { @MainActor in ... } instead — safe even if timer fires off-main.
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
```

- [ ] **Step 2: Add `MarkdownCodeBlock`**

```swift
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
                // Line numbers
                VStack(alignment: .trailing, spacing: 0) {
                    ForEach(Array(lines.enumerated()), id: \.offset) { i, _ in
                        Text("\(i + 1)")
                            .font(.system(size: 13, design: .monospaced))
                            .foregroundColor(Color(hex: "#546e7a"))
                            .frame(minWidth: 24, alignment: .trailing)
                    }
                }
                // Highlighted text
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
```

- [ ] **Step 3: Verify `Color(hex:)` added to `Extensions.swift`**

`Color(hex:)` was added in Task 1 Step 1. Verify it's present in `Extensions.swift` (it must be accessible across the whole project):
```bash
grep -r "init(hex:" "EonCode/Shared/Utilities/Extensions.swift" | head -3
```
If not found there yet, move the extension from `MarkdownRenderer.swift` to `Extensions.swift` (or duplicate it there).

- [ ] **Step 4: Verify compilation**
```bash
xcodebuild -scheme Navi -destination 'generic/platform=iOS' -quiet 2>&1 | grep -E "error:|Build succeeded"
```

- [ ] **Step 5: Commit**
```bash
git add "EonCode/Shared/Views/Components/MarkdownRenderer.swift" "EonCode/Shared/Utilities/Extensions.swift"
git commit -m "feat(markdown): add StreamingMarkdownBuffer and MarkdownCodeBlock with syntax highlighting"
```

---

## Task 3: Add new `MarkdownTextView` to `MarkdownRenderer.swift`

**Files:**
- Modify: `EonCode/Shared/Views/Components/MarkdownRenderer.swift`

- [ ] **Step 1: Add block types and parser**

Append to `MarkdownRenderer.swift`:

**⚠️ Architecture note:** `@StateObject` in a struct with a custom `init` causes the buffer to reset on every re-render. Instead, `StreamingMarkdownBuffer` ownership lives at the **call site** — passed in as `@ObservedObject`. Drop `Equatable` (it conflicts with `@ObservedObject`). Call sites that need streaming create a `@StateObject StreamingMarkdownBuffer` and pass it in.

```swift
// MARK: - MarkdownTextView

struct MarkdownTextView: View {
    let text: String
    var isStreaming: Bool = false
    // Call site owns the buffer (passed as @ObservedObject) when isStreaming=true.
    // When isStreaming=false (historical), pass nil — MarkdownTextView renders text directly.
    // ⚠️ IMPORTANT: Do NOT use @StateObject here — in a struct with custom init it resets on every render.
    // The call site owns the buffer as @StateObject and passes it in. For non-streaming (historical)
    // messages, pass nil — we fall back to StreamingMarkdownBuffer.dummy (a static singleton).
    @ObservedObject var buffer: StreamingMarkdownBuffer

    init(text: String, isStreaming: Bool = false, buffer: StreamingMarkdownBuffer? = nil) {
        self.text = text
        self.isStreaming = isStreaming
        // Use provided buffer or the shared dummy singleton — never create a new instance here
        // (that would reset the animation on every re-render).
        self.buffer = buffer ?? .dummy
    }

    private var blocks: [MarkdownBlock] {
        MarkdownBlock.parse(isStreaming ? buffer.displayText : text)
    }

    // ⚠️ No second init(text:isStreaming:) — `blocks` is a computed property (not stored),
    // and a duplicate init would conflict. One init only.
    // ⚠️ No Equatable conformance — @ObservedObject wraps a reference type (not Equatable),
    // and a custom == would silently ignore buffer inequality causing wrong SwiftUI diffing.

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            ForEach(Array(blocks.enumerated()), id: \.offset) { i, block in
                blockView(block, isFirst: i == 0)
            }
        }
        // For streaming views: call site drives buffer.update(text:animated:)
        // For historical views (isStreaming=false): blocks computed directly from text, no animation needed
        .onAppear {
            if isStreaming { buffer.update(text: text, animated: true) }
        }
        // ⚠️ Two-argument onChange { _, newText in } requires iOS 17+.
        // Use single-argument form (iOS 14+) for backwards compatibility:
        .onChange(of: text) { newText in
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

    // MARK: - Inline text with AttributedString

    @ViewBuilder
    private func inlineText(_ raw: String) -> some View {
        if let attributed = try? AttributedString(
            markdown: raw,
            options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        ) {
            Text(attributed)
                .font(.system(size: 16, weight: .regular, design: .default))
                .lineSpacing(6)  // lineHeight ~1.6 at 16pt
                .tracking(-0.1)
        } else {
            Text(raw)
                .font(.system(size: 16, weight: .regular, design: .default))
                .lineSpacing(6)
                .tracking(-0.1)
        }
    }

    // MARK: - Header

    @ViewBuilder
    private func headerView(level: Int, text: String) -> some View {
        let config: (size: CGFloat, weight: Font.Weight, design: Font.Design) = {
            switch level {
            case 1:  return (22, .bold,     .default)
            case 2:  return (19, .semibold, .default)
            default: return (16, .semibold, .default)
            }
        }()
        Group {
            if let attributed = try? AttributedString(
                markdown: text,
                options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)
            ) {
                Text(attributed)
                    .font(.system(size: config.size, weight: config.weight, design: config.design))
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                Text(text)
                    .font(.system(size: config.size, weight: config.weight, design: config.design))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    // MARK: - Bullet list

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

    // MARK: - Numbered list

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

    // MARK: - Blockquote

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

    // MARK: - Table

    @ViewBuilder
    private func tableView(headers: [String], rows: [[String]]) -> some View {
        VStack(spacing: 0) {
            // Header row
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

            // Data rows
            ForEach(Array(rows.enumerated()), id: \.offset) { rowIdx, row in
                HStack(spacing: 0) {
                    ForEach(Array(row.enumerated()), id: \.offset) { _, cell in
                        inlineText(cell)
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
```

- [ ] **Step 2: Add `MarkdownBlock` parser**

Append:

```swift
// MARK: - MarkdownBlock parser

enum MarkdownBlock {
    case paragraph(String)
    case header(Int, String)
    case code(String, String)     // language, content
    case bulletList([(level: Int, text: String)])
    case numberedList([(number: Int, text: String)])
    case blockquote(String)
    case table([String], [[String]])
    case divider

    static func parse(_ text: String) -> [MarkdownBlock] {
        var blocks: [MarkdownBlock] = []
        var lines = text.components(separatedBy: "\n")
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
            if let _ = line.range(of: #"^\d+\. "#, options: .regularExpression) {
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
            if line.contains("|") && i + 1 < lines.count && lines[i+1].contains("---") {
                let headers = line.split(separator: "|").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
                i += 2 // skip header + separator
                var rows: [[String]] = []
                while i < lines.count && lines[i].contains("|") {
                    let row = lines[i].split(separator: "|").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
                    if !row.isEmpty { rows.append(row) }
                    i += 1
                }
                blocks.append(.table(headers, rows))
                continue
            }

            // Paragraph (skip empty lines)
            if !line.isEmpty {
                var paraLines = [line]
                i += 1
                while i < lines.count && !lines[i].isEmpty && !lines[i].hasPrefix("#")
                    && !lines[i].hasPrefix("```") && !lines[i].hasPrefix("- ")
                    && !lines[i].hasPrefix("* ") && !lines[i].hasPrefix("> ") {
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
```

- [ ] **Step 3: Verify compilation**
```bash
xcodebuild -scheme Navi -destination 'generic/platform=iOS' -quiet 2>&1 | grep -E "error:|Build succeeded"
```

- [ ] **Step 4: Commit**
```bash
git add "EonCode/Shared/Views/Components/MarkdownRenderer.swift"
git commit -m "feat(markdown): complete MarkdownTextView + MarkdownBlock parser in MarkdownRenderer.swift"
```

---

## Task 4: Migrate PureChatView — remove old MarkdownTextView and MarkdownCodeBlock

**Files:**
- Modify: `EonCode/Shared/Views/Chat/PureChatView.swift`

- [ ] **Step 1: Remove the old MarkdownTextView struct (lines ~804–1238) and MarkdownCodeBlock (lines ~1239–end)**

Read PureChatView.swift from line 800 to confirm exact location:
```
read_file("EonCode/Shared/Views/Chat/PureChatView.swift", start_line=800)
```

Delete both structs entirely. The file will now use `MarkdownTextView` from `MarkdownRenderer.swift`.

- [ ] **Step 2: Update all `MarkdownTextView(text:)` call sites in PureChatView to pass `isStreaming`**

Find call sites:
```bash
grep -n "MarkdownTextView" "EonCode/Shared/Views/Chat/PureChatView.swift"
```

For call sites inside streaming bubbles (where content is being streamed), add `isStreaming: true`. For historical messages, leave as default (`isStreaming: false`).

- [ ] **Step 3: Verify compilation**
```bash
xcodebuild -scheme Navi -destination 'generic/platform=iOS' -quiet 2>&1 | grep -E "error:|Build succeeded"
```

- [ ] **Step 4: Commit**
```bash
git add "EonCode/Shared/Views/Chat/PureChatView.swift"
git commit -m "refactor(markdown): migrate PureChatView to MarkdownRenderer — remove old MarkdownTextView"
```

---

## Task 5: Migrate ChatView, CodeView, ServerView

**Files:**
- Modify: `EonCode/Shared/Views/Chat/ChatView.swift`
- Modify: `EonCode/Shared/Views/Code/CodeView.swift`
- Modify: `EonCode/Shared/Views/Server/ServerView.swift`

- [ ] **Step 1: Update ChatView — add `isStreaming` to streaming bubble call site**

```bash
grep -n "MarkdownTextView" "EonCode/Shared/Views/Chat/ChatView.swift"
```
For the `AgentStreamingBubble` or streaming text call sites, pass `isStreaming: true`.

- [ ] **Step 2: Update CodeView — add `isStreaming` to streaming row**

```bash
grep -n "MarkdownTextView" "EonCode/Shared/Views/Code/CodeView.swift"
```
Pass `isStreaming: true` for `ServerStreamingRow`, `isStreaming: false` for completed messages.

- [ ] **Step 3: Update ServerView**

```bash
grep -n "MarkdownTextView" "EonCode/Shared/Views/Server/ServerView.swift"
```
All ServerView messages are historical — no `isStreaming` needed.

- [ ] **Step 4: Verify all compile clean**
```bash
xcodebuild -scheme Navi -destination 'generic/platform=iOS' -quiet 2>&1 | grep -E "error:|Build succeeded"
```

- [ ] **Step 5: Commit**
```bash
git add "EonCode/Shared/Views/Chat/ChatView.swift" "EonCode/Shared/Views/Code/CodeView.swift" "EonCode/Shared/Views/Server/ServerView.swift"
git commit -m "refactor(markdown): migrate ChatView, CodeView, ServerView to MarkdownRenderer"
```

---

## Task 6: Redesign chat bubbles (PureChatView + ChatView)

**Files:**
- Modify: `EonCode/Shared/Views/Chat/PureChatView.swift`
- Modify: `EonCode/Shared/Views/Chat/ChatView.swift`

### Design spec:
- **Assistant**: no bubble, full-width, avatar (28pt) top-left, text starts at 44pt offset, 24pt spacing between messages
- **User**: `#1c1c2e` bubble, 16pt radius, max 85% width, time shows on tap
- **Streaming cursor**: 6×14pt vertical bar, accent color, 600ms fade

- [ ] **Step 1: Update `MessageBubble` in PureChatView (or equivalent assistant message view)**

Read the current implementation:
```bash
grep -n "MessageBubble\|AssistantAvatar\|struct.*Bubble\|isUser\|isAssistant" "EonCode/Shared/Views/Chat/PureChatView.swift" | head -20
```

Rewrite the assistant message layout:
```swift
// Assistant message — no bubble, full width
if !message.isUser {
    HStack(alignment: .top, spacing: 0) {
        // Avatar
        AssistantAvatar()
            .frame(width: 28, height: 28)
            .padding(.top, 2)

        VStack(alignment: .leading, spacing: 6) {
            MarkdownTextView(text: message.content)
        }
        .padding(.leading, 8)
        Spacer(minLength: 0)
    }
    .padding(.horizontal, 16)
    .padding(.vertical, 4)
}
```

User message bubble:
```swift
// User message — bubble
// ⚠️ UIScreen.main is deprecated iOS 16+. Use GeometryReader for dynamic width constraint.
if message.isUser {
    GeometryReader { geo in
      HStack {
        Spacer(minLength: 0)
        VStack(alignment: .trailing, spacing: 4) {
            Text(message.content)
                .font(.system(size: 16))
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(Color(hex: "#1c1c2e"))
                .cornerRadius(16)
                .frame(maxWidth: geo.size.width * 0.85, alignment: .trailing)

            if showTime {
                Text(message.timestamp.formatted(date: .omitted, time: .shortened))
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .transition(.opacity)
            }
        }
        .onTapGesture { withAnimation { showTime.toggle() } }
    }
    .padding(.horizontal, 16)
    .padding(.vertical, 4)
}
```

Note: `showTime` needs `@State private var showTime = false` in the message view.

- [ ] **Step 2: Add streaming cursor view**

Replace the current blinkable I-beam cursor with:
```swift
struct StreamingCursor: View {
    @State private var visible = true

    var body: some View {
        Rectangle()
            .fill(Color.accentColor)
            .frame(width: 6, height: 14)  // spec: 6×14pt (not 2×16)
            .opacity(visible ? 1 : 0)
            .animation(.easeInOut(duration: 0.6).repeatForever(autoreverses: true), value: visible)
            .onAppear { visible = false }
    }
}
```

Add `StreamingCursor()` after the last character of the streaming text view.

- [ ] **Step 3: Apply same bubble redesign to ChatView**

```bash
grep -n "MessageBubble\|isUser\|bubble\|backgroundColor" "EonCode/Shared/Views/Chat/ChatView.swift" | head -20
```

Apply the same pattern — no bubble for assistant, `#1c1c2e` bubble for user.

- [ ] **Step 4: Verify**
```bash
xcodebuild -scheme Navi -destination 'generic/platform=iOS' -quiet 2>&1 | grep -E "error:|Build succeeded"
```

- [ ] **Step 5: Run navi-ui-reviewer**

Dispatch `navi-ui-reviewer` agent on the changed files to verify against UI spec.

- [ ] **Step 6: Commit**
```bash
git add "EonCode/Shared/Views/Chat/PureChatView.swift" "EonCode/Shared/Views/Chat/ChatView.swift"
git commit -m "feat(ui): redesign chat bubbles — ChatGPT-style assistant layout, updated user bubble"
```

---

## Task 7: Code view UI improvements

**Files:**
- Modify: `EonCode/Shared/Views/Code/CodeView.swift`

### Changes:
- Tool cards → pills (`✓ write_file server.js · 1.2s`), stack >3 collapses
- phaseStrip → thin 3pt progressbar at top
- Git checkpoint expands to syntax-highlighted diff
- Add `"reviewing"` phase label

- [ ] **Step 1: Add `"reviewing"` phase to phaseLabel mapping**

Find the phase→label mapping:
```bash
grep -n "thinking\|tools\|done\|phaseLabel\|phase ==" "EonCode/Shared/Views/Code/CodeView.swift" | head -15
```

Add:
```swift
case "reviewing": return "Granskar kod..."
```

⚠️ **No change needed in `ServerCodeSession.swift`** — `ServerEventType` handles AG-UI event *types* (CONNECTED, PHASE, etc.), not phase *values*. The phase value is a free string in `event.phase`, read via `@Published var phase: String`. Adding `case reviewing` to `ServerEventType` would cause a compile error (duplicate `.phase` case). The only required change is the `phaseLabelFromPhase(_:)` mapping above.

- [ ] **Step 2: Replace phaseStrip with 3pt progress bar**

Find `phaseStrip` in CodeView. Replace with:
```swift
// Thin progress bar at top
GeometryReader { geo in
    if session.isRunning {
        Rectangle()
            .fill(Color.accentColor.opacity(0.8))
            .frame(width: geo.size.width * progressFraction, height: 3)
            .animation(.linear(duration: 0.3), value: progressFraction)
    }
}
.frame(height: 3)
```

Where `progressFraction` is computed from `session.iteration` / `maxIteration` (default 30):
```swift
private var progressFraction: Double {
    guard session.maxIteration > 0 else { return 0 }
    return Double(session.iteration) / Double(session.maxIteration)
}
```

Move the phase label + step counter into the top bar `HStack`.

- [ ] **Step 3: Compress tool cards to pills**

Find `ToolEventsSummary` or `ToolEventRow`. Rework:

```swift
struct ToolPill: View {
    let event: ServerToolEvent

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: event.isError == true ? "xmark.circle.fill" : "checkmark.circle.fill")
                .font(.system(size: 11))
                .foregroundColor(event.isError == true ? .red : .green)
            Text(pillLabel)
                .font(.system(size: 12, weight: .medium, design: .monospaced))
                .foregroundColor(.primary.opacity(0.85))
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Color.white.opacity(0.07))
        .cornerRadius(6)
    }

    private var pillLabel: String {
        // ⚠️ ServerToolEvent.name is non-optional (String). Use directly.
        // ⚠️ ServerToolEvent has `params: [String: String]` (not `args` or `keyParam`).
        //    See ServerCodeSession.swift line ~170.
        let name = event.name
        let param = event.params.values.first ?? ""
        let duration = event.durationMs.map { " · \($0 / 1000 > 0 ? "\($0/1000)s" : "\($0)ms")" } ?? ""
        return param.isEmpty ? "\(name)\(duration)" : "\(name) \(param)\(duration)"
    }
}
```

When >3 tools in a group, show a collapsed pill: `"▸ 4 verktyg"` with tap to expand.

- [ ] **Step 4: Git diff expansion**

When tapping `GitCheckpointBadge`, show a sheet/overlay with the diff content from `session.gitCheckpoints[n].diff` (if available) formatted with `MarkdownCodeBlock(language: "diff", code: diffText)`.

If diff isn't stored in the checkpoint, add fetching from the server (out of scope for this task — log a TODO).

- [ ] **Step 5: Verify**
```bash
xcodebuild -scheme Navi -destination 'generic/platform=iOS' -quiet 2>&1 | grep -E "error:|Build succeeded"
```

- [ ] **Step 6: Run navi-ui-reviewer**

Dispatch `navi-ui-reviewer` on `CodeView.swift`.

- [ ] **Step 7: Commit**
```bash
git add "EonCode/Shared/Views/Code/CodeView.swift"
git commit -m "feat(ui): code view — tool pills, thin progress bar, reviewing phase label"
```

---

## Task 8: Navigation — recent sessions in sidebar + empty states

**Files:**
- Modify: `EonCode/Shared/Views/Main/SidebarView.swift`
- Modify: `EonCode/Shared/Views/Chat/PureChatView.swift` (empty state)

- [ ] **Step 1: Add recent code sessions section to SidebarView**

Read SidebarView structure:
```bash
grep -n "Section\|NavigationLink\|List\|ForEach\|struct" "EonCode/Shared/Views/Main/SidebarView.swift" | head -25
```

Add a new `Section("Senaste kod-sessioner")`. First check what the store exposes:
```bash
grep -n "var sessions\|recentSessions\|func recent" "EonCode/Shared/Services/Code/CodeSessionsStore.swift" | head -5
```
⚠️ There may already be a `recentSessions` computed property with a different signature (e.g. no `limit:` parameter). Use `sessions.sorted { $0.updatedAt > $1.updatedAt }.prefix(5)` directly if needed to avoid conflicts.

```swift
Section("Senaste kod-sessioner") {
    ForEach(Array(codeSessionsStore.sessions.sorted { $0.updatedAt > $1.updatedAt }.prefix(5))) { session in
        HStack(spacing: 8) {
            Circle()
                .fill(statusColor(session.status))
                .frame(width: 7, height: 7)
            Text(session.task)
                .lineLimit(1)
                .font(.system(size: 13))
        }
        .onTapGesture {
            // Navigate to code view and resume this session
            selectedSection = .code
            codeSessionsStore.selectedSessionId = session.id
        }
    }
}
```

`statusColor`: `"done"/"idle"` → green, `"error"/"stopped"` → gray, `"running"` → orange.

- [ ] **Step 2: Verify `CodeSessionsStore` has `sessions` array and `switchToSession(_:)`**

```bash
grep -n "var sessions\|func switchToSession\|func recent" "EonCode/Shared/Services/Code/CodeSessionsStore.swift" | head -10
```

The sidebar uses `codeSessionsStore.sessions` sorted inline (no `recentSessions(limit:)` method needed). If `switchToSession(_:)` doesn't exist, add it to `CodeSessionsStore.swift`.

⚠️ **Navigation — use `switchToSession()` instead of `selectedSessionId`** (`switchToSession` already exists, see `CodeSessionsStore.swift:192`). The tap gesture should be:
```swift
.onTapGesture {
    selectedSection = .code
    codeSessionsStore.switchToSession(session)
}
```
Verify method signature:
```bash
grep -n "switchToSession\|func switch" "EonCode/Shared/Services/Code/CodeSessionsStore.swift" | head -5
```

- [ ] **Step 3: Add empty state to PureChatView**

Find where the message list is shown when `agent.conversation.messages.isEmpty`. Add:

```swift
if agent.conversation.messages.isEmpty {
    VStack(spacing: 20) {
        Spacer()
        Image("navi-icon") // or app icon
            .resizable()
            .frame(width: 64, height: 64)
            .cornerRadius(14)
            .opacity(0.7)

        Text("Vad kan jag hjälpa dig med?")
            .font(.system(size: 17, weight: .medium))
            .foregroundColor(.secondary)

        HStack(spacing: 10) {
            ForEach(["Bygg en webbapp", "Debugga min kod", "Förklara en codebase"], id: \.self) { suggestion in
                Button(suggestion) {
                    inputText = suggestion
                }
                .font(.system(size: 13, weight: .medium))
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .background(Color.white.opacity(0.08))
                .cornerRadius(16)
            }
        }
        Spacer()
    }
    .frame(maxWidth: .infinity)
}
```

- [ ] **Step 4: Verify**
```bash
xcodebuild -scheme Navi -destination 'generic/platform=iOS' -quiet 2>&1 | grep -E "error:|Build succeeded"
```

- [ ] **Step 5: Commit**
```bash
git add "EonCode/Shared/Views/Main/SidebarView.swift" "EonCode/Shared/Views/Chat/PureChatView.swift" "EonCode/Shared/Services/Code/CodeSessionsStore.swift"
git commit -m "feat(ui): recent sessions in sidebar, empty state with suggestion chips"
```

---

## Task 9: Cost tracking — re-enable and add monthly + OpenRouter support

**Files:**
- Modify: `EonCode/Shared/Services/ClaudeAPI/CostTracker.swift`
- Modify: `EonCode/Shared/Services/ClaudeAPI/CostCalculator.swift`
- Modify: `EonCode/Shared/Services/Code/ServerCodeSession.swift`

- [ ] **Step 1: Read current CostTracker**

```bash
cat "EonCode/Shared/Services/ClaudeAPI/CostTracker.swift"
```

- [ ] **Step 2: Re-enable BOTH `record()` methods and add monthly tracking**

The existing `CostTracker.swift` has **two** record methods that are no-ops:
1. `func record(usage: TokenUsage, model: ClaudeModel) {}` — used by Anthropic chat (re-enable this)
2. A new `func record(usd: Double)` — add this for OpenRouter

First read the existing `CostTracker.swift` to understand all tracked fields (totalRequests, totalInputTokens, sessionUSD, etc.):
```bash
cat "EonCode/Shared/Services/ClaudeAPI/CostTracker.swift"
```

**Re-enable `record(usage:model:)` — restore ALL tracked fields, not just USD:**
```swift
func record(usage: TokenUsage, model: ClaudeModel) {
    let (usd, _) = CostCalculator.shared.calculate(usage: usage, model: model)
    // ⚠️ Also update token counts and session fields that the original tracked:
    totalRequests += 1
    totalInputTokens += usage.inputTokens
    totalOutputTokens += usage.outputTokens
    sessionRequests += 1
    sessionUSD += usd
    record(usd: usd)  // delegate USD + monthly tracking
}
```
Adapt property names to match the actual fields in the existing CostTracker (read the file first in Step 1).

**Add new `record(usd:)` method with monthly tracking:**
```swift
func record(usd: Double) {
    let now = Date()
    if !Calendar.current.isDate(monthlyResetDate, equalTo: now, toGranularity: .month) {
        monthlyUSD = 0
        monthlyResetDate = now
    }
    totalUSD += usd
    monthlyUSD += usd
    save()
}
```

**Add properties** (alongside existing `totalUSD`):
```swift
@Published var monthlyUSD: Double = 0
private var monthlyResetDate: Date = Date()
```

Persist `monthlyUSD` and `monthlyResetDate` alongside `totalUSD` in the existing save mechanism.

- [ ] **Step 3: Add `calculateOpenRouter` to CostCalculator**

OpenRouter pricing for MiniMax M2.5 (as of 2026-03): $0.30/M input, $1.10/M output (verify current pricing at openrouter.ai if needed).

⚠️ `OpenRouterPricing` and `openRouterPrices` must be at **class/type scope**, not inside the function body — Swift does not allow nested type declarations inside a method.

```swift
// At class scope (inside CostCalculator class body, alongside existing properties):
private struct OpenRouterPricing {
    let inputPerMillion: Double
    let outputPerMillion: Double
}

private static let openRouterPrices: [String: OpenRouterPricing] = [
    "minimax":   OpenRouterPricing(inputPerMillion: 0.30, outputPerMillion: 1.10),
    "qwen":      OpenRouterPricing(inputPerMillion: 0.00, outputPerMillion: 0.00),  // free
    "deepseek":  OpenRouterPricing(inputPerMillion: 0.55, outputPerMillion: 2.19),
]

// Static method (implicitly @MainActor on a @MainActor class — call site in handleEvent is fine):
static func calculateOpenRouter(inputTokens: Int, outputTokens: Int, model: String) -> Double {
    let pricing = openRouterPrices[model] ?? OpenRouterPricing(inputPerMillion: 0.50, outputPerMillion: 1.50)
    let inputCost  = Double(inputTokens)  / 1_000_000 * pricing.inputPerMillion
    let outputCost = Double(outputTokens) / 1_000_000 * pricing.outputPerMillion
    return inputCost + outputCost
}
```

- [ ] **Step 4: Handle `RUN_FINISHED` usage in ServerCodeSession**

In `ServerCodeSession.swift`, find `handleEvent()`. In the `.runFinished` case, add:
```swift
case .runFinished:
    isRunning = false
    phase = "done"
    // Cost tracking
    if let usage = event.usage {
        let usd = CostCalculator.calculateOpenRouter(
            inputTokens:  usage.inputTokens,
            outputTokens: usage.outputTokens,
            model:        usage.model
        )
        CostTracker.shared.record(usd: usd)
    }
```

Add `usage` field and a **top-level** `ServerUsage` struct to `ServerCodeSession.swift`:

```swift
// Add as a TOP-LEVEL struct at file scope (adjacent to ServerEvent, NOT nested inside handleEvent):
struct ServerUsage: Decodable {
    let inputTokens: Int
    let outputTokens: Int
    let model: String
}

// Inside ServerEvent struct, add the field:
// let usage: ServerUsage?
```

⚠️ **`ServerEvent` uses a manual `CodingKeys` enum** (line ~88). You must add the key and decode line or `usage` will always decode as `nil`:
```swift
// In CodingKeys enum:
case usage

// In init(from decoder:):
usage = try? c.decode(ServerUsage.self, forKey: .usage)
```
Verify the manual decode:
```bash
grep -n "CodingKeys\|usage\|case type\|case text" "EonCode/Shared/Services/Code/ServerCodeSession.swift" | head -20
```

- [ ] **Step 5: Verify**
```bash
xcodebuild -scheme Navi -destination 'generic/platform=iOS' -quiet 2>&1 | grep -E "error:|Build succeeded"
```

- [ ] **Step 6: Commit**
```bash
git add "EonCode/Shared/Services/ClaudeAPI/CostTracker.swift" "EonCode/Shared/Services/ClaudeAPI/CostCalculator.swift" "EonCode/Shared/Services/Code/ServerCodeSession.swift"
git commit -m "feat(cost): re-enable tracking, add monthly bucketing and OpenRouter pricing"
```

---

## Task 10: Settings — cost dashboard, model selector, API key status

**Files:**
- Modify: `EonCode/Shared/Views/Settings/SettingsView.swift`
- Modify: `EonCode/Shared/Services/Persistence/SettingsStore.swift`

- [ ] **Step 1: Add per-view model settings to SettingsStore**

```swift
@AppStorage("chatModel") var chatModel: String = "claude-sonnet-4-6"
@AppStorage("codeModel") var codeModel: String = "minimax"
```

- [ ] **Step 2: Add cost dashboard section to SettingsView**

```swift
Section("Kostnad") {
    HStack {
        Label("Denna månad", systemImage: "calendar")
        Spacer()
        VStack(alignment: .trailing, spacing: 2) {
            Text(formatSEK(costTracker.monthlyUSD * ExchangeRateService.shared.usdToSEK))
                .font(.system(size: 15, weight: .semibold))
            Text(String(format: "$%.4f", costTracker.monthlyUSD))
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }
    HStack {
        Label("Totalt", systemImage: "chart.bar")
        Spacer()
        Text(formatSEK(costTracker.totalUSD * ExchangeRateService.shared.usdToSEK))
            .foregroundColor(.secondary)
    }
}
```

- [ ] **Step 3: Add model selector section**

```swift
Section("Modell") {
    Picker("Chatt", selection: $settings.chatModel) {
        Text("Claude Sonnet 4.6").tag("claude-sonnet-4-6")
        Text("Claude Haiku 4.5").tag("claude-haiku-4-5-20251001")
    }
    Picker("Kod-agent", selection: $settings.codeModel) {
        Text("MiniMax M2.5 (standard)").tag("minimax")
        Text("Qwen3-Coder (gratis)").tag("qwen")
        Text("DeepSeek R1").tag("deepseek")
        Text("Claude Sonnet 4.6").tag("claude")
    }
}
```

- [ ] **Step 4: Add API key status indicators**

⚠️ API keys are stored in `KeychainManager`, **not** `SettingsStore`. Use the existing convenience properties (not `get(key:)` which throws):
```bash
grep -n "anthropicAPIKey\|openRouterAPIKey\|var.*Key\|KeychainManager" "EonCode/Shared/Services/Code/ServerCodeSession.swift" | head -5
grep -n "var anthropic\|var openRouter\|var.*APIKey" "EonCode/Shared/Utilities/KeychainManager.swift" | head -5
```

```swift
Section("API-nycklar") {
    // ⚠️ KeychainManager.get(key:) is `throws` — use convenience properties instead
    // e.g. KeychainManager.shared.anthropicAPIKey and KeychainManager.shared.openRouterAPIKey
    apiKeyRow("Anthropic", hasKey: !(KeychainManager.shared.anthropicAPIKey ?? "").isEmpty)
    apiKeyRow("OpenRouter", hasKey: !(KeychainManager.shared.openRouterAPIKey ?? "").isEmpty)
}

func apiKeyRow(_ name: String, hasKey: Bool) -> some View {
    HStack {
        Text(name)
        Spacer()
        Circle()
            .fill(hasKey ? Color.green : Color.red)
            .frame(width: 8, height: 8)
        Text(hasKey ? "Aktiv" : "Ej satt")
            .font(.caption)
            .foregroundColor(.secondary)
    }
}
```

- [ ] **Step 5: Verify**
```bash
xcodebuild -scheme Navi -destination 'generic/platform=iOS' -quiet 2>&1 | grep -E "error:|Build succeeded"
```

- [ ] **Step 6: Commit**
```bash
git add "EonCode/Shared/Views/Settings/SettingsView.swift" "EonCode/Shared/Services/Persistence/SettingsStore.swift"
git commit -m "feat(settings): cost dashboard, per-view model selector, API key status indicators"
```

---

## Task 11: Final verification and cleanup

- [ ] **Step 1: Full build — zero errors**
```bash
xcodebuild -scheme Navi -destination 'generic/platform=iOS' 2>&1 | grep -E "error:|warning:|Build succeeded|Build failed"
```
Expected: `Build succeeded` with zero errors.

- [ ] **Step 2: Run navi-ui-reviewer on all changed views**

Dispatch `navi-ui-reviewer` with a list of all modified view files for a final pass.

- [ ] **Step 3: Final commit**
```bash
git add -A
git commit -m "feat: iOS markdown + UI improvements — ChatGPT-quality rendering, bubble redesign, cost tracking"
```

- [ ] **Step 4: Push to remote**
```bash
git push origin dev/next-200-changes
```
