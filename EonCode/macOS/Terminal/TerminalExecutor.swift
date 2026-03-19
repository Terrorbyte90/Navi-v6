#if os(macOS)
import Foundation

// MARK: - Thread-safe data box for concurrent closure capture

private final class LockedData: @unchecked Sendable {
    private let lock = NSLock()
    private var storage = Data()

    func append(_ data: Data) {
        lock.withLock { storage.append(data) }
    }

    var data: Data {
        lock.withLock { storage }
    }
}

// MARK: - MacTerminalExecutor

// macOS terminal executor — used by ToolExecutor on Mac
enum MacTerminalExecutor {

    struct CommandResult {
        let output: String
        let errorOutput: String
        let exitCode: Int32

        var combined: String {
            [output, errorOutput].filter { !$0.isEmpty }.joined(separator: "\n")
        }

        var isSuccess: Bool { exitCode == 0 }
    }

    // MARK: - Run command

    @discardableResult
    static func run(_ command: String, timeout: TimeInterval = 120) async -> String {
        let result = await runFull(command, timeout: timeout)
        return result.combined.isEmpty ? "(exit \(result.exitCode))" : result.combined
    }

    static func runFull(_ command: String, timeout: TimeInterval = 120) async -> CommandResult {
        await withCheckedContinuation { continuation in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/bin/bash")
            process.arguments = ["-l", "-c", command]

            let outPipe = Pipe()
            let errPipe = Pipe()
            process.standardOutput = outPipe
            process.standardError = errPipe

            // Set environment
            var env = ProcessInfo.processInfo.environment
            env["PATH"] = "/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin:/opt/homebrew/bin:" + (env["PATH"] ?? "")
            process.environment = env

            // Thread-safe collection via reference types (Swift 6 safe)
            let outputBox = LockedData()
            let errorBox  = LockedData()

            outPipe.fileHandleForReading.readabilityHandler = { handle in
                outputBox.append(handle.availableData)
            }
            errPipe.fileHandleForReading.readabilityHandler = { handle in
                errorBox.append(handle.availableData)
            }

            do {
                try process.run()
            } catch {
                continuation.resume(returning: CommandResult(output: "", errorOutput: error.localizedDescription, exitCode: -1))
                return
            }

            // Timeout handler
            let timeoutWork = DispatchWorkItem {
                process.terminate()
            }
            DispatchQueue.global().asyncAfter(deadline: .now() + timeout, execute: timeoutWork)

            process.terminationHandler = { p in
                timeoutWork.cancel()
                outPipe.fileHandleForReading.readabilityHandler = nil
                errPipe.fileHandleForReading.readabilityHandler = nil

                // Read remaining
                outputBox.append(outPipe.fileHandleForReading.readDataToEndOfFile())
                errorBox.append(errPipe.fileHandleForReading.readDataToEndOfFile())

                let output      = String(data: outputBox.data, encoding: .utf8) ?? ""
                let errorOutput = String(data: errorBox.data,  encoding: .utf8) ?? ""

                continuation.resume(returning: CommandResult(
                    output: output,
                    errorOutput: errorOutput,
                    exitCode: p.terminationStatus
                ))
            }
        }
    }

    // MARK: - Interactive-style streaming

    static func stream(
        _ command: String,
        onOutput: @escaping (String) -> Void
    ) async -> CommandResult {
        await withCheckedContinuation { continuation in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/bin/bash")
            process.arguments = ["-l", "-c", command]

            let pipe = Pipe()
            process.standardOutput = pipe
            process.standardError = pipe

            var env = ProcessInfo.processInfo.environment
            env["PATH"] = "/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin:/opt/homebrew/bin:" + (env["PATH"] ?? "")
            process.environment = env

            // Thread-safe collection via reference type (Swift 6 safe)
            let allOutput = LockedData()

            pipe.fileHandleForReading.readabilityHandler = { handle in
                let data = handle.availableData
                allOutput.append(data)
                if let text = String(data: data, encoding: .utf8), !text.isEmpty {
                    Task { @MainActor in onOutput(text) }
                }
            }

            do {
                try process.run()
            } catch {
                continuation.resume(returning: CommandResult(output: "", errorOutput: error.localizedDescription, exitCode: -1))
                return
            }

            process.terminationHandler = { p in
                pipe.fileHandleForReading.readabilityHandler = nil
                allOutput.append(pipe.fileHandleForReading.readDataToEndOfFile())
                let output = String(data: allOutput.data, encoding: .utf8) ?? ""
                continuation.resume(returning: CommandResult(output: output, errorOutput: "", exitCode: p.terminationStatus))
            }
        }
    }
}

// MARK: - Safety guard for destructive commands

struct SafetyGuard {
    static let dangerousPatterns = [
        "rm -rf", "rm -f /", "sudo rm", "format", "diskutil erase",
        "mkfs", "dd if=", "shutdown", "reboot", "poweroff",
        "> /dev/", "chmod -R 777 /", "chown -R root"
    ]

    static func isDestructive(_ command: String) -> Bool {
        let lower = command.lowercased()
        return dangerousPatterns.contains { lower.contains($0) }
    }

    static func sanitize(_ output: String) -> String {
        // Remove ANSI escape codes
        let ansiPattern = "\u{001B}\\[[0-9;]*[mABCDEFGHJKLMSTf]"
        return output.replacingOccurrences(of: ansiPattern, with: "", options: .regularExpression)
    }
}
#endif
