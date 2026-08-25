import Foundation
import CryptoKit

/// Backend replacement seam. Network endpoints are intentionally isolated from presentation code.
final class RemoteRepository: YouthRepository {
    let supportsRemoteAcknowledgement = true
    private let client: ApiClient
    private let statsApi: StatsApi
    private let reportApi: ReportApi
    private let workflowApi: WorkflowApi
    private let taskApi: TaskApi
    private let studentApi: StudentApi
    private let messageApi: MessageApi
    private let privacyApi: PrivacyApi
    private let accountDeletionApi: AccountDeletionApi
    private let notificationCampaignApi: NotificationCampaignApi
    private let courseApi: CourseApi
    private let healthObservationApi: HealthObservationApi
    private let classPostApi: ClassPostApi
    private var schoolID: String

    init(client: ApiClient = .shared) {
        self.client = client
        self.statsApi = StatsApi(client: client)
        self.reportApi = ReportApi(client: client)
        self.workflowApi = WorkflowApi(client: client)
        self.taskApi = TaskApi(client: client)
        self.studentApi = StudentApi(client: client)
        self.messageApi = MessageApi(client: client)
        self.privacyApi = PrivacyApi(client: client)
        self.accountDeletionApi = AccountDeletionApi(client: client)
        self.notificationCampaignApi = NotificationCampaignApi(client: client)
        self.courseApi = CourseApi(client: client)
        self.healthObservationApi = HealthObservationApi(client: client)
        self.classPostApi = ClassPostApi(client: client)
        self.schoolID = ProcessInfo.processInfo.environment["XS_SCHOOL_ID"] ?? "school-1"
    }

    func configureSession(_ profile: UserProfile) {
        if let schoolID = profile.schoolID, !schoolID.isEmpty { self.schoolID = schoolID }
    }

    func loadDashboard() async throws -> DashboardData {
        try await loadDashboard(studentPage: 1, studentPageSize: 100)
    }

    func loadDashboard(studentPage: Int? = nil, studentPageSize: Int? = nil) async throws -> DashboardData {
        try await statsApi.dashboard(schoolID: schoolID, studentPage: studentPage ?? 1, studentPageSize: min(max(studentPageSize ?? 100, 1), 100))
    }
    func taskStudentStatuses(taskID: String) async throws -> [TaskStudentStatusRecord] {
        try await taskApi.taskStudents(taskID: taskID)
    }
    func taskStudentRoster(taskID: String, page: Int, pageSize: Int, status: TaskStatus?, keyword: String?) async throws -> [TaskStudentStatusRecord] {
        try await taskApi.taskStudents(taskID: taskID, page: page, pageSize: min(max(pageSize, 1), 200), status: status, keyword: keyword)
    }

    func report(for student: Student) -> DiagnosisReport { DiagnosisReport.unavailable(for: student) }

    func loadReport(for student: Student) async throws -> DiagnosisReport {
        try await reportApi.report(studentID: student.id)
    }

