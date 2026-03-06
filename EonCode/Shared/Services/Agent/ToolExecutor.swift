import Foundation

// MARK: - ToolExecutor
// Cross-platform tool executor. macOS: full execution. iOS: routes to LocalAgentEngine.

final class ToolExecutor {

    // MARK: - Dispatch

    func execute(name: String, params: [String: String], projectRoot: URL?) async -> String {
        switch name {
        case "read_file":        return await readFile(path: params["path"] ?? "", projectRoot: projectRoot)
        case "write_file":       return await writeFile(path: params["path"] ?? "", content: params["content"] ?? "", projectRoot: projectRoot)
        case "move_file":        return await moveFile(from: params["from"] ?? "", to: params["to"] ?? "", projectRoot: projectRoot)
        case "delete_file":      return await deleteFile(path: params["path"] ?? "", projectRoot: projectRoot)
        case "create_directory": return await createDirectory(path: params["path"] ?? "", projectRoot: projectRoot)
        case "list_directory":   return await listDirectory(path: params["path"] ?? "", projectRoot: projectRoot)
        case "run_command":      return await runCommand(cmd: params["cmd"] ?? "", workingDir: projectRoot)
        case "search_files":     return await searchFiles(query: params["query"] ?? "", projectRoot: projectRoot)
        case "get_api_key":      return getAPIKey(service: params["service"] ?? "")
        case "build_project":    return await buildProject(path: params["path"] ?? "", projectRoot: projectRoot)
        case "download_file":    return await downloadFile(url: params["url"] ?? "", destination: params["destination"] ?? "", projectRoot: projectRoot)
        case "zip_files":        return await zipFiles(source: params["source"] ?? "", destination: params["destination"] ?? "", projectRoot: projectRoot)
        default:                 return "Okänt verktyg: \(name)"
        }
    }

    // MARK: - Path resolution

    func resolvedPath(_ path: String, projectRoot: URL?) -> URL {
        if path.hasPrefix("/") {
            return URL(fileURLWithPath: path)
        }
        if path.hasPrefix("~") {
            #if os(macOS)
            let expanded = path.replacingOccurrences(of: "~", with: FileManager.default.homeDirectoryForCurrentUser.path, options: .anchored)
            return URL(fileURLWithPath: expanded)
            #else
            let docsDir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first?.deletingLastPathComponent()
            let expanded = path.replacingOccurrences(of: "~", with: docsDir?.path ?? "/var/mobile", options: .anchored)
            return URL(fileURLWithPath: expanded)
            #endif
        }
        return (projectRoot ?? URL(fileURLWithPath: NSTemporaryDirectory())).appendingPathComponent(path)
    }

    /// Validates that a resolved path stays within project boundaries.
    /// Returns nil and an error string if the path escapes the project root.
    private func validatedPath(_ path: String, projectRoot: URL?) -> (URL?, String?) {
        let url = resolvedPath(path, projectRoot: projectRoot)
        guard let root = projectRoot else { return (url, nil) }
        let resolvedStandardized = url.standardizedFileURL.path
        let rootStandardized = root.standardizedFileURL.path
        if !resolvedStandardized.hasPrefix(rootStandardized) && !path.hasPrefix("/") && !path.hasPrefix("~") {
            return (nil, "FEL: Sökvägen '\(path)' pekar utanför projektroten. Använd relativa sökvägar inom projektet.")
        }
        return (url, nil)
    }

    // MARK: - read_file

    func readFile(path: String, projectRoot: URL?) async -> String {
        let url = resolvedPath(path, projectRoot: projectRoot)
        do {
            let content = try String(contentsOf: url, encoding: .utf8)
            let lines = content.components(separatedBy: "\n").count
            // Truncate very large files to avoid context overflow
            if content.count > 80_000 {
                let truncated = String(content.prefix(80_000))
                let truncatedLines = truncated.components(separatedBy: "\n").count
                return truncated + "\n\n⚠️ [FIL TRUNKERAD: visar \(truncatedLines)/\(lines) rader, \(80_000)/\(content.count) tecken. Använd search_files för att hitta specifika delar.]"
            }
            return content
        } catch {
            return "FEL: Kunde inte läsa \(path): \(error.localizedDescription)"
        }
    }

    // MARK: - write_file

    var currentProjectID: UUID?
    var currentConversationID: UUID?

