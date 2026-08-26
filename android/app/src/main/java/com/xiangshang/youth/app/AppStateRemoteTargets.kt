package com.xiangshang.youth.app

import android.app.Application
import androidx.lifecycle.viewModelScope
import com.xiangshang.youth.core.service.ApiClient
import com.xiangshang.youth.core.service.ApiError
import com.xiangshang.youth.core.service.ContentManifestApi
import com.xiangshang.youth.core.service.ContentManifestVersionStore
import com.xiangshang.youth.core.service.requireData
import com.xiangshang.youth.core.model.UserRole
import com.xiangshang.youth.core.service.RemoteLesson
import com.xiangshang.youth.core.service.PlaybackSource
import com.xiangshang.youth.core.service.ClassPost
import com.xiangshang.youth.core.service.ClassPostAttachment
import com.xiangshang.youth.core.service.LocalSubmissionStatus
import kotlinx.coroutines.launch

/**
 * Remote-content navigation state is intentionally isolated from login and
 * local feature persistence. These targets are stable business IDs received
 * from reports or messages, never display titles used as identifiers.
 */
fun AppViewModel.openRecommendedCourse(childId: String, courseId: String?, lessonId: String?, title: String) {
    updateRemoteTargetState {
        it.copy(courseRecommendationTarget = CourseRecommendationTarget(childId, courseId, lessonId, title))
    }
}

fun AppViewModel.clearRecommendedCourseTarget() = updateRemoteTargetState { it.copy(courseRecommendationTarget = null) }
fun AppViewModel.openActivityTarget(activityId: String) = updateRemoteTargetState { it.copy(pendingActivityId = activityId) }
fun AppViewModel.clearActivityTarget() = updateRemoteTargetState { it.copy(pendingActivityId = null) }
fun AppViewModel.openExpertAppointmentTarget(appointmentId: String) = updateRemoteTargetState { it.copy(pendingExpertAppointmentId = appointmentId) }
fun AppViewModel.clearExpertAppointmentTarget() = updateRemoteTargetState { it.copy(pendingExpertAppointmentId = null) }

private suspend fun AppViewModel.refreshPublishedContentManifest() {
    if (!repository.supportsRemoteAcknowledgement) return
    val schoolId = _state.value.profile?.schoolId?.takeIf(String::isNotBlank)
    val roleChannel = if (_state.value.role == UserRole.Teacher) "teacher" else "family"
    val store = ContentManifestVersionStore(getApplication<Application>())
    val api = ApiClient.retrofit.create(ContentManifestApi::class.java)
    listOf("mobile", roleChannel).distinct().forEach { channel ->
        val knownVersion = store.version(schoolId, channel)
        val manifest = api.manifest(schoolId, channel, knownVersion).requireData()
        if (manifest.dataAvailable) store.acknowledge(schoolId, channel, manifest.version)
    }
}

/** Activity and appointment catalogues are one remote-content domain. */
fun AppViewModel.loadActivities() {
    _state.value = _state.value.copy(activitiesLoading = true, activitiesError = null)
    viewModelScope.launch {
        runCatching {
            runCatching { refreshPublishedContentManifest() }
            repository.activities(_state.value.selectedChild?.id) to repository.activityRegistrationHistory()
        }
            .onSuccess { (activities, history) ->
                _state.value = _state.value.copy(activitiesLoading = false, remoteActivities = activities, activityRegistrationHistory = history)
            }
            .onFailure { error ->
                if (error is ApiError.Unauthorized) handleDashboardFailure(error)
                else _state.value = _state.value.copy(activitiesLoading = false, activitiesError = error.message ?: "活动加载失败")
            }
    }
}

fun AppViewModel.loadExperts() {
    _state.value = _state.value.copy(expertsLoading = true, expertsError = null)
    viewModelScope.launch {
        runCatching {
            runCatching { refreshPublishedContentManifest() }
            repository.experts() to repository.expertAppointmentHistory()
        }
            .onSuccess { (experts, history) ->
                _state.value = _state.value.copy(expertsLoading = false, remoteExperts = experts, expertAppointmentHistory = history)
            }
            .onFailure { error ->
                if (error is ApiError.Unauthorized) handleDashboardFailure(error)
                else _state.value = _state.value.copy(expertsLoading = false, expertsError = error.message ?: "专家加载失败")
            }
    }
}

