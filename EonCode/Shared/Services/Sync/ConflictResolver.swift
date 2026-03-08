import Foundation

// Handles sync conflicts by creating branches for iOS changes
struct ConflictResolver {

    enum Resolution {
        case useLocal
        case useRemote
        case createBranch(branchName: String)
    }

    static func resolve(
        localFile: URL,
        remoteFile: URL,
        project: NaviProject
    ) async -> Resolution {
        guard let localDate = localFile.modificationDate as Date?,
              let remoteDate = remoteFile.modificationDate as Date?
        else { return .useRemote }

        // If same content, no conflict
        if let local = try? String(contentsOf: localFile),
           let remote = try? String(contentsOf: remoteFile),
           local == remote {
            return .useLocal
        }

        // iOS changes are never destructive — create branch
        let isIOSChange = !UIDevice.isMac
        if isIOSChange || remoteDate > localDate {
            let branchName = "ios-changes-\(Date().iso8601.prefix(10))"
            return .createBranch(branchName: String(branchName))
        }

        return localDate >= remoteDate ? .useLocal : .useRemote
    }

    static func applyResolution(
        _ resolution: Resolution,
        localFile: URL,
        remoteFile: URL,
        project: NaviProject
    ) async {
        switch resolution {
        case .useLocal:
            try? FileManager.default.copyItem(at: localFile, to: remoteFile)
        case .useRemote:
            try? FileManager.default.copyItem(at: remoteFile, to: localFile)
        case .createBranch(let branchName):
            // Save iOS version to branch
            let branchDir = localFile.deletingLastPathComponent()
                .appendingPathComponent(".branches")
                .appendingPathComponent(branchName)
            try? FileManager.default.createDirectory(at: branchDir, withIntermediateDirectories: true)
            let branchFile = branchDir.appendingPathComponent(localFile.lastPathComponent)
            try? FileManager.default.copyItem(at: localFile, to: branchFile)
            // Use remote as main
            try? FileManager.default.copyItem(at: remoteFile, to: localFile)
        }
    }
}
