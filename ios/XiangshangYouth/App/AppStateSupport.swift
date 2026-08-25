import SwiftUI
import Network

/// Stable destination supplied by a report recommendation. `title` is used
/// only by the bundled offline catalogue; remote courses resolve by IDs.
struct CourseRecommendationTarget: Equatable {
    let childID: String
    let courseID: String?
    let lessonID: String?
    let title: String
}

@MainActor final class NetworkMonitor: ObservableObject {
    @Published private(set) var isOffline = false
    private let monitor = NWPathMonitor()
    private let queue = DispatchQueue(label: "com.xiangshang.youth.network-monitor")
    private var started = false

    func start() {
        guard !started else { return }
        started = true
        monitor.pathUpdateHandler = { [weak self] path in
            Task { @MainActor in self?.isOffline = path.status != .satisfied }
        }
        monitor.start(queue: queue)
    }

    deinit { monitor.cancel() }
}

enum WorkflowCommandState: Equatable {
    case idle
    case submitting
    case succeeded(String)
    case failed(String)

    var isSubmitting: Bool {
        if case .submitting = self { return true }
        return false
    }
}
