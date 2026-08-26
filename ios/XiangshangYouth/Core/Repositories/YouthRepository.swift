import Foundation

protocol YouthRepository {
    /// `false` for bundled Mock data. A local write must never be presented as
    /// school-side confirmation until a real service has acknowledged it.
    var supportsRemoteAcknowledgement: Bool { get }
    func loadDashboard() async throws -> DashboardData
    func loadDashboard(studentPage: Int?, studentPageSize: Int?) async throws -> DashboardData
    func taskStudentStatuses(taskID: String) async throws -> [TaskStudentStatusRecord]
    func taskStudentRoster(taskID: String, page: Int, pageSize: Int, status: TaskStatus?, keyword: String?) async throws -> [TaskStudentStatusRecord]
    func configureSession(_ profile: UserProfile)
    func bindChild(name: String, code: String) async throws -> ParentChild
    func markMessageRead(messageID: String) async throws
    func grantHealthConsent(studentID: String, version: String) async throws
    /// A persisted consent ID is the idempotency identity for guardian approval.
    func grantHealthConsent(_ consent: HealthConsentRecord) async throws
    func revokeHealthConsent(studentID: String, version: String) async throws
    func submitBodyAssessment(studentID: String, record: BodyAssessmentRecord, consentVersion: String) async throws -> PostureAssessmentReport?
    func loadHealthObservations(studentID: String) async throws -> [FamilyHealthRecord]
    func submitHealthObservation(studentID: String, category: String, record: FamilyHealthRecord) async throws -> FamilyHealthRecord
    func loadHealthCheckins(studentID: String, from: String?, to: String?) async throws -> [HealthCheckInRecord]
    func submitHealthCheckin(_ record: HealthCheckInRecord, expectedVersion: Int?) async throws -> HealthCheckInRecord
    func report(for student: Student) -> DiagnosisReport
    /// Async report seam used by the detail route. Mock repositories inherit a
    /// deterministic local report; RemoteRepository waits for ReportApi and
    /// never presents bundled scores as a remote result.
    func loadReport(for student: Student) async throws -> DiagnosisReport
    func submitActivity(_ value: ActivityRegistration) async throws -> ActivityRegistrationAck
    func updateActivityRegistration(_ value: ActivityRegistration) async throws -> ActivityRegistrationAck
    func cancelActivityRegistration(_ value: ActivityRegistration) async throws -> ActivityRegistrationAck
    func loadActivityRegistrationHistory() async throws -> [ActivityRegistrationAck]
    func bookExpert(_ value: ExpertAppointment) async throws -> ExpertAppointmentAck
    func rescheduleExpert(_ value: ExpertAppointment, slotID: String) async throws -> ExpertAppointmentAck
    func cancelExpert(_ value: ExpertAppointment) async throws -> ExpertAppointmentAck
    func loadExpertAppointmentHistory() async throws -> [ExpertAppointmentAck]
    func loadActivities(childID: String?) async throws -> [RemoteActivity]
    func loadExperts() async throws -> [RemoteExpert]
    func loadExpertSlots(expertID: String) async throws -> [ExpertAvailableSlot]
    func uploadCourse(_ value: CourseUploadRecord) async throws
    /// Course delivery is keyed by the child and lesson IDs, never by a
    /// display title. Remote repositories return only service-provided data;
    /// an empty collection is a valid "no assigned course" result.
    func loadCourses(childID: String) async throws -> [RemoteLesson]
    func loadLessonPlayback(lessonID: String) async throws -> PlaybackSource
    func saveLessonProgress(childID: String, lessonID: String, lastPositionMs: Int, completed: Bool, expectedVersion: Int?) async throws -> LessonProgressAck
    func loadFollowAlongSessions(childID: String, from: String?, to: String?) async throws -> [TrainingSessionRecord]
    func submitFollowAlongSession(_ record: FollowAlongSessionRecord) async throws -> TrainingSessionRecord?
    /// Returns the server's incremented task-row version when the write was
    /// acknowledged remotely. Task status always uses taskId + studentId.
    func updateTaskStatus(taskID: String, studentID: String, status: TaskStatus, note: String?, expectedVersion: Int?) async throws -> Int?
    func batchUpdateTaskStatus(taskID: String, updates: [TaskStatusBatchItem]) async throws -> TaskBatchStatusAck
    func taskStatusHistory(taskID: String, studentID: String) async throws -> [TaskStatusEvent]
    func publishClassPost(author: String, content: String, schoolID: String?, classID: String?, attachments: [ClassPostAttachment]) async throws -> String?
    func loadClassPosts(schoolID: String?, classID: String?, cursor: String?) async throws -> ClassPostPage
    func loadClassPostAttachment(fileID: String) async throws -> Data
    func deleteClassPost(postID: String) async throws
    func reportClassPost(postID: String, reason: String) async throws
    func setClassPostPinned(postID: String, pinned: Bool) async throws
    func addClassPostComment(postID: String, content: String) async throws -> RemoteClassPostCommentAck
    func loadClassPostComments(postID: String, cursor: String?) async throws -> RemoteClassPostCommentPage
    func deleteClassPostComment(postID: String, commentID: String) async throws
    func listNotificationDrafts(schoolID: String) async throws -> [NotificationCampaign]
    func loadClassNotice(notificationID: String) async throws -> NotificationCampaignDetail
    func acknowledgeClassNotice(notificationID: String) async throws -> NotificationReceiptAck
    func createNotificationDraft(schoolID: String, classIDs: [String], title: String, content: String, recipientScope: String, scheduledAt: String?, parentReceiptEnabled: Bool) async throws -> NotificationCampaign
    func updateNotificationDraft(notificationID: String, schoolID: String, classIDs: [String], title: String, content: String, draftVersion: Int, recipientScope: String, scheduledAt: String?, parentReceiptEnabled: Bool) async throws -> NotificationCampaign
    func sendNotification(notificationID: String) async throws -> NotificationCampaignReceipt
    func retryNotification(notificationID: String) async throws -> NotificationCampaignReceipt
    func discardNotificationDraft(notificationID: String) async throws
    func sendClassNotice(schoolID: String, classID: String, title: String, content: String) async throws -> NotificationCampaignReceipt
    func sendSupportMessage(_ content: String) async throws
    func submitPrivacyRequest(studentID: String, type: PrivacyRequestType) async throws -> PrivacyRequestReceipt
    func submitAccountDeletionRequest() async throws -> AccountDeletionReceipt
}

