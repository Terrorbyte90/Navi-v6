import SwiftUI

// MARK: - ArtifactView
// Main artifact browser — shows all saved artifacts with search, filter, preview and edit.

struct ArtifactView: View {
    @StateObject private var store = ArtifactStore.shared
    @StateObject private var projectStore = ProjectStore.shared

    @State private var searchText = ""
    @State private var selectedType: ArtifactType? = nil
    @State private var selectedArtifact: Artifact? = nil
    @State private var showNewArtifact = false
    @State private var showDeleteConfirm = false
    @State private var artifactToDelete: Artifact? = nil

    var filtered: [Artifact] {
        var result = store.artifacts
        if let type = selectedType {
            result = result.filter { $0.type == type }
        }
        if !searchText.isEmpty {
            result = store.search(searchText)
            if let type = selectedType {
                result = result.filter { $0.type == type }
            }
        }
        return result
    }

    var body: some View {
        #if os(macOS)
        macLayout
        #else
        iOSLayout
        #endif
    }

    // MARK: - macOS layout (split view)

    #if os(macOS)
    var macLayout: some View {
        HSplitView {
            // Left: list
            VStack(spacing: 0) {
                artifactToolbar
                Divider().opacity(0.15)
                typeFilter
                Divider().opacity(0.1)
                artifactList
            }
            .frame(minWidth: 260, maxWidth: 340)
            .background(Color.sidebarBackground)

            // Right: detail/editor
            if let artifact = selectedArtifact {
                ArtifactDetailView(artifact: artifact, onUpdate: { store.save($0) })
            } else {
                artifactEmptyDetail
            }
        }
        .sheet(isPresented: $showNewArtifact) {
            NewArtifactSheet { artifact in
                store.save(artifact)
                selectedArtifact = artifact
            }
            .frame(width: 560, height: 480)
        }
    }
    #endif

    // MARK: - iOS layout (list → detail push)

