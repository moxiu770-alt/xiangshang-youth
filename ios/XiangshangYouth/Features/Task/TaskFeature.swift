import Foundation

/// Task feature namespace reserved for task actions and future site-side refresh subscriptions.
enum TaskFeature { static let refreshNotification = Notification.Name("taskStatusDidRefresh") }
