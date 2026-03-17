import Foundation
import UserNotifications
import Combine
#if os(iOS)
import UIKit
#endif

// MARK: - NotificationManager
// Central hub for all push & local notifications in Navi.
// Handles: ntfy.sh polling for server events, APNs registration,
// local notifications for proactive reminders, task completions, and server activity.

@MainActor
final class NotificationManager: NSObject, ObservableObject {
    static let shared = NotificationManager()

    // MARK: - Published State

    @Published var isRegistered = false
    @Published var deviceToken: String?
    @Published var recentNotifications: [NaviNotification] = []
    @Published var unreadCount: Int = 0

    // MARK: - ntfy.sh Polling

    @Published var isPollingNtfy = false
    private var ntfyTask: Task<Void, Never>?
    private var ntfyPollInterval: TimeInterval = 5.0

    // MARK: - Deduplication

    /// Seen ntfy message IDs — prevents the same server message from re-firing on each poll
    private var seenNtfyMessageIds: Set<String> = []
    /// Last error text + timestamp — prevents spam of the same error notification
    private var lastErrorText: String = ""
    private var lastErrorAt: Date = .distantPast
    /// Min seconds between identical error notifications
    private let errorDedupeWindow: TimeInterval = 60

    // MARK: - Private

    private let center = UNUserNotificationCenter.current()
    private let maxRecentNotifications = 50

    private override init() {
        super.init()
    }

    // MARK: - Permission & Registration

    func requestPermission() async -> Bool {
        do {
            let granted = try await center.requestAuthorization(options: [.alert, .badge, .sound])
            isRegistered = granted
            if granted {
                #if os(iOS)
                UIApplication.shared.registerForRemoteNotifications()
                #endif
            }
            return granted
        } catch {
            NaviLog.error("Notification permission failed", error: error)
            return false
        }
    }

    func handleDeviceToken(_ token: Data) {
        let tokenString = token.map { String(format: "%02.2hhx", $0) }.joined()
        deviceToken = tokenString
        NaviLog.info("APNs device token: \(tokenString.prefix(16))...")
    }

    func handleRegistrationError(_ error: Error) {
        NaviLog.error("APNs registration failed", error: error)
    }

    // MARK: - ntfy.sh Subscription (server push via polling)

    /// Start polling ntfy.sh for server notifications.
    /// The server publishes to a topic when tasks complete or notable events occur.
    func startNtfyPolling() {
        guard !isPollingNtfy else { return }
        isPollingNtfy = true

        ntfyTask = Task { [weak self] in
            guard let self else { return }

            // Wait for topic to be fetched
            var topic: String?
            for _ in 0..<10 {
                topic = NaviBrainService.shared.ntfyTopic
                if topic != nil { break }
                try? await Task.sleep(nanoseconds: 2_000_000_000)
            }

            guard let topic, !topic.isEmpty else {
                NaviLog.info("NotificationManager: No ntfy topic available, skipping polling")
                await MainActor.run { self.isPollingNtfy = false }
                return
            }

            let since = "since=\(Int(Date().timeIntervalSince1970))"
            guard let url = URL(string: "https://ntfy.sh/\(topic)/json?\(since)&poll=1") else { return }

            NaviLog.info("NotificationManager: Started ntfy polling on topic '\(topic)'")

            while !Task.isCancelled {
                do {
                    var request = URLRequest(url: url, timeoutInterval: 10)
                    request.setValue("application/json", forHTTPHeaderField: "Accept")

                    let (data, response) = try await URLSession.shared.data(for: request)
                    if let httpResp = response as? HTTPURLResponse, httpResp.statusCode == 200 {
                        let text = String(data: data, encoding: .utf8) ?? ""
                        let lines = text.components(separatedBy: "\n").filter { !$0.isEmpty }
                        for line in lines {
                            if let msgData = line.data(using: .utf8),
                               let json = try? JSONSerialization.jsonObject(with: msgData) as? [String: Any],
                               let event = json["event"] as? String, event == "message" {
                                // Deduplicate by ntfy message id — prevents re-delivery on repeated polls
                                let msgId = json["id"] as? String ?? UUID().uuidString
                                guard !self.seenNtfyMessageIds.contains(msgId) else { continue }
                                self.seenNtfyMessageIds.insert(msgId)
                                // Periodic reset to avoid unbounded memory growth (ntfy IDs are ephemeral)
                                if self.seenNtfyMessageIds.count > 1000 { self.seenNtfyMessageIds.removeAll() }

                                let title = json["title"] as? String ?? "Navi Brain"
                                let message = json["message"] as? String ?? ""
                                let tags = json["tags"] as? [String] ?? []
                                let priority = json["priority"] as? Int ?? 3

                                await self.handleNtfyMessage(
                                    title: title,
                                    message: message,
                                    tags: tags,
                                    priority: priority
                                )
                            }
                        }
                    }
                } catch {
                    // Silent fail — ntfy polling is best-effort
                }

                try? await Task.sleep(nanoseconds: UInt64(ntfyPollInterval * 1_000_000_000))
            }
        }
    }

