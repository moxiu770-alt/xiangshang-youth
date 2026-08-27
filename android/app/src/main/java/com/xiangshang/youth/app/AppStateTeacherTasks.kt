package com.xiangshang.youth.app

import androidx.lifecycle.viewModelScope
import com.xiangshang.youth.core.model.*
import com.xiangshang.youth.core.repository.DashboardData
import com.xiangshang.youth.core.service.*
import kotlinx.coroutines.launch

fun AppViewModel.refreshDashboard(onSuccess: () -> Unit = {}) = viewModelScope.launch {
        // Do not turn an explicit refresh tap into a network request while the
        // device is offline. Cached/Mock data remains usable and the banner
        // explains why the refresh is deferred.
        if (_state.value.profile == null || _state.value.loading || _state.value.isOffline) return@launch
        _state.value = _state.value.copy(loading = true, error = null)
        runCatching { repository.dashboard() }.onSuccess { data ->
            val profile = _state.value.profile ?: return@onSuccess
            val (local, selected) = reconcileChildScope(profile, data, _state.value.local)
            featureStore.save(local)
            _state.value = _state.value.copy(data = data, selectedChild = selected, local = local, loading = false, studentsLoadError = null)
            onSuccess()
        }.onFailure { handleDashboardFailure(it) }
    }
    /** Appends the next bounded remote student-directory page. */
fun AppViewModel.loadMoreStudents() = viewModelScope.launch {
        val current = _state.value.data ?: return@launch
        val total = current.studentTotal ?: return@launch
        val page = current.studentPage ?: return@launch
        val pageSize = current.studentPageSize ?: return@launch
        if (_state.value.studentsLoadingMore || _state.value.loading || _state.value.isOffline || total <= current.students.size) return@launch
        val nextPage = page + 1
        if ((nextPage - 1) * pageSize >= total) return@launch
        _state.value = _state.value.copy(studentsLoadingMore = true, studentsLoadError = null)
        try {
            val next = repository.dashboard(nextPage, pageSize)
            val existing = current.students.map { it.id }.toHashSet()
            val merged = current.students + next.students.filter { existing.add(it.id) }
            _state.value = _state.value.copy(data = next.copy(students = merged, studentTotal = next.studentTotal ?: total, studentPage = next.studentPage ?: nextPage, studentPageSize = next.studentPageSize ?: pageSize), studentsLoadingMore = false)
        } catch (error: Throwable) {
            if (error is ApiError.Unauthorized) handleDashboardFailure(error)
            else _state.value = _state.value.copy(studentsLoadingMore = false, studentsLoadError = error.localizedMessage ?: "学生名单加载失败，请重试")
        }
    }
    /**
     * A dashboard row only contains a student's latest summary.  Task detail
     * must load the selected task's rows, otherwise a student in two tasks can
     * be shown with the wrong status or optimistic-lock version.
     */
fun AppViewModel.loadTaskStudents(taskId: String) = viewModelScope.launch {
        if (taskId.isBlank() || !repository.supportsRemoteAcknowledgement || _state.value.isOffline) return@launch
        runCatching { repository.taskStudentRoster(taskId, page = 1, pageSize = 500, status = null, keyword = null) }.onSuccess { rows ->
            _state.value = _state.value.copy(taskRosterRecords = _state.value.taskRosterRecords + (taskId to rows))
            mutate { local ->
                val statuses = rows.associate { "${it.taskId}|${it.studentId}" to it.status }
                val versions = rows.associate { "${it.taskId}|${it.studentId}" to it.version }
                local.copy(
                    taskScopedStatuses = local.taskScopedStatuses + statuses,
                    taskScopedStatusVersions = local.taskScopedStatusVersions + versions
                )
            }
        }.onFailure { error ->
            if (error is ApiError.Unauthorized) handleDashboardFailure(error)
            else _state.value = _state.value.copy(error = error.localizedMessage ?: "任务学生状态加载失败，请重试")
        }
    }