    func writeFile(path: String, content: String, projectRoot: URL?) async -> String {
        let (validated, error) = validatedPath(path, projectRoot: projectRoot)
        if let error { return error }
        let url = validated!
        do {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try content.write(to: url, atomically: true, encoding: .utf8)
            let lines = content.components(separatedBy: "\n").count

            // Auto-save to ArtifactStore (skip binary/very large files)
            let ext = url.pathExtension.lowercased()
            let skipExtensions: Set<String> = ["png", "jpg", "jpeg", "gif", "webp", "pdf", "zip", "tar", "gz", "exe", "bin"]
            if !skipExtensions.contains(ext) && content.count < 500_000 {
                await MainActor.run {
                    ArtifactStore.shared.recordFromWrite(
                        path: url.path,
                        content: content,
                        projectID: currentProjectID,
                        conversationID: currentConversationID
                    )
                }
            }

            return "✓ Sparad: \(path) (\(lines) rader, \(content.count) tecken)"
        } catch {
            return "FEL: Kunde inte skriva \(path): \(error.localizedDescription)"
        }
    }

    // MARK: - move_file

    func moveFile(from: String, to: String, projectRoot: URL?) async -> String {
        let fromURL = resolvedPath(from, projectRoot: projectRoot)
        let toURL = resolvedPath(to, projectRoot: projectRoot)
        do {
            try FileManager.default.createDirectory(at: toURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            if FileManager.default.fileExists(atPath: toURL.path) {
                try FileManager.default.removeItem(at: toURL)
            }
            try FileManager.default.moveItem(at: fromURL, to: toURL)
            return "✓ Flyttad: \(from) → \(to)"
        } catch {
            return "FEL: Kunde inte flytta: \(error.localizedDescription)"
        }
    }

    // MARK: - delete_file

    func deleteFile(path: String, projectRoot: URL?) async -> String {
        let (validated, error) = validatedPath(path, projectRoot: projectRoot)
        if let error { return error }
        let url = validated!
        do {
            try FileManager.default.removeItem(at: url)
            return "✓ Borttagen: \(path)"
        } catch {
            return "FEL: Kunde inte ta bort \(path): \(error.localizedDescription)"
        }
    }

    // MARK: - create_directory

    func createDirectory(path: String, projectRoot: URL?) async -> String {
        let url = resolvedPath(path, projectRoot: projectRoot)
        do {
            try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
            return "✓ Mapp skapad: \(path)"
        } catch {
            return "FEL: Kunde inte skapa mapp: \(error.localizedDescription)"
        }
    }

    // MARK: - list_directory

    func listDirectory(path: String, projectRoot: URL?) async -> String {
        let url = resolvedPath(path, projectRoot: projectRoot)
        do {
            let items = try FileManager.default.contentsOfDirectory(
                at: url,
                includingPropertiesForKeys: [.isDirectoryKey, .fileSizeKey],
                options: [.skipsHiddenFiles]
            )
            let lines = items.map { item -> String in
                let isDir = (try? item.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
                let sizeStr: String
                if !isDir, let sz = try? item.resourceValues(forKeys: [.fileSizeKey]).fileSize {
                    sizeStr = " (\(sz) B)"
                } else {
                    sizeStr = ""
                }
                return "\(isDir ? "📁" : "📄") \(item.lastPathComponent)\(sizeStr)"
            }.sorted()
            return lines.isEmpty ? "(tom katalog)" : lines.joined(separator: "\n")
        } catch {
            return "FEL: Kunde inte lista katalog \(path): \(error.localizedDescription)"
        }
    }

    // MARK: - search_files

    func searchFiles(query: String, projectRoot: URL?) async -> String {
        guard let root = projectRoot else { return "Inget projekt valt" }
        var results: [String] = []
        let lq = query.lowercased()

        let enumerator = FileManager.default.enumerator(
            at: root,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        )

        let textExtensions: Set<String> = ["swift", "py", "js", "ts", "tsx", "jsx", "html", "css",
                                            "json", "yaml", "yml", "md", "txt", "sh", "rb", "go",
                                            "rs", "kt", "java", "c", "cpp", "h", "m", "toml"]

        while let url = enumerator?.nextObject() as? URL {
            guard let isDir = try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory,
                  !isDir else { continue }

            // Filename match
            if url.lastPathComponent.lowercased().contains(lq) {
                results.append(url.path.replacingOccurrences(of: root.path + "/", with: ""))
                continue
            }

            // Content match (text files only)
            let ext = url.pathExtension.lowercased()
            guard textExtensions.contains(ext) else { continue }
            guard let content = try? String(contentsOf: url, encoding: .utf8) else { continue }

            if content.lowercased().contains(lq) {
                // Find line numbers
                let lines = content.components(separatedBy: "\n")
                let matchingLines = lines.enumerated()
                    .filter { $0.element.lowercased().contains(lq) }
                    .prefix(3)
                    .map { "  L\($0.offset + 1): \($0.element.trimmed.prefix(80))" }
                    .joined(separator: "\n")

                let relPath = url.path.replacingOccurrences(of: root.path + "/", with: "")
                results.append("\(relPath)\n\(matchingLines)")
            }

            if results.count >= 30 { break }
        }

        if results.isEmpty { return "Inga träffar för '\(query)'" }
        let output = results.joined(separator: "\n---\n")
        if results.count >= 30 {
            return output + "\n\n⚠️ [Visar första 30 träffar — det kan finnas fler.]"
        }
        return output
    }

    // MARK: - get_api_key

    func getAPIKey(service: String) -> String {
        if let key = KeychainManager.shared.getKey(for: service), !key.isEmpty {
            return "API-nyckel hittad för '\(service)' (\(key.prefix(8))...)"
        }
        return "Ingen nyckel hittad för '\(service)'"
    }

    // MARK: - run_command (macOS only)

    func runCommand(cmd: String, workingDir: URL? = nil) async -> String {
        #if os(macOS)
        // Safety check (read setting on main actor)
        let confirmDestructive = await MainActor.run { SettingsStore.shared.agentConfirmDestructive }
        if SafetyGuard.isDestructive(cmd) && confirmDestructive {
            return "SÄKERHET: Kommandot '\(cmd)' är destruktivt och blockerades. Bekräfta i inställningar om du vill tillåta."
        }
        let fullCmd = workingDir != nil ? "cd '\(workingDir!.path)' && \(cmd)" : cmd
        let result = await MacTerminalExecutor.runFull(fullCmd, timeout: 120)
        let output = SafetyGuard.sanitize(result.combined)
        return output.isEmpty ? "(exit \(result.exitCode))" : output
        #else
        let instruction = Instruction(instruction: "run_command: \(cmd)")
        await InstructionQueue.shared.enqueue(instruction)
        return "🟡 Köad för macOS: \(cmd)"
        #endif
    }

    // MARK: - build_project

    func buildProject(path: String, projectRoot: URL?) async -> String {
        #if os(macOS)
        let resolvedBuildPath: String
        if path.hasPrefix("/") {
            resolvedBuildPath = path
        } else if let root = projectRoot {
            resolvedBuildPath = root.appendingPathComponent(path).path
        } else {
            resolvedBuildPath = path
        }

        let result = await XcodeBuildManager.shared.build(projectPath: resolvedBuildPath)
        let status = result.succeeded ? "✅ Bygget lyckades" : "❌ Bygget misslyckades"
        let errors = result.errors.prefix(10).map { $0.description }.joined(separator: "\n")
        return "\(status)\n\(errors)\n\(result.output.suffix(2000))"
        #else
        let instruction = Instruction(instruction: "build_project: \(path)")
        await InstructionQueue.shared.enqueue(instruction)
        return "🟡 Byggkommando köat för macOS"
        #endif
    }

    // MARK: - download_file

    func downloadFile(url urlString: String, destination: String, projectRoot: URL?) async -> String {
        guard let url = URL(string: urlString) else { return "FEL: Ogiltig URL: \(urlString)" }
        let destURL = resolvedPath(destination, projectRoot: projectRoot)

        do {
            let (data, response) = try await URLSession.shared.data(from: url)
            guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
                return "FEL: HTTP \((response as? HTTPURLResponse)?.statusCode ?? 0) för \(urlString)"
            }
            try FileManager.default.createDirectory(at: destURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try data.write(to: destURL)
            return "✓ Nedladdad \(ByteCountFormatter.string(fromByteCount: Int64(data.count), countStyle: .file)) → \(destination)"
        } catch {
            return "FEL: Nedladdning misslyckades: \(error.localizedDescription)"
        }
    }

    // MARK: - zip_files

    func zipFiles(source: String, destination: String, projectRoot: URL?) async -> String {
        #if os(macOS)
        let srcPath = resolvedPath(source, projectRoot: projectRoot).path
        let dstPath = resolvedPath(destination, projectRoot: projectRoot).path
        let result = await MacTerminalExecutor.run("zip -r '\(dstPath)' '\(srcPath)' 2>&1")
        return result.contains("adding:") ? "✓ Zip skapad: \(destination)" : "FEL: \(result)"
        #else
        let srcURL = resolvedPath(source, projectRoot: projectRoot)
        let dstURL = resolvedPath(destination, projectRoot: projectRoot)
        var coordError: NSError?
        var success = false
        NSFileCoordinator().coordinate(readingItemAt: srcURL, options: .forUploading, error: &coordError) { zippedURL in
            try? FileManager.default.createDirectory(at: dstURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try? FileManager.default.copyItem(at: zippedURL, to: dstURL)
            success = true
        }
        if let err = coordError { return "FEL: \(err.localizedDescription)" }
        return success ? "✓ Zip skapad: \(destination)" : "FEL: Zip misslyckades"
        #endif
    }
}

