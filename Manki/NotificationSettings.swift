import Foundation
import UserNotifications

struct DailyNotificationTime: Codable, Equatable, Identifiable {
    let id: UUID
    var hour: Int
    var minute: Int

    init(id: UUID = UUID(), hour: Int, minute: Int) {
        self.id = id
        self.hour = hour
        self.minute = minute
    }

    var date: Date {
        Calendar.current.date(from: DateComponents(hour: hour, minute: minute)) ?? .now
    }
}

@MainActor
final class NotificationSettings: ObservableObject {
    @Published private(set) var times: [DailyNotificationTime]
    @Published private(set) var isEnabled: Bool
    @Published private(set) var permissionDenied = false

    private let center: UNUserNotificationCenter
    private let defaults: UserDefaults
    private var decks: [Deck] = []

    private enum Keys {
        static let times = "dailyNotificationTimes"
        static let enabled = "dailyNotificationsEnabled"
    }

    init(center: UNUserNotificationCenter = .current(), defaults: UserDefaults = .standard) {
        self.center = center
        self.defaults = defaults
        if let data = defaults.data(forKey: Keys.times),
           let saved = try? JSONDecoder().decode([DailyNotificationTime].self, from: data) {
            times = saved
        } else {
            times = [DailyNotificationTime(hour: 9, minute: 0)]
        }
        isEnabled = defaults.bool(forKey: Keys.enabled)
    }

    func setEnabled(_ enabled: Bool) async {
        if enabled {
            do {
                let granted = try await center.requestAuthorization(options: [.alert, .sound])
                guard granted else {
                    permissionDenied = true
                    return
                }
            } catch {
                permissionDenied = true
                return
            }
        }

        permissionDenied = false
        isEnabled = enabled
        defaults.set(enabled, forKey: Keys.enabled)
        await reschedule()
    }

    func addTime() async {
        times.append(DailyNotificationTime(hour: 18, minute: 0))
        persistTimes()
        await reschedule()
    }

    func updateTime(id: UUID, date: Date) async {
        guard let index = times.firstIndex(where: { $0.id == id }) else { return }
        let components = Calendar.current.dateComponents([.hour, .minute], from: date)
        times[index].hour = components.hour ?? 9
        times[index].minute = components.minute ?? 0
        persistTimes()
        await reschedule()
    }

    func removeTime(id: UUID) async {
        center.removePendingNotificationRequests(withIdentifiers: ["manki.daily-reminder.\(id.uuidString)"])
        times.removeAll { $0.id == id }
        persistTimes()
        await reschedule()
    }

    func updateDecks(_ decks: [Deck]) async {
        self.decks = decks.filter { $0.contributesToBadge && $0.dueCount > 0 }
        await reschedule()
    }

    private func persistTimes() {
        defaults.set(try? JSONEncoder().encode(times), forKey: Keys.times)
    }

    private func reschedule() async {
        center.removePendingNotificationRequests(withIdentifiers: times.map(identifier))
        guard isEnabled else { return }

        for time in times {
            let content = UNMutableNotificationContent()
            if let deck = decks.randomElement() {
                content.title = deck.name
                let encouragements = [
                    "a little practice goes a long way!",
                    "you've got this!",
                    "make today’s knowledge stick!",
                ]
                let count = deck.dueCount
                content.body = "\(count) \(count == 1 ? "card is" : "cards are") due — \(encouragements.randomElement()!)"
            } else {
                content.title = "Ready for a quick review?"
                content.body = "Keep your learning streak shining!"
            }
            content.sound = .default
            let trigger = UNCalendarNotificationTrigger(
                dateMatching: DateComponents(hour: time.hour, minute: time.minute),
                repeats: true
            )
            try? await center.add(UNNotificationRequest(identifier: identifier(time), content: content, trigger: trigger))
        }
    }

    private func identifier(_ time: DailyNotificationTime) -> String {
        "manki.daily-reminder.\(time.id.uuidString)"
    }
}
