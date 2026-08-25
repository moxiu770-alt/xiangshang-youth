import Foundation
#if canImport(Sentry)
import Sentry
#endif

/// Crash reporting is deliberately inert until CI injects a Sentry DSN. This
/// prevents source images, health values and identifiers from leaving local or
/// demo builds while preserving a production-ready monitoring boundary.
enum CrashMonitoring {
    private static var isConfigured = false

    static func configure() {
        guard !isConfigured else { return }
        let dsn = (Bundle.main.object(forInfoDictionaryKey: "SentryDSN") as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !dsn.isEmpty, !dsn.hasPrefix("$(") else { return }

#if canImport(Sentry)
        SentrySDK.start { options in
            options.dsn = dsn
            options.environment = (Bundle.main.object(forInfoDictionaryKey: "ReleaseChannel") as? String) ?? "internal"
            options.releaseName = "com.xiangshang.youth@\(appVersion)"
            options.sendDefaultPii = false
            options.enableUserInteractionTracing = false
        }
        isConfigured = true
#endif
    }

    static func record(_ error: Error, feature: String) {
#if canImport(Sentry)
        guard isConfigured else { return }
        SentrySDK.configureScope { scope in scope.setTag(value: feature, key: "feature") }
        SentrySDK.capture(error: error)
#else
        // Sentry is an optional production dependency. Keep local/demo builds inert.
        _ = (error, feature)
#endif
    }

    private static var appVersion: String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "0"
        return "\(version)+\(build)"
    }
}
