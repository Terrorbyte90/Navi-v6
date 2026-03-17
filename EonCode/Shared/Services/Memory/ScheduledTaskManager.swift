import Foundation
import UserNotifications

// MARK: - ScheduledTaskManager
// Manages user-created reminders and recurring tasks.
// Detects "remind me" intent in chat messages via a lightweight Haiku call,
// then schedules local UNUserNotification reminders.

@MainActor
final class ScheduledTaskManager: ObservableObject {
    static let shared = ScheduledTaskManager()

    @Published var tasks: [ScheduledTask] = []

    private let storageKey = "naviScheduledTasks"
    private let api = ClaudeAPIClient.shared

    private init() {
        load()
    }

    // MARK: - Persistence (UserDefaults, small data)

    private func load() {
        guard let data = UserDefaults.standard.data(forKey: storageKey),
              let decoded = try? JSONDecoder().decode([ScheduledTask].self, from: data) else { return }
        tasks = decoded
        purgeCompletedPast()
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(tasks) else { return }
        UserDefaults.standard.set(data, forKey: storageKey)
    }

    /// Remove one-time tasks that are in the past and marked completed
    private func purgeCompletedPast() {
        let now = Date()
        tasks.removeAll { task in
            !task.isRecurring && task.isCompleted && task.scheduledDate < now
        }
    }

    // MARK: - Schedule a task

    func schedule(_ task: ScheduledTask) async {
        tasks.append(task)
        persist()
        await scheduleNotification(for: task)
        NaviLog.info("ScheduledTask: lagt till \"\(task.title)\" @ \(task.scheduledDate.formatted())")
    }

    // MARK: - Delete

    func delete(_ task: ScheduledTask) {
        UNUserNotificationCenter.current()
            .removePendingNotificationRequests(withIdentifiers: [task.notificationIdentifier])
        tasks.removeAll { $0.id == task.id }
        persist()
    }