fun AppViewModel.loadExpertSlots(expertId: String) {
    if (expertId.isBlank()) return
    _state.value = _state.value.copy(expertSlotErrors = _state.value.expertSlotErrors - expertId)
    viewModelScope.launch {
        runCatching { repository.expertSlots(expertId) }
            .onSuccess { slots -> _state.value = _state.value.copy(expertSlots = _state.value.expertSlots + (expertId to slots)) }
            .onFailure { error ->
                if (error is ApiError.Unauthorized) handleDashboardFailure(error)
                else _state.value = _state.value.copy(expertSlotErrors = _state.value.expertSlotErrors + (expertId to (error.message ?: "时段加载失败")))
            }
    }
}

/** Class-circle data is constrained by the active child or the teacher's class scope. */
fun AppViewModel.loadClassPosts(cursor: String? = null) {
    if (!repository.supportsRemoteAcknowledgement) return
    _state.value = _state.value.copy(classPostsLoading = true, classPostsError = null)
    viewModelScope.launch {
        val teacherMode = _state.value.role == UserRole.Teacher
        val childId = if (teacherMode) null else _state.value.selectedChild?.id
        val classId = if (teacherMode) _state.value.managedTeacherClasses.firstOrNull()?.id else _state.value.selectedChild?.classId
        runCatching { repository.loadClassPosts(_state.value.profile?.schoolId, classId, cursor) }
            .onSuccess { page ->
                val valid = if (teacherMode) classId == null || _state.value.managedTeacherClasses.any { it.id == classId }
                else _state.value.selectedChild?.id == childId && _state.value.selectedChild?.classId == classId
                if (!valid) return@onSuccess
                mutate { local -> local.copy(classPosts = if (cursor == null) page.posts else local.classPosts + page.posts) }
                _state.value = _state.value.copy(classPostsLoading = false, classPostsNextCursor = page.nextCursor)
            }
            .onFailure { error ->
                if (error is ApiError.Unauthorized) handleDashboardFailure(error)
                else _state.value = _state.value.copy(classPostsLoading = false, classPostsError = error.message ?: "班级圈加载失败")
            }
    }
}

fun AppViewModel.loadClassPostAttachment(fileId: String) {
    if (!repository.supportsRemoteAcknowledgement || fileId.isBlank() || _state.value.classPostAttachmentBytes.containsKey(fileId)) return
    _state.value = _state.value.copy(classPostAttachmentErrors = _state.value.classPostAttachmentErrors - fileId)
    viewModelScope.launch {
        runCatching { repository.loadClassPostAttachment(fileId) }
            .onSuccess { bytes -> _state.value = _state.value.copy(classPostAttachmentBytes = _state.value.classPostAttachmentBytes + (fileId to bytes)) }
            .onFailure { error -> _state.value = _state.value.copy(classPostAttachmentErrors = _state.value.classPostAttachmentErrors + (fileId to (error.message ?: "附件暂时无法打开"))) }
    }
}

/** Course catalogue and progress use stable child/course/module/lesson identifiers. */
fun AppViewModel.loadCourses(childId: String) {
    if (!repository.supportsRemoteAcknowledgement) return
    _state.value = _state.value.copy(coursesLoading = true, coursesError = null, remoteCourses = emptyList(), coursesChildId = childId, courseProgressSaveError = null, courseProgressSaveConflict = false)
    viewModelScope.launch {
        runCatching {
            runCatching { refreshPublishedContentManifest() }
            repository.courses(childId)
        }
            .onSuccess { courses -> if (_state.value.coursesChildId == childId) _state.value = _state.value.copy(coursesLoading = false, remoteCourses = courses) }
            .onFailure { error ->
                if (error is ApiError.Unauthorized) handleDashboardFailure(error)
                else if (_state.value.coursesChildId == childId) _state.value = _state.value.copy(coursesLoading = false, coursesError = error.message ?: "课程加载失败")
            }
    }
}

