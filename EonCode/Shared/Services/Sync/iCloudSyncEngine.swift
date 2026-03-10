import Foundation
import Combine

@MainActor
final class iCloudSyncEngine: ObservableObject {
    static let shared = iCloudSyncEngine()

    @Published var isAvailable = false
    @Published var isSyncing = false
    @Published var lastSyncDate: Date?
    @Published var syncError: String?

    private let fm = FileManager.default
    private var metadataQuery: NSMetadataQuery?
    private var cancellables = Set<AnyCancellable>()

    // MARK: - iCloud container root

    var naviRoot: URL? {
        fm.url(forUbiquityContainerIdentifier: Constants.iCloud.containerID)?
            .appendingPathComponent("Documents")
            .appendingPathComponent(Constants.iCloud.rootFolder)
    }

    var projectsRoot: URL? {
        naviRoot?.appendingPathComponent(Constants.iCloud.projectsFolder)
    }

    var instructionsRoot: URL? {
        naviRoot?.appendingPathComponent(Constants.iCloud.instructionsFolder)
    }

    var versionsRoot: URL? {
        naviRoot?.appendingPathComponent(Constants.iCloud.versionsFolder)
    }

    var conversationsRoot: URL? {
        naviRoot?.appendingPathComponent(Constants.iCloud.conversationsFolder)
    }

    var deviceStatusRoot: URL? {
        naviRoot?.appendingPathComponent(Constants.iCloud.deviceStatusFolder)
    }

    var plansRoot: URL? {
        naviRoot?.appendingPathComponent(Constants.iCloud.plansFolder)
    }

    var agentsRoot: URL? {
        naviRoot?.appendingPathComponent(Constants.iCloud.agentsFolder)
    }

    var mediaRoot: URL? {
        let base: URL
        if let icloud = naviRoot {
            base = icloud
        } else if let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first {
            base = docs.appendingPathComponent("Navi")
        } else {
            return nil
        }
        return base.appendingPathComponent(Constants.iCloud.mediaFolder)
    }
    
    // MARK: - GitHub repos folder (iCloud)
    
    var githubReposRoot: URL? {
        let base: URL
        if let icloud = naviRoot {
            base = icloud
        } else if let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first {
            base = docs.appendingPathComponent("Navi")
        } else {
            return nil
        }
        return base.appendingPathComponent(Constants.iCloud.githubReposFolder)
    }

    var mediaImagesRoot: URL? {
        naviRoot?.appendingPathComponent(Constants.iCloud.mediaImagesFolder)
    }

    var mediaVideosRoot: URL? {
        naviRoot?.appendingPathComponent(Constants.iCloud.mediaVideosFolder)
    }

    var mediaAudioRoot: URL? {
        let base: URL
        if let icloud = naviRoot {
            base = icloud
        } else if let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first {
            base = docs.appendingPathComponent("Navi")
        } else {
            return nil
        }
        let dir = base.appendingPathComponent(Constants.iCloud.mediaAudioFolder)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private init() {
        checkAvailability()
        Task { await setupDirectories() }
        startMonitoring()
    }

    // MARK: - Setup

    private func checkAvailability() {
        isAvailable = fm.ubiquityIdentityToken != nil
    }

    func setupDirectories() async {
        guard let root = naviRoot else { return }

        let dirs = [
            root,
            root.appendingPathComponent(Constants.iCloud.projectsFolder),
            root.appendingPathComponent(Constants.iCloud.instructionsFolder),
            root.appendingPathComponent(Constants.iCloud.versionsFolder),
            root.appendingPathComponent(Constants.iCloud.conversationsFolder),
            root.appendingPathComponent(Constants.iCloud.deviceStatusFolder),
            root.appendingPathComponent(Constants.iCloud.checkpointsFolder),
            root.appendingPathComponent(Constants.iCloud.plansFolder),
            root.appendingPathComponent(Constants.iCloud.agentsFolder),
            root.appendingPathComponent(Constants.iCloud.mediaFolder),
            root.appendingPathComponent(Constants.iCloud.mediaImagesFolder),
            root.appendingPathComponent(Constants.iCloud.mediaVideosFolder),
            root.appendingPathComponent(Constants.iCloud.mediaAudioFolder),
            root.appendingPathComponent("Handoff"),
            root.appendingPathComponent("Handoff/completed")
        ]

        // Offload directory creation to a background thread — never block the main actor
        await Task.detached(priority: .background) {
            let fm = FileManager.default
            for dir in dirs {
                try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
            }
        }.value
    }

    // MARK: - Write with coordinator

    func write<T: Encodable>(_ value: T, to url: URL) async throws {
        let data = try value.encoded()
        try await writeData(data, to: url)
    }

    func writeData(_ data: Data, to url: URL) async throws {
        try fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            DispatchQueue.global(qos: .utility).async {
                let coordinator = NSFileCoordinator()
                var coordError: NSError?
                var blockRan = false
                coordinator.coordinate(writingItemAt: url, options: .forReplacing, error: &coordError) { writeURL in
                    blockRan = true
                    do {
                        try data.write(to: writeURL, options: .atomic)
                        cont.resume()
                    } catch {
                        cont.resume(throwing: error)
                    }
                }
                if !blockRan {
                    cont.resume(throwing: coordError ?? URLError(.cannotWriteToFile))
                }
            }
        }
    }

