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

/// Support messages are an independent local-first workflow, separate from
/// the app-wide session and dashboard state.
@MainActor extension AppState {
    func submitSupportCommand(_ content: String) async -> Bool {
        guard !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            workflowStates["support"] = .failed("请输入咨询内容。")
            return false
        }
        let normalized = content.trimmingCharacters(in: .whitespacesAndNewlines)
        let record = sendSupportMessage(normalized)
        let succeeded = await executeWorkflow("support") { try await self.repository.sendSupportMessage(normalized) }
        if succeeded { updateSupportSyncStatus(record.id, to: repository.supportsRemoteAcknowledgement ? .submitted : .pendingSync) }
        else if case .failed = workflowState(for: "support") { updateSupportSyncStatus(record.id, to: .failed) }
        return succeeded
    }

    @discardableResult
    func sendSupportMessage(_ text: String) -> SupportChatMessage {
        let message = SupportChatMessage(id: UUID(), text: text, isMine: true, status: .pendingSync, createdAt: .now)
        mutateLocal { $0.supportMessages.append(message) }
        return message
    }

    func updateSupportSyncStatus(_ id: UUID, to status: LocalSubmissionStatus) {
        mutateLocal { values in
            guard let index = values.supportMessages.firstIndex(where: { $0.id == id }) else { return }
            values.supportMessages[index].status = status
        }
    }
}