fun AppViewModel.loadLessonPlayback(lessonId: String) {
    if (!repository.supportsRemoteAcknowledgement) return
    _state.value = _state.value.copy(coursePlayback = null, coursePlaybackLessonId = lessonId, coursePlaybackLoading = true, coursePlaybackError = null)
    viewModelScope.launch {
        runCatching { repository.lessonPlayback(lessonId) }
            .onSuccess { playback ->
                if (_state.value.coursePlaybackLessonId == lessonId) {
                    _state.value = _state.value.copy(coursePlayback = playback, coursePlaybackLoading = false)
                }
            }
            .onFailure { error ->
                if (error is ApiError.Unauthorized) handleDashboardFailure(error)
                else if (_state.value.coursePlaybackLessonId == lessonId) {
                    _state.value = _state.value.copy(coursePlaybackLoading = false, coursePlaybackError = error.message ?: "课程视频加载失败")
                }
            }
    }
}

fun AppViewModel.clearLessonPlayback() {
    _state.value = _state.value.copy(coursePlayback = null, coursePlaybackLessonId = null, coursePlaybackLoading = false, coursePlaybackError = null)
}

fun AppViewModel.saveRemoteLessonProgress(childId: String, lesson: RemoteLesson, lastPositionMs: Int, completed: Boolean) = viewModelScope.launch {
    if (!repository.supportsRemoteAcknowledgement) return@launch
    _state.value = _state.value.copy(courseProgressSaveLessonId = lesson.lessonId, courseProgressSaving = true, courseProgressSaveError = null, courseProgressSaveConflict = false)
    runCatching { repository.saveLessonProgress(childId, lesson.lessonId, lastPositionMs, completed, lesson.version) }
        .onSuccess { ack ->
            val key = AppViewModel.courseProgressKey(childId, lesson.courseId, lesson.moduleId ?: "default", lesson.lessonId)
            mutate { it.copy(courseProgress = it.courseProgress + (key to if (ack.completed) 1f else (ack.lastPositionMs.toFloat() / lesson.durationMs.coerceAtLeast(1)).coerceIn(0f, 1f))) }
            _state.value = _state.value.copy(remoteCourses = _state.value.remoteCourses.map { current -> if (current.lessonId == ack.lessonId) current.copy(lastPositionMs = ack.lastPositionMs, completed = ack.completed, version = ack.version) else current }, courseProgressSaving = false, courseProgressSaveError = null, courseProgressSaveConflict = false)
        }
        .onFailure { error ->
            if (error is ApiError.Unauthorized) handleDashboardFailure(error)
            else _state.value = _state.value.copy(
                courseProgressSaving = false,
                courseProgressSaveError = if (error is ApiError.Conflict) "播放进度已在其他设备更新，请刷新课程后重试。" else (error.message ?: "播放进度暂未同步，请重试。"),
                courseProgressSaveConflict = error is ApiError.Conflict
            )
        }
}

/** Class-circle writes are isolated from the notification and support-message domains. */
fun AppViewModel.submitClassPostCommand(author: String, content: String, attachments: List<ClassPostAttachment> = emptyList()) = run {
    var localId: String? = null
    var serverId: String? = null
    executeWorkflow("post:${_state.value.profile?.id ?: "session"}", operation = {
        if (content.trim().isBlank()) throw IllegalArgumentException("动态内容不能为空。")
        localId = publishPost(author, content.trim(), attachments)
        val post = localId?.let { _state.value.local.classPosts.firstOrNull { post -> post.id == it } }
            ?: throw IllegalStateException("动态草稿保存失败，请重试。")
        serverId = repository.publishClassPost(author, content.trim(), _state.value.profile?.schoolId, post.classId, attachments)
    }, onSuccess = { localId?.let { updatePostSyncStatus(it, if (repository.supportsRemoteAcknowledgement) LocalSubmissionStatus.Submitted else LocalSubmissionStatus.PendingSync, serverId) } }, onFailure = { localId?.let { updatePostSyncStatus(it, LocalSubmissionStatus.Failed) } })
}

