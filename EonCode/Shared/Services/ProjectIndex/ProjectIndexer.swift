import Foundation
import Combine

@MainActor
final class ProjectIndexer: ObservableObject {
    static let shared = ProjectIndexer()

    @Published var fileTree: [UUID: FileNode] = [:]    // projectID → root node
    @Published var isIndexing = false
    @Published var indexedProjectCount = 0

    private var fileWatchers: [UUID: FileWatcher] = [:]
    private init() {}

    // MARK: - Index project

    func index(project: NaviProject) async {
        guard let rootURL = project.resolvedURL else { return }
        isIndexing = true
        defer { isIndexing = false }

        let root = await Task.detached(priority: .userInitiated) {
            FileNode(
                name: project.name,
                path: rootURL.path,
                relativePath: "",
                isDirectory: true
            )
        }.value

        await buildTree(node: root, url: rootURL, projectRoot: rootURL)

        fileTree[project.id] = root
        indexedProjectCount += 1

        // Start watching for changes
        startWatching(project: project)
    }

    private func buildTree(node: FileNode, url: URL, projectRoot: URL) async {
        guard url.isDirectory else { return }

        let fm = FileManager.default
        guard let items = try? fm.contentsOfDirectory(
            at: url,
            includingPropertiesForKeys: [.isDirectoryKey, .fileSizeKey, .contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ) else { return }

        let ignoredDirs = Set(["node_modules", ".git", "build", "DerivedData", ".build", "__pycache__", ".DS_Store"])

        var children: [FileNode] = []

        for item in items.sorted(by: { a, b in
            // Directories first, then alphabetical
            let aIsDir = a.isDirectory
            let bIsDir = b.isDirectory
            if aIsDir != bIsDir { return aIsDir }
            return a.lastPathComponent < b.lastPathComponent
        }) {
            if ignoredDirs.contains(item.lastPathComponent) { continue }

            let relative = item.path.replacingOccurrences(of: projectRoot.path + "/", with: "")
            let child = FileNode(
                name: item.lastPathComponent,
                path: item.path,
                relativePath: relative,
                isDirectory: item.isDirectory,
                size: item.fileSize,
                modifiedAt: item.modificationDate
            )
            child.parent = node
            children.append(child)

            if item.isDirectory {
                await buildTree(node: child, url: item, projectRoot: projectRoot)
            }
        }

        await MainActor.run { node.children = children }
    }

    // MARK: - File watching

    func startWatching(project: NaviProject) {
        guard let url = project.resolvedURL else { return }
        let watcher = FileWatcher(url: url) { [weak self] in
            Task { await self?.index(project: project) }
        }
        fileWatchers[project.id] = watcher
    }

    func stopWatching(project: NaviProject) {
        fileWatchers[project.id] = nil
    }

    // MARK: - Find file node

    func findNode(path: String, in projectID: UUID) -> FileNode? {
        guard let root = fileTree[projectID] else { return nil }
        return findInTree(root, path: path)
    }

    private func findInTree(_ node: FileNode, path: String) -> FileNode? {
        if node.path == path || node.relativePath == path { return node }
        guard let children = node.children else { return nil }
        for child in children {
            if let found = findInTree(child, path: path) { return found }
        }
        return nil
    }

    // MARK: - All files flat list

    func allFiles(in projectID: UUID) -> [FileNode] {
        guard let root = fileTree[projectID] else { return [] }
        return flattenTree(root).filter { !$0.isDirectory }
    }

    private func flattenTree(_ node: FileNode) -> [FileNode] {
        var result = [node]
        for child in node.children ?? [] {
            result.append(contentsOf: flattenTree(child))
        }
        return result
    }
}

// MARK: - File Watcher using DispatchSource

final class FileWatcher {
    private var source: DispatchSourceFileSystemObject?
    private let onChange: () -> Void
    private var debounceWork: DispatchWorkItem?

    init(url: URL, onChange: @escaping () -> Void) {
        self.onChange = onChange
        start(url: url)
    }

    private func start(url: URL) {
        let fd = open(url.path, O_EVTONLY)
        guard fd >= 0 else { return }

        source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd,
            eventMask: [.write, .rename, .delete, .attrib],
            queue: .global(qos: .utility)
        )

        source?.setEventHandler { [weak self] in
            self?.debouncedChange()
        }

        source?.setCancelHandler { close(fd) }
        source?.resume()
    }

    private func debouncedChange() {
        debounceWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            self?.onChange()
        }
        debounceWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0, execute: work)
    }

    deinit {
        source?.cancel()
    }
}
