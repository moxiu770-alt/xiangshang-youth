package com.xiangshang.youth.app

import androidx.lifecycle.viewModelScope
import com.xiangshang.youth.core.model.UserRole
import com.xiangshang.youth.core.service.ApiError
import com.xiangshang.youth.core.service.ClassPost
import com.xiangshang.youth.core.service.LocalSubmissionStatus
import com.xiangshang.youth.core.util.BusinessClock
import kotlinx.coroutines.launch

fun AppViewModel.completeAssessment(category: String, entries: Map<String, String> = emptyMap(), structuredAnswers: List<com.xiangshang.youth.core.service.HealthObservationAnswer>? = null) = mutate { local ->
        val childId = _state.value.selectedChild?.id ?: "anonymous"
        val completed = local.completedAssessments + "$childId-$category"
        if (category == "fitness") local.copy(completedAssessments = completed)
        else {
            val previous = local.familyHealthRecords["$childId-$category"]
            val answers = structuredAnswers ?: makeStructuredObservationAnswers(category, entries)
            val record = com.xiangshang.youth.core.service.FamilyHealthRecord(childId, category, BusinessClock.format("yyyy-MM-dd HH:mm"), entries, formVersion = "family-observation-v2", submittedAt = BusinessClock.format("yyyy-MM-dd HH:mm"), version = (previous?.version ?: 0) + 1, frequency = entries["频率"], severity = entries["严重程度"], structuredAnswers = answers)
            local.copy(completedAssessments = completed, familyHealthRecords = local.familyHealthRecords + ("$childId-$category" to record), healthObservationSyncStates = local.healthObservationSyncStates + ("$childId|$category" to if (repository.supportsRemoteAcknowledgement) LocalSubmissionStatus.PendingSync else LocalSubmissionStatus.Submitted))
        }
    }.also {
        if (repository.supportsRemoteAcknowledgement && category != "fitness") {
            val childId = _state.value.selectedChild?.id ?: return@also
            val record = _state.value.local.familyHealthRecords["$childId-$category"] ?: return@also
            executeWorkflow("health-observation:$childId:$category", operation = {
                val canonical = repository.submitHealthObservation(childId, category, record)
                if (_state.value.selectedChild?.id == childId) {
                    mutate { local -> local.copy(completedAssessments = local.completedAssessments + "$childId-$category", familyHealthRecords = local.familyHealthRecords + ("$childId-$category" to canonical), healthObservationSyncStates = local.healthObservationSyncStates + ("$childId|$category" to LocalSubmissionStatus.Submitted)) }
                }
            }, onFailure = { mutate { local -> local.copy(healthObservationSyncStates = local.healthObservationSyncStates + ("$childId|$category" to LocalSubmissionStatus.Failed)) } })
        }
    }

private fun AppViewModel.makeStructuredObservationAnswers(category: String, entries: Map<String, String>): List<com.xiangshang.youth.core.service.HealthObservationAnswer> {
        val questionIds = mapOf(
            "基础信息" to "profile-confirmed",
            "用眼习惯" to "vision-screen-time",
            "视力筛查" to "vision-screening",
            "口腔习惯" to "oral-hygiene",
            "口腔筛查" to "oral-screening",
            "开始说明" to "mental-consent",
            "家庭感受记录" to "mental-observations",
            "家庭观察结果" to "mental-follow-up",
            "频率" to "observation-frequency",
            "严重程度" to "observation-severity",
            "补充说明" to "observation-note"
        )
        return entries.keys.sortedBy { questionIds[it] ?: it }.mapNotNull { key ->
            val raw = entries[key]?.trim().orEmpty()
            if (raw.isBlank()) return@mapNotNull null
            val parts = raw.split("｜", limit = 2)
            val selection = parts.firstOrNull()?.trim().orEmpty()
            val note = parts.getOrNull(1)?.trim()?.takeIf { it.isNotBlank() }
            val type = when (key) {
                "频率" -> "frequency"
                "严重程度" -> "severity"
                "补充说明" -> "text"
                "家庭感受记录" -> "multiple"
                else -> "single"
            }
            val required = type !in setOf("frequency", "severity", "text")
            val selected = if (type == "text") emptyList() else selection.split('、', ',', '，').map { it.trim() }.filter { it.isNotBlank() }
            com.xiangshang.youth.core.service.HealthObservationAnswer(
                questionId = questionIds[key] ?: "$category-$key",
                questionType = type,
                selectedOptionIds = selected,
                note = if (type == "text") selection.ifBlank { note } else note,
                required = required
            )
        }
    }

