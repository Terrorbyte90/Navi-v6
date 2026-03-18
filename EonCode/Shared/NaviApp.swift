import SwiftUI
#if os(iOS)
import UserNotifications
import UIKit
import BackgroundTasks
#endif

// MARK: - AppDelegate (handles APNs device token + background remote notifications)

#if os(iOS)
class NaviAppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication,
                     didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        Task { @MainActor in
            NotificationManager.shared.handleDeviceToken(deviceToken)
        }
    }

    func application(_ application: UIApplication,
                     didFailToRegisterForRemoteNotificationsWithError error: Error) {
        Task { @MainActor in
            NotificationManager.shared.handleRegistrationError(error)
        }
    }

    func application(_ application: UIApplication,
                     didReceiveRemoteNotification userInfo: [AnyHashable: Any],
                     fetchCompletionHandler completionHandler: @escaping (UIBackgroundFetchResult) -> Void) {
        let title = userInfo["title"] as? String ?? "Navi"
        let message = userInfo["message"] as? String ?? ""
        let tags = userInfo["tags"] as? [String] ?? []
        let priority = userInfo["priority"] as? Int ?? 3

        Task { @MainActor in
            await NotificationManager.shared.handleNtfyMessage(
                title: title, message: message, tags: tags, priority: priority)
        }
        completionHandler(.newData)
    }
}
#endif

@main
struct NaviApp: App {
    #if os(iOS)
    @UIApplicationDelegateAdaptor(NaviAppDelegate.self) private var appDelegate
    #endif
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

        // Set notification delegate before requesting permission
        UNUserNotificationCenter.current().delegate = NotificationManager.shared

        // Register BGAppRefreshTask for Code Agent background status check
        BGTaskScheduler.shared.register(
            forTaskWithIdentifier: "com.tedsvard.navi.ios.refresh",
            using: nil
        ) { task in
            guard let refreshTask = task as? BGAppRefreshTask else { task.setTaskCompleted(success: false); return }
            refreshTask.expirationHandler = { refreshTask.setTaskCompleted(success: false) }
            Task {
                _ = await CodeSessionsStore.backgroundCheckAndNotify()
                refreshTask.setTaskCompleted(success: true)
                // Schedule next refresh if sessions are still running
                NaviApp.scheduleCodeSessionRefresh()
            }
        }

        Task { @MainActor in
            // Delay network init until after the UI renders to keep startup snappy
            try? await Task.sleep(nanoseconds: 500_000_000) // 0.5s
            PeerSyncEngine.shared.startBrowsing()
            InstructionQueue.shared.startProcessingLoop()

            // Request notification permission and register for remote notifications
            let granted = await NotificationManager.shared.requestPermission()
            if granted {
                NaviLog.info("Push notifications: tillstånd beviljat")
            }
            ProactiveNotificationManager.shared.requestPermission()

            // Check for proactive notification on cold launch (rate-limited to once per 4h)
            await ProactiveNotificationManager.shared.checkAndNotify()

            // Start ntfy.sh polling for server push notifications
            // First ensure Brain service fetches the topic
            await NaviBrainService.shared.fetchNtfyTopic()
            NotificationManager.shared.startNtfyPolling()
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
                            // Auto-sync GitHub repos to iCloud when app becomes active
                            await GitHubManager.shared.autoSyncToiCloud()
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
                            // Proactive notification check (rate-limited to once per 4h)
                            await ProactiveNotificationManager.shared.checkAndNotify()
                            // Auto-sync GitHub repos to iCloud when app becomes active
                            await GitHubManager.shared.autoSyncToiCloud()
                            // Resume ntfy polling and check server tasks
                            NotificationManager.shared.startNtfyPolling()
                            NotificationManager.shared.clearBadge()
                            // Resume polling any active server tasks
                            if NaviBrainService.shared.serverTasks.contains(where: { $0.status.isActive }) {
                                NaviBrainService.shared.startTaskPolling()
                            }
                        }
                    } else if newPhase == .background {
                        // Snapshot current running sessions so BGTask can detect completions
                        let running = CodeSessionsStore.shared.sessions
                            .filter { $0.isRunning }.map { $0.id }
                        UserDefaults.standard.set(running, forKey: "bgKnownRunningSessions")
                        // Stop ntfy polling (system will wake us via BGTask)
                        NotificationManager.shared.stopNtfyPolling()
                        // Schedule BGAppRefresh so we can notify when code sessions finish
                        NaviApp.scheduleCodeSessionRefresh()
                    }
                }
        }
        #endif
    }
}

// MARK: - Background Task Scheduling

#if os(iOS)
extension NaviApp {
    /// Schedule a BGAppRefreshTask to fire in ~15 minutes so we can check
    /// code-session status and send local notifications when the app is closed.
    static func scheduleCodeSessionRefresh() {
        let request = BGAppRefreshTaskRequest(identifier: "com.tedsvard.navi.ios.refresh")
        request.earliestBeginDate = Date(timeIntervalSinceNow: 10 * 60) // 10 min
        do {
            try BGTaskScheduler.shared.submit(request)
        } catch {
            NaviLog.warning("BGAppRefresh submit failed: \(error.localizedDescription)")
        }
    }
}
#endif

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
