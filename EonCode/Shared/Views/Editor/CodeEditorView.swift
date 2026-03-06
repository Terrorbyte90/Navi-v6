import SwiftUI

struct CodeEditorView: View {
    @Binding var content: String
    let fileType: FileType
    var isReadOnly = false
    var onSave: ((String) -> Void)? = nil

    @State private var editableContent: String = ""
    @State private var isDirty = false
    @State private var showSearch = false
    @State private var searchQuery = ""
    @State private var replaceQuery = ""

    var body: some View {
        VStack(spacing: 0) {
            // Toolbar
            EditorToolbar(
                isDirty: isDirty,
                fileType: fileType,
                showSearch: $showSearch,
                onSave: saveFile
            )

            Divider().opacity(0.2)

            // Search bar
            if showSearch {
                SearchReplaceBar(
                    searchQuery: $searchQuery,
                    replaceQuery: $replaceQuery,
                    onClose: { showSearch = false },
                    onReplace: replaceAll
                )
                Divider().opacity(0.2)
            }

            // Editor
            HStack(spacing: 0) {
                // Line numbers
                LineNumberView(text: editableContent)
                    .frame(width: 44)

                Divider().opacity(0.1)

                // Code area
                #if os(macOS)
                NSTextViewWrapper(text: $editableContent, isReadOnly: isReadOnly) {
                    isDirty = true
                }
                #else
                IOSCodeEditor(text: $editableContent, isReadOnly: isReadOnly) {
                    isDirty = true
                }
                #endif
            }
        }
        .background(Color.codeBackground)
        .onAppear {
            editableContent = content
        }
        .onChange(of: content) { new in
            if !isDirty { editableContent = new }
        }
    }

    private func saveFile() {
        content = editableContent
        isDirty = false
        onSave?(editableContent)
    }

    private func replaceAll() {
        guard !searchQuery.isEmpty else { return }
        editableContent = editableContent.replacingOccurrences(of: searchQuery, with: replaceQuery)
        isDirty = true
    }
}

// MARK: - Editor Toolbar

struct EditorToolbar: View {
    let isDirty: Bool
    let fileType: FileType
    @Binding var showSearch: Bool
    let onSave: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            // File type badge
            Text(fileType.syntaxLanguage)
                .font(.system(size: 11, weight: .medium, design: .monospaced))
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(Color.white.opacity(0.08))
                .cornerRadius(6)
                .foregroundColor(.secondary)

            Spacer()

            if isDirty {
                Circle()
                    .fill(Color.orange)
                    .frame(width: 6, height: 6)
            }

            Button {
                showSearch.toggle()
            } label: {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 13))
                    .foregroundColor(showSearch ? .accentEon : .secondary)
            }
            .buttonStyle(.plain)
            .keyboardShortcut("f", modifiers: .command)

            if isDirty {
                Button("Spara", action: onSave)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.accentEon)
                    .buttonStyle(.plain)
                    .keyboardShortcut("s", modifiers: .command)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(Color.codeBackground)
    }
}

// MARK: - Line Numbers

struct LineNumberView: View {
    let text: String

    private var lineCount: Int {
        max(1, text.components(separatedBy: "\n").count)
    }

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            LazyVStack(alignment: .trailing, spacing: 0) {
                ForEach(1...lineCount, id: \.self) { n in
                    Text("\(n)")
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundColor(.secondary.opacity(0.4))
                        .frame(height: 18.5) // Match line height
                        .padding(.trailing, 8)
                }
            }
            .padding(.top, 8)
        }
        .background(Color.codeBackground)
    }
}

// MARK: - Search/Replace Bar

struct SearchReplaceBar: View {
    @Binding var searchQuery: String
    @Binding var replaceQuery: String
    let onClose: () -> Void
    let onReplace: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundColor(.secondary)
                .font(.system(size: 13))

            GlassTextField(placeholder: "Sök…", text: $searchQuery)

            Image(systemName: "arrow.2.squarepath")
                .foregroundColor(.secondary)
                .font(.system(size: 13))

            GlassTextField(placeholder: "Ersätt…", text: $replaceQuery)

            GlassButton("Ersätt alla", action: onReplace)
                .disabled(searchQuery.isEmpty)

            Button(action: onClose) {
                Image(systemName: "xmark")
                    .foregroundColor(.secondary)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(Color.codeBackground)
    }
}

// MARK: - macOS Native TextEditor wrapper

#if os(macOS)
import AppKit

struct NSTextViewWrapper: NSViewRepresentable {
    @Binding var text: String
    var isReadOnly: Bool
    var onChange: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSTextView.scrollableTextView()
        let tv = scrollView.documentView as! NSTextView

        tv.delegate = context.coordinator
        tv.isEditable = !isReadOnly
        tv.font = NSFont.monospacedSystemFont(ofSize: 13, weight: .regular)
        tv.backgroundColor = NSColor(Color.codeBackground)
        tv.textColor = .labelColor
        tv.isAutomaticQuoteSubstitutionEnabled = false
        tv.isAutomaticDashSubstitutionEnabled = false
        tv.isAutomaticSpellingCorrectionEnabled = false
        tv.isGrammarCheckingEnabled = false
        tv.usesFontPanel = false
        tv.isRichText = false
        tv.allowsUndo = true

        return scrollView
    }

    func updateNSView(_ nsView: NSScrollView, context: Context) {
        guard let tv = nsView.documentView as? NSTextView else { return }
        if tv.string != text {
            let selectedRange = tv.selectedRange()
            tv.string = text
            tv.setSelectedRange(selectedRange)
        }
    }

    class Coordinator: NSObject, NSTextViewDelegate {
        var parent: NSTextViewWrapper
        init(_ parent: NSTextViewWrapper) { self.parent = parent }

        func textDidChange(_ notification: Notification) {
            guard let tv = notification.object as? NSTextView else { return }
            parent.text = tv.string
            parent.onChange()
        }
    }
}
#endif

// MARK: - iOS TextEditor wrapper

#if os(iOS)
struct IOSCodeEditor: View {
    @Binding var text: String
    var isReadOnly: Bool
    var onChange: () -> Void

    var body: some View {
        TextEditor(text: $text)
            .font(.system(size: 13, design: .monospaced))
            .foregroundColor(.primary)
            .scrollContentBackground(.hidden)
            .background(Color.codeBackground)
            .disabled(isReadOnly)
            .autocorrectionDisabled()
            .autocapitalization(.none)
            .onChange(of: text) { _ in onChange() }
    }
}
#endif

// MARK: - Previews

#Preview("CodeEditorView – Swift") {
    CodeEditorView(
        content: .constant("""
import SwiftUI

struct MyView: View {
    var body: some View {
        Text("Hej världen!")
            .font(.largeTitle)
            .padding()
    }
}
"""),
        fileType: .swift
    )
    .frame(width: 500, height: 400)
}

#Preview("EditorToolbar") {
    EditorToolbar(
        isDirty: true,
        fileType: .swift,
        showSearch: .constant(false),
        onSave: {}
    )
    .background(Color.black)
}

#Preview("LineNumberView") {
    LineNumberView(text: "rad ett\nrad två\nrad tre\nrad fyra\nrad fem")
        .frame(width: 44, height: 120)
        .background(Color.black)
}

#Preview("SearchReplaceBar") {
    SearchReplaceBar(
        searchQuery: .constant("foo"),
        replaceQuery: .constant("bar"),
        onClose: {},
        onReplace: {}
    )
    .background(Color.black)
}