    func stopNtfyPolling() {
        ntfyTask?.cancel()
        ntfyTask = nil
        isPollingNtfy = false
    }

    private func handleNtfyMessage(title: String, message: String, tags: [String], priority: Int) async {
        let category = NotificationCategory.from(tags: tags)

        let notification = NaviNotification(
            title: title,
            body: message,
            category: category,
            source: .server,
            priority: priority
        )

        addNotification(notification)
        scheduleLocalNotification(notification)
    }

    // MARK: - Local Notification Scheduling

    func scheduleLocalNotification(_ notification: NaviNotification) {
        let content = UNMutableNotificationContent()
        content.title = notification.title
        content.body = notification.body
        content.sound = notification.priority >= 4 ? .defaultCritical : .default
        content.categoryIdentifier = notification.category.rawValue
        content.userInfo = [
            "source": notification.source.rawValue,
            "category": notification.category.rawValue,
            "notificationId": notification.id.uuidString
        ]

        #if os(iOS)
        if notification.priority >= 4 {
            content.interruptionLevel = .timeSensitive
        }
        #endif

        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false)
        let request = UNNotificationRequest(
            identifier: notification.id.uuidString,
            content: content,
            trigger: trigger
        )
        center.add(request)
    }

    /// Schedule a notification for a server task completion
    func notifyTaskCompleted(taskDescription: String, model: String, duration: String?) {
        let body: String
        if let dur = duration {
            body = "\(model) slutförde uppgiften på \(dur)"
        } else {
            body = "\(model) har slutfört uppgiften"
        }

        let notification = NaviNotification(
            title: "Uppgift klar: \(taskDescription.prefix(40))",
            body: body,
            category: .taskCompleted,
            source: .server,
            priority: 4
        )

        addNotification(notification)
        scheduleLocalNotification(notification)
    }

    /// Schedule a notification for server activity (tool calls, errors, etc.)
    func notifyServerActivity(action: String, details: String) {
        let notification = NaviNotification(
            title: "Navi Brain: \(action)",
            body: details.prefix(100).description,
            category: .serverActivity,
            source: .server,
            priority: 3
        )

        addNotification(notification)
        scheduleLocalNotification(notification)
    }

    /// Schedule a notification for a server error.
    /// Deduplicates: the same error message won't fire more than once per 60 seconds.
    func notifyServerError(error: String) {
        let now = Date()
        let normalized = error.prefix(120).description
        // Skip if identical error was already notified recently
        if normalized == lastErrorText && now.timeIntervalSince(lastErrorAt) < errorDedupeWindow {
            return
        }
        lastErrorText = normalized
        lastErrorAt = now

        let notification = NaviNotification(
            title: "Serverfel",
            body: normalized,
            category: .serverError,
            source: .server,
            priority: 5
        )

        addNotification(notification)
        scheduleLocalNotification(notification)
    }

    /// Proactive notification from AI analysis
    func notifyProactive(title: String, body: String) {
        let notification = NaviNotification(
            title: title,
            body: body,
            category: .proactive,
            source: .local,
            priority: 2
        )

        addNotification(notification)
        scheduleLocalNotification(notification)
    }

    /// Handoff task completed on Mac
    func notifyHandoffCompleted(instruction: String) {
        let notification = NaviNotification(
            title: "Navi",
            body: "Uppgiften '\(instruction.prefix(50))' är klar!",
            category: .taskCompleted,
            source: .handoff,
            priority: 4
        )

        addNotification(notification)
        scheduleLocalNotification(notification)
    }

    // MARK: - Notification History

    private func addNotification(_ notification: NaviNotification) {
        recentNotifications.insert(notification, at: 0)
        if recentNotifications.count > maxRecentNotifications {
            recentNotifications = Array(recentNotifications.prefix(maxRecentNotifications))
        }
        unreadCount += 1
    }

    func markAllRead() {
        unreadCount = 0
    }

    func clearHistory() {
        recentNotifications = []
        unreadCount = 0
    }

    // MARK: - Badge Management

    func updateBadge() {
        #if os(iOS)
        UNUserNotificationCenter.current().setBadgeCount(unreadCount)
        #endif
    }

    func clearBadge() {
        unreadCount = 0
        #if os(iOS)
        UNUserNotificationCenter.current().setBadgeCount(0)
        #endif
    }
}