struct ClassPostPage {
    let posts: [ClassPostDraft]
    let nextCursor: String?
}

extension YouthRepository {
    /// Defaults are Mock-only. A RemoteRepository must override every service
    /// seam it advertises, otherwise callers receive a configuration failure
    /// instead of an apparently valid empty response.
    private func requireMockDefault() throws {
        guard !supportsRemoteAcknowledgement else { throw ApiError.notConfigured }
    }
    func loadDashboard(studentPage: Int?, studentPageSize: Int?) async throws -> DashboardData { try requireMockDefault(); return try await loadDashboard() }
    func taskStudentStatuses(taskID: String) async throws -> [TaskStudentStatusRecord] { try requireMockDefault(); return [] }
    func taskStudentRoster(taskID: String, page: Int, pageSize: Int, status: TaskStatus?, keyword: String?) async throws -> [TaskStudentStatusRecord] { try await taskStudentStatuses(taskID: taskID) }
    func configureSession(_ profile: UserProfile) {}
    func bindChild(name: String, code: String) async throws -> ParentChild { throw ApiError.notConfigured }
    func markMessageRead(messageID: String) async throws { try requireMockDefault() }
    func grantHealthConsent(studentID: String, version: String) async throws { try requireMockDefault() }
    func grantHealthConsent(_ consent: HealthConsentRecord) async throws { try await grantHealthConsent(studentID: consent.childID, version: consent.privacyPolicyVersion) }
    func revokeHealthConsent(studentID: String, version: String) async throws { try requireMockDefault() }
    func submitBodyAssessment(studentID: String, record: BodyAssessmentRecord, consentVersion: String) async throws -> PostureAssessmentReport? { try requireMockDefault(); return nil }
    func loadHealthObservations(studentID: String) async throws -> [FamilyHealthRecord] { try requireMockDefault(); return [] }
    func loadFollowAlongSessions(childID: String, from: String?, to: String?) async throws -> [TrainingSessionRecord] { try requireMockDefault(); return [] }
    func submitFollowAlongSession(_ record: FollowAlongSessionRecord) async throws -> TrainingSessionRecord? { try requireMockDefault(); return nil }
    func submitHealthObservation(studentID: String, category: String, record: FamilyHealthRecord) async throws -> FamilyHealthRecord { try requireMockDefault(); return record }
    func loadHealthCheckins(studentID: String, from: String? = nil, to: String? = nil) async throws -> [HealthCheckInRecord] { try requireMockDefault(); return [] }
    func submitHealthCheckin(_ record: HealthCheckInRecord, expectedVersion: Int? = nil) async throws -> HealthCheckInRecord { try requireMockDefault(); return record }
    func loadClassPosts(schoolID: String?, classID: String?, cursor: String?) async throws -> ClassPostPage { try requireMockDefault(); return ClassPostPage(posts: [], nextCursor: nil) }
    func loadClassPostAttachment(fileID: String) async throws -> Data { throw ApiError.notConfigured }
    var supportsRemoteAcknowledgement: Bool { false }

