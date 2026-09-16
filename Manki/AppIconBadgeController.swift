import UserNotifications

protocol AppIconBadgeSetting {
    func setBadgeCount(_ count: Int) async
}

struct UserNotificationBadgeSetter: AppIconBadgeSetting {
    private let center = UNUserNotificationCenter.current()

    func setBadgeCount(_ count: Int) async {
        if count > 0 {
            let settings = await center.notificationSettings()
            switch settings.authorizationStatus {
            case .notDetermined:
                guard (try? await center.requestAuthorization(options: [.badge])) == true else { return }
            case .denied:
                return
            case .authorized, .provisional, .ephemeral:
                break
            @unknown default:
                return
            }
        }

        // setBadgeCount is the supported badge API on the app's iOS 17
        // deployment target. A zero value removes an existing badge.
        try? await center.setBadgeCount(count)
    }
}

@MainActor
final class AppIconBadgeController {
    private let setter: any AppIconBadgeSetting

    init(setter: any AppIconBadgeSetting = UserNotificationBadgeSetter()) {
        self.setter = setter
    }

    func update(decks: [Deck], isAuthenticated: Bool) async {
        await setter.setBadgeCount(isAuthenticated ? DueBadgeCount.total(for: decks) : 0)
    }
}