    #if os(iOS)
    var iOSLayout: some View {
        NavigationView {
            VStack(spacing: 0) {
                typeFilter
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                Divider().opacity(0.1)
                artifactList
            }
            .navigationTitle("Artefakter")
            .navigationBarTitleDisplayMode(.large)
            .searchable(text: $searchText, prompt: "Sök artefakter…")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        showNewArtifact = true
                    } label: {
                        Image(systemName: "plus")
                    }
                }
            }
            .sheet(isPresented: $showNewArtifact) {
                NewArtifactSheet { artifact in
                    store.save(artifact)
                }
            }
        }
        .navigationViewStyle(.stack)
    }
    #endif

    // MARK: - Toolbar (macOS)

    var artifactToolbar: some View {
        HStack(spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
                TextField("Sök…", text: $searchText)
                    .font(.system(size: 13))
                    #if os(macOS)
                    .textFieldStyle(.plain)
                    #endif
                if !searchText.isEmpty {
                    Button { searchText = "" } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 12))
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(Color.white.opacity(0.06))
            .cornerRadius(8)

            Button {
                showNewArtifact = true
            } label: {
                Image(systemName: "plus")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(Color.accentNavi)
                    .frame(width: 28, height: 28)
                    .background(Color.accentNavi.opacity(0.12))
                    .cornerRadius(7)
            }
            .buttonStyle(.plain)
            .help("Ny artefakt")
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
    }

    // MARK: - Type filter chips

    var typeFilter: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                typeChip(nil, label: "Alla", icon: "square.grid.2x2")
                ForEach(usedTypes, id: \.self) { type in
                    typeChip(type, label: type.displayName, icon: iconFor(type))
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
        }
    }

    var usedTypes: [ArtifactType] {
        let types = Set(store.artifacts.map { $0.type })
        return ArtifactType.allCases.filter { types.contains($0) }
    }

    @ViewBuilder
    private func typeChip(_ type: ArtifactType?, label: String, icon: String) -> some View {
        let isSelected = selectedType == type
        Button {
            withAnimation(.easeInOut(duration: 0.15)) {
                selectedType = isSelected ? nil : type
            }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 11))
                Text(label)
                    .font(.system(size: 12, weight: .medium))
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(
                Capsule()
                    .fill(isSelected ? Color.accentNavi.opacity(0.15) : Color.primary.opacity(0.06))
            )
            .foregroundColor(isSelected ? Color.accentNavi : Color.primary.opacity(0.5))
            .contentShape(Capsule())
            .overlay(
                Capsule()
                    .stroke(isSelected ? Color.accentNavi.opacity(0.3) : Color.clear, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    private func iconFor(_ type: ArtifactType) -> String {
        switch type {
        case .code:      return "chevron.left.forwardslash.chevron.right"
        case .markdown:  return "doc.richtext"
        case .text:      return "doc.text"
        case .json:      return "curlybraces"
        case .html:      return "globe"
        case .csv:       return "tablecells"
        case .image:     return "photo"
        case .pdf:       return "doc.fill"
        case .other:     return "doc"
        }
    }

    // MARK: - Artifact list

    var artifactList: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                if filtered.isEmpty {
                    emptyState
                } else {
                    let favorites = filtered.filter { $0.isFavorite }
                    let rest = filtered.filter { !$0.isFavorite }

                    if !favorites.isEmpty {
                        artifactSectionHeader("Favoriter")
                        ForEach(favorites) { artifact in
                            artifactRow(artifact)
                        }
                    }

                    if !rest.isEmpty {
                        if !favorites.isEmpty {
                            artifactSectionHeader("Alla artefakter")
                        }
                        ForEach(rest) { artifact in
                            artifactRow(artifact)
                        }
                    }
                }
            }
            .padding(.bottom, 12)
        }
    }

    @ViewBuilder
    private func artifactRow(_ artifact: Artifact) -> some View {
        #if os(iOS)
        NavigationLink(destination: ArtifactDetailView(artifact: artifact, onUpdate: { store.save($0) })) {
            artifactRowContent(artifact)
        }
        .buttonStyle(.plain)
        .contextMenu { artifactContextMenu(artifact) }
        #else
        Button {
            selectedArtifact = artifact
        } label: {
            artifactRowContent(artifact)
        }
        .buttonStyle(.plain)
        .contextMenu { artifactContextMenu(artifact) }
        #endif
    }

    @ViewBuilder
    private func artifactRowContent(_ artifact: Artifact) -> some View {
        let isSelected: Bool = {
            #if os(macOS)
            return selectedArtifact?.id == artifact.id
            #else
            return false
            #endif
        }()

        HStack(spacing: 10) {
            // Type icon
            ZStack {
                RoundedRectangle(cornerRadius: 7)
                    .fill(artifact.displayColor.opacity(0.15))
                    .frame(width: 32, height: 32)
                Image(systemName: artifact.displayIcon)
                    .font(.system(size: 14))
                    .foregroundColor(artifact.displayColor)
            }

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Text(artifact.title)
                        .font(.system(size: 13, weight: isSelected ? .semibold : .regular))
                        .foregroundColor(isSelected ? .white : .primary)
                        .lineLimit(1)
                    if artifact.isFavorite {
                        Image(systemName: "star.fill")
                            .font(.system(size: 9))
                            .foregroundColor(.yellow)
                    }
                }
                HStack(spacing: 6) {
                    if let lang = artifact.language {
                        Text(lang)
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundColor(.secondary.opacity(0.6))
                    }
                    Text(artifact.sizeDescription)
                        .font(.system(size: 10))
                        .foregroundColor(.secondary.opacity(0.5))
                    Text("·")
                        .foregroundColor(.secondary.opacity(0.3))
                        .font(.system(size: 10))
                    Text(artifact.modifiedAt.relativeString)
                        .font(.system(size: 10))
                        .foregroundColor(.secondary.opacity(0.5))
                }
            }

            Spacer()
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(isSelected ? Color.accentNavi.opacity(0.15) : Color.clear)
        )
        .padding(.horizontal, 6)
    }

    @ViewBuilder
    private func artifactContextMenu(_ artifact: Artifact) -> some View {
        Button {
            store.toggleFavorite(artifact)
        } label: {
            Label(artifact.isFavorite ? "Ta bort favorit" : "Markera som favorit",
                  systemImage: artifact.isFavorite ? "star.slash" : "star")
        }

        Button {
            copyToClipboard(artifact.content)
        } label: {
            Label("Kopiera innehåll", systemImage: "doc.on.doc")
        }

        if let path = artifact.filePath {
            Button {
                copyToClipboard(path)
            } label: {
                Label("Kopiera sökväg", systemImage: "link")
            }
        }

        Divider()

        Button(role: .destructive) {
            store.delete(artifact)
            #if os(macOS)
            if selectedArtifact?.id == artifact.id { selectedArtifact = nil }
            #endif
        } label: {
            Label("Radera", systemImage: "trash")
        }
    }

    private func copyToClipboard(_ text: String) {
        #if os(macOS)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        #else
        UIPasteboard.general.string = text
        #endif
    }

    @ViewBuilder
    private func artifactSectionHeader(_ title: String) -> some View {
        Text(title.uppercased())
            .font(.system(size: 10, weight: .semibold))
            .foregroundColor(.secondary.opacity(0.5))
            .padding(.horizontal, 16)
            .padding(.top, 10)
            .padding(.bottom, 2)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "tray")
                .font(.system(size: 36))
                .foregroundColor(.secondary.opacity(0.3))
            Text(searchText.isEmpty ? "Inga artefakter ännu" : "Inga träffar")
                .font(.system(size: 14))
                .foregroundColor(.secondary.opacity(0.6))
            if searchText.isEmpty {
                Text("Agenten sparar automatiskt filer som artefakter.\nDu kan också skapa manuellt med +.")
                    .font(.system(size: 12))
                    .foregroundColor(.secondary.opacity(0.4))
                    .multilineTextAlignment(.center)
            }
        }
        .padding(.top, 48)
        .padding(.horizontal, 24)
    }

    var artifactEmptyDetail: some View {
        VStack(spacing: 12) {
            Image(systemName: "doc.text.magnifyingglass")
                .font(.system(size: 48))
                .foregroundColor(.secondary.opacity(0.25))
            Text("Välj en artefakt")
                .font(.system(size: 16))
                .foregroundColor(.secondary.opacity(0.5))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.chatBackground)
    }
}

