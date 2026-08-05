import UserNotifications

/// System notification permission stays independent from the remote message API
/// so it can be exercised in Mock mode and reused after push delivery is wired.
enum NotificationPermission {
    static func request() async -> Bool {
        let center = UNUserNotificationCenter.current()
        let settings = await withCheckedContinuation { continuation in
            center.getNotificationSettings { continuation.resume(returning: $0) }
        }
        if settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional {
            return true
        }
        return (try? await center.requestAuthorization(options: [.alert, .badge, .sound])) ?? false
    }
}