    func bindChild(name: String, code: String) async throws -> ParentChild { try await studentApi.bindChild(name: name, bindingCode: code) }
    func markMessageRead(messageID: String) async throws { try await messageApi.markRead(messageID: messageID) }
    func grantHealthConsent(studentID: String, version: String) async throws { try await studentApi.grantConsent(studentID: studentID, version: version) }
    func grantHealthConsent(_ consent: HealthConsentRecord) async throws { try await studentApi.grantConsent(consent) }
    func revokeHealthConsent(studentID: String, version: String) async throws { try await studentApi.revokeConsent(studentID: studentID, version: version) }
    func submitBodyAssessment(studentID: String, record: BodyAssessmentRecord, consentVersion: String) async throws -> PostureAssessmentReport? {
        let snapshots = (record.postureReport?.snapshots ?? [:]).map { key, snapshot in
            BodySnapshotRequest(captureTask: key.rawValue, sampleCount: snapshot.sampleCount, confidence: snapshot.confidence, metrics: snapshot)
        }
        let key = stableWriteKey("body-assessment", studentID, String(record.measuredAt.timeIntervalSince1970), record.postureReport?.algorithm ?? BodyAssessmentRecord.ruleVersion)
        let response = try await client.request(path: "v1/students/\(studentID)/body-assessments", method: "POST", body: BodyAssessmentRequest(heightCm: record.heightCentimeters, weightKg: record.weightKilograms, overallLevel: record.postureReport?.overallLevel.rawValue ?? "pending", algorithmVersion: record.postureReport?.algorithm ?? BodyAssessmentRecord.ruleVersion, consentVersion: consentVersion, data: record, snapshots: snapshots), type: RemoteBodyAssessmentResult.self, idempotencyKey: key)
        guard response.bmiAlgorithmVersion == BodyAssessmentRecord.bmiAlgorithmVersion else {
            throw RemoteModelContractError.unsupportedBMI(response.bmiAlgorithmVersion ?? "missing")
        }
        guard response.heightAlgorithmVersion == BodyAssessmentRecord.heightAlgorithmVersion else {
            throw RemoteModelContractError.unsupportedHeight(response.heightAlgorithmVersion ?? "missing")
        }
        guard response.modelRegistryVersion == AssessmentScoreRules.modelRegistryVersion else {
            throw RemoteModelContractError.unsupportedRegistry(response.modelRegistryVersion ?? "missing")
        }
        guard let summary = response.postureReport else { return nil }
        guard summary.algorithm == PostureAssessmentReport.algorithmVersion else { throw RemoteModelContractError.unsupportedAlgorithm(summary.algorithm) }
        guard summary.calibrationVersion == PostureAssessmentReport.calibrationVersion else { throw RemoteModelContractError.unsupportedCalibration(summary.calibrationVersion ?? "missing") }
        guard summary.rulesSourceVersion == PostureScreeningRules.rulesSourceVersion else { throw RemoteModelContractError.unsupportedRules(summary.rulesSourceVersion ?? "missing") }
        return PostureAssessmentReport(generatedAt: .now, algorithm: summary.algorithm, snapshots: record.postureReport?.snapshots ?? [:], overallLevel: summary.overallLevel, reasons: summary.reasons, disclaimer: summary.disclaimer, riskScore: summary.riskScore, qualityScore: summary.qualityScore, calibrationVersion: summary.calibrationVersion ?? PostureAssessmentReport.calibrationVersion, rulesSourceVersion: summary.rulesSourceVersion ?? PostureScreeningRules.rulesSourceVersion)
    }

    func loadHealthObservations(studentID: String) async throws -> [FamilyHealthRecord] {
        try await healthObservationApi.list(studentID: studentID).map { Self.localHealthRecord($0) }
    }

    func submitHealthObservation(studentID: String, category: String, record: FamilyHealthRecord) async throws -> FamilyHealthRecord {
        let answers = (record.structuredAnswers ?? []).map {
            RemoteHealthObservationAnswer(questionID: $0.questionID, questionType: $0.questionType, selectedOptionIDs: $0.selectedOptionIDs, note: $0.note, required: $0.required)
        }
        // The local record version represents the version after this edit. The
        // API expects the version that was read before the edit (0 for a new
        // record), so stale edits can be rejected with HTTP 409.
        let expectedVersion = record.version.map { max(0, $0 - 1) }
        let response = try await healthObservationApi.submit(studentID: studentID, category: category, formVersion: record.formVersion ?? "family-observation-v1", answers: answers, frequency: record.frequency, severity: record.severity, note: record.entries["补充说明"], expectedVersion: expectedVersion)
        return Self.localHealthRecord(response)
    }

    private static func localHealthRecord(_ remote: RemoteHealthObservation) -> FamilyHealthRecord {
        let answers = remote.answers.map { HealthObservationAnswer(questionID: $0.questionID, questionType: $0.questionType, selectedOptionIDs: $0.selectedOptionIDs, note: $0.note, required: $0.required) }
        let entries = Dictionary(uniqueKeysWithValues: answers.map { ($0.questionID, $0.selectedOptionIDs.joined(separator: "、")) })
        let formatter = ISO8601DateFormatter()
        let date = formatter.date(from: remote.submittedAt ?? remote.updatedAt ?? "") ?? .now
        return FamilyHealthRecord(childID: remote.childID, category: remote.category, completedAt: date, entries: entries, formVersion: remote.formVersion, submittedAt: formatter.date(from: remote.submittedAt ?? ""), version: remote.version, frequency: remote.frequency, severity: remote.severity, structuredAnswers: answers)
    }

