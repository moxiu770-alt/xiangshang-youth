import Foundation

@MainActor extension AppState {
    func updateActivitySyncStatus(_ id: UUID, to status: LocalSubmissionStatus) {
        mutateLocal { values in
            guard let index = values.activityRegistrations.firstIndex(where: { $0.id == id }) else { return }
            values.activityRegistrations[index].status = status
        }
    }
    func updateActivityProjection(_ id: UUID, ack: ActivityRegistrationAck?, fallbackStatus: LocalSubmissionStatus) {
        mutateLocal { values in
            guard let index = values.activityRegistrations.firstIndex(where: { $0.id == id }) else { return }
            values.activityRegistrations[index].status = fallbackStatus
            if let ack {
                values.activityRegistrations[index].registrationID = ack.registrationID
                values.activityRegistrations[index].registrationStatus = ack.status
                values.activityRegistrations[index].version = ack.version
                values.activityRegistrations[index].childID = ack.childID ?? values.activityRegistrations[index].childID
                if let name = ack.contactName { values.activityRegistrations[index].contactName = name }
                if let phone = ack.phone { values.activityRegistrations[index].phone = phone }
                let activityID = values.activityRegistrations[index].activityID
                let hasActiveRegistration = values.activityRegistrations.contains {
                    $0.activityID == activityID && $0.registrationStatus != "cancelled" && $0.status != .failed
                }
                if hasActiveRegistration { values.registeredActivities.insert(activityID) }
                else { values.registeredActivities.remove(activityID) }
            }
        }
        if let ack {
            activityRegistrationHistory.removeAll { $0.registrationID == ack.registrationID }
            activityRegistrationHistory.insert(ack, at: 0)
        }
    }
    func applyActivityCancellation(activityID: String, childID: String?, ack: ActivityRegistrationAck?) {
        mutateLocal { values in
            if let index = values.activityRegistrations.firstIndex(where: { $0.activityID == activityID && ($0.childID == childID || $0.childID == nil) }) {
                values.activityRegistrations[index].status = .submitted
                values.activityRegistrations[index].registrationStatus = ack?.status ?? "cancelled"
                values.activityRegistrations[index].version = ack?.version ?? values.activityRegistrations[index].version
            }
            let stillRegistered = values.activityRegistrations.contains {
                $0.activityID == activityID &&
                ($0.childID != childID) &&
                $0.registrationStatus != "cancelled" &&
                $0.status != .failed
            }
            if stillRegistered { values.registeredActivities.insert(activityID) }
            else { values.registeredActivities.remove(activityID) }
        }
        if let ack {
            activityRegistrationHistory.removeAll { $0.registrationID == ack.registrationID }
            activityRegistrationHistory.insert(ack, at: 0)
        }
    }
    func updateExpertSyncStatus(_ id: UUID, to status: LocalSubmissionStatus) {
        mutateLocal { values in
            guard let index = values.expertAppointments.firstIndex(where: { $0.id == id }) else { return }
            values.expertAppointments[index].status = status
        }
    }
    func updateExpertProjection(_ id: UUID, ack: ExpertAppointmentAck?, fallbackStatus: LocalSubmissionStatus) {
        mutateLocal { values in
            guard let index = values.expertAppointments.firstIndex(where: { $0.id == id }) else { return }
            values.expertAppointments[index].status = fallbackStatus
            if let ack {
                values.expertAppointments[index].appointmentID = ack.appointmentID
                values.expertAppointments[index].expertID = ack.expertID ?? values.expertAppointments[index].expertID
                values.expertAppointments[index].serviceID = ack.serviceID ?? values.expertAppointments[index].serviceID
                values.expertAppointments[index].slotID = ack.slotID ?? values.expertAppointments[index].slotID
                values.expertAppointments[index].childID = ack.childID ?? values.expertAppointments[index].childID
                values.expertAppointments[index].appointmentStatus = ack.status
                values.expertAppointments[index].expectedVersion = ack.version
                if let preferred = ack.preferredDate { values.expertAppointments[index].preferredDate = preferred }
                if let note = ack.note { values.expertAppointments[index].note = note }
                values.expertAppointments[index].scheduledStartAt = ack.scheduledStartAt.flatMap(Self.parseISODate) ?? values.expertAppointments[index].scheduledStartAt
                values.expertAppointments[index].scheduledEndAt = ack.scheduledEndAt.flatMap(Self.parseISODate) ?? values.expertAppointments[index].scheduledEndAt
            }
        }
        if let ack {
            expertAppointmentHistory.removeAll { $0.appointmentID == ack.appointmentID }
            expertAppointmentHistory.insert(ack, at: 0)
        }
    }
    func updateCourseSyncStatus(_ id: UUID, to status: LocalSubmissionStatus) {
        mutateLocal { values in
            guard let index = values.courseUploads.firstIndex(where: { $0.id == id }) else { return }
            values.courseUploads[index].status = status
        }
    }
    func updateTaskStatusSyncState(_ studentID: String, taskID: String? = nil, to status: LocalSubmissionStatus) {
        mutateLocal { values in
            let key = taskKey(taskID: taskID, studentID: studentID)
            values.taskScopedSyncStates[key] = status
        }
    }
    /// Persists the server's optimistic-concurrency version after an accepted
    /// write. Remote mode never invents a version: the server response is the
    /// only safe optimistic-lock value for the next task-row mutation.
    func acknowledgeTaskStatusVersion(_ studentID: String, taskID: String? = nil, serverVersion: Int?) {
        guard repository.supportsRemoteAcknowledgement else { return }
        guard let next = serverVersion else { return }
        mutateLocal { values in
            let key = taskKey(taskID: taskID, studentID: studentID)
            values.taskScopedStatusVersions[key] = next
        }
    }
    /// A rejected optimistic write must not remain as a local overlay: doing so
    /// would replay the stale transition forever and hide the server's current
    /// status after a refresh.
    func resetTaskStatusProjectionAfterConflict(_ studentID: String, taskID: String? = nil) {
        mutateLocal {
            let key = taskKey(taskID: taskID, studentID: studentID)
            $0.taskScopedStatuses.removeValue(forKey: key)
            $0.taskScopedStatusVersions.removeValue(forKey: key)
            $0.taskScopedSyncStates[key] = .failed
        }
    }
}
