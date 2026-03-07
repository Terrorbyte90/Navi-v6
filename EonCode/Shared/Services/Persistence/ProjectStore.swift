import Foundation
import Combine

@MainActor
final class ProjectStore: ObservableObject {
    static let shared = ProjectStore()

    @Published var projects: [EonProject] = []
    @Published var activeProject: EonProject?
    @Published var isLoading = false

    private let sync = iCloudSyncEngine.shared
    private var cancellables = Set<AnyCancellable>()
    private let localKey = "localProjects"

    private init() {
        Task { await load() }

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(iCloudDidSync),
            name: .iCloudDidSync,
            object: nil
        )
    }

    // MARK: - Load

    func load() async {
        isLoading = true
        defer { isLoading = false }

        var loaded: [EonProject] = []

        // Load from iCloud first
        if let dir = sync.projectsRoot,
           let subdirs = try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil) {
            for subdir in subdirs {
                let metaURL = subdir.appendingPathComponent("project.json")
                if let project = try? await sync.read(EonProject.self, from: metaURL) {
                    loaded.append(project)
                }
            }
        }

        // Merge with local
        if let localData = UserDefaults.standard.data(forKey: localKey),
           let localProjects = try? JSONDecoder().decode([EonProject].self, from: localData) {
            for local in localProjects where !loaded.contains(where: { $0.id == local.id }) {
                loaded.append(local)
            }
        }

        projects = loaded.sorted { $0.modifiedAt > $1.modifiedAt }
    }

    // MARK: - Save

    func save(_ project: EonProject) async {
        var updated = project
        updated.modifiedAt = Date()

        // Update in array
        if let idx = projects.firstIndex(where: { $0.id == project.id }) {
            projects[idx] = updated
        } else {
            projects.insert(updated, at: 0)
        }

        // Save to iCloud
        if let dir = sync.urlForProject(project) {
            do {
                try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            } catch {
                NaviLog.error("ProjectStore: kunde inte skapa katalog", error: error)
            }
            let metaURL = dir.appendingPathComponent("project.json")
            do {
                try await sync.write(updated, to: metaURL)
            } catch {
                NaviLog.error("ProjectStore: kunde inte spara projekt '\(updated.name)'", error: error)
            }
        }

        saveLocally()
    }

    // MARK: - Create

    func create(name: String, at path: URL) async -> EonProject {
        // Allocate a stable ID first so the iCloud path is deterministic
        let stableID = UUID()
        let iCloudPath: String? = sync.projectsRoot?
            .appendingPathComponent(stableID.uuidString).path

        let project = EonProject(
            id: stableID,
            name: name,
            rootPath: path.path,
            iCloudPath: iCloudPath,
            localPath: path.path
        )

        // Create project directory
        try? FileManager.default.createDirectory(at: path, withIntermediateDirectories: true)

        await save(project)
        return project
    }

    // MARK: - Delete

    func delete(_ project: EonProject) async {
        projects.removeAll { $0.id == project.id }

        // Remove from iCloud
        if let dir = sync.urlForProject(project) {
            do {
                try FileManager.default.removeItem(at: dir)
            } catch {
                NaviLog.error("ProjectStore: kunde inte radera projekt '\(project.name)'", error: error)
            }
        }

        if activeProject?.id == project.id {
            activeProject = projects.first
        }

        saveLocally()
    }

    // MARK: - Find

    func project(by id: UUID?) -> EonProject? {
        guard let id = id else { return nil }
        return projects.first { $0.id == id }
    }

    // MARK: - Local cache

    private func saveLocally() {
        if let data = try? JSONEncoder().encode(projects) {
            UserDefaults.standard.set(data, forKey: localKey)
        }
    }

    @objc private func iCloudDidSync() {
        Task { await load() }
    }
}
