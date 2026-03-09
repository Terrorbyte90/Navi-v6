import SwiftUI
#if os(iOS)
import UserNotifications
import UIKit
#endif

@main
struct NaviApp: App {
    @StateObject private var projectStore = ProjectStore.shared
    @StateObject private var icloud = iCloudSyncEngine.shared
    @Environment(\.scenePhase) private var scenePhase

    init() {
        #if os(macOS)
        Task { @MainActor in
            BackgroundDaemon.shared.start()
            TaskHandoffManager.shared.startMonitoring()
        }
        #else
        // Global: all UIScrollViews (incl. SwiftUI ScrollView) dismiss keyboard on drag
        UIScrollView.appearance().keyboardDismissMode = .interactive

        Task { @MainActor in
            // Delay network init until after the UI renders to keep startup snappy
            try? await Task.sleep(nanoseconds: 500_000_000) // 0.5s
            PeerSyncEngine.shared.startBrowsing()
            InstructionQueue.shared.startProcessingLoop()
            UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
        }
        #endif
    }

    var body: some Scene {
        #if os(macOS)
        WindowGroup {
            ContentView()
                .frame(
                    minWidth: Constants.UI.minWindowWidth,
                    minHeight: Constants.UI.minWindowHeight
                )
                .environmentObject(projectStore)
                .onChange(of: scenePhase) { _, newPhase in
                    if newPhase == .active {
                        Task { @MainActor in
                            await DeviceStatusBroadcaster.shared.broadcast()
                        }
                    }
                }
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 1200, height: 800)
        .commands {
            NaviCommands()
        }
        #else
        WindowGroup {
            ContentView()
                .environmentObject(projectStore)
                .onChange(of: scenePhase) { _, newPhase in
                    if newPhase == .active {
                        // Aggressive re-connect + check handoff completions
                        Task { @MainActor in
                            await DeviceStatusBroadcaster.shared.broadcast()
                            await DeviceStatusBroadcaster.shared.fetchRemoteStatus()
                            PeerSyncEngine.shared.startBrowsing()
                            LocalNetworkClient.shared.startAutoDiscovery()
                            await TaskHandoffManager.shared.checkForCompletions()
                        }
                    }
                }
        }
        #endif
    }
}

// MARK: - macOS Menu Commands

#if os(macOS)
struct NaviCommands: Commands {
    @CommandsBuilder
    var body: some Commands {
        CommandGroup(after: .newItem) {
            Button("Nytt projekt") {
                NotificationCenter.default.post(name: .showNewProject, object: nil)
            }
            .keyboardShortcut("n", modifiers: [.command, .shift])
        }

        CommandMenu("Agent") {
            Button("Starta agent") {
                NotificationCenter.default.post(name: .startAgent, object: nil)
            }
            .keyboardShortcut("r", modifiers: [.command, .shift])

            Button("Stoppa alla agenter") {
                AgentPool.shared.stopAll()
            }
        }

        CommandMenu("Synk") {
            Button("Tvinga iCloud-synk") {
                Task { await iCloudSyncEngine.shared.setupDirectories() }
            }
            Button("Bonjour: Starta reklam") {
                PeerSyncEngine.shared.startAdvertising()
            }
        }
    }
}
#endif

extension Notification.Name {
    static let showNewProject = Notification.Name("showNewProject")
    static let startAgent = Notification.Name("startAgent")
    static let showCreateAgent = Notification.Name("showCreateAgent")
}