// MARK: - ArtifactDetailView

struct ArtifactDetailView: View {
    let artifact: Artifact
    let onUpdate: (Artifact) -> Void

    @State private var editedContent: String
    @State private var editedTitle: String
    @State private var isEditing = false
    @State private var showCopied = false

    init(artifact: Artifact, onUpdate: @escaping (Artifact) -> Void) {
        self.artifact = artifact
        self.onUpdate = onUpdate
        self._editedContent = State(initialValue: artifact.content)
        self._editedTitle = State(initialValue: artifact.title)
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            detailHeader

            Divider().opacity(0.15)

            // Content
            if isEditing {
                TextEditor(text: $editedContent)
                    .font(.system(size: 13, design: .monospaced))
                    .scrollContentBackground(.hidden)
                    .background(Color.chatBackground)
                    .padding(12)
            } else {
                ScrollView {
                    Text(editedContent)
                        .font(.system(size: 13, design: artifact.type == .code || artifact.type == .json ? .monospaced : .default))
                        .foregroundColor(.primary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(16)
                        .textSelection(.enabled)
                }
            }
        }
        .background(Color.chatBackground)
        .onChange(of: artifact.id) { _ in
            editedContent = artifact.content
            editedTitle = artifact.title
            isEditing = false
        }
    }

    var detailHeader: some View {
        HStack(spacing: 12) {
            // Icon + title
            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(artifact.displayColor.opacity(0.15))
                    .frame(width: 36, height: 36)
                Image(systemName: artifact.displayIcon)
                    .font(.system(size: 16))
                    .foregroundColor(artifact.displayColor)
            }

            VStack(alignment: .leading, spacing: 2) {
                if isEditing {
                    TextField("Titel", text: $editedTitle)
                        .font(.system(size: 15, weight: .semibold))
                        #if os(macOS)
                        .textFieldStyle(.plain)
                        #endif
                } else {
                    Text(editedTitle)
                        .font(.system(size: 15, weight: .semibold))
                        .lineLimit(1)
                }
                HStack(spacing: 6) {
                    Text(artifact.type.displayName)
                        .font(.system(size: 11))
                        .foregroundColor(.secondary.opacity(0.6))
                    if let lang = artifact.language {
                        Text("·")
                            .foregroundColor(.secondary.opacity(0.3))
                        Text(lang)
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundColor(.secondary.opacity(0.6))
                    }
                    Text("·")
                        .foregroundColor(.secondary.opacity(0.3))
                    Text("\(artifact.lineCount) rader · \(artifact.sizeDescription)")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary.opacity(0.5))
                }
            }

            Spacer()

