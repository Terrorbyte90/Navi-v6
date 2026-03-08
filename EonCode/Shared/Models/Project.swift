import Foundation
import SwiftUI

struct NaviProject: Identifiable, Codable, Equatable {
    var id: UUID
    var name: String
    var description: String
    var rootPath: String          // Relative to iCloud container or absolute
    var iCloudPath: String?       // iCloud Drive path if synced
    var localPath: String?        // Local override path
    var createdAt: Date
    var modifiedAt: Date
    var activeModel: ClaudeModel
    var isAgentRunning: Bool
    var agentStatus: String
    var fileCount: Int
    var totalSize: Int64
    var activeConversationID: UUID?
    var activeVersionID: UUID?
    var customSystemPrompt: String?
    var tags: [String]
    var isFavorite: Bool
    var color: ProjectColor
    var githubRepoFullName: String?   // e.g. "owner/repo"
    var githubBranch: String?         // active branch

    init(
        id: UUID = UUID(),
        name: String,
        description: String = "",
        rootPath: String,
        iCloudPath: String? = nil,
        localPath: String? = nil,
        activeModel: ClaudeModel = .haiku,
        color: ProjectColor = .blue
    ) {
        self.id = id
        self.name = name
        self.description = description
        self.rootPath = rootPath
        self.iCloudPath = iCloudPath
        self.localPath = localPath
        self.createdAt = Date()
        self.modifiedAt = Date()
        self.activeModel = activeModel
        self.isAgentRunning = false
        self.agentStatus = ""
        self.fileCount = 0
        self.totalSize = 0
        self.tags = []
        self.isFavorite = false
        self.color = color
    }

    var resolvedURL: URL? {
        if let local = localPath {
            return URL(fileURLWithPath: local)
        }
        if let cloud = iCloudPath {
            return URL(fileURLWithPath: cloud)
        }
        return nil
    }

    static func == (lhs: NaviProject, rhs: NaviProject) -> Bool {
        lhs.id == rhs.id
    }
}

enum ProjectColor: String, Codable, CaseIterable {
    case blue, green, orange, purple, red, yellow, teal, pink

    var color: Color {
        switch self {
        case .blue: return .blue
        case .green: return .green
        case .orange: return .orange
        case .purple: return .purple
        case .red: return .red
        case .yellow: return .yellow
        case .teal: return .teal
        case .pink: return .pink
        }
    }
}