    // MARK: - Read with coordinator

    func read<T: Decodable>(_ type: T.Type, from url: URL) async throws -> T {
        let data = try await readData(from: url)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(type, from: data)
    }

    func readData(from url: URL) async throws -> Data {
        try? fm.startDownloadingUbiquitousItem(at: url)
        return try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Data, Error>) in
            DispatchQueue.global(qos: .userInitiated).async {
                let coordinator = NSFileCoordinator()
                var coordError: NSError?
                var blockRan = false
                coordinator.coordinate(readingItemAt: url, options: .withoutChanges, error: &coordError) { readURL in
                    blockRan = true
                    do {
                        cont.resume(returning: try Data(contentsOf: readURL))
                    } catch {
                        cont.resume(throwing: error)
                    }
                }
                if !blockRan {
                    cont.resume(throwing: coordError ?? URLError(.cannotOpenFile))
                }
            }
        }
    }

    // MARK: - iCloud metadata monitoring

    func startMonitoring() {
        guard isAvailable else { return }

        let query = NSMetadataQuery()
        query.searchScopes = [NSMetadataQueryUbiquitousDocumentsScope]
        query.predicate = NSPredicate(format: "%K BEGINSWITH %@",
                                      NSMetadataItemPathKey,
                                      naviRoot?.path ?? "")

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(queryDidUpdate(_:)),
            name: .NSMetadataQueryDidUpdate,
            object: query
        )

        query.start()
        metadataQuery = query
    }

    @objc private func queryDidUpdate(_ notification: Notification) {
        lastSyncDate = Date()
        NotificationCenter.default.post(name: .iCloudDidSync, object: nil)
    }

    // MARK: - Convenience helpers

    func urlForProject(_ project: NaviProject) -> URL? {
        projectsRoot?.appendingPathComponent(project.id.uuidString)
    }

    func urlForInstruction(_ instruction: Instruction) -> URL? {
        instructionsRoot?.appendingPathComponent(instruction.filename)
    }

    func urlForConversation(_ conversation: Conversation) -> URL? {
        conversationsRoot?.appendingPathComponent("\(conversation.id.uuidString).json")
    }

    // MARK: - User-selected folder (custom iCloud folder)

    var customProjectsFolder: URL? {
        get {
            guard let path = UserDefaults.standard.string(forKey: "customProjectsFolder") else { return nil }
            return URL(fileURLWithPath: path)
        }
        set {
            UserDefaults.standard.set(newValue?.path, forKey: "customProjectsFolder")
        }
    }

    func saveProject(_ project: NaviProject, to url: URL) async throws {
        let projectDir = url.appendingPathComponent(project.id.uuidString)
        try fm.createDirectory(at: projectDir, withIntermediateDirectories: true)
        let metaURL = projectDir.appendingPathComponent("project.json")
        try await write(project, to: metaURL)
    }
}

extension Notification.Name {
    static let iCloudDidSync = Notification.Name("iCloudDidSync")
}
