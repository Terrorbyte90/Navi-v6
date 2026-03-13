#if os(macOS)
import Foundation

@MainActor
final class XcodeBuildManager: ObservableObject {
    static let shared = XcodeBuildManager()

    @Published var isBuilding = false
    @Published var buildOutput = ""
    @Published var lastErrors: [XcodeBuildError] = []
    @Published var lastBuildSucceeded = false

    private init() {}

    // MARK: - Build project

    func build(projectPath: String, scheme: String? = nil, destination: String? = "generic/platform=iOS Simulator") async -> BuildResult {
        isBuilding = true
        buildOutput = ""
        lastErrors = []
        defer { isBuilding = false }

        var cmd = "xcodebuild"

        // Detect project type
        if projectPath.hasSuffix(".xcworkspace") {
            cmd += " -workspace '\(projectPath)'"
        } else if projectPath.hasSuffix(".xcodeproj") {
            cmd += " -project '\(projectPath)'"
        } else if FileManager.default.fileExists(atPath: projectPath + "/Package.swift") {
            // SPM project
            return await buildSPM(path: projectPath)
        } else {
            cmd += " -project '\(projectPath)'"
        }

        if let scheme = scheme { cmd += " -scheme '\(scheme)'" }
        if let dest = destination { cmd += " -destination '\(dest)'" }
        cmd += " build 2>&1"

        let output = await MacTerminalExecutor.stream(cmd) { [weak self] text in
            self?.buildOutput += text
        }

        let errors = XcodeErrorParser.parseErrors(from: output.combined)
        lastErrors = errors
        lastBuildSucceeded = output.exitCode == 0

        return BuildResult(
            succeeded: output.exitCode == 0,
            output: output.combined,
            errors: errors,
            exitCode: output.exitCode
        )
    }

    func buildSPM(path: String) async -> BuildResult {
        let cmd = "cd '\(path)' && swift build 2>&1"
        let output = await MacTerminalExecutor.stream(cmd) { [weak self] text in
            self?.buildOutput += text
        }
        let errors = XcodeErrorParser.parseErrors(from: output.combined)
        return BuildResult(succeeded: output.exitCode == 0, output: output.combined, errors: errors, exitCode: output.exitCode)
    }

    // MARK: - Self-healing build loop

    func buildUntilSuccess(
        projectPath: String,
        maxAttempts: Int = Constants.Agent.maxBuildAttempts,
        onAttempt: @escaping (Int, String) -> Void,
        onFix: @escaping (String) -> Void
    ) async -> BuildResult {
        var lastResult = BuildResult(succeeded: false, output: "", errors: [], exitCode: -1)

        for attempt in 1...maxAttempts {
            CheckpointManager.shared.save(
                taskID: UUID(),
                step: attempt,
                data: ["phase": "build-attempt", "attempt": attempt]
            )

            let result = await build(projectPath: projectPath)
            lastResult = result
            onAttempt(attempt, result.output)

            if result.succeeded { return result }

            guard !result.errors.isEmpty else { break }

            // Ask Claude to fix the errors
            let errorSummary = result.errors.map { $0.description }.joined(separator: "\n")
            let fixPrompt = "Fixa dessa Xcode-byggefel:\n\n\(errorSummary)\n\nÄndra filerna direkt."

            onFix("🔧 Fixar \(result.errors.count) fel...")

            // Create a conversation and ask for fixes
            var conv = Conversation(projectID: UUID(), model: .haiku)
            await AgentEngine.shared.run(
                task: AgentTask(projectID: UUID(), instruction: fixPrompt),
                conversation: &conv,
                onUpdate: onFix
            )
        }

        return lastResult
    }

    // MARK: - Archive & Upload to TestFlight (local fallback)

    func archiveAndUpload(projectPath: String, scheme: String) async -> String {
        // Prefer Xcode Cloud via API — this is the local fallback
        let result = await XcodeCloudService.shared.triggerBuild(scheme: scheme)
        return result
    }
}

// MARK: - Error parser

struct XcodeErrorParser {
    static func parseErrors(from output: String) -> [XcodeBuildError] {
        var errors: [XcodeBuildError] = []
        let lines = output.components(separatedBy: "\n")

        for line in lines {
            // Xcode format: path/file.swift:LINE:COL: error: message
            // Also SPM format: error: message
            if let error = parseLine(line) {
                errors.append(error)
            }
        }

        return errors
    }

    private static func parseLine(_ line: String) -> XcodeBuildError? {
        // error: pattern
        if line.contains(": error:") || line.contains("error:") && !line.hasPrefix("//") {
            let severity: XcodeBuildError.Severity = line.contains(": warning:") ? .warning : .error

            // Try to extract file:line:col
            let parts = line.components(separatedBy: ":")
            if parts.count >= 4,
               let lineNum = Int(parts[1].trimmed),
               let col = Int(parts[2].trimmed) {
                let file = parts[0].trimmed
                let message = parts.dropFirst(4).joined(separator: ":").trimmed
                return XcodeBuildError(file: file, line: lineNum, column: col, message: message, severity: severity, rawLine: line)
            }

            // Simple error line
            return XcodeBuildError(file: nil, line: nil, column: nil, message: line.trimmed, severity: .error, rawLine: line)
        }

        if line.contains(": warning:") {
            return XcodeBuildError(file: nil, line: nil, column: nil, message: line.trimmed, severity: .warning, rawLine: line)
        }

        return nil
    }
}

struct XcodeBuildError: Identifiable {
    let id = UUID()
    let file: String?
    let line: Int?
    let column: Int?
    let message: String
    let severity: Severity
    let rawLine: String

    enum Severity { case error, warning, note }

    var description: String {
        var parts: [String] = []
        if let f = file { parts.append(f) }
        if let l = line { parts.append("L\(l)") }
        parts.append(message)
        return parts.joined(separator: " | ")
    }
}

struct BuildResult {
    let succeeded: Bool
    let output: String
    let errors: [XcodeBuildError]
    let exitCode: Int32

    var warningCount: Int { errors.filter { $0.severity == .warning }.count }
    var errorCount: Int { errors.filter { $0.severity == .error }.count }
}
#endif
