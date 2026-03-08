import SwiftUI

struct FileTreeView: View {
    let project: NaviProject
    @Binding var selectedNode: FileNode?
    @ObservedObject private var indexer = ProjectIndexer.shared

    var rootNode: FileNode? {
        indexer.fileTree[project.id]
    }

    var body: some View {
        ScrollView {
            if let root = rootNode {
                LazyVStack(alignment: .leading, spacing: 1) {
                    ForEach(root.children ?? [], id: \.id) { node in
                        FileNodeRow(
                            node: node,
                            selectedNode: $selectedNode,
                            depth: 0
                        )
                    }
                }
                .padding(.vertical, 4)
            } else {
                VStack(spacing: 12) {
                    ProgressView()
                    Text("Indexerar…")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.top, 40)
                .task {
                    await indexer.index(project: project)
                }
            }
        }
    }
}

struct FileNodeRow: View {
    @ObservedObject var node: FileNode
    @Binding var selectedNode: FileNode?
    let depth: Int
    @State private var showDeleteConfirmation = false

    private var isSelected: Bool { selectedNode?.id == node.id }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                if node.isDirectory {
                    withAnimation(.easeInOut(duration: 0.15)) {
                        node.isExpanded.toggle()
                    }
                } else {
                    selectedNode = node
                }
            } label: {
                HStack(spacing: 6) {
                    // Indent
                    Rectangle()
                        .fill(Color.clear)
                        .frame(width: CGFloat(depth) * 16)

                    // Expand arrow for directories
                    if node.isDirectory {
                        Image(systemName: node.isExpanded ? "chevron.down" : "chevron.right")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundColor(.secondary.opacity(0.6))
                            .frame(width: 12)
                    } else {
                        Rectangle()
                            .fill(Color.clear)
                            .frame(width: 12)
                    }

                    // Icon
                    Image(systemName: node.icon)
                        .font(.system(size: 12))
                        .foregroundColor(iconColor)
                        .frame(width: 16)

                    // Name
                    Text(node.name)
                        .font(.system(size: 13))
                        .foregroundColor(isSelected ? .white : .primary)
                        .lineLimit(1)

                    Spacer()

                    // File size
                    if !node.isDirectory && node.size > 0 {
                        Text(node.size.formattedFileSize)
                            .font(.system(size: 10))
                            .foregroundColor(.secondary.opacity(0.5))
                    }
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .contentShape(Rectangle())
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(isSelected ? Color.accentNavi.opacity(0.3) : Color.clear)
                )
            }
            .buttonStyle(.plain)
            .contextMenu { contextMenuItems }

            // Children (animated)
            if node.isDirectory && node.isExpanded {
                ForEach(node.children ?? [], id: \.id) { child in
                    FileNodeRow(node: child, selectedNode: $selectedNode, depth: depth + 1)
                }
            }
        }
        .padding(.horizontal, 4)
        .alert("Ta bort \"\(node.name)\"?", isPresented: $showDeleteConfirmation) {
            Button("Avbryt", role: .cancel) {}
            Button("Ta bort", role: .destructive) {
                try? FileManager.default.removeItem(atPath: node.path)
                if selectedNode?.id == node.id { selectedNode = nil }
            }
        } message: {
            Text(node.isDirectory ? "Mappen och allt dess innehåll tas bort permanent." : "Filen tas bort permanent.")
        }
    }

    var iconColor: Color {
        if node.isDirectory { return .accentNavi.opacity(0.8) }
        switch node.fileType {
        case .swift: return Color(red: 0.9, green: 0.5, blue: 0.2)
        case .python: return Color(red: 0.3, green: 0.7, blue: 0.9)
        case .javascript, .typescript: return Color(red: 0.9, green: 0.85, blue: 0.3)
        case .html: return Color(red: 0.9, green: 0.4, blue: 0.3)
        case .css: return Color(red: 0.3, green: 0.6, blue: 0.9)
        case .json: return Color(red: 0.7, green: 0.8, blue: 0.5)
        case .markdown: return Color.secondary
        default: return Color.secondary
        }
    }

    @ViewBuilder
    var contextMenuItems: some View {
        Button("Öppna") { selectedNode = node }
        Button("Kopiera sökväg") {
            #if os(macOS)
            NSPasteboard.general.setString(node.path, forType: .string)
            #else
            UIPasteboard.general.string = node.path
            #endif
        }
        #if os(macOS)
        Button("Visa i Finder") {
            NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: node.path)])
        }
        #endif
        Divider()
        Button("Ta bort", role: .destructive) {
            showDeleteConfirmation = true
        }
    }
}

// MARK: - Previews

#Preview("FileTreeView") {
    let project = NaviProject(name: "Navi Preview", rootPath: "/tmp/preview", color: .blue)
    return FileTreeView(project: project, selectedNode: .constant(nil))
        .frame(width: 260, height: 400)
        .background(Color.black)
}
