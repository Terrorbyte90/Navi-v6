#if os(macOS)
import Foundation
import AppKit

final class FileSystemAgent {
    static let shared = FileSystemAgent()
    private init() {}

    private let fm = FileManager.default

    // MARK: - Create project structure

    func createNewProject(name: String, type: ProjectType, at url: URL) async throws -> URL {
        let projectDir = url.appendingPathComponent(name)
        try fm.createDirectory(at: projectDir, withIntermediateDirectories: true)

        switch type {
        case .swift:
            try createSwiftProject(name: name, at: projectDir)
        case .python:
            try createPythonProject(name: name, at: projectDir)
        case .node:
            try createNodeProject(name: name, at: projectDir)
        case .generic:
            try createGenericProject(name: name, at: projectDir)
        }

        return projectDir
    }

    private func createSwiftProject(name: String, at dir: URL) throws {
        // Package.swift
        let packageSwift = """
        // swift-tools-version: 5.9
        import PackageDescription

        let package = Package(
            name: "\(name)",
            targets: [
                .executableTarget(name: "\(name)", path: "Sources")
            ]
        )
        """
        try packageSwift.write(to: dir.appendingPathComponent("Package.swift"), atomically: true, encoding: .utf8)

        let sourcesDir = dir.appendingPathComponent("Sources")
        try fm.createDirectory(at: sourcesDir, withIntermediateDirectories: true)

        let mainSwift = """
        import Foundation

        print("Hello from \\(name)!")
        """
        try mainSwift.write(to: sourcesDir.appendingPathComponent("main.swift"), atomically: true, encoding: .utf8)
    }

    private func createPythonProject(name: String, at dir: URL) throws {
        let main = "def main():\n    print('Hello from \(name)!')\n\nif __name__ == '__main__':\n    main()\n"
        try main.write(to: dir.appendingPathComponent("main.py"), atomically: true, encoding: .utf8)
        let req = "# Add dependencies here\n"
        try req.write(to: dir.appendingPathComponent("requirements.txt"), atomically: true, encoding: .utf8)
    }

    private func createNodeProject(name: String, at dir: URL) throws {
        let pkg = """
        {
          "name": "\(name.lowercased())",
          "version": "1.0.0",
          "main": "index.js"
        }
        """
        try pkg.write(to: dir.appendingPathComponent("package.json"), atomically: true, encoding: .utf8)
        let index = "console.log('Hello from \(name)!');\n"
        try index.write(to: dir.appendingPathComponent("index.js"), atomically: true, encoding: .utf8)
    }

    private func createGenericProject(name: String, at dir: URL) throws {
        let readme = "# \(name)\n\nEtt nytt projekt skapat med Navi.\n"
        try readme.write(to: dir.appendingPathComponent("README.md"), atomically: true, encoding: .utf8)
    }

    // MARK: - Open in Finder

    func revealInFinder(_ url: URL) {
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    // MARK: - Export as zip

    func exportAsZip(projectURL: URL) async throws -> URL {
        let zipName = projectURL.lastPathComponent + ".zip"
        let dest = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(zipName)

        try? fm.removeItem(at: dest)

        let result = await MacTerminalExecutor.run("cd '\(projectURL.deletingLastPathComponent().path)' && zip -r '\(dest.path)' '\(projectURL.lastPathComponent)'")
        if result.contains("FEL") { throw ExportError.zipFailed }

        return dest
    }

    enum ProjectType: String, CaseIterable {
        case swift, python, node, generic
        var displayName: String { rawValue.capitalized }
    }

    enum ExportError: LocalizedError {
        case zipFailed
        var errorDescription: String? { "Zip-export misslyckades" }
    }
}

// MARK: - Archive Manager

final class ArchiveManager {
    static let shared = ArchiveManager()
    private init() {}

    func zip(source: URL, destination: URL) async throws {
        let result = await MacTerminalExecutor.run("zip -r '\(destination.path)' '\(source.path)'")
        guard !result.contains("error") else { throw ArchiveError.failed(result) }
    }

    func unzip(source: URL, destination: URL) async throws {
        let result = await MacTerminalExecutor.run("unzip -o '\(source.path)' -d '\(destination.path)'")
        guard !result.contains("error") else { throw ArchiveError.failed(result) }
    }

    func tar(source: URL, destination: URL) async throws {
        let result = await MacTerminalExecutor.run("tar -czf '\(destination.path)' -C '\(source.deletingLastPathComponent().path)' '\(source.lastPathComponent)'")
        guard !result.contains("error") else { throw ArchiveError.failed(result) }
    }

    enum ArchiveError: LocalizedError {
        case failed(String)
        var errorDescription: String? { "Arkivering misslyckades" }
    }
}
#endif