fun AppViewModel.loadFamilyHealthObservations(studentId: String) = viewModelScope.launch {
        if (!repository.supportsRemoteAcknowledgement) return@launch
        runCatching { repository.loadHealthObservations(studentId) }
            .onSuccess { records ->
                if (_state.value.selectedChild?.id != studentId) return@onSuccess
                mutate { local ->
                    val updatedRecords = local.familyHealthRecords.toMutableMap()
                    val completed = local.completedAssessments.toMutableSet()
                    records.forEach { record ->
                        updatedRecords["$studentId-${record.category}"] = record
                        completed += "$studentId-${record.category}"
                    }
                    local.copy(familyHealthRecords = updatedRecords, completedAssessments = completed)
                }
            }
            .onFailure { error ->
                _state.value = _state.value.copy(workflowStates = _state.value.workflowStates + ("health-observation-load:$studentId" to WorkflowCommandState(WorkflowCommandStatus.Failed, error.localizedMessage ?: "健康记录加载失败")))
            }
    }
fun AppViewModel.loadHealthCheckins(studentId: String) = viewModelScope.launch {
        if (!repository.supportsRemoteAcknowledgement) return@launch
        runCatching { repository.loadHealthCheckins(studentId) }
            .onSuccess { records ->
                if (_state.value.selectedChild?.id != studentId) return@onSuccess
                mutate { local ->
                    val merged = records + local.healthCheckins.filterNot { localRecord -> records.any { it.id == localRecord.id || (it.childId == studentId && it.checkInDate == localRecord.checkInDate) } }
                    local.copy(healthCheckins = merged, checkedInDates = local.checkedInDates + records.map { it.checkInDate }, checkedInToday = records.any { it.checkInDate == BusinessClock.day() })
                }
            }
            .onFailure { error -> if (error is ApiError.Unauthorized) handleDashboardFailure(error) }
    }

fun AppViewModel.publishPost(author: String, content: String, attachments: List<com.xiangshang.youth.core.service.ClassPostAttachment> = emptyList()): String? {
        if (content.isBlank()) return null
        val id = java.util.UUID.randomUUID().toString()
        val classId = _state.value.profile?.authorizedClassIds?.firstOrNull() ?: _state.value.selectedChild?.classId
        mutate { it.copy(classPosts = listOf(ClassPost(id = id, author = author, content = content, status = LocalSubmissionStatus.PendingSync, classId = classId, displayName = privacyDisplayName(author), visibilityScope = "class", moderationStatus = "pending_review", pinned = false, attachments = attachments, authorRole = if (_state.value.role == UserRole.Teacher) "teacher" else "parent")) + it.classPosts) }
        return id
    }
fun AppViewModel.updatePost(id: String, content: String) { if (content.isBlank()) return; mutate { local -> local.copy(classPosts = local.classPosts.map { if (it.id == id) it.copy(content = content, status = LocalSubmissionStatus.PendingSync) else it }) } }
internal fun AppViewModel.updatePostSyncStatus(id: String, status: LocalSubmissionStatus, serverPostId: String? = null) = mutate { local ->
        local.copy(classPosts = local.classPosts.map { post ->
            if (post.id == id) post.copy(status = status, postId = serverPostId ?: post.postId, ownedByCurrentUser = post.ownedByCurrentUser || !serverPostId.isNullOrBlank()) else post
        })
    }
fun AppViewModel.togglePostLike(postId: String) = mutate { local -> local.copy(likedPostIds = if (postId in local.likedPostIds) local.likedPostIds - postId else local.likedPostIds + postId) }
fun AppViewModel.addPostComment(postId: String, content: String) {
        val trimmed = content.trim()
        if (trimmed.isBlank()) return
        val post = _state.value.local.classPosts.firstOrNull { it.id == postId || it.postId == postId }
        val serverPostId = post?.postId
        mutate { local -> local.copy(postComments = local.postComments + (postId to (local.postComments[postId].orEmpty() + trimmed))) }
        if (!repository.supportsRemoteAcknowledgement || serverPostId.isNullOrBlank()) return
        executeWorkflow("class-post:comment:$serverPostId", operation = {
            repository.addClassPostComment(serverPostId, trimmed)
        }, onFailure = {
            mutate { local ->
                val updated = local.postComments[postId].orEmpty().dropLast(1) + "$trimmed（同步失败）"
                local.copy(postComments = local.postComments + (postId to updated))
            }
        })
    }
fun AppViewModel.saveDraft(key: String, content: String) = mutate { it.copy(drafts = it.drafts + (key to content)) }
fun AppViewModel.clearDraft(key: String) = mutate { it.copy(drafts = it.drafts - key) }
private fun AppViewModel.privacyDisplayName(value: String): String {
        val first = value.trim().firstOrNull() ?: return "本班家长"
        return "${first}同学家长"
    }