    func submitActivity(_ value: ActivityRegistration) async throws -> ActivityRegistrationAck { try await workflowApi.registerActivity(value) }
    func updateActivityRegistration(_ value: ActivityRegistration) async throws -> ActivityRegistrationAck { try await workflowApi.updateActivityRegistration(value) }
    func cancelActivityRegistration(_ value: ActivityRegistration) async throws -> ActivityRegistrationAck { try await workflowApi.cancelActivityRegistration(value) }
    func loadActivityRegistrationHistory() async throws -> [ActivityRegistrationAck] { try await workflowApi.activityRegistrationHistory() }
    func bookExpert(_ value: ExpertAppointment) async throws -> ExpertAppointmentAck { try await workflowApi.bookExpert(value) }
    func rescheduleExpert(_ value: ExpertAppointment, slotID: String) async throws -> ExpertAppointmentAck { try await workflowApi.rescheduleExpert(value, slotID: slotID) }
    func cancelExpert(_ value: ExpertAppointment) async throws -> ExpertAppointmentAck { try await workflowApi.cancelExpert(value) }
    func loadExpertAppointmentHistory() async throws -> [ExpertAppointmentAck] { try await workflowApi.expertAppointmentHistory() }
    func loadActivities(childID: String? = nil) async throws -> [RemoteActivity] { try await workflowApi.activities(childID: childID) }
    func loadExperts() async throws -> [RemoteExpert] { try await workflowApi.experts() }
    func loadExpertSlots(expertID: String) async throws -> [ExpertAvailableSlot] { try await workflowApi.availableSlots(expertID: expertID) }
    func uploadCourse(_ value: CourseUploadRecord) async throws { try await workflowApi.uploadCourse(value) }
    func loadCourses(childID: String) async throws -> [RemoteLesson] { try await courseApi.courses(childID: childID) }
    func loadLessonPlayback(lessonID: String) async throws -> PlaybackSource { try await courseApi.playback(lessonID: lessonID) }
    func saveLessonProgress(childID: String, lessonID: String, lastPositionMs: Int, completed: Bool, expectedVersion: Int?) async throws -> LessonProgressAck {
        try await courseApi.saveProgress(childID: childID, lessonID: lessonID, lastPositionMs: lastPositionMs, completed: completed, expectedVersion: expectedVersion)
    }
    func loadFollowAlongSessions(childID: String, from: String? = nil, to: String? = nil) async throws -> [TrainingSessionRecord] {
        try await workflowApi.trainingSessions(childID: childID, from: from, to: to)
    }
    func submitFollowAlongSession(_ record: FollowAlongSessionRecord) async throws -> TrainingSessionRecord? {
        try await workflowApi.submitTrainingSession(record)
    }
    func loadHealthCheckins(studentID: String, from: String?, to: String?) async throws -> [HealthCheckInRecord] {
        try await workflowApi.healthCheckins(childID: studentID, from: from, to: to)
    }
    func submitHealthCheckin(_ record: HealthCheckInRecord, expectedVersion: Int?) async throws -> HealthCheckInRecord {
        try await workflowApi.submitHealthCheckin(record, expectedVersion: expectedVersion)
    }
    func listNotificationDrafts(schoolID: String) async throws -> [NotificationCampaign] { try await notificationCampaignApi.drafts(schoolID: schoolID) }
    func loadClassNotice(notificationID: String) async throws -> NotificationCampaignDetail { try await notificationCampaignApi.detail(notificationID: notificationID) }
    func acknowledgeClassNotice(notificationID: String) async throws -> NotificationReceiptAck { try await notificationCampaignApi.acknowledgeReceipt(notificationID: notificationID) }
    func createNotificationDraft(schoolID: String, classIDs: [String], title: String, content: String, recipientScope: String, scheduledAt: String?, parentReceiptEnabled: Bool) async throws -> NotificationCampaign {
        try await notificationCampaignApi.createDraft(schoolID: schoolID, classIDs: classIDs, title: title, content: content, recipientScope: recipientScope, scheduledAt: scheduledAt, parentReceiptEnabled: parentReceiptEnabled, idempotencyKey: stableWriteKey("notification-create", schoolID, classIDs.sorted().joined(separator: ","), title, content, scheduledAt ?? ""))
    }
    func updateNotificationDraft(notificationID: String, schoolID: String, classIDs: [String], title: String, content: String, draftVersion: Int, recipientScope: String, scheduledAt: String?, parentReceiptEnabled: Bool) async throws -> NotificationCampaign {
        try await notificationCampaignApi.updateDraft(notificationID: notificationID, schoolID: schoolID, classIDs: classIDs, title: title, content: content, draftVersion: draftVersion, recipientScope: recipientScope, scheduledAt: scheduledAt, parentReceiptEnabled: parentReceiptEnabled, idempotencyKey: stableWriteKey("notification-update", notificationID, String(draftVersion), title, content))
    }
    func sendNotification(notificationID: String) async throws -> NotificationCampaignReceipt { try await notificationCampaignApi.sendDraft(notificationID: notificationID) }
    func retryNotification(notificationID: String) async throws -> NotificationCampaignReceipt { try await notificationCampaignApi.retry(notificationID: notificationID) }
    func discardNotificationDraft(notificationID: String) async throws { try await notificationCampaignApi.discard(notificationID: notificationID) }
    func sendClassNotice(schoolID: String, classID: String, title: String, content: String) async throws -> NotificationCampaignReceipt { try await notificationCampaignApi.send(schoolID: schoolID, classID: classID, title: title, content: content) }
    func updateTaskStatus(studentID: String, status: TaskStatus, note: String?, expectedVersion: Int?) async throws -> Int? {
        try await workflowApi.updateTaskStatus(studentID: studentID, status: status, note: note, expectedVersion: expectedVersion)
    }
    func updateTaskStatus(taskID: String, studentID: String, status: TaskStatus, note: String?, expectedVersion: Int?) async throws -> Int? {
        let operationID = UUID().uuidString
        return try await taskApi.updateStatus(taskID: taskID, studentID: studentID, status: status, note: note, expectedVersion: expectedVersion, clientOperationID: operationID)
    }
    func batchUpdateTaskStatus(taskID: String, updates: [TaskStatusBatchItem]) async throws -> TaskBatchStatusAck { try await taskApi.batchUpdateStatus(taskID: taskID, updates: updates) }
    func taskStatusHistory(taskID: String, studentID: String) async throws -> [TaskStatusEvent] { try await taskApi.statusHistory(taskID: taskID, studentID: studentID) }
    func publishClassPost(author: String, content: String, schoolID: String?, classID: String?, attachments: [ClassPostAttachment]) async throws -> String? {
        try await workflowApi.publishClassPost(author: author, content: content, schoolID: schoolID, classID: classID, attachments: attachments)
    }
    func loadClassPosts(schoolID: String?, classID: String?, cursor: String?) async throws -> ClassPostPage {
        let page = try await classPostApi.list(schoolID: schoolID, classID: classID, cursor: cursor)
        let formatter = ISO8601DateFormatter()
        let posts = page.items.map { remote in
            ClassPostDraft(
                id: UUID(uuidString: remote.id) ?? UUID(),
                author: remote.displayName ?? "班级成员",
                content: remote.content,
                status: .submitted,
                createdAt: formatter.date(from: remote.createdAt ?? "") ?? .now,
                postID: remote.id,
                classID: remote.classID,
                displayName: remote.displayName,
                visibilityScope: remote.visibilityScope,
                moderationStatus: remote.moderationStatus,
                isPinned: remote.pinned,
                reportStatus: remote.reportStatus,
                attachments: remote.attachments?.map { ClassPostAttachment(id: $0.id, type: $0.type, objectID: $0.objectID, localReference: nil, thumbnailObjectID: $0.thumbnailObjectID) },
                authorRole: remote.authorRole,
                ownedByCurrentUser: remote.ownedByCurrentUser == true
            )
        }
        return ClassPostPage(posts: posts, nextCursor: page.nextCursor)
    }
    func loadClassPostAttachment(fileID: String) async throws -> Data {
        try await FileApi(client: client).downloadClassPostAttachment(fileID: fileID)
    }
    func deleteClassPost(postID: String) async throws { try await classPostApi.delete(postID: postID) }
    func reportClassPost(postID: String, reason: String) async throws { try await classPostApi.report(postID: postID, reason: reason) }
    func setClassPostPinned(postID: String, pinned: Bool) async throws { try await classPostApi.setPinned(postID: postID, pinned: pinned) }
    func addClassPostComment(postID: String, content: String) async throws -> RemoteClassPostCommentAck {
        try await classPostApi.addComment(postID: postID, content: content)
    }
    func loadClassPostComments(postID: String, cursor: String?) async throws -> RemoteClassPostCommentPage {
        try await classPostApi.comments(postID: postID, cursor: cursor)
    }
    func deleteClassPostComment(postID: String, commentID: String) async throws {
        try await classPostApi.deleteComment(postID: postID, commentID: commentID)
    }
    func sendSupportMessage(_ content: String) async throws { try await workflowApi.sendSupportMessage(content) }
    func submitPrivacyRequest(studentID: String, type: PrivacyRequestType) async throws -> PrivacyRequestReceipt {
        try await privacyApi.submit(studentID: studentID, type: type)
    }
    func submitAccountDeletionRequest() async throws -> AccountDeletionReceipt { try await accountDeletionApi.submit() }
}