// MARK: - UNUserNotificationCenterDelegate

extension NotificationManager: UNUserNotificationCenterDelegate {
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        // Show notifications even when app is in foreground
        [.banner, .sound, .badge]
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        let userInfo = response.notification.request.content.userInfo
        let categoryRaw = userInfo["category"] as? String

        // Update badge/unread count immediately on the main actor.
        await MainActor.run {
            if self.unreadCount > 0 {
                self.unreadCount -= 1
            }
        }

        // Delay navigation so SwiftUI finishes initialising before we post
        // the notification (avoids the "Call must be made on main thread"
        // assertion when the app is cold-launched via a notification tap).
        try? await Task.sleep(nanoseconds: 600_000_000) // 0.6 s

        await MainActor.run {
            if let categoryRaw,
               let category = NotificationCategory(rawValue: categoryRaw) {
                self.handleNotificationTap(category: category, userInfo: userInfo)
            }
        }
    }

    @MainActor
    private func handleNotificationTap(category: NotificationCategory, userInfo: [AnyHashable: Any]) {
        switch category {
        case .taskCompleted:
            // Navigate to server view to see result
            NotificationCenter.default.post(name: .navigateToServer, object: nil)
        case .serverError:
            NotificationCenter.default.post(name: .navigateToServer, object: nil)
        case .serverActivity:
            NotificationCenter.default.post(name: .navigateToServer, object: nil)
        case .proactive:
            // Navigate to chat
            NotificationCenter.default.post(name: .navigateToChat, object: nil)
        case .handoffCompleted:
            NotificationCenter.default.post(name: .navigateToServer, object: nil)
        }
    }
}

// MARK: - Notification Model

struct NaviNotification: Identifiable {
    let id: UUID
    let title: String
    let body: String
    let category: NotificationCategory
    let source: NotificationSource
    let priority: Int
    let timestamp: Date

    init(
        title: String,
        body: String,
        category: NotificationCategory,
        source: NotificationSource,
        priority: Int = 3
    ) {
        self.id = UUID()
        self.title = title
        self.body = body
        self.category = category
        self.source = source
        self.priority = priority
        self.timestamp = Date()
    }
}

enum NotificationCategory: String {
    case taskCompleted = "TASK_COMPLETED"
    case serverActivity = "SERVER_ACTIVITY"
    case serverError = "SERVER_ERROR"
    case proactive = "PROACTIVE"
    case handoffCompleted = "HANDOFF_COMPLETED"

    static func from(tags: [String]) -> NotificationCategory {
        if tags.contains("task_complete") || tags.contains("done") { return .taskCompleted }
        if tags.contains("error") { return .serverError }
        if tags.contains("activity") { return .serverActivity }
        return .serverActivity
    }
}

enum NotificationSource: String {
    case server = "server"
    case local = "local"
    case handoff = "handoff"
}

// MARK: - Navigation Notifications

extension Notification.Name {
    static let navigateToServer = Notification.Name("navigateToServer")
    static let navigateToChat = Notification.Name("navigateToChat")
}