            // Actions
            HStack(spacing: 6) {
                // Copy
                Button {
                    copyToClipboard(editedContent)
                    withAnimation { showCopied = true }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                        withAnimation { showCopied = false }
                    }
                } label: {
                    Image(systemName: showCopied ? "checkmark" : "doc.on.doc")
                        .font(.system(size: 13))
                        .foregroundColor(showCopied ? .green : .secondary)
                        .frame(width: 28, height: 28)
                        .background(Color.white.opacity(0.06))
                        .cornerRadius(7)
                }
                .buttonStyle(.plain)
                .help("Kopiera")

                // Edit / Save
                Button {
                    if isEditing {
                        var updated = artifact
                        updated.content = editedContent
                        updated.title = editedTitle
                        onUpdate(updated)
                    }
                    isEditing.toggle()
                } label: {
                    Image(systemName: isEditing ? "checkmark.circle.fill" : "pencil")
                        .font(.system(size: 13))
                        .foregroundColor(isEditing ? .green : .secondary)
                        .frame(width: 28, height: 28)
                        .background(Color.white.opacity(0.06))
                        .cornerRadius(7)
                }
                .buttonStyle(.plain)
                .help(isEditing ? "Spara" : "Redigera")

                // Favorite
                Button {
                    ArtifactStore.shared.toggleFavorite(artifact)
                } label: {
                    Image(systemName: artifact.isFavorite ? "star.fill" : "star")
                        .font(.system(size: 13))
                        .foregroundColor(artifact.isFavorite ? .yellow : .secondary)
                        .frame(width: 28, height: 28)
                        .background(Color.white.opacity(0.06))
                        .cornerRadius(7)
                }
                .buttonStyle(.plain)
                .help(artifact.isFavorite ? "Ta bort favorit" : "Markera som favorit")
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    private func copyToClipboard(_ text: String) {
        #if os(macOS)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        #else
        UIPasteboard.general.string = text
        #endif
    }
}

// MARK: - NewArtifactSheet

struct NewArtifactSheet: View {
    let onSave: (Artifact) -> Void
    @Environment(\.dismiss) private var dismiss

    @State private var title = ""
    @State private var content = ""
    @State private var type: ArtifactType = .text
    @State private var language = ""

    var body: some View {
        NavigationView {
            VStack(spacing: 16) {
                // Title
                VStack(alignment: .leading, spacing: 6) {
                    Text("Titel")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.secondary)
                    GlassTextField(placeholder: "Artefaktens namn", text: $title)
                }

                // Type picker
                VStack(alignment: .leading, spacing: 6) {
                    Text("Typ")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.secondary)
                    Picker("Typ", selection: Binding<String>(
                        get: { type.rawValue },
                        set: { type = ArtifactType(rawValue: $0) ?? .text }
                    )) {
                        ForEach(ArtifactType.allCases, id: \.self) { t in
                            Text(t.displayName).tag(t.rawValue)
                        }
                    }
                    .pickerStyle(.menu)
                }

                // Language (for code)
                if type == .code {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Språk (valfritt)")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(.secondary)
                        GlassTextField(placeholder: "Swift, Python, JavaScript…", text: $language)
                    }
                }

                // Content
                VStack(alignment: .leading, spacing: 6) {
                    Text("Innehåll")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.secondary)
                    TextEditor(text: $content)
                        .font(.system(size: 13, design: type == .code || type == .json ? .monospaced : .default))
                        .scrollContentBackground(.hidden)
                        .background(Color.white.opacity(0.06))
                        .cornerRadius(10)
                        .frame(minHeight: 180)
                }

                Spacer()

                GlassButton("Spara artefakt", icon: "checkmark", isPrimary: true) {
                    let artifact = Artifact(
                        title: title.isEmpty ? "Namnlös artefakt" : title,
                        content: content,
                        type: type,
                        language: language.isEmpty ? nil : language,
                        sourceDescription: "Skapad manuellt"
                    )
                    onSave(artifact)
                    dismiss()
                }
                .disabled(content.isEmpty)
            }
            .padding()
            .navigationTitle("Ny artefakt")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Avbryt") { dismiss() }
                }
            }
            #else
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Avbryt") { dismiss() }
                }
            }
            #endif
        }
        .background(Color.chatBackground)
    }
}

// MARK: - Preview

#Preview("ArtifactView") {
    ArtifactView()
        #if os(macOS)
        .frame(width: 900, height: 600)
        #endif
}
