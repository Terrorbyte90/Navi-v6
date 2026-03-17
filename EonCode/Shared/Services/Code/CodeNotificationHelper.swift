import Foundation
import UserNotifications

// MARK: - Sends local notification when Code Agent finishes

enum CodeNotificationHelper {

    static func sendCompletionNotification(task: String, summary: String) async {
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        guard settings.authorizationStatus == .authorized ||
              settings.authorizationStatus == .provisional else { return }

        let content = UNMutableNotificationContent()
        content.title = "Navi — Agent klar ✓"
        content.subtitle = String(task.prefix(60))
        content.body = summary
        content.sound = .default
        content.categoryIdentifier = "CODE_AGENT_DONE"

        // Badge
        #if os(iOS)
        content.badge = 1
        #endif

        let request = UNNotificationRequest(
            identifier: "code-agent-done-\(UUID().uuidString)",
            content: content,
            trigger: nil   // immediate
        )
        try? await center.add(request)
    }

    static func sendErrorNotification(task: String, error: String) async {
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        guard settings.authorizationStatus == .authorized ||
              settings.authorizationStatus == .provisional else { return }

        let content = UNMutableNotificationContent()
        content.title = "Navi — Agent fel"
        content.subtitle = String(task.prefix(60))
        content.body = String(error.prefix(100))
        content.sound = .defaultCritical

        let request = UNNotificationRequest(
            identifier: "code-agent-err-\(UUID().uuidString)",
            content: content,
            trigger: nil
        )
        try? await center.add(request)
    }

    /// Request notification permission (call once at app start)
    static func requestPermission() {
        UNUserNotificationCenter.current().requestAuthorization(
            options: [.alert, .badge, .sound]
        ) { _, _ in }
    }
}
