import Foundation
import SwiftUI

// MARK: - Artifact model

struct Artifact: Identifiable, Codable, Equatable {
    var id: UUID
    var title: String
    var content: String
    var type: ArtifactType
    var language: String?         // For code artifacts
    var filePath: String?         // Original file path (if from agent)
    var projectID: UUID?
    var conversationID: UUID?
    var createdAt: Date
    var modifiedAt: Date
    var isFavorite: Bool
    var tags: [String]
    var sourceDescription: String // e.g. "Skriven av agent", "Klistrad in", "Uppladdad"

    init(
        id: UUID = UUID(),
        title: String,
        content: String,
        type: ArtifactType,
        language: String? = nil,
        filePath: String? = nil,
        projectID: UUID? = nil,
        conversationID: UUID? = nil,
        sourceDescription: String = "Skapad manuellt"
    ) {
        self.id = id
        self.title = title
        self.content = content
        self.type = type
        self.language = language
        self.filePath = filePath
        self.projectID = projectID
        self.conversationID = conversationID
        self.createdAt = Date()
        self.modifiedAt = Date()
        self.isFavorite = false
        self.tags = []
        self.sourceDescription = sourceDescription
    }

    var displayIcon: String {
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

    var displayColor: Color {
        switch type {
        case .code:      return .blue
        case .markdown:  return .purple
        case .text:      return .primary
        case .json:      return .orange
        case .html:      return .green
        case .csv:       return .teal
        case .image:     return .pink
        case .pdf:       return .red
        case .other:     return .secondary
        }
    }

    var wordCount: Int {
        content.components(separatedBy: .whitespacesAndNewlines).filter { !$0.isEmpty }.count
    }

    var lineCount: Int {
        content.components(separatedBy: "\n").count
    }

    var sizeDescription: String {
        let bytes = content.utf8.count
        if bytes < 1024 { return "\(bytes) B" }
        if bytes < 1024 * 1024 { return String(format: "%.1f KB", Double(bytes) / 1024) }
        return String(format: "%.1f MB", Double(bytes) / (1024 * 1024))
    }

    static func == (lhs: Artifact, rhs: Artifact) -> Bool { lhs.id == rhs.id }
}

// MARK: - Artifact type

enum ArtifactType: String, Codable, CaseIterable {
    case code, markdown, text, json, html, csv, image, pdf, other

    var displayName: String {
        switch self {
        case .code:     return "Kod"
        case .markdown: return "Markdown"
        case .text:     return "Text"
        case .json:     return "JSON"
        case .html:     return "HTML"
        case .csv:      return "CSV"
        case .image:    return "Bild"
        case .pdf:      return "PDF"
        case .other:    return "Övrigt"
        }
    }

    static func infer(from path: String, content: String) -> ArtifactType {
        let ext = URL(fileURLWithPath: path).pathExtension.lowercased()
        switch ext {
        case "swift", "py", "js", "ts", "tsx", "jsx", "rs", "go", "kt", "java", "c", "cpp", "h", "m", "rb", "sh", "bash", "zsh":
            return .code
        case "md", "markdown": return .markdown
        case "json":           return .json
        case "html", "htm":    return .html
        case "csv":            return .csv
        case "png", "jpg", "jpeg", "gif", "webp", "svg": return .image
        case "pdf":            return .pdf
        case "txt":            return .text
        default:
            // Infer from content
            if content.hasPrefix("{") || content.hasPrefix("[") { return .json }
            if content.hasPrefix("<html") || content.hasPrefix("<!DOCTYPE") { return .html }
            if content.hasPrefix("#") && content.contains("\n") { return .markdown }
            return .other
        }
    }

    static func language(for path: String) -> String? {
        let ext = URL(fileURLWithPath: path).pathExtension.lowercased()
        let map: [String: String] = [
            "swift": "Swift", "py": "Python", "js": "JavaScript",
            "ts": "TypeScript", "tsx": "TypeScript", "jsx": "JavaScript",
            "rs": "Rust", "go": "Go", "kt": "Kotlin", "java": "Java",
            "c": "C", "cpp": "C++", "h": "C/C++", "m": "Objective-C",
            "rb": "Ruby", "sh": "Shell", "bash": "Bash", "zsh": "Zsh",
            "css": "CSS", "html": "HTML", "xml": "XML", "yaml": "YAML",
            "yml": "YAML", "toml": "TOML", "sql": "SQL"
        ]
        return map[ext]
    }
}

// MARK: - ArtifactStore

@MainActor
final class ArtifactStore: ObservableObject {
    static let shared = ArtifactStore()

    @Published var artifacts: [Artifact] = []

    private let storageKey = "navi.artifacts"
    private let maxArtifacts = 500

    private init() {
        load()
    }

    // MARK: - CRUD

    func save(_ artifact: Artifact) {
        if let idx = artifacts.firstIndex(where: { $0.id == artifact.id }) {
            var updated = artifact
            updated.modifiedAt = Date()
            artifacts[idx] = updated
        } else {
            artifacts.insert(artifact, at: 0)
            // Trim if over limit
            if artifacts.count > maxArtifacts {
                artifacts = Array(artifacts.prefix(maxArtifacts))
            }
        }
        persist()
    }

    func delete(_ artifact: Artifact) {
        artifacts.removeAll { $0.id == artifact.id }
        persist()
    }

    func deleteAll(where predicate: (Artifact) -> Bool) {
        artifacts.removeAll(where: predicate)
        persist()
    }

    func toggleFavorite(_ artifact: Artifact) {
        if let idx = artifacts.firstIndex(where: { $0.id == artifact.id }) {
            artifacts[idx].isFavorite.toggle()
            persist()
        }
    }

    // MARK: - Auto-save from agent file writes

    /// Called by ToolExecutor when write_file succeeds
    func recordFromWrite(path: String, content: String, projectID: UUID? = nil, conversationID: UUID? = nil) {
        let fileName = URL(fileURLWithPath: path).lastPathComponent
        let type = ArtifactType.infer(from: path, content: content)
        let lang = ArtifactType.language(for: path)

        // Update existing if same path + project
        if let idx = artifacts.firstIndex(where: { $0.filePath == path && $0.projectID == projectID }) {
            artifacts[idx].content = content
            artifacts[idx].modifiedAt = Date()
            artifacts[idx].title = fileName
            persist()
            return
        }

        let artifact = Artifact(
            title: fileName,
            content: content,
            type: type,
            language: lang,
            filePath: path,
            projectID: projectID,
            conversationID: conversationID,
            sourceDescription: "Skriven av agent"
        )
        save(artifact)
    }

    // MARK: - Filtering

    func artifacts(forProject projectID: UUID) -> [Artifact] {
        artifacts.filter { $0.projectID == projectID }
    }

    func artifacts(forConversation conversationID: UUID) -> [Artifact] {
        artifacts.filter { $0.conversationID == conversationID }
    }

    func search(_ query: String) -> [Artifact] {
        let q = query.lowercased()
        return artifacts.filter {
            $0.title.lowercased().contains(q) ||
            $0.content.lowercased().contains(q) ||
            $0.tags.contains { $0.lowercased().contains(q) }
        }
    }

    var favorites: [Artifact] {
        artifacts.filter { $0.isFavorite }
    }

    // MARK: - Persistence

    private func persist() {
        guard let data = try? JSONEncoder().encode(artifacts) else { return }
        UserDefaults.standard.set(data, forKey: storageKey)
    }

    private func load() {
        guard let data = UserDefaults.standard.data(forKey: storageKey),
              let decoded = try? JSONDecoder().decode([Artifact].self, from: data)
        else { return }
        artifacts = decoded
    }
}
