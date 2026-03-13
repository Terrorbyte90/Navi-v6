import Foundation

// MARK: - Platform capability of each AgentAction

extension AgentAction {

    /// True if this action can run directly on iOS without a terminal/shell.
    var canRunOnIOS: Bool {
        switch self {
        case .readFile, .writeFile, .moveFile, .deleteFile,
             .createDirectory, .listDirectory, .searchFiles,
             .downloadFile, .think, .askUser, .research, .getAPIKey,
             .deployTestFlight:
            return true
        case .runCommand, .buildProject, .extractArchive, .createArchive:
            return false
        case .custom(let name, _):
            // Download via URLSession is fine; anything else needs terminal
            return name == "download"
        }
    }

    /// Short label shown in the queue UI
    var queueLabel: String {
        switch self {
        case .runCommand(let cmd):   return "Terminal: \(String(cmd.prefix(60)))"
        case .buildProject(let p):  return "xcodebuild: \((p as NSString).lastPathComponent)"
        case .extractArchive(let p, _): return "unzip: \((p as NSString).lastPathComponent)"
        case .createArchive(let s, _):  return "zip: \((s as NSString).lastPathComponent)"
        default: return displayName
        }
    }

    /// Whether this action requires Mac, used for UI badges
    var requiresMac: Bool { !canRunOnIOS }

    /// Emoji badge for step-status UI
    var platformBadge: String {
        canRunOnIOS ? "📱" : "💻"
    }
}
