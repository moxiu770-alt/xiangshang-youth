import Foundation
import OSLog

enum FrontendEvent: String {
    case growthReportOpened = "growth_report_opened"
    case growthReportPeriodChanged = "growth_report_period_changed"
    case adaptivePlanOpenedCourses = "adaptive_plan_opened_courses"
}

enum FrontendTelemetry {
    private static let sink = ProductEventSink()

    static func configure(enabled: Bool) {
        Task { await sink.configure(enabled: enabled) }
    }
    static func record(_ event: FrontendEvent, value: String? = nil) {
        Task { await sink.record(event, value: value) }
    }
}

private actor ProductEventSink {
    private let logger = Logger(subsystem: "com.xiangshang.youth", category: "product-events")
    private let clientSessionID = UUID()
    private var enabled = false

    func configure(enabled: Bool) { self.enabled = enabled }

    func record(_ event: FrontendEvent, value: String?) async {
        guard enabled else { return }
        let allowedValue = ["本周", "本月"].contains(value) ? value : nil
        logger.info("event=\(event.rawValue, privacy: .public) value=\(allowedValue ?? "none", privacy: .public)")
        let payload = ProductEventInput(
            eventID: UUID(), eventName: event.rawValue, coarseValue: allowedValue,
            platform: "ios", appVersion: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0",
            clientSessionID: clientSessionID, occurredAt: ISO8601DateFormatter().string(from: Date())
        )
        // Analytics must never block, retry, or alter a family/teacher flow.
        try? await ProductEventApi.submit([payload])
    }
}