fun AppViewModel.taskRosterStudents(taskId: String, fallbackTask: TestTask? = null): List<Student> {
        val current = _state.value
        val rows = current.taskRosterRecords[taskId].orEmpty()
        if (rows.isEmpty() && !repository.supportsRemoteAcknowledgement) {
            return fallbackTask?.scopedStudents(current.data?.students.orEmpty()).orEmpty()
        }
        return rows.map { row ->
            current.data?.students?.firstOrNull { it.id == row.studentId } ?: Student(
                id = row.studentId,
                name = row.studentName,
                grade = row.gradeName ?: fallbackTask?.gradeName.orEmpty(),
                className = row.className,
                region = current.data?.school?.region.orEmpty(),
                isPovertyArea = current.data?.school?.isPovertyArea ?: false,
                taskStatus = row.status,
                totalScore = null,
                gender = row.studentGender.orEmpty(),
                taskVersion = row.version,
                classId = row.classId
            )
        }
    }
    /**
     * A task can span an entire school, while a teacher claim normally covers
     * only a subset of its classes.  Keep this check close to every local
     * mutation as well as in the screen filter: hiding a row is not enough if
     * a stale deep link or a crafted UI event can still invoke the command.
     */
internal fun AppViewModel.canManageTaskStudent(student: Student): Boolean {
        return _state.value.isTeacherAuthorizedFor(student)
    }
fun AppViewModel.submitTaskStatusBatch(taskId: String, studentIds: List<String>, status: TaskStatus, note: String? = null) = viewModelScope.launch {
        val ids = studentIds.distinct().filter { it.isNotBlank() }
        val commandKey = "task-batch:$taskId"
        if (taskId.isBlank() || ids.isEmpty() || _state.value.workflowStates[commandKey]?.isSubmitting == true) return@launch
        val roster = taskRosterStudents(taskId, _state.value.data?.tasks?.firstOrNull { it.id == taskId })
        val studentsById = (_state.value.data?.students.orEmpty() + roster).associateBy { it.id }
        if (ids.any { studentId -> studentsById[studentId]?.let { canManageTaskStudent(it) } != true }) {
            setWorkflow(commandKey, WorkflowCommandState(WorkflowCommandStatus.Failed, "只能更新已授权班级内的学生。"))
            return@launch
        }
        setWorkflow(commandKey, WorkflowCommandState(WorkflowCommandStatus.Submitting))
        val updates = ids.map { studentId ->
            com.xiangshang.youth.core.service.TaskStatusBatchItem(studentId, status, note, expectedVersion = _state.value.local.taskScopedStatusVersions["$taskId|$studentId"])
        }
        runCatching { repository.batchUpdateTaskStatus(taskId, updates) }
            .onSuccess { acknowledgement ->
                acknowledgement.items.orEmpty().forEach { row ->
                    mutate { local ->
                        val key = "$taskId|${row.studentId}"
                        local.copy(
                            taskScopedStatuses = local.taskScopedStatuses + (key to row.status),
                            taskScopedStatusVersions = local.taskScopedStatusVersions + (key to row.version),
                            taskScopedSyncStates = local.taskScopedSyncStates + (key to LocalSubmissionStatus.Submitted)
                        )
                    }
                }
                setWorkflow(commandKey, WorkflowCommandState(WorkflowCommandStatus.Succeeded, "已更新 ${acknowledgement.updated ?: acknowledgement.items.orEmpty().size} 名学生"))
            }
            .onFailure { setWorkflow(commandKey, WorkflowCommandState(WorkflowCommandStatus.Failed, it.localizedMessage ?: "批量更新失败，请重试")) }
    }
fun AppViewModel.loadTeacherOverview(classId: String, task: TestTask) = viewModelScope.launch {
        val profile = _state.value.profile ?: return@launch
        if (!repository.supportsRemoteAcknowledgement || profile.schoolId.isNullOrBlank()) return@launch
        val context = TeacherOverviewContext(profile.schoolId, classId, task.id, task.ruleVersion)
        _state.value = _state.value.copy(teacherOverview = null, teacherOverviewContext = context)
        runCatching { repository.teacherOverview(profile.schoolId, classId, task.id, task.ruleVersion) }
            .onSuccess { overview ->
                if (_state.value.teacherOverviewContext == context) {
                    _state.value = _state.value.copy(teacherOverview = overview)
                }
            }
            .onFailure {
                if (_state.value.teacherOverviewContext == context) {
                    _state.value = _state.value.copy(teacherOverview = null, error = it.localizedMessage ?: "班级统计加载失败，请重试")
                }
            }
    }
    /** A mobile role is usable only when it is present in the signed-in
     * account claims. `UserRole.mobileRoles` is a product capability list,
     * never a substitute for a teacher authorization grant. */