    func deleteAll() {
        let ids = tasks.map { $0.notificationIdentifier }
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: ids)
        tasks = []
        UserDefaults.standard.removeObject(forKey: storageKey)
    }

    // MARK: - Mark completed

    func markCompleted(_ task: ScheduledTask) {
        guard let idx = tasks.firstIndex(where: { $0.id == task.id }) else { return }
        tasks[idx].isCompleted = true
        if !task.isRecurring {
            UNUserNotificationCenter.current()
                .removePendingNotificationRequests(withIdentifiers: [task.notificationIdentifier])
        }
        persist()
    }

    // MARK: - Schedule local notification

    private func scheduleNotification(for task: ScheduledTask) async {
        let content = UNMutableNotificationContent()
        content.title = "⏰ \(task.title)"
        content.body = task.notificationBody
        content.sound = .default
        content.userInfo = ["taskId": task.id.uuidString]

        let cal = Calendar.current

        let trigger: UNNotificationTrigger

        switch task.recurringInterval {
        case .daily:
            var comps = cal.dateComponents([.hour, .minute], from: task.scheduledDate)
            comps.second = 0
            trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: true)

        case .weekly:
            var comps = cal.dateComponents([.weekday, .hour, .minute], from: task.scheduledDate)
            comps.second = 0
            trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: true)

        case .workday:
            // Schedule Mon–Fri by firing once per day; system handles Mon–Fri via separate requests
            var comps = cal.dateComponents([.hour, .minute], from: task.scheduledDate)
            comps.second = 0
            // We'll create 5 separate requests for Mon–Fri
            for weekday in 2...6 {  // 2=Mon, 6=Fri in Calendar
                var wdComps = comps
                wdComps.weekday = weekday
                let wdTrigger = UNCalendarNotificationTrigger(dateMatching: wdComps, repeats: true)
                let req = UNNotificationRequest(
                    identifier: "\(task.notificationIdentifier)-wd\(weekday)",
                    content: content,
                    trigger: wdTrigger
                )
                try? await UNUserNotificationCenter.current().add(req)
            }
            return  // early return — requests already added above

        case nil:
            // One-time
            let comps = cal.dateComponents([.year, .month, .day, .hour, .minute], from: task.scheduledDate)
            trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: false)
        }

        let request = UNNotificationRequest(
            identifier: task.notificationIdentifier,
            content: content,
            trigger: trigger
        )
        do {
            try await UNUserNotificationCenter.current().add(request)
        } catch {
            NaviLog.error("ScheduledTaskManager: kunde inte schemalägga notis", error: error)
        }
    }

    // MARK: - Detect reminder intent in chat

    /// Call after a user message is sent. If the message contains a reminder/schedule intent,
    /// parses it via Haiku and schedules the notification. Returns the created task if any.
    func detectAndSchedule(from userText: String, conversationId: UUID) async -> ScheduledTask? {
        let lowered = userText.lowercased()
        // Quick keyword pre-filter to avoid Haiku calls on every message
        let triggerWords = ["påminn", "remind", "kom ihåg", "remember", "schemalägg",
                            "schedule", "varje dag", "every day", "varje morgon", "every morning",
                            "varje vecka", "every week", "kl.", "klockan", "om en timme",
                            "imorgon", "tomorrow", "fredag", "måndag", "tisdag", "onsdag",
                            "torsdag", "lördag", "söndag"]
        guard triggerWords.contains(where: { lowered.contains($0) }) else { return nil }
        guard KeychainManager.shared.anthropicAPIKey?.isEmpty == false else { return nil }

        let now = Date().formatted(date: .complete, time: .shortened)
        let prompt = """
        Analysera detta meddelande och avgör om det innehåller en påminnelse eller schemalagd uppgift.

        Meddelande: "\(userText)"
        Nuvarande datum och tid: \(now)

        Returnera BARA JSON:
        {
          "hasReminder": true/false,
          "title": "kort titel (max 6 ord)",
          "body": "lite längre text (max 15 ord)",
          "scheduledDateISO": "YYYY-MM-DDTHH:mm:ss" eller null,
          "recurring": null | "daily" | "weekly" | "workday"
        }

        Om inget tydligt datum/tid finns och inget återkommande mönster: scheduledDateISO = null och hasReminder = false.
        """

        do {
            let (response, _) = try await api.sendMessage(
                messages: [ChatMessage(role: .user, content: [.text(prompt)])],
                model: .haiku,
                systemPrompt: "Returnera BARA giltig JSON. Inga kommentarer.",
                maxTokens: 120
            )
            guard let parsed = parseReminderJSON(response),
                  parsed.hasReminder,
                  let isoStr = parsed.scheduledDateISO,
                  let date = parseISO8601(isoStr) else { return nil }

            var recurring: RecurringInterval? = nil
            if let r = parsed.recurring {
                recurring = RecurringInterval(rawValue: r)
            }
            let isRecurring = recurring != nil
            let task = ScheduledTask(
                title: parsed.title ?? "Påminnelse",
                notificationBody: parsed.body ?? userText,
                scheduledDate: date,
                isRecurring: isRecurring,
                recurringInterval: recurring
            )
            await schedule(task)
            return task
        } catch {
            return nil  // Silent fail
        }
    }

    // MARK: - JSON parsing helpers

    private struct ReminderJSON: Decodable {
        let hasReminder: Bool
        let title: String?
        let body: String?
        let scheduledDateISO: String?
        let recurring: String?
    }

    private func parseReminderJSON(_ text: String) -> ReminderJSON? {
        guard let start = text.firstIndex(of: "{"),
              let end   = text.lastIndex(of: "}") else { return nil }
        let slice = String(text[start...end])
        guard let data = slice.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(ReminderJSON.self, from: data)
    }

    private func parseISO8601(_ str: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withDashSeparatorInDate,
                                   .withColonSeparatorInTime, .withTimeZone]
        if let d = formatter.date(from: str) { return d }
        // Fallback: without timezone
        let fallback = DateFormatter()
        fallback.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"
        return fallback.date(from: str)
    }
}
