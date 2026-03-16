import Foundation
import SwiftUI
import Combine

// MARK: - NaviOrchestrator: The intelligent agent layer that sits on top of everything

@MainActor
@Observable
final class NaviOrchestrator {
    static let shared = NaviOrchestrator()

    // MARK: - Context awareness

    var activeView: AppSection = .pureChat
    var activeProject: NaviProject?
    var platform: Platform { UIDevice.isMac ? .macOS : .iOS }
    var isConnectedToMac: Bool { DeviceStatusBroadcaster.shared.remoteMacIsOnline }

    // MARK: - Agent activity (drives all visual feedback)

    let activity = AgentActivityState()

    // MARK: - Execution state

    private(set) var isProcessing = false
    private var currentTask: Task<Void, Never>?
    private var projectFileCache: [UUID: (files: [String], cachedAt: Date)] = [:]
    private let cacheTTL: TimeInterval = 120 // 2 minutes

    // MARK: - Init

    private init() {}

    // MARK: - View awareness (called from ContentView)

    func setActiveView(_ view: AppSection) {
        activeView = view
    }

    func setActiveProject(_ project: NaviProject?) {
        activeProject = project
    }

    // MARK: - Available tools based on platform

    var availableTools: [ClaudeTool] {
        #if os(macOS)
        return agentTools // All tools available
        #else
        return agentTools.filter { tool in
            // iOS can do file ops, search, api keys - but not terminal, build
            !["run_command", "build_project"].contains(tool.name)
        }
        #endif
    }

    // MARK: - Main entry: handle user request

    func handleRequest(_ instruction: String, project: NaviProject? = nil) {
        guard !isProcessing else { return }

        let targetProject = project ?? activeProject
        isProcessing = true
        activity.begin()

        // Mac Remote: route all execution to Mac via InstructionQueue
        #if os(iOS)
        if SettingsStore.shared.macRemoteEnabled {
            Task {
                await executeRemoteOnMac(instruction: instruction, project: targetProject)
                isProcessing = false
                activity.complete(summary: "Skickad till Mac")
            }
            return
        }
        #endif

        currentTask = Task {
            defer {
                isProcessing = false
            }

            do {
                // Step 1: Scan project if needed
                if let proj = targetProject {
                    await scanProjectIfNeeded(proj)
                }

                // Step 2: Create plan via Haiku (cheap)
                await createPlan(instruction: instruction, project: targetProject)

                // Step 3: Execute via AgentEngine
                await executeWithEngine(instruction: instruction, project: targetProject)

                // Step 4: Complete
                let summary = activity.buildSummary()
                activity.complete(summary: summary)

            } catch is CancellationError {
                activity.fail(message: "Avbrutet av användaren")
            } catch {
                activity.fail(message: error.localizedDescription)
            }
        }
    }

    // MARK: - Stop

    func stop() {
        currentTask?.cancel()
        currentTask = nil
        isProcessing = false
        activity.setPhase(.idle)
    }

    // MARK: - Project scanning (cached)

    private func scanProjectIfNeeded(_ project: NaviProject) async {
        // Check cache
        if let cached = projectFileCache[project.id],
           Date().timeIntervalSince(cached.cachedAt) < cacheTTL {
            activity.setPhase(.scanning(fileCount: cached.files.count))
            try? await Task.sleep(for: .milliseconds(300)) // Brief visual feedback
            return
        }

        activity.setPhase(.scanning(fileCount: 0))

        guard let projectURL = project.resolvedURL else { return }

        var fileList: [String] = []
        let fm = FileManager.default
        let ignoredDirs = Set(["node_modules", ".git", "build", "DerivedData", ".build", "__pycache__", ".DS_Store", "Pods"])

        if let enumerator = fm.enumerator(
            at: projectURL,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) {
            for case let fileURL as URL in enumerator {
                let pathComponents = fileURL.pathComponents
                if pathComponents.contains(where: { ignoredDirs.contains($0) }) {
                    continue
                }
                if let values = try? fileURL.resourceValues(forKeys: [.isRegularFileKey]),
                   values.isRegularFile == true {
                    fileList.append(fileURL.path)
                }
            }
        }

        projectFileCache[project.id] = (files: fileList, cachedAt: Date())
        activity.setPhase(.scanning(fileCount: fileList.count))
        activity.addTimelineEntry(
            icon: "doc.text.magnifyingglass",
            title: "Projektskanning klar",
            detail: "\(fileList.count) filer hittade"
        )

        try? await Task.sleep(for: .milliseconds(200))
    }

    // MARK: - Planning (uses Haiku for cost efficiency)

