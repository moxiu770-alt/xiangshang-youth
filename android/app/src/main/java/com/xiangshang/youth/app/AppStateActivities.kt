package com.xiangshang.youth.app

import com.xiangshang.youth.core.service.ActivityRegistration
import com.xiangshang.youth.core.service.ActivityRegistrationAck
import com.xiangshang.youth.core.service.ExpertAppointment
import com.xiangshang.youth.core.service.ExpertAppointmentAck
import com.xiangshang.youth.core.service.LocalSubmissionStatus
import java.util.UUID

/**
 * Activity registration and expert appointments share a scheduling domain.
 * All local records retain server-issued IDs and versions once available.
 */
fun AppViewModel.registerActivity(contactName: String, phone: String, activityId: String = "health-growth-season-2026") {
    if (contactName.isBlank() || phone.filter(Char::isDigit).length != 11) return
    val childId = _state.value.selectedChild?.id
    mutate { local ->
        val previous = local.activityRegistrations.firstOrNull { it.activityId == activityId && it.childId == childId }
        val record = ActivityRegistration(
            id = previous?.id ?: UUID.randomUUID().toString(), activityId = activityId,
            contactName = contactName.trim(), phone = phone, status = LocalSubmissionStatus.PendingSync,
            registrationId = previous?.registrationId, childId = childId, contactUserId = previous?.contactUserId,
            capacity = previous?.capacity, remainingCapacity = previous?.remainingCapacity,
            registrationStartAt = previous?.registrationStartAt, registrationEndAt = previous?.registrationEndAt,
            registrationStatus = previous?.registrationStatus ?: "pending", version = previous?.version
        )
        local.copy(activityRegistered = true, activityRegistrations = listOf(record) + local.activityRegistrations.filterNot { it.activityId == record.activityId && it.childId == childId })
    }
}

fun AppViewModel.cancelActivityRegistration(activityId: String = "health-growth-season-2026") {
    val childId = _state.value.selectedChild?.id
    mutate { local ->
        val remaining = local.activityRegistrations.filterNot { it.activityId == activityId && (it.childId == childId || it.childId == null) }
        local.copy(activityRegistered = remaining.any { it.registrationStatus != "cancelled" }, activityRegistrations = remaining)
    }
    clearDraft("activity-registration-$activityId")
    clearWorkflowState("activity:$activityId")
}

/** [registrationKey] is a server registration ID in remote mode, or a local draft ID offline. */
fun AppViewModel.cancelActivityRegistrationCommand(registrationKey: String) =
    executeWorkflow(childWorkflowKey("activity-cancel:$registrationKey"), {
        val childId = _state.value.selectedChild?.id
        val record = _state.value.local.activityRegistrations.firstOrNull {
            (it.registrationId == registrationKey || it.id == registrationKey ||
                (!repository.supportsRemoteAcknowledgement && it.activityId == registrationKey)) &&
                (it.childId == childId || it.childId == null)
        } ?: return@executeWorkflow
        if (repository.supportsRemoteAcknowledgement && record.registrationId != null) {
            applyActivityAck(record.activityId, repository.cancelActivityRegistration(record), LocalSubmissionStatus.Submitted)
        } else cancelActivityRegistration(record.activityId)
    }, onSuccess = { if (repository.supportsRemoteAcknowledgement) loadActivities() })

fun AppViewModel.bookExpert(
    name: String, date: String, note: String, expertIdOverride: String? = null, serviceId: String? = null,
    slotId: String? = null, scheduledStartAt: String? = null, scheduledEndAt: String? = null
) {
    if (date.isBlank() || note.isBlank()) return
    val expertId = expertIdOverride?.takeIf { it.isNotBlank() } ?: return
    val childId = _state.value.selectedChild?.id
    mutate { local ->
        val record = ExpertAppointment(expertName = name, preferredDate = date, note = note,
            status = LocalSubmissionStatus.PendingSync, expertId = expertId, serviceId = serviceId?.takeIf { it.isNotBlank() },
            slotId = slotId?.takeIf { it.isNotBlank() }, childId = childId, appointmentStatus = "pending",
            scheduledStartAt = scheduledStartAt, scheduledEndAt = scheduledEndAt)
        local.copy(expertAppointments = listOf(record) + local.expertAppointments.filterNot { it.expertId == expertId && (it.childId == childId || it.childId == null) })
    }
}

