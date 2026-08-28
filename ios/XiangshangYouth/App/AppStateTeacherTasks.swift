import Foundation

struct TeacherOverviewContext: Equatable {
    let schoolID: String
    let classID: String
    let taskID: String
    let standardVersion: String
}

/// Teacher task operations. Every mutable student row is addressed by the
/// taskId + studentId composite key so separate assessment tasks cannot leak
/// status, optimistic-lock versions or review notes into each other.
@MainActor extension AppState {
    func taskKey(taskID: String?, studentID: String) -> String { "\(taskID?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false ? taskID! : "missing-task")|\(studentID)" }

    func loadTaskStudents(taskID: String) async {
        guard usesRemoteDataSource, !taskID.isEmpty else { return }
        do {
            let records = try await repository.taskStudentRoster(taskID: taskID, page: 1, pageSize: 500, status: nil, keyword: nil)
            taskRosterRecords[taskID] = records
            mutateLocal { values in for record in records { let key = taskKey(taskID: record.taskID, studentID: record.studentID); values.taskScopedStatuses[key] = record.status; values.taskScopedStatusVersions[key] = record.version } }
        } catch { handleDashboardError(error) }
    }

    func taskRosterStudents(taskID: String, fallbackTask: TestTask? = nil) -> [Student] {
        let rows = taskRosterRecords[taskID] ?? []
        if rows.isEmpty && !usesRemoteDataSource {
            return fallbackTask?.scopedStudents(from: data?.students ?? []) ?? []
        }
        return rows.map { row in
            data?.students.first(where: { $0.id == row.studentID }) ?? Student(id: row.studentID, name: row.studentName, gender: row.studentGender ?? "", grade: row.gradeName ?? fallbackTask?.gradeName ?? "", className: row.className, region: data?.school.region ?? "", isPovertyArea: data?.school.isPovertyArea ?? false, taskStatus: row.status, totalScore: nil, taskVersion: row.version, classID: row.classID)
        }
    }

    /// A school-wide task roster is not itself an authorization grant.  This
    /// predicate is used by both the detail screen and mutation commands so a
    /// crafted navigation event cannot update a student outside this teacher's
    /// stable class scope.
    func canManageTaskStudent(_ student: Student) -> Bool {
        guard selectedRole == .teacher || profile?.role == .teacher,
              let classID = student.classID else { return false }
        return managedTeacherClasses.contains(where: { $0.id == classID })
    }

    func submitTaskStatusBatch(taskID: String, studentIDs: [String], status: TaskStatus, note: String? = nil) async {
        let ids = Array(Set(studentIDs)).filter { !$0.isEmpty }; let key = "task-batch-\(taskID)"
        guard !taskID.isEmpty, !ids.isEmpty, !workflowState(for: key).isSubmitting else { return }
        let roster = taskRosterStudents(taskID: taskID, fallbackTask: data?.tasks.first(where: { $0.id == taskID }))
        let studentsByID = Dictionary(uniqueKeysWithValues: ((data?.students ?? []) + roster).map { ($0.id, $0) })
        guard ids.allSatisfy({ studentsByID[$0].map(canManageTaskStudent) == true }) else {
            workflowStates[key] = .failed("只能更新已授权班级内的学生。")
            return
        }
        workflowStates[key] = .submitting
        let updates = ids.map { TaskStatusBatchItem(studentID: $0, status: status, note: note, expectedVersion: localFeatures.taskScopedStatusVersions[taskKey(taskID: taskID, studentID: $0)]) }
        do {
            let acknowledgement = try await repository.batchUpdateTaskStatus(taskID: taskID, updates: updates)
            mutateLocal { values in for item in acknowledgement.items ?? [] { let itemKey = taskKey(taskID: taskID, studentID: item.studentID); values.taskScopedStatuses[itemKey] = item.status; values.taskScopedStatusVersions[itemKey] = item.version; values.taskScopedSyncStates[itemKey] = .submitted } }
            workflowStates[key] = .succeeded("已更新 \(acknowledgement.updated ?? acknowledgement.items?.count ?? 0) 名学生")
        } catch { workflowStates[key] = .failed(error.localizedDescription) }
    }

    func loadTeacherOverview(classID: String, task: TestTask) async {
        guard usesRemoteDataSource, let schoolID = profile?.schoolID else { return }
        let context = TeacherOverviewContext(schoolID: schoolID, classID: classID, taskID: task.id, standardVersion: task.ruleVersion)
        teacherOverviewContext = context
        teacherOverview = nil
        do {
            let overview = try await StatsApi().teacherOverview(schoolID: schoolID, classID: classID, taskID: task.id, standardVersion: task.ruleVersion)
            guard teacherOverviewContext == context else { return }
            teacherOverview = overview
        } catch {
            guard teacherOverviewContext == context else { return }
            teacherOverview = nil
            self.error = error.localizedDescription
        }
    }

