import Foundation
import Combine
import UserNotifications

/// Local reminders for service intervals. Everything is computed on device
/// from the same insights the Wartung tab shows, so no backend support is
/// needed: for each tracked item one notification fires when it enters the
/// "due" window (90 days ahead) and one on the due date itself. Rescheduled
/// whenever a bike's insights change, keyed per bike + item so stale
/// reminders are replaced, never duplicated.
///
/// Reminders are opt-in (Settings → Erinnerungen). Only bikes whose Wartung
/// tab has been opened since enabling get scheduled — the insights need the
/// bike's records, which are loaded per workspace.
@MainActor
final class MaintenanceReminderScheduler: ObservableObject {
    static let shared = MaintenanceReminderScheduler()

    static let enabledKey = "com.motomanager.intervalReminders"
    private static let identifierPrefix = "interval."
    private static let reminderHour = 9
    private static let dueWindowDays = 90

    @Published private(set) var isEnabled: Bool
    /// The user declined the system permission prompt; the toggle shows a
    /// pointer to the system settings instead of silently doing nothing.
    @Published private(set) var isDenied = false

    private let defaults: UserDefaults
    private let center = UNUserNotificationCenter.current()

    private init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        isEnabled = defaults.bool(forKey: Self.enabledKey)
    }

    /// Turns reminders on (asking for permission on first use) or off.
    /// Returns the resulting state; `false` after a denied prompt.
    @discardableResult
    func setEnabled(_ enabled: Bool) async -> Bool {
        guard enabled else {
            isEnabled = false
            defaults.set(false, forKey: Self.enabledKey)
            cancelAll()
            return false
        }
        let settings = await center.notificationSettings()
        var granted = settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional
        if settings.authorizationStatus == .notDetermined {
            granted = (try? await center.requestAuthorization(options: [.alert, .sound, .badge])) ?? false
        }
        isDenied = !granted
        isEnabled = granted
        defaults.set(granted, forKey: Self.enabledKey)
        return granted
    }

    /// Replaces the reminders of one bike with the ones its current insights
    /// call for. Items already due or overdue get none: they are visible in
    /// the app, and a reminder "in the past" would fire immediately.
    func schedule(for motorcycle: Motorcycle, insights: [MaintenanceInsight], now: Date = Date()) {
        guard isEnabled else { return }
        let bikePrefix = "\(Self.identifierPrefix)\(motorcycle.id)."
        let name = "\(motorcycle.make) \(motorcycle.model)"
        let requests = insights.flatMap { Self.requests(for: $0, bikePrefix: bikePrefix, bikeName: name, now: now) }
        Task {
            let pending = await center.pendingNotificationRequests()
                .map(\.identifier)
                .filter { $0.hasPrefix(bikePrefix) }
            center.removePendingNotificationRequests(withIdentifiers: pending)
            for request in requests {
                try? await center.add(request)
            }
        }
    }

    /// Drops every interval reminder (logout, reminders switched off).
    func cancelAll() {
        Task {
            let pending = await center.pendingNotificationRequests()
                .map(\.identifier)
                .filter { $0.hasPrefix(Self.identifierPrefix) }
            center.removePendingNotificationRequests(withIdentifiers: pending)
        }
    }

    // MARK: - Request building (pure, testable)

    struct PlannedReminder: Equatable {
        let identifier: String
        let fireDate: Date
        let title: String
        let body: String
    }

    /// The reminders one insight calls for: entering the due window, and the
    /// due date itself — each only when still ahead of `now`.
    static func plan(
        for insight: MaintenanceInsight, bikeId: Int, bikeName: String, now: Date
    ) -> [PlannedReminder] {
        let calendar = Calendar.current
        func at9(_ date: Date) -> Date {
            var components = calendar.dateComponents([.year, .month, .day], from: date)
            components.hour = reminderHour
            components.minute = 0
            return calendar.date(from: components) ?? date
        }
        let rule = insight.intervalYears == 1 ? "jedes Jahr" : "alle \(insight.intervalYears) Jahre"
        var planned: [PlannedReminder] = []
        if let windowStart = calendar.date(byAdding: .day, value: -dueWindowDays, to: insight.nextDate) {
            let fire = at9(windowStart)
            if fire > now {
                planned.append(PlannedReminder(
                    identifier: "\(identifierPrefix)\(bikeId).\(insight.key).due",
                    fireDate: fire,
                    title: "\(bikeName): Service bald fällig",
                    body: "\(insight.label) ist in etwa 3 Monaten fällig (\(rule))."
                ))
            }
        }
        let dueFire = at9(insight.nextDate)
        if dueFire > now {
            planned.append(PlannedReminder(
                identifier: "\(identifierPrefix)\(bikeId).\(insight.key).overdue",
                fireDate: dueFire,
                title: "\(bikeName): Service fällig",
                body: "\(insight.label) ist jetzt fällig (\(rule))."
            ))
        }
        return planned
    }

    private static func requests(
        for insight: MaintenanceInsight, bikePrefix: String, bikeName: String, now: Date
    ) -> [UNNotificationRequest] {
        let bikeId = Int(bikePrefix.dropFirst(identifierPrefix.count).dropLast()) ?? 0
        return plan(for: insight, bikeId: bikeId, bikeName: bikeName, now: now).map { reminder in
            let content = UNMutableNotificationContent()
            content.title = reminder.title
            content.body = reminder.body
            content.sound = .default
            let components = Calendar.current.dateComponents(
                [.year, .month, .day, .hour, .minute], from: reminder.fireDate)
            let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
            return UNNotificationRequest(identifier: reminder.identifier, content: content, trigger: trigger)
        }
    }
}