fun AppViewModel.deleteClassPostCommand(post: ClassPost) {
    val serverId = post.postId
    if (serverId.isNullOrBlank()) { mutate { it.copy(classPosts = it.classPosts.filterNot { current -> current.id == post.id }) }; return }
    executeWorkflow("class-post:delete:$serverId", operation = { repository.deleteClassPost(serverId) }, onSuccess = {
        mutate { local -> local.copy(classPosts = local.classPosts.filterNot { it.id == post.id || it.postId == serverId }) }
    })
}

fun AppViewModel.reportClassPostCommand(post: ClassPost, reason: String = "不适合班级圈展示") {
    val serverId = post.postId ?: return
    val clean = reason.trim(); if (clean.isBlank()) return
    executeWorkflow("class-post:report:$serverId", operation = { repository.reportClassPost(serverId, clean) }, onSuccess = {
        mutate { local -> local.copy(classPosts = local.classPosts.map { if (it.id == post.id || it.postId == serverId) it.copy(reportStatus = "reported") else it }) }
    })
}

fun AppViewModel.setClassPostPinnedCommand(post: ClassPost, pinned: Boolean) {
    val serverId = post.postId ?: return
    executeWorkflow("class-post:pin:$serverId", operation = { repository.setClassPostPinned(serverId, pinned) }, onSuccess = {
        mutate { local -> local.copy(classPosts = local.classPosts.map { if (it.id == post.id || it.postId == serverId) it.copy(pinned = pinned) else it }) }
    })
}

/** Activity and appointment submissions keep their child-scoped idempotency keys. */
fun AppViewModel.submitActivityCommand(contactName: String, phone: String, activityId: String = "health-growth-season-2026") =
    executeWorkflow(childWorkflowKey("activity:$activityId"), operation = {
        if (contactName.isBlank() || phone.filter(Char::isDigit).length != 11) throw IllegalArgumentException("请填写有效的联系人和手机号。")
        registerActivity(contactName.trim(), phone.trim(), activityId)
        val childId = _state.value.selectedChild?.id
        val record = _state.value.local.activityRegistrations.firstOrNull { it.activityId == activityId && (it.childId == childId || it.childId == null) }
            ?: throw IllegalArgumentException("报名信息不完整。")
        val ack = if (record.registrationId == null) repository.submitActivity(record) else repository.updateActivityRegistration(record)
        applyActivityAck(activityId, ack, if (repository.supportsRemoteAcknowledgement) LocalSubmissionStatus.Submitted else LocalSubmissionStatus.PendingSync)
    }, onSuccess = { if (repository.supportsRemoteAcknowledgement) loadActivities() }, onFailure = { markActivitySyncFailed(activityId) })

fun AppViewModel.submitExpertCommand(name: String, date: String, note: String, expertId: String? = null, serviceId: String? = null, slotId: String? = null, scheduledStartAt: String? = null, scheduledEndAt: String? = null) =
    executeWorkflow(childWorkflowKey("expert:${expertId?.takeIf { it.isNotBlank() } ?: "unresolved"}"), operation = {
        val stableId = expertId?.takeIf { it.isNotBlank() } ?: throw IllegalArgumentException("专家信息缺少编号，请刷新专家列表后重试。")
        if (date.isBlank() || note.trim().isBlank()) throw IllegalArgumentException("请填写咨询时间和说明。")
        bookExpert(name, date.trim(), note.trim(), stableId, serviceId, slotId, scheduledStartAt, scheduledEndAt)
        val childId = _state.value.selectedChild?.id
        val record = _state.value.local.expertAppointments.firstOrNull { it.expertId == stableId && (it.childId == childId || it.childId == null) }
            ?: throw IllegalArgumentException("预约信息不完整。")
        val ack = repository.bookExpert(record)
        applyExpertAck(stableId, ack, if (repository.supportsRemoteAcknowledgement) LocalSubmissionStatus.Submitted else LocalSubmissionStatus.PendingSync)
    }, onSuccess = { if (repository.supportsRemoteAcknowledgement) loadExperts() }, onFailure = {
        expertId?.takeIf { it.isNotBlank() }?.let { stableId -> _state.value.local.expertAppointments.firstOrNull { it.expertId == stableId }?.let(::markExpertSyncFailed) }
    })