    func submitTaskStatusCommand(taskID: String? = nil, studentID: String, status: TaskStatus, note: String?) async -> Bool {
        guard !studentID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { workflowStates["task-status:\(studentID)"] = .failed("学生信息缺失，无法提交状态。"); return false }
        // A task-row status never has a meaningful server identity without the
        // task ID.  Legacy local reads may still render a student's last known
        // status, but a write must never manufacture a missing task identity.
        guard let resolvedTaskID = taskID?.trimmingCharacters(in: .whitespacesAndNewlines), !resolvedTaskID.isEmpty else {
            workflowStates["task-status:\(studentID)"] = .failed("任务信息缺失，请返回任务列表后重试。")
            return false
        }
        guard let student = data?.students.first(where: { $0.id == studentID }) else { workflowStates["task-status:\(studentID)"] = .failed("未找到学生档案，请刷新名单后重试。"); return false }
        guard canManageTaskStudent(student) else { workflowStates["task-status:\(studentID)"] = .failed("无权修改该学生的测评状态。"); return false }
        let key = taskKey(taskID: taskID, studentID: studentID)
        let current = taskStatus(for: student, taskID: taskID)
        let version = localFeatures.taskScopedStatusVersions[key] ?? student.taskVersion
        guard current.allowsTransition(to: status) else { workflowStates["task-status:\(studentID)"] = .failed("当前为\(current.rawValue)，不能直接变更为\(status.rawValue)。请按现场队列流程操作。"); return false }
        mutateLocal { values in
            values.taskScopedStatuses[key] = status; values.taskScopedSyncStates[key] = .pendingSync
            if let note = note?.trimmingCharacters(in: .whitespacesAndNewlines), !note.isEmpty { values.taskScopedReviewNotes[key] = note }
        }
        var acknowledged: Int?; let workflowKey = "task-status:\(key)"
        let succeeded = await executeWorkflow(workflowKey) { acknowledged = try await self.repository.updateTaskStatus(taskID: resolvedTaskID, studentID: studentID, status: status, note: note, expectedVersion: version) }
        if succeeded { acknowledgeTaskStatusVersion(studentID, taskID: taskID, serverVersion: acknowledged); updateTaskStatusSyncState(studentID, taskID: taskID, to: repository.supportsRemoteAcknowledgement ? .submitted : .pendingSync) }
        else if case .failed = workflowState(for: workflowKey) { updateTaskStatusSyncState(studentID, taskID: taskID, to: .failed) }
        return succeeded
    }

    func taskStatus(for student: Student, taskID: String? = nil) -> TaskStatus {
        let key = taskKey(taskID: taskID, studentID: student.id)
        return localFeatures.taskScopedStatuses[key] ?? student.taskStatus
    }

    func taskStatusSyncState(for student: Student, taskID: String? = nil) -> LocalSubmissionStatus? {
        let key = taskKey(taskID: taskID, studentID: student.id)
        return localFeatures.taskScopedSyncStates[key]
    }

    func updateTaskStatus(for student: Student, status: TaskStatus, reviewNote: String? = nil, taskID: String? = nil) {
        guard taskStatus(for: student, taskID: taskID).allowsTransition(to: status) else { return }
        let note = reviewNote?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        mutateLocal { values in let key = taskKey(taskID: taskID, studentID: student.id); values.taskScopedStatuses[key] = status; if !note.isEmpty { values.taskScopedReviewNotes[key] = note } }
    }

    func loadBodyScreeningReviews() async {
        guard teacherHasCapability("REVIEW_RESULT"), let schoolID = profile?.schoolID, !bodyScreeningReviewsLoading else {
            if !teacherHasCapability("REVIEW_RESULT") { bodyScreeningReviewsError = "当前账号没有身体观察复核权限。" }
            return
        }
        bodyScreeningReviewsLoading = true
        bodyScreeningReviewsError = nil
        defer { bodyScreeningReviewsLoading = false }
        do { bodyScreeningReviews = try await repository.loadBodyScreeningReviews(schoolID: schoolID, limit: 50) }
        catch {
            if case ApiError.unauthorized = error { handleDashboardError(error) }
            else { bodyScreeningReviewsError = error.localizedDescription }
        }
    }

    func submitBodyScreeningReview(_ item: BodyScreeningReviewItem, decision: BodyScreeningReviewDecision, comment: String?, recaptureTasks: Set<BodyAssessmentRecord.CaptureTask>) async -> Bool {
        let key = "body-screening-review:\(item.reviewId)"
        guard teacherHasCapability("REVIEW_RESULT"), !workflowState(for: key).isSubmitting else { return false }
        let trimmed = comment?.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !(trimmed ?? "").isEmpty else { workflowStates[key] = .failed("请填写复核依据和后续处理说明。"); return false }
        guard decision != .recapture || !recaptureTasks.isEmpty else { workflowStates[key] = .failed("要求重采时至少选择一个动作。"); return false }
        workflowStates[key] = .submitting
        do {
            let ack = try await repository.decideBodyScreeningReview(reviewID: item.reviewId, decision: decision, expectedVersion: item.version, comment: trimmed, requestedRecaptureTasks: Array(recaptureTasks))
            if ack.status == "completed" { bodyScreeningReviews.removeAll { $0.reviewId == item.reviewId } }
            else { await loadBodyScreeningReviews() }
            workflowStates[key] = .succeeded(decision == .recapture ? "重采任务已发送" : "复核结论已保存")
            return true
        } catch {
            workflowStates[key] = .failed(error.localizedDescription)
            if error.localizedDescription.localizedCaseInsensitiveContains("version") || error.localizedDescription.contains("更新") { await loadBodyScreeningReviews() }
            return false
        }
    }
}
