package com.xiangshang.youth.app

import com.xiangshang.youth.core.service.CourseUploadRecord
import com.xiangshang.youth.core.service.CourseUploadValidator
import com.xiangshang.youth.core.service.LocalSubmissionStatus

/** Course playback and teacher upload state, keyed by stable lesson IDs. */
fun AppViewModel.courseProgress(childId: String, courseId: String, moduleId: String = "default", lessonId: String, legacyTitle: String? = null): Float {
    val key = AppViewModel.courseProgressKey(childId, courseId, moduleId, lessonId)
    return _state.value.local.courseProgress[key] ?: legacyTitle?.let { _state.value.local.courseProgress[it] } ?: 0f
}

fun AppViewModel.updateCourseProgress(title: String, progress: Float) = mutate {
    it.copy(courseProgress = it.courseProgress + (title to progress.coerceIn(0f, 1f)))
}

fun AppViewModel.updateCourseProgress(childId: String, courseId: String, moduleId: String = "default", lessonId: String, progress: Float) = mutate {
    it.copy(courseProgress = it.courseProgress + (AppViewModel.courseProgressKey(childId, courseId, moduleId, lessonId) to progress.coerceIn(0f, 1f)))
}

fun AppViewModel.saveCourseUpload(taskId: String, attendance: Int, notes: String, attachment: String, attachmentReference: String? = null, submit: Boolean) {
    val cleanNotes = notes.trim(); val cleanAttachment = attachment.trim()
    if (attendance < 0 || (submit && !CourseUploadValidator.isValidForSubmission(attendance, cleanNotes, cleanAttachment, attachmentReference))) return
    mutate { local ->
        val record = CourseUploadRecord(taskId = taskId, attendanceCount = attendance, notes = cleanNotes, attachmentName = cleanAttachment, attachmentReference = attachmentReference, status = if (submit) LocalSubmissionStatus.PendingSync else LocalSubmissionStatus.Draft)
        local.copy(courseUploads = listOf(record) + local.courseUploads.filterNot { it.taskId == taskId }, uploadedTaskIds = if (submit) local.uploadedTaskIds + taskId else local.uploadedTaskIds)
    }
}

/** A remote upload is only marked submitted after the repository acknowledges
 * the write. Mock mode deliberately remains pending so it cannot masquerade
 * as a school-server receipt. */
fun AppViewModel.submitCourseUploadCommand(taskId: String, attendance: Int, notes: String, attachment: String, attachmentReference: String?) =
    executeWorkflow("course:$taskId", {
        if (attendance <= 0 || notes.trim().isBlank() || attachment.trim().isBlank() || attachmentReference.isNullOrBlank()) {
            throw IllegalArgumentException("提交前请补齐出勤人数、课堂记录和可上传的照片附件。")
        }
        saveCourseUpload(taskId, attendance, notes, attachment, attachmentReference, true)
        val record = _state.value.local.courseUploads.firstOrNull { it.taskId == taskId }
            ?: throw IllegalArgumentException("课程记录不完整。")
        repository.uploadCourse(record)
    }, onSuccess = {
        updateCourseSyncStatus(taskId, if (repository.supportsRemoteAcknowledgement) LocalSubmissionStatus.Submitted else LocalSubmissionStatus.PendingSync)
    }, onFailure = { markCourseSyncFailed(taskId) })

internal fun AppViewModel.markCourseSynced(taskId: String) = updateCourseSyncStatus(taskId, LocalSubmissionStatus.Submitted)
internal fun AppViewModel.markCourseSyncSubmitting(taskId: String) = updateCourseSyncStatus(taskId, LocalSubmissionStatus.Submitting)
internal fun AppViewModel.markCourseSyncFailed(taskId: String) = updateCourseSyncStatus(taskId, LocalSubmissionStatus.Failed)
internal fun AppViewModel.updateCourseSyncStatus(taskId: String, status: LocalSubmissionStatus) = mutate { local ->
    local.copy(courseUploads = local.courseUploads.map { if (it.taskId == taskId) it.copy(status = status) else it })
}

internal suspend fun AppViewModel.syncPendingCourseUploads(): Int {
    var failed = 0
    _state.value.local.courseUploads.filter { it.status == LocalSubmissionStatus.PendingSync || it.status == LocalSubmissionStatus.Failed }.forEach { record ->
        markCourseSyncSubmitting(record.taskId)
        try { repository.uploadCourse(record); markCourseSynced(record.taskId) }
        catch (error: Throwable) {
            if (error is com.xiangshang.youth.core.service.ApiError.Unauthorized) throw error
            markCourseSyncFailed(record.taskId); failed += 1
        }
    }
    return failed
}