fun AppViewModel.cancelExpertCommand(appointmentKey: String) =
    executeWorkflow(childWorkflowKey("expert-cancel:$appointmentKey"), {
        val childId = _state.value.selectedChild?.id
        val record = _state.value.local.expertAppointments.firstOrNull {
            (it.appointmentId == appointmentKey || it.id == appointmentKey ||
                (!repository.supportsRemoteAcknowledgement && it.expertId == appointmentKey)) &&
                (it.childId == childId || it.childId == null)
        } ?: return@executeWorkflow
        if (repository.supportsRemoteAcknowledgement && record.appointmentId != null) {
            applyExpertAck(record.expertId ?: throw IllegalArgumentException("预约记录缺少专家编号，请刷新后重试。"), repository.cancelExpert(record), LocalSubmissionStatus.Submitted)
        } else mutate { local -> local.copy(expertAppointments = local.expertAppointments.filterNot { it.id == record.id }) }
    }, onSuccess = { if (repository.supportsRemoteAcknowledgement) loadExperts() })

fun AppViewModel.rescheduleExpertCommand(
    name: String, date: String, note: String, expertId: String, serviceId: String?, slotId: String?,
    scheduledStartAt: String?, scheduledEndAt: String?
) {
    val childId = _state.value.selectedChild?.id
    executeWorkflow(childWorkflowKey("expert:$expertId", childId), {
        if (slotId.isNullOrBlank()) throw IllegalArgumentException("请选择可预约时段。")
        val existing = _state.value.local.expertAppointments.firstOrNull { it.expertId == expertId && (it.childId == childId || it.childId == null) }
        if (existing?.appointmentId == null || !repository.supportsRemoteAcknowledgement) {
            bookExpert(name, date, note, expertId, serviceId, slotId, scheduledStartAt, scheduledEndAt)
            val record = _state.value.local.expertAppointments.firstOrNull { it.expertId == expertId && (it.childId == childId || it.childId == null) }
                ?: throw IllegalArgumentException("预约信息不完整。")
            applyExpertAck(expertId, repository.bookExpert(record), if (repository.supportsRemoteAcknowledgement) LocalSubmissionStatus.Submitted else LocalSubmissionStatus.PendingSync)
        } else {
            applyExpertAck(expertId, repository.rescheduleExpert(existing.copy(expertName = name, preferredDate = date, note = note, expertId = expertId, serviceId = serviceId, slotId = slotId, scheduledStartAt = scheduledStartAt, scheduledEndAt = scheduledEndAt), slotId), LocalSubmissionStatus.Submitted)
        }
    }, onSuccess = { if (repository.supportsRemoteAcknowledgement) loadExperts() }, onFailure = {
        _state.value.local.expertAppointments.firstOrNull { it.expertId == expertId && (it.childId == childId || it.childId == null) }?.let(::markExpertSyncFailed)
    })
}

internal fun AppViewModel.applyActivityAck(activityId: String, ack: ActivityRegistrationAck, status: LocalSubmissionStatus) {
    mutate { local ->
        val childId = ack.childId ?: _state.value.selectedChild?.id
        val exact = local.activityRegistrations.indexOfFirst { it.activityId == activityId && it.registrationId == ack.registrationId }
        val target = if (exact >= 0) exact else local.activityRegistrations.indexOfFirst { it.activityId == activityId && (it.childId == childId || it.childId == null) }
        val projected = local.activityRegistrations.mapIndexed { index, value ->
            if (index == target) value.copy(status = status, registrationId = ack.registrationId, childId = ack.childId ?: value.childId,
                contactName = ack.contactName ?: value.contactName, phone = ack.phone ?: value.phone,
                registrationStatus = ack.status, version = ack.version) else value
        }
        local.copy(activityRegistered = projected.any { it.registrationStatus != "cancelled" }, activityRegistrations = projected)
    }
    _state.value = _state.value.copy(activityRegistrationHistory = listOf(ack) + _state.value.activityRegistrationHistory.filterNot { it.registrationId == ack.registrationId })
}

