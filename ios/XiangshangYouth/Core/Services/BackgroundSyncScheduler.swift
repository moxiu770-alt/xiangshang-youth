import BackgroundTasks
import Foundation

/// Schedules durable sync after the app leaves the foreground. iOS decides
/// the execution time; foreground/reconnect sync remains the fast path.
enum BackgroundSyncScheduler {
    static let identifier = "com.xiangshang.youth.pending-sync"
    private static var registered = false

    @MainActor
    static func register(operation: @escaping @MainActor () async -> Bool) {
        guard !registered else { return }
        registered = BGTaskScheduler.shared.register(forTaskWithIdentifier: identifier, using: nil) { task in
            guard let processingTask = task as? BGProcessingTask else {
                task.setTaskCompleted(success: false)
                return
            }
            let work = Task { @MainActor in
                let succeeded = await operation()
                processingTask.setTaskCompleted(success: succeeded)
                if !succeeded { schedule() }
            }
            processingTask.expirationHandler = { work.cancel() }
        }
    }

    static func schedule() {
        let request = BGProcessingTaskRequest(identifier: identifier)
        request.requiresNetworkConnectivity = true
        request.requiresExternalPower = false
        request.earliestBeginDate = Date(timeIntervalSinceNow: 60)
        do {
            try BGTaskScheduler.shared.submit(request)
        } catch {
            // Simulator, disabled background refresh and duplicate submissions
            // can reject a request. Foreground/reconnect sync remains active;
            // do not log child data or turn scheduling into a user-facing error.
        }
    }
}
