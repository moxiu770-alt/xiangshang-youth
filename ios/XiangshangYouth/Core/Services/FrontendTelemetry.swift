import Foundation
import OSLog

enum FrontendEvent: String {
    case growthReportOpened = "growth_report_opened"
    case growthReportPeriodChanged = "growth_report_period_changed"
    case adaptivePlanOpenedCourses = "adaptive_plan_opened_courses"
}

/// Privacy-safe event boundary. It intentionally accepts only predefined
/// event names and coarse values, never student ids, names, phone numbers or
/// health measurements. A production analytics SDK can replace the sink.
enum FrontendTelemetry {
    private static let logger = Logger(subsystem: "com.xiangshang.youth", category: "product-events")

    static func record(_ event: FrontendEvent, value: String? = nil) {
        logger.info("event=\(event.rawValue, privacy: .public) value=\(value ?? "none", privacy: .public)")
    }
}