internal fun AppViewModel.applyExpertAck(expertId: String, ack: ExpertAppointmentAck, status: LocalSubmissionStatus) {
    mutate { local ->
        val childId = ack.childId ?: _state.value.selectedChild?.id
        val target = local.expertAppointments.indexOfFirst { it.expertId == expertId && (it.childId == childId || it.childId == null) }
        local.copy(expertAppointments = local.expertAppointments.mapIndexed { index, value ->
            if (index == target) value.copy(status = status, appointmentId = ack.appointmentId, expertId = ack.expertId ?: value.expertId,
                serviceId = ack.serviceId ?: value.serviceId, slotId = ack.slotId ?: value.slotId, childId = ack.childId ?: value.childId,
                expertName = ack.expertName ?: value.expertName, preferredDate = ack.preferredDate ?: value.preferredDate,
                note = ack.note ?: value.note, appointmentStatus = ack.status, expectedVersion = ack.version,
                scheduledStartAt = ack.scheduledStartAt ?: value.scheduledStartAt, scheduledEndAt = ack.scheduledEndAt ?: value.scheduledEndAt) else value
        })
    }
    _state.value = _state.value.copy(expertAppointmentHistory = listOf(ack) + _state.value.expertAppointmentHistory.filterNot { it.appointmentId == ack.appointmentId })
}

internal fun AppViewModel.markActivitySyncFailed(activityId: String) = updateActivitySyncStatus(activityId, LocalSubmissionStatus.Failed)
internal fun AppViewModel.markActivitySyncSubmitting(activityId: String) = updateActivitySyncStatus(activityId, LocalSubmissionStatus.Submitting)
internal fun AppViewModel.updateActivitySyncStatus(activityId: String, status: LocalSubmissionStatus) = mutate { local ->
    local.copy(activityRegistrations = local.activityRegistrations.map { if (it.activityId == activityId) it.copy(status = status) else it })
}
internal fun AppViewModel.markExpertSyncFailed(record: ExpertAppointment) = updateExpertSyncStatus(record, LocalSubmissionStatus.Failed)
internal fun AppViewModel.markExpertSyncSubmitting(record: ExpertAppointment) = updateExpertSyncStatus(record, LocalSubmissionStatus.Submitting)
internal fun AppViewModel.updateExpertSyncStatus(record: ExpertAppointment, status: LocalSubmissionStatus) = mutate { local ->
    local.copy(expertAppointments = local.expertAppointments.map { if (it.id == record.id) it.copy(status = status) else it })
}

/** Returns retryable failures while leaving authorization errors for the
 * session coordinator to handle globally. */
internal suspend fun AppViewModel.syncPendingSchedulingRecords(): Int {
    var failed = 0
    _state.value.local.activityRegistrations.filter { it.status == LocalSubmissionStatus.PendingSync || it.status == LocalSubmissionStatus.Failed }.forEach { record ->
        markActivitySyncSubmitting(record.activityId)
        try {
            val ack = if (record.registrationId == null) repository.submitActivity(record) else repository.updateActivityRegistration(record)
            applyActivityAck(record.activityId, ack, LocalSubmissionStatus.Submitted)
        } catch (error: Throwable) {
            if (error is com.xiangshang.youth.core.service.ApiError.Unauthorized) throw error
            markActivitySyncFailed(record.activityId); failed += 1
        }
    }
    _state.value.local.expertAppointments.filter { it.status == LocalSubmissionStatus.PendingSync || it.status == LocalSubmissionStatus.Failed }.forEach { record ->
        markExpertSyncSubmitting(record)
        try {
            val ack = repository.bookExpert(record)
            val expertId = record.expertId ?: throw IllegalStateException("本地预约缺少专家编号，请刷新专家列表后重新预约。")
            applyExpertAck(expertId, ack, LocalSubmissionStatus.Submitted)
        } catch (error: Throwable) {
            if (error is com.xiangshang.youth.core.service.ApiError.Unauthorized) throw error
            markExpertSyncFailed(record); failed += 1
        }
    }
    return failed
}