private enum RemoteModelContractError: LocalizedError {
    case unsupportedAlgorithm(String)
    case unsupportedCalibration(String)
    case unsupportedRules(String)
    case unsupportedBMI(String)
    case unsupportedHeight(String)
    case unsupportedRegistry(String)

    var errorDescription: String? {
        switch self {
        case .unsupportedAlgorithm(let value): return "服务端返回了未支持的姿态算法版本：\(value)"
        case .unsupportedCalibration(let value): return "服务端返回了未支持的标定版本：\(value)"
        case .unsupportedRules(let value): return "服务端返回了未支持的姿态规则版本：\(value)"
        case .unsupportedBMI(let value): return "服务端返回了未支持的 BMI 算法版本：\(value)"
        case .unsupportedHeight(let value): return "服务端返回了未支持的身高算法版本：\(value)"
        case .unsupportedRegistry(let value): return "服务端返回了未支持的模型注册表版本：\(value)"
        }
    }
}

private struct BodySnapshotRequest: Encodable {
    let captureTask: String
    let sampleCount: Int
    let confidence: Double
    let metrics: PostureMetricSnapshot
}

private struct BodyAssessmentRequest: Encodable {
    let heightCm: Double
    let weightKg: Double
    let overallLevel: String
    let algorithmVersion: String
    let consentVersion: String
    let data: BodyAssessmentRecord
    let snapshots: [BodySnapshotRequest]
}

private struct RemoteBodyAssessmentResult: Decodable {
    let postureReport: RemotePostureSummary?
    let bmiAlgorithmVersion: String?
    let heightAlgorithmVersion: String?
    let modelRegistryVersion: String?
}

private struct RemotePostureSummary: Decodable {
    let algorithm: String
    let overallLevel: BodyAssessmentRecord.AttentionLevel
    let reasons: [String]
    let disclaimer: String
    let riskScore: Int
    let qualityScore: Int
    let calibrationVersion: String?
    let rulesSourceVersion: String?
}

/// Produces a retry-stable key for a logical write without storing request
/// bodies or exposing personal data in headers.  The caller includes the
/// server-side version/record identifier whenever the operation is editable.
private func stableWriteKey(_ parts: String...) -> String {
    let value = parts.joined(separator: "\u{1F}")
    let digest = SHA256.hash(data: Data(value.utf8))
    return digest.map { String(format: "%02x", $0) }.joined()
}
