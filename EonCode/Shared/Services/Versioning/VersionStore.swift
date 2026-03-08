import Foundation

@MainActor
final class VersionStore: ObservableObject {
    static let shared = VersionStore()

    @Published var versions: [UUID: [ProjectVersion]] = [:]  // projectID → versions

    private let sync = iCloudSyncEngine.shared
    private init() {}

    // MARK: - Snapshot

    func createSnapshot(
        for project: NaviProject,
        name: String? = nil,
        branch: String = "main",
        changedFiles: [String] = []
    ) async throws -> ProjectVersion {
        var version = ProjectVersion(
            projectID: project.id,
            name: name,
            branch: branch,
            parentVersionID: versions[project.id]?.last?.id,
            filesChanged: changedFiles
        )

        // Store snapshot in iCloud
        let snapshotDir = sync.versionsRoot?
            .appendingPathComponent(project.id.uuidString)
            .appendingPathComponent(version.id.uuidString)

        if let dir = snapshotDir {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

            // Copy project files to snapshot
            if let projectURL = project.resolvedURL {
                let dest = dir.appendingPathComponent("files")
                try? FileManager.default.copyItem(at: projectURL, to: dest)
            }

            version.snapshotPath = "\(project.id.uuidString)/\(version.id.uuidString)"

            // Save version metadata
            let metaURL = dir.appendingPathComponent("version.json")
            try await sync.write(version, to: metaURL)
        }

        // Update in-memory cache
        var projectVersions = versions[project.id] ?? []
        projectVersions.append(version)
        versions[project.id] = projectVersions

        return version
    }

    // MARK: - Load versions

    func loadVersions(for project: NaviProject) async {
        guard let dir = sync.versionsRoot?.appendingPathComponent(project.id.uuidString),
              let subdirs = try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)
        else { return }

        var loaded: [ProjectVersion] = []
        for subdir in subdirs {
            let metaURL = subdir.appendingPathComponent("version.json")
            if let version = try? await sync.read(ProjectVersion.self, from: metaURL) {
                loaded.append(version)
            }
        }

        versions[project.id] = loaded.sorted { $0.createdAt < $1.createdAt }
    }

    // MARK: - Rollback

    func rollback(to version: ProjectVersion, project: NaviProject) async throws {
        guard let snapshotPath = version.snapshotPath,
              let versionsRoot = sync.versionsRoot
        else { throw VersionError.noSnapshot }

        let filesDir = versionsRoot
            .appendingPathComponent(snapshotPath)
            .appendingPathComponent("files")

        guard let projectURL = project.resolvedURL else { throw VersionError.noProjectURL }

        // Create auto-snapshot of current state before rollback
        _ = try? await createSnapshot(for: project, name: "before-rollback-\(Date().iso8601)", branch: version.branch)

        // Copy snapshot files back
        let fm = FileManager.default
        if fm.fileExists(atPath: projectURL.path) {
            try fm.removeItem(at: projectURL)
        }
        try fm.copyItem(at: filesDir, to: projectURL)
    }

    // MARK: - Delete

    func deleteVersion(_ version: ProjectVersion) async {
        guard let snapshotPath = version.snapshotPath,
              let versionsRoot = sync.versionsRoot
        else { return }

        let versionDir = versionsRoot.appendingPathComponent(snapshotPath)
        try? FileManager.default.removeItem(at: versionDir)

        var projectVersions = versions[version.projectID] ?? []
        projectVersions.removeAll { $0.id == version.id }
        versions[version.projectID] = projectVersions
    }

    func versionsForProject(_ projectID: UUID) -> [ProjectVersion] {
        versions[projectID] ?? []
    }
}

enum VersionError: LocalizedError {
    case noSnapshot, noProjectURL

    var errorDescription: String? {
        switch self {
        case .noSnapshot: return "Snapshot saknas"
        case .noProjectURL: return "Projektsökväg saknas"
        }
    }
}
