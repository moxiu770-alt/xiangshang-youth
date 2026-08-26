import Foundation

/// Activity registrations and expert appointments are independent scheduling
/// workflows. They retain stable server IDs and versions, never names/titles.
@MainActor extension AppState {
    func submitActivityCommand(_ activityID: String, contactName: String, phone: String) async -> Bool {
        let key = childWorkflowKey("activity:\(activityID)")
        guard !contactName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, phone.filter(\.isNumber).count == 11 else {
            workflowStates[key] = .failed("报名信息不完整，请检查姓名和手机号。"); return false
        }
        registerActivity(activityID, contactName: contactName, phone: phone)
        let childID = selectedChild?.id
        guard let record = localFeatures.activityRegistrations.first(where: { $0.activityID == activityID && ($0.childID == childID || $0.childID == nil) }) else {
            workflowStates[key] = .failed("报名信息不完整，请检查姓名和手机号。"); return false
        }
        var ack: ActivityRegistrationAck?
        let succeeded = await executeWorkflow(key) {
            ack = record.registrationID == nil ? try await self.repository.submitActivity(record) : try await self.repository.updateActivityRegistration(record)
        }
        if succeeded {
            updateActivityProjection(record.id, ack: ack, fallbackStatus: repository.supportsRemoteAcknowledgement ? .submitted : .pendingSync)
            if repository.supportsRemoteAcknowledgement { await loadActivities() }
        } else if case .failed = workflowState(for: key) { updateActivitySyncStatus(record.id, to: .failed) }
        return succeeded
    }

    func registerActivity(_ id: String, contactName: String, phone: String) {
        guard !contactName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, phone.filter(\.isNumber).count == 11 else { return }
        let childID = selectedChild?.id
        mutateLocal { values in
            let previous = values.activityRegistrations.first { $0.activityID == id && $0.childID == childID }
            values.registeredActivities.insert(id)
            values.activityRegistrations.removeAll { $0.activityID == id && $0.childID == childID }
            values.activityRegistrations.insert(ActivityRegistration(id: previous?.id ?? UUID(), activityID: id, contactName: contactName.trimmingCharacters(in: .whitespacesAndNewlines), phone: phone, status: .pendingSync, createdAt: previous?.createdAt ?? .now, registrationID: previous?.registrationID, childID: childID, contactUserID: previous?.contactUserID, capacity: previous?.capacity, remainingCapacity: previous?.remainingCapacity, registrationStartAt: previous?.registrationStartAt, registrationEndAt: previous?.registrationEndAt, registrationStatus: previous?.registrationStatus ?? "pending", version: previous?.version), at: 0)
        }
    }

    func cancelActivityRegistration(_ id: String) {
        let childID = selectedChild?.id
        mutateLocal { values in values.registeredActivities.remove(id); values.activityRegistrations.removeAll { $0.activityID == id && $0.childID == childID } }
        clearDraft("activity-registration-\(id)"); clearWorkflowState("activity:\(id)")
    }

    func cancelActivityRegistrationCommand(_ activityID: String) async -> Bool {
        let childID = selectedChild?.id
        guard let record = localFeatures.activityRegistrations.first(where: { $0.activityID == activityID && ($0.childID == childID || $0.childID == nil) }) else { cancelActivityRegistration(activityID); return true }
        guard repository.supportsRemoteAcknowledgement, record.registrationID != nil else { cancelActivityRegistration(activityID); return true }
        let key = childWorkflowKey("activity-cancel:\(activityID)", childID: childID)
        var ack: ActivityRegistrationAck?
        let succeeded = await executeWorkflow(key) { ack = try await self.repository.cancelActivityRegistration(record) }
        if succeeded { applyActivityCancellation(activityID: activityID, childID: childID, ack: ack); await loadActivities() }
        return succeeded
    }

    func submitExpertCommand(name: String, preferredDate: String, note: String, expertID suppliedExpertID: String? = nil, serviceID: String? = nil, slotID: String? = nil, scheduledStartAt: String? = nil, scheduledEndAt: String? = nil) async -> Bool {
        guard let expertID = suppliedExpertID?.nilIfBlank else { workflowStates["expert:unresolved"] = .failed("专家信息缺少编号，请刷新专家列表后重试。"); return false }
        let key = childWorkflowKey("expert:\(expertID)")
        guard !preferredDate.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, !note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { workflowStates[key] = .failed("预约信息不完整，请填写时间和咨询说明。"); return false }
        bookExpert(name: name, preferredDate: preferredDate, note: note, expertID: expertID, serviceID: serviceID, slotID: slotID, scheduledStartAt: scheduledStartAt, scheduledEndAt: scheduledEndAt)
        let childID = selectedChild?.id
        guard let record = localFeatures.expertAppointments.first(where: { $0.expertID == expertID && ($0.childID == childID || $0.childID == nil) }) else { workflowStates[key] = .failed("预约信息不完整，请填写时间和咨询说明。"); return false }
        var ack: ExpertAppointmentAck?
        let succeeded = await executeWorkflow(key) { ack = try await self.repository.bookExpert(record) }
        if succeeded { updateExpertProjection(record.id, ack: ack, fallbackStatus: repository.supportsRemoteAcknowledgement ? .submitted : .pendingSync); if repository.supportsRemoteAcknowledgement { await loadExperts() } }
        else if case .failed = workflowState(for: key) { updateExpertSyncStatus(record.id, to: .failed) }
        return succeeded
    }