    private func createPlan(instruction: String, project: NaviProject?) async {
        activity.setPhase(.planning(description: "Analyserar uppgiften…"))

        // Build a lightweight planning prompt
        let planPrompt = """
        Analysera denna uppgift och skapa en kort TODO-lista (max 8 steg) på svenska.
        Svara BARA med en JSON-array av strängar, inget annat.

        Uppgift: \(instruction)
        \(project != nil ? "Projekt: \(project!.name)" : "")
        Plattform: \(platform == .macOS ? "macOS" : "iOS")

        Exempel: ["Läs och förstå projektet", "Skapa ny vy", "Implementera logik", "Testa"]
        """

        do {
            let response = try await ClaudeAPIClient.shared.sendMessage(
                messages: [ChatMessage(role: .user, content: [.text(planPrompt)])],
                model: .haiku, // Always Haiku for planning — cheapest
                systemPrompt: "Du är en kodplanerare. Svara BARA med en JSON-array av svenska steg-beskrivningar."
            )

            activity.addCost(usage: response.usage, model: .haiku)

            // Parse the TODO items from response
            let todoStrings = parseTodoStrings(response.text)
            if !todoStrings.isEmpty {
                activity.setTodoItems(todoStrings.map { ($0, nil) })
            }
        } catch {
            // Planning failed — continue without plan, not critical
            activity.addTimelineEntry(
                icon: "exclamationmark.triangle",
                title: "Planering hoppades över",
                detail: error.localizedDescription
            )
        }

        activity.setPhase(.thinking(about: "arkitekturen"))
    }

    // MARK: - Execution via existing AgentEngine

    private func executeWithEngine(instruction: String, project: NaviProject?) async {
        guard let project = project else {
            // No project — delegate to chat mode
            activity.setPhase(.thinking(about: instruction.prefix(50) + "…"))
            return
        }

        let engine = AgentEngine.shared
        engine.setProject(project)

        var conversation = Conversation(
            projectID: project.id,
            model: project.activeModel
        )

        let task = AgentTask(
            projectID: project.id,
            instruction: instruction
        )

        // Hook into the engine's updates to drive our visual state
        await engine.run(
            task: task,
            conversation: &conversation,
            onUpdate: { [weak self] update in
                Task { @MainActor in
                    self?.processEngineUpdate(update)
                }
            }
        )
    }

    // MARK: - Process engine updates into visual state

    private func processEngineUpdate(_ update: String) {
        // Parse tool executions from the update string
        if update.contains("read_file:") || update.contains("Läser") {
            let file = extractFileName(from: update)
            activity.setPhase(.reading(file: file))
        } else if update.contains("write_file:") || update.contains("Skriver") {
            let file = extractFileName(from: update)
            activity.setPhase(.writing(file: file, added: 0, removed: 0))
            activity.advanceTodo()
        } else if update.contains("run_command:") || update.contains("Kör:") {
            let cmd = extractCommand(from: update)
            activity.setPhase(.running(command: cmd))
        } else if update.contains("build_project:") || update.contains("Bygger") {
            activity.setPhase(.building(progress: 0.5))
        } else if update.contains("search_files:") || update.contains("Söker") {
            activity.setPhase(.thinking(about: "sökning i filer"))
        } else if update.hasPrefix("❌") {
            activity.addTimelineEntry(icon: "xmark.circle", title: "Fel", detail: String(update.dropFirst(2)))
        } else if update.hasPrefix("✅") {
            activity.addTimelineEntry(icon: "checkmark.circle", title: "Verktyg klar", detail: String(update.prefix(100)))
        }
    }

    // MARK: - Helpers

    private func parseTodoStrings(_ text: String) -> [String] {
        // Find JSON array in response
        guard let startIndex = text.firstIndex(of: "["),
              let endIndex = text.lastIndex(of: "]") else { return [] }

        let jsonString = String(text[startIndex...endIndex])
        guard let data = jsonString.data(using: .utf8),
              let array = try? JSONSerialization.jsonObject(with: data) as? [String]
        else { return [] }

        return array
    }

    private func extractFileName(from update: String) -> String {
        // Try to extract file path from update like "✅ read_file: /path/to/file.swift..."
        let parts = update.components(separatedBy: ":")
        if parts.count >= 2 {
            let path = parts[1].trimmingCharacters(in: .whitespaces)
            if path.contains("/") || path.contains(".") {
                return String(path.prefix(200))
            }
        }
        return "fil"
    }

    private func extractCommand(from update: String) -> String {
        let parts = update.components(separatedBy: ":")
        if parts.count >= 2 {
            return String(parts[1...].joined(separator: ":").trimmingCharacters(in: .whitespaces).prefix(80))
        }
        return "kommando"
    }

    // MARK: - Invalidate project cache

    func invalidateProjectCache(for projectID: UUID) {
        projectFileCache.removeValue(forKey: projectID)
    }

    func invalidateAllCaches() {
        projectFileCache.removeAll()
    }

    // MARK: - Mac Remote execution

    #if os(iOS)
    private func executeRemoteOnMac(instruction: String, project: NaviProject?) async {
        activity.setPhase(.thinking(about: "Skickar till Mac…"))

        guard let projectID = project?.id else {
            activity.fail(message: "Inget projekt valt")
            return
        }

        // Create instruction for Mac
        let macInstruction = Instruction(
            instruction: instruction,
            projectID: projectID,
            deviceID: UIDevice.deviceID
        )

        // Queue to Mac via all channels
        await InstructionQueue.shared.enqueue(macInstruction)

        // Also start handoff tracking
        await TaskHandoffManager.shared.startTracking(
            projectID: projectID,
            instruction: instruction,
            todoItems: activity.todoItems
        )

        activity.setPhase(.thinking(about: "Körs på Mac…"))
        activity.addTimelineEntry(icon: "desktopcomputer", title: "Skickad till Mac", detail: instruction)
    }
    #endif
}

// MARK: - Platform enum

enum Platform {
    case macOS, iOS

    var displayName: String {
        switch self {
        case .macOS: return "macOS"
        case .iOS: return "iOS"
        }
    }
}