    func loadReport(for student: Student) async throws -> DiagnosisReport { try requireMockDefault(); return report(for: student) }

    func submitActivity(_ value: ActivityRegistration) async throws -> ActivityRegistrationAck {
        try requireMockDefault()
        return ActivityRegistrationAck(registrationID: value.registrationID ?? value.id.uuidString, activityID: value.activityID, childID: value.childID, contactName: value.contactName, phone: value.phone, status: value.registrationStatus ?? "pending", version: value.version ?? 1, createdAt: nil, updatedAt: nil, cancelledAt: nil, activityTitle: nil, startsAt: nil, endsAt: nil)
    }
    func updateActivityRegistration(_ value: ActivityRegistration) async throws -> ActivityRegistrationAck { try await submitActivity(value) }
    func cancelActivityRegistration(_ value: ActivityRegistration) async throws -> ActivityRegistrationAck {
        try requireMockDefault()
        return ActivityRegistrationAck(registrationID: value.registrationID ?? value.id.uuidString, activityID: value.activityID, childID: value.childID, contactName: value.contactName, phone: value.phone, status: "cancelled", version: (value.version ?? 0) + 1, createdAt: nil, updatedAt: nil, cancelledAt: nil, activityTitle: nil, startsAt: nil, endsAt: nil)
    }
    func loadActivityRegistrationHistory() async throws -> [ActivityRegistrationAck] { try requireMockDefault(); return [] }
    func bookExpert(_ value: ExpertAppointment) async throws -> ExpertAppointmentAck {
        try requireMockDefault()
        return ExpertAppointmentAck(appointmentID: value.appointmentID ?? value.id.uuidString, expertID: value.expertID, serviceID: value.serviceID, slotID: value.slotID, childID: value.childID, expertName: value.expertName, preferredDate: value.preferredDate, scheduledStartAt: value.scheduledStartAt.map { ISO8601DateFormatter().string(from: $0) }, scheduledEndAt: value.scheduledEndAt.map { ISO8601DateFormatter().string(from: $0) }, status: value.appointmentStatus ?? "pending", version: value.expectedVersion ?? 1, note: value.note, createdAt: nil, updatedAt: nil, cancelledAt: nil)
    }
    func rescheduleExpert(_ value: ExpertAppointment, slotID: String) async throws -> ExpertAppointmentAck { try await bookExpert(value) }
    func cancelExpert(_ value: ExpertAppointment) async throws -> ExpertAppointmentAck {
        try requireMockDefault()
        return ExpertAppointmentAck(appointmentID: value.appointmentID ?? value.id.uuidString, expertID: value.expertID, serviceID: value.serviceID, slotID: value.slotID, childID: value.childID, expertName: value.expertName, preferredDate: value.preferredDate, scheduledStartAt: value.scheduledStartAt.map { ISO8601DateFormatter().string(from: $0) }, scheduledEndAt: value.scheduledEndAt.map { ISO8601DateFormatter().string(from: $0) }, status: "cancelled", version: (value.expectedVersion ?? 0) + 1, note: value.note, createdAt: nil, updatedAt: nil, cancelledAt: nil)
    }
    func loadExpertAppointmentHistory() async throws -> [ExpertAppointmentAck] { try requireMockDefault(); return [] }
    func loadActivities(childID: String? = nil) async throws -> [RemoteActivity] {
        try requireMockDefault()
        return [RemoteActivity(activityID: "health-growth-season-2026", schoolID: nil, title: "向上少年健康成长季", description: "综合测评 · 运动表现更出彩", startsAt: nil, endsAt: nil, capacity: 60, registrationStartAt: nil, registrationEndAt: "2026-09-10", status: "open", version: 1, registeredCount: 42, remainingCapacity: 18, registrationID: nil, registrationStatus: nil, childID: nil)]
    }
    func loadExperts() async throws -> [RemoteExpert] {
        try requireMockDefault()
        return [
            RemoteExpert(expertID: "expert-zhang-child-sports", schoolID: nil, name: "张教授", title: "儿童运动发展", bio: "儿童运动发展与家庭训练建议", status: "active"),
            RemoteExpert(expertID: "expert-li-growth-screening", schoolID: nil, name: "李医生", title: "儿童健康评估", bio: "成长筛查与家庭观察建议", status: "active"),
            RemoteExpert(expertID: "expert-wang-youth-training", schoolID: nil, name: "王教练", title: "青少年运动训练", bio: "动作训练和运动习惯建立", status: "active"),
            RemoteExpert(expertID: "expert-liu-family-support", schoolID: nil, name: "刘主任", title: "儿童心理成长", bio: "家庭支持与心理观察", status: "active")
        ]
    }
    func loadExpertSlots(expertID: String) async throws -> [ExpertAvailableSlot] { try requireMockDefault(); return [] }
    func uploadCourse(_ value: CourseUploadRecord) async throws { try requireMockDefault() }
    func loadCourses(childID: String) async throws -> [RemoteLesson] { try requireMockDefault(); return [] }
    func loadLessonPlayback(lessonID: String) async throws -> PlaybackSource { throw ApiError.notConfigured }
    func saveLessonProgress(childID: String, lessonID: String, lastPositionMs: Int, completed: Bool, expectedVersion: Int?) async throws -> LessonProgressAck {
        try requireMockDefault()
        return LessonProgressAck(lessonID: lessonID, lastPositionMs: lastPositionMs, completed: completed, version: 0)
    }
    func updateTaskStatus(taskID: String, studentID: String, status: TaskStatus, note: String?, expectedVersion: Int?) async throws -> Int? {
        guard !taskID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, taskID != "unscoped" else { throw ApiError.message("任务编号缺失，无法更新学生测评状态") }
        try requireMockDefault()
        return nil
    }
    func batchUpdateTaskStatus(taskID: String, updates: [TaskStatusBatchItem]) async throws -> TaskBatchStatusAck { try requireMockDefault(); return TaskBatchStatusAck(updated: 0, items: []) }
    func taskStatusHistory(taskID: String, studentID: String) async throws -> [TaskStatusEvent] { try requireMockDefault(); return [] }
    func publishClassPost(author: String, content: String, schoolID: String? = nil, classID: String? = nil, attachments: [ClassPostAttachment] = []) async throws -> String? { try requireMockDefault(); return nil }
    func deleteClassPost(postID: String) async throws { try requireMockDefault() }
    func reportClassPost(postID: String, reason: String) async throws { try requireMockDefault() }
    func setClassPostPinned(postID: String, pinned: Bool) async throws { try requireMockDefault() }
    func addClassPostComment(postID: String, content: String) async throws -> RemoteClassPostCommentAck {
        try requireMockDefault()
        return RemoteClassPostCommentAck(commentID: UUID().uuidString, postID: postID, displayName: nil, content: content, status: "pending_sync", createdAt: nil, ownedByCurrentUser: true)
    }
    func loadClassPostComments(postID: String, cursor: String?) async throws -> RemoteClassPostCommentPage { try requireMockDefault(); return RemoteClassPostCommentPage(items: [], nextCursor: nil) }
    func deleteClassPostComment(postID: String, commentID: String) async throws { try requireMockDefault() }
    func listNotificationDrafts(schoolID: String) async throws -> [NotificationCampaign] { try requireMockDefault(); return [] }
    func loadClassNotice(notificationID: String) async throws -> NotificationCampaignDetail {
        try requireMockDefault()
        return NotificationCampaignDetail(notificationID: notificationID, schoolID: "", senderTeacherID: nil, title: "班级通知", content: "通知内容将在学校数据同步后显示。", targetClassIDs: [], recipientScope: "class", status: "sent", draftVersion: 1, scheduledAt: nil, sentAt: nil, failureReason: nil, parentReceiptEnabled: false, userReceiptStatus: nil, acknowledgedAt: nil, receiptStats: nil)
    }
    func acknowledgeClassNotice(notificationID: String) async throws -> NotificationReceiptAck {
        try requireMockDefault()
        return NotificationReceiptAck(id: nil, notificationID: notificationID, receiverUserID: nil, status: "pending_sync", acknowledgedAt: nil, version: nil)
    }
    func createNotificationDraft(schoolID: String, classIDs: [String], title: String, content: String, recipientScope: String, scheduledAt: String?, parentReceiptEnabled: Bool) async throws -> NotificationCampaign {
        try requireMockDefault()
        return NotificationCampaign(notificationID: UUID().uuidString, schoolID: schoolID, senderTeacherID: nil, title: title, content: content, targetClassIDs: classIDs, recipientScope: recipientScope, scheduledAt: scheduledAt, status: "draft", draftVersion: 1, sentAt: nil, failureReason: nil, idempotencyKey: nil, parentReceiptEnabled: parentReceiptEnabled)
    }
    func updateNotificationDraft(notificationID: String, schoolID: String, classIDs: [String], title: String, content: String, draftVersion: Int, recipientScope: String, scheduledAt: String?, parentReceiptEnabled: Bool) async throws -> NotificationCampaign {
        try requireMockDefault()
        return NotificationCampaign(notificationID: notificationID, schoolID: schoolID, senderTeacherID: nil, title: title, content: content, targetClassIDs: classIDs, recipientScope: recipientScope, scheduledAt: scheduledAt, status: "draft", draftVersion: draftVersion + 1, sentAt: nil, failureReason: nil, idempotencyKey: nil, parentReceiptEnabled: parentReceiptEnabled)
    }
    func sendNotification(notificationID: String) async throws -> NotificationCampaignReceipt { try requireMockDefault(); return NotificationCampaignReceipt(id: notificationID, title: "", status: "pending_sync", sentCount: 0) }
    func retryNotification(notificationID: String) async throws -> NotificationCampaignReceipt { try await sendNotification(notificationID: notificationID) }
    func discardNotificationDraft(notificationID: String) async throws { try requireMockDefault() }
    func sendClassNotice(schoolID: String, classID: String, title: String, content: String) async throws -> NotificationCampaignReceipt { try requireMockDefault(); return NotificationCampaignReceipt(id: UUID().uuidString, title: title, status: "pending_sync", sentCount: 0) }
    func sendSupportMessage(_ content: String) async throws { try requireMockDefault() }
    func submitPrivacyRequest(studentID: String, type: PrivacyRequestType) async throws -> PrivacyRequestReceipt {
        try requireMockDefault()
        return PrivacyRequestReceipt(id: UUID().uuidString, requestType: type, status: "pending_sync", createdAt: ISO8601DateFormatter().string(from: .now), jobID: nil)
    }
    func submitAccountDeletionRequest() async throws -> AccountDeletionReceipt {
        try requireMockDefault()
        return AccountDeletionReceipt(id: UUID().uuidString, status: "pending_sync", createdAt: ISO8601DateFormatter().string(from: .now), completedAt: nil)
    }
}