    func bookExpert(name: String, preferredDate: String, note: String, expertID suppliedExpertID: String? = nil, serviceID: String? = nil, slotID: String? = nil, scheduledStartAt: String? = nil, scheduledEndAt: String? = nil) {
        guard !preferredDate.isEmpty, !note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, let expertID = suppliedExpertID?.nilIfBlank else { return }
        let childID = selectedChild?.id
        mutateLocal { values in
            values.expertAppointments.removeAll { $0.expertID == expertID && ($0.childID == childID || $0.childID == nil) }
            values.expertAppointments.insert(ExpertAppointment(id: UUID(), expertName: name, preferredDate: preferredDate, note: note, status: .pendingSync, createdAt: .now, expertID: expertID, serviceID: serviceID?.nilIfBlank, slotID: slotID?.nilIfBlank, childID: childID, appointmentStatus: "pending", scheduledStartAt: scheduledStartAt.flatMap(Self.parseISODate), scheduledEndAt: scheduledEndAt.flatMap(Self.parseISODate)), at: 0)
        }
    }

    func cancelExpertCommand(expertID: String, expertName _: String) async -> Bool {
        let childID = selectedChild?.id
        guard let record = localFeatures.expertAppointments.first(where: { $0.expertID == expertID && ($0.childID == childID || $0.childID == nil) }) else { return true }
        guard repository.supportsRemoteAcknowledgement, record.appointmentID != nil else { mutateLocal { $0.expertAppointments.removeAll { $0.id == record.id } }; return true }
        let key = childWorkflowKey("expert-cancel:\(expertID)", childID: childID)
        var ack: ExpertAppointmentAck?
        let succeeded = await executeWorkflow(key) { ack = try await self.repository.cancelExpert(record) }
        if succeeded { updateExpertProjection(record.id, ack: ack, fallbackStatus: .submitted); await loadExperts() }
        return succeeded
    }

    func rescheduleExpertCommand(name: String, preferredDate: String, note: String, expertID: String, serviceID: String?, slotID: String?, scheduledStartAt: String?, scheduledEndAt: String?) async -> Bool {
        guard let slotID, !slotID.isEmpty else { return await submitExpertCommand(name: name, preferredDate: preferredDate, note: note, expertID: expertID, serviceID: serviceID, slotID: slotID, scheduledStartAt: scheduledStartAt, scheduledEndAt: scheduledEndAt) }
        let childID = selectedChild?.id
        guard let existing = localFeatures.expertAppointments.first(where: { $0.expertID == expertID && ($0.childID == childID || $0.childID == nil) }), repository.supportsRemoteAcknowledgement, existing.appointmentID != nil else { return await submitExpertCommand(name: name, preferredDate: preferredDate, note: note, expertID: expertID, serviceID: serviceID, slotID: slotID, scheduledStartAt: scheduledStartAt, scheduledEndAt: scheduledEndAt) }
        bookExpert(name: name, preferredDate: preferredDate, note: note, expertID: expertID, serviceID: serviceID, slotID: slotID, scheduledStartAt: scheduledStartAt, scheduledEndAt: scheduledEndAt)
        guard let local = localFeatures.expertAppointments.first(where: { $0.expertID == expertID && ($0.childID == childID || $0.childID == nil) }) else { return false }
        let transport = ExpertAppointment(id: local.id, expertName: name, preferredDate: preferredDate, note: note, status: local.status, createdAt: local.createdAt, expertID: expertID, appointmentID: existing.appointmentID, serviceID: serviceID?.nilIfBlank, slotID: slotID, childID: local.childID, appointmentStatus: existing.appointmentStatus, expectedVersion: existing.expectedVersion, scheduledStartAt: scheduledStartAt.flatMap(Self.parseISODate), scheduledEndAt: scheduledEndAt.flatMap(Self.parseISODate))
        let key = childWorkflowKey("expert:\(expertID)", childID: childID); var ack: ExpertAppointmentAck?
        let succeeded = await executeWorkflow(key) { ack = try await self.repository.rescheduleExpert(transport, slotID: slotID) }
        if succeeded { updateExpertProjection(local.id, ack: ack, fallbackStatus: .submitted); await loadExperts() }
        else if case .failed = workflowState(for: key) { updateExpertSyncStatus(local.id, to: .failed) }
        return succeeded
    }
}
