import Foundation
struct TaskApi {
    let client: ApiClient
    init(client: ApiClient = .shared) { self.client = client }
    func tasks(schoolID: String, gradeID: String? = nil, classID: String? = nil) async throws -> [TestTask] {
        let query = [
            gradeID.map { URLQueryItem(name: "gradeId", value: $0) },
            classID.map { URLQueryItem(name: "classId", value: $0) }
        ].compactMap { $0 }
        return try await client.request(path: "v1/schools/\(schoolID)/tasks", query: query, type: [TestTask].self)
    }
    func taskStudents(taskID: String, page: Int? = nil, pageSize: Int? = nil, status: TaskStatus? = nil, keyword: String? = nil) async throws -> [TaskStudentStatusRecord] {
        let query = [
            page.map { URLQueryItem(name: "page", value: String($0)) },
            pageSize.map { URLQueryItem(name: "pageSize", value: String($0)) },
            status.map { URLQueryItem(name: "status", value: $0.rawValue) },
            keyword.flatMap { $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : URLQueryItem(name: "keyword", value: $0) }
        ].compactMap { $0 }
        return try await client.request(path: "v1/tasks/\(taskID)/students", query: query, type: [TaskStudentStatusRecord].self)
    }
    func updateStatus(taskID: String, studentID: String, status: TaskStatus, note: String? = nil, expectedVersion: Int? = nil, clientOperationID: String = UUID().uuidString) async throws -> Int? {
        let acknowledgement: TaskStatusWriteAck = try await client.request(
            path: "v1/tasks/\(taskID)/students/\(studentID)/status",
            method: "PATCH",
            body: TaskStatusRequest(status: status, note: note, expectedVersion: expectedVersion, clientOperationID: clientOperationID),
            type: TaskStatusWriteAck.self,
            idempotencyKey: "task-status-\(clientOperationID)"
        )
        return acknowledgement.version
    }
    func batchUpdateStatus(taskID: String, updates: [TaskStatusBatchItem]) async throws -> TaskBatchStatusAck {
        let operationKey = updates.map(\.clientOperationID).sorted().joined(separator: ",")
        return try await client.request(path: "v1/tasks/\(taskID)/students/batch-status", method: "POST", body: TaskBatchStatusRequest(updates: updates), type: TaskBatchStatusAck.self, idempotencyKey: "task-batch-status-\(operationKey)")
    }
    func statusHistory(taskID: String, studentID: String) async throws -> [TaskStatusEvent] {
        try await client.request(path: "v1/tasks/\(taskID)/students/\(studentID)/status-history", type: [TaskStatusEvent].self)
    }
}

struct TaskStatusBatchItem: Encodable {
    let studentID: String; let status: TaskStatus; let note: String?; let reasonCode: String?; let expectedVersion: Int?; let clientOperationID: String
    init(studentID: String, status: TaskStatus, note: String? = nil, reasonCode: String? = nil, expectedVersion: Int? = nil, clientOperationID: String = UUID().uuidString) { self.studentID = studentID; self.status = status; self.note = note; self.reasonCode = reasonCode; self.expectedVersion = expectedVersion; self.clientOperationID = clientOperationID }
    enum CodingKeys: String, CodingKey { case studentID = "studentId", status, note, reasonCode, expectedVersion, clientOperationID = "clientOperationId" }
}
private struct TaskBatchStatusRequest: Encodable { let updates: [TaskStatusBatchItem] }
struct TaskBatchStatusAck: Decodable { let updated: Int?; let items: [TaskStudentStatusRecord]? }
struct TaskStatusEvent: Decodable, Identifiable { let id: String; let taskID: String; let studentID: String; let fromStatus: TaskStatus; let toStatus: TaskStatus; let note: String?; let reasonCode: String?; let operatorTeacherID: String?; let resultingVersion: Int?; let createdAt: String
    enum CodingKeys: String, CodingKey { case id, note, reasonCode, createdAt, fromStatus, toStatus, resultingVersion; case taskID = "taskId"; case studentID = "studentId"; case operatorTeacherID = "operatorTeacherId" }
}

struct TaskStudentStatusRecord: Decodable, Identifiable, Equatable {
    let id: String
    let taskID: String
    let studentID: String
    let status: TaskStatus
    let version: Int
    let studentName: String
    let className: String
    let studentGender: String?
    let gradeID: String?
    let gradeName: String?
    let classID: String?

    init(id: String, taskID: String, studentID: String, status: TaskStatus, version: Int, studentName: String, className: String, studentGender: String? = nil, gradeID: String? = nil, gradeName: String? = nil, classID: String? = nil) {
        self.id = id; self.taskID = taskID; self.studentID = studentID; self.status = status; self.version = version
        self.studentName = studentName; self.className = className; self.studentGender = studentGender
        self.gradeID = gradeID; self.gradeName = gradeName; self.classID = classID
    }

    enum CodingKeys: String, CodingKey {
        case id, status, version, studentName, className, studentGender, gradeName
        case taskID = "taskId"
        case studentID = "studentId"
        case gradeID = "gradeId"
        case classID = "classId"
    }
}

private struct TaskStatusRequest: Encodable {
    let status: TaskStatus
    let note: String?
    let expectedVersion: Int?
    let clientOperationID: String

    init(status: TaskStatus, note: String?, expectedVersion: Int?, clientOperationID: String = UUID().uuidString) {
        self.status = status
        self.note = note
        self.expectedVersion = expectedVersion
        self.clientOperationID = clientOperationID
    }

    enum CodingKeys: String, CodingKey {
        case status, note, expectedVersion
        case clientOperationID = "clientOperationId"
    }
}
private struct TaskStatusWriteAck: Decodable { let version: Int? }

/// Write-side API seam for local-first workflows. The MockRepository uses the
/// default no-op implementations on YouthRepository; RemoteRepository can be
/// enabled later without changing form or navigation code.
struct WorkflowApi {
    let client: ApiClient
    init(client: ApiClient = .shared) { self.client = client }

    func trainingSessions(childID: String, from: String? = nil, to: String? = nil) async throws -> [TrainingSessionRecord] {
        let query = [from.map { URLQueryItem(name: "from", value: $0) }, to.map { URLQueryItem(name: "to", value: $0) }].compactMap { $0 }
        return try await client.request(path: "v1/students/\(childID)/training-sessions", query: query, type: [TrainingSessionRecord].self)
    }

    func submitTrainingSession(_ value: FollowAlongSessionRecord) async throws -> TrainingSessionRecord {
        try await client.request(path: "v1/students/\(value.childID)/training-sessions", method: "POST", body: TrainingSessionRequest(value), type: TrainingSessionRecord.self, idempotencyKey: "training-session-\(value.id.uuidString)")
    }

    func healthCheckins(childID: String, from: String? = nil, to: String? = nil) async throws -> [HealthCheckInRecord] {
        let query = [from.map { URLQueryItem(name: "from", value: $0) }, to.map { URLQueryItem(name: "to", value: $0) }].compactMap { $0 }
        return try await client.request(path: "v1/students/\(childID)/health-checkins", query: query, type: [HealthCheckInRecord].self)
    }

    func submitHealthCheckin(_ value: HealthCheckInRecord, expectedVersion: Int? = nil) async throws -> HealthCheckInRecord {
        try await client.request(path: "v1/students/\(value.childID)/health-checkins", method: "POST", body: HealthCheckInRequest(value, expectedVersion: expectedVersion), type: HealthCheckInRecord.self, idempotencyKey: "health-checkin-\(value.id)-v\(expectedVersion ?? 0)")
    }

    func activities(childID: String? = nil) async throws -> [RemoteActivity] {
        let query = childID.map { [URLQueryItem(name: "childId", value: $0)] } ?? []
        return try await client.request(path: "v1/activities", query: query, type: [RemoteActivity].self)
    }

    func experts() async throws -> [RemoteExpert] {
        try await client.request(path: "v1/experts", type: [RemoteExpert].self)
    }

    func availableSlots(expertID: String) async throws -> [ExpertAvailableSlot] {
        try await client.request(path: "v1/experts/\(expertID)/available-slots", type: [ExpertAvailableSlot].self)
    }

    func activityRegistrationHistory() async throws -> [ActivityRegistrationAck] {
        try await client.request(path: "v1/activities/registrations/history", type: [ActivityRegistrationAck].self)
    }

    func registerActivity(_ value: ActivityRegistration) async throws -> ActivityRegistrationAck {
        try await client.request(path: "v1/activities/\(value.activityID)/registrations", method: "POST", body: ActivityRegistrationRequest(childID: value.childID, contactName: value.contactName, phone: value.phone), type: ActivityRegistrationAck.self, idempotencyKey: "activity-register-\(value.id.uuidString)")
    }

    func updateActivityRegistration(_ value: ActivityRegistration) async throws -> ActivityRegistrationAck {
        guard let registrationID = value.registrationID else { return try await registerActivity(value) }
        return try await client.request(path: "v1/activities/\(value.activityID)/registrations/\(registrationID)", method: "PUT", body: ActivityRegistrationUpdateRequest(childID: value.childID, contactName: value.contactName, phone: value.phone, expectedVersion: value.version), type: ActivityRegistrationAck.self, idempotencyKey: "activity-update-\(registrationID)-v\(value.version ?? 0)-\(value.id.uuidString)")
    }

    func cancelActivityRegistration(_ value: ActivityRegistration) async throws -> ActivityRegistrationAck {
        guard let registrationID = value.registrationID else { throw ApiError.message("缺少报名记录编号，请刷新后重试") }
        return try await client.request(path: "v1/activities/\(value.activityID)/registrations/\(registrationID)/cancel", method: "POST", body: CancellationRequest(expectedVersion: value.version), type: ActivityRegistrationAck.self, idempotencyKey: "activity-cancel-\(registrationID)-v\(value.version ?? 0)")
    }

    func expertAppointmentHistory() async throws -> [ExpertAppointmentAck] {
        try await client.request(path: "v1/expert-appointments/history", type: [ExpertAppointmentAck].self)
    }

    func bookExpert(_ value: ExpertAppointment) async throws -> ExpertAppointmentAck {
        try await client.request(path: "v1/expert-appointments", method: "POST", body: ExpertAppointmentRequest(expertID: value.expertID, serviceID: value.serviceID, slotID: value.slotID, childID: value.childID, expertName: value.expertName, preferredDate: value.preferredDate, note: value.note), type: ExpertAppointmentAck.self, idempotencyKey: "expert-book-\(value.id.uuidString)")
    }

    func rescheduleExpert(_ value: ExpertAppointment, slotID: String) async throws -> ExpertAppointmentAck {
        guard let appointmentID = value.appointmentID else { return try await bookExpert(value) }
        return try await client.request(path: "v1/expert-appointments/\(appointmentID)/reschedule", method: "PUT", body: ExpertRescheduleRequest(slotID: slotID, expectedVersion: value.expectedVersion), type: ExpertAppointmentAck.self, idempotencyKey: "expert-reschedule-\(appointmentID)-\(slotID)-v\(value.expectedVersion ?? 0)")
    }

    func cancelExpert(_ value: ExpertAppointment) async throws -> ExpertAppointmentAck {
        guard let appointmentID = value.appointmentID else { throw ApiError.message("缺少预约记录编号，请刷新后重试") }
        return try await client.request(path: "v1/expert-appointments/\(appointmentID)/cancel", method: "POST", body: CancellationRequest(expectedVersion: value.expectedVersion), type: ExpertAppointmentAck.self, idempotencyKey: "expert-cancel-\(appointmentID)-v\(value.expectedVersion ?? 0)")
    }

    func uploadCourse(_ value: CourseUploadRecord) async throws {
        guard let reference = value.attachmentReference, !reference.isEmpty else {
            throw CourseAttachmentError.unavailable
        }
        let fileID = try await FileApi(client: client).uploadCourseAttachment(localReference: reference, displayName: value.attachmentName)
        try await client.send(path: "v1/courses/uploads", body: CourseUploadRequest(taskID: value.taskID, attendanceCount: value.attendanceCount, notes: value.notes, attachmentName: value.attachmentName, attachmentFileID: fileID))
    }

    func publishClassPost(author: String, content: String, schoolID: String?, classID: String?, attachments: [ClassPostAttachment] = []) async throws -> String? {
        let uploadedAttachments = try await attachments.asyncMap { attachment -> ClassPostAttachmentRequest in
            if let objectID = attachment.objectID, !objectID.isEmpty {
                return ClassPostAttachmentRequest(id: attachment.id, type: attachment.type, objectID: objectID, thumbnailObjectID: attachment.thumbnailObjectID)
            }
            guard let reference = attachment.localReference else { throw CourseAttachmentError.unavailable }
            let fileID = try await FileApi(client: client).uploadClassPostAttachment(localReference: reference, displayName: attachment.id)
            return ClassPostAttachmentRequest(id: attachment.id, type: attachment.type, objectID: fileID, thumbnailObjectID: attachment.thumbnailObjectID)
        }
        let receipt: ClassPostCreateReceipt = try await client.request(path: "v1/class-posts", method: "POST", body: ClassPostRequest(author: author, content: content, schoolID: schoolID, classID: classID, attachments: uploadedAttachments), type: ClassPostCreateReceipt.self)
        return receipt.postID
    }

    func sendSupportMessage(_ content: String) async throws {
        try await client.send(path: "v1/support/messages", body: SupportMessageRequest(content: content))
    }
}

private struct TrainingSessionRequest: Encodable {
    let sessionID: String; let dayID: Int; let completedAt: String; let durationSeconds: Int; let completionRatio: Double; let qualityScore: Int; let cameraVerified: Bool; let visualUnits: [String: Int]; let manualUnits: Int; let modelVersion: String; let mode: String
    init(_ value: FollowAlongSessionRecord) { sessionID = value.id.uuidString; dayID = value.dayID; completedAt = ISO8601DateFormatter().string(from: value.completedAt); durationSeconds = value.durationSeconds; completionRatio = value.completionRatio; qualityScore = value.qualityScore; cameraVerified = value.cameraVerified; visualUnits = value.visualUnits; manualUnits = value.manualUnits; modelVersion = value.modelVersion; mode = value.mode }
    enum CodingKeys: String, CodingKey { case sessionID = "sessionId", dayID = "dayId", completedAt, durationSeconds, completionRatio, qualityScore, cameraVerified, visualUnits, manualUnits, modelVersion, mode }
}

struct TrainingSessionRecord: Decodable, Equatable, Identifiable {
    let id: String; let childID: String; let dayID: Int; let completedAt: String; let durationSeconds: Int; let completionRatio: Double; let qualityScore: Int; let cameraVerified: Bool; let visualUnits: [String: Int]; let manualUnits: Int; let modelVersion: String; let mode: String
    enum CodingKeys: String, CodingKey { case id, completedAt, durationSeconds, completionRatio, qualityScore, cameraVerified, visualUnits, manualUnits, modelVersion, mode; case childID = "childId"; case dayID = "dayId" }
}

struct HealthCheckInRequest: Encodable {
    let checkInDate: String
    let activityType: String
    let durationMinutes: Int
    let intensity: String
    let feeling: String?
    let completedRecommended: Bool
    let parentNote: String?
    let expectedVersion: Int?
    init(_ value: HealthCheckInRecord, expectedVersion: Int?) {
        checkInDate = value.checkInDate; activityType = value.activityType; durationMinutes = value.durationMinutes
        intensity = value.intensity; feeling = value.feeling; completedRecommended = value.completedRecommended
        parentNote = value.parentNote; self.expectedVersion = expectedVersion
    }
}

struct HealthCheckInRecord: Codable, Equatable, Identifiable {
    let id: String
    let childID: String
    let checkInDate: String
    let activityType: String
    let durationMinutes: Int
    let intensity: String
    let feeling: String?
    let completedRecommended: Bool
    let parentNote: String?
    let version: Int
    let createdAt: String?
    let updatedAt: String?
    enum CodingKeys: String, CodingKey { case id, checkInDate, activityType, durationMinutes, intensity, feeling, completedRecommended, parentNote, version, createdAt, updatedAt; case childID = "childId" }
}

/// Read-side class-circle feed. Pagination is cursor based and the server
/// returns a privacy-safe display name plus moderation metadata.
struct ClassPostApi {
    let client: ApiClient
    init(client: ApiClient = .shared) { self.client = client }
    func list(schoolID: String?, classID: String?, cursor: String?, pageSize: Int = 20) async throws -> RemoteClassPostPage {
        let query = [
            schoolID.map { URLQueryItem(name: "schoolId", value: $0) },
            classID.map { URLQueryItem(name: "classId", value: $0) },
            cursor.map { URLQueryItem(name: "cursor", value: $0) },
            URLQueryItem(name: "pageSize", value: String(min(max(pageSize, 1), 50)))
        ].compactMap { $0 }
        return try await client.request(path: "v1/class-posts", query: query, type: RemoteClassPostPage.self)
    }
    func delete(postID: String) async throws {
        _ = try await client.request(path: "v1/class-posts/\(postID)", method: "DELETE", type: RemoteClassPostActionAck.self, idempotencyKey: "class-post-delete-\(postID)")
    }
    func report(postID: String, reason: String) async throws {
        _ = try await client.request(path: "v1/class-posts/\(postID)/report", method: "POST", body: ClassPostReportRequest(reason: reason), type: RemoteClassPostActionAck.self, idempotencyKey: "class-post-report-\(postID)-\(abs(reason.hashValue))")
    }
    func setPinned(postID: String, pinned: Bool) async throws {
        _ = try await client.request(path: "v1/class-posts/\(postID)/pin", method: "POST", body: ClassPostPinRequest(pinned: pinned), type: RemoteClassPostActionAck.self, idempotencyKey: "class-post-pin-\(postID)-\(pinned)")
    }
    func addComment(postID: String, content: String) async throws -> RemoteClassPostCommentAck {
        try await client.request(path: "v1/class-posts/\(postID)/comments", method: "POST", body: ClassPostCommentRequest(content: content), type: RemoteClassPostCommentAck.self, idempotencyKey: "class-post-comment-\(postID)-\(abs(content.hashValue))")
    }
    func comments(postID: String, cursor: String?, pageSize: Int = 20) async throws -> RemoteClassPostCommentPage {
        let query = [
            cursor.map { URLQueryItem(name: "cursor", value: $0) },
            URLQueryItem(name: "pageSize", value: String(min(max(pageSize, 1), 50)))
        ].compactMap { $0 }
        return try await client.request(path: "v1/class-posts/\(postID)/comments", query: query, type: RemoteClassPostCommentPage.self)
    }
    func deleteComment(postID: String, commentID: String) async throws {
        _ = try await client.request(path: "v1/class-posts/\(postID)/comments/\(commentID)", method: "DELETE", type: RemoteClassPostCommentAck.self, idempotencyKey: "class-post-comment-delete-\(postID)-\(commentID)")
    }
}

private struct ClassPostReportRequest: Encodable { let reason: String }
private struct ClassPostPinRequest: Encodable { let pinned: Bool }
private struct ClassPostCommentRequest: Encodable { let content: String }
private struct RemoteClassPostActionAck: Decodable {
    let postID: String?
    let status: String?
    let pinned: Bool?
    enum CodingKeys: String, CodingKey { case status, pinned; case postID = "postId" }
}
struct RemoteClassPostCommentAck: Decodable {
    let commentID: String
    let postID: String
    let displayName: String?
    let content: String?
    let status: String?
    let createdAt: String?
    let ownedByCurrentUser: Bool?
    enum CodingKeys: String, CodingKey { case displayName, content, status, createdAt, ownedByCurrentUser; case commentID = "commentId"; case postID = "postId" }
}

struct RemoteClassPostCommentPage: Decodable {
    let items: [RemoteClassPostCommentAck]
    let nextCursor: String?
}

struct RemoteClassPostPage: Decodable {
    let items: [RemoteClassPost]
    let nextCursor: String?
}

struct RemoteClassPost: Decodable, Identifiable {
    let id: String
    let schoolID: String?
    let classID: String?
    let displayName: String?
    let content: String
    let status: String?
    let visibilityScope: String?
    let moderationStatus: String?
    let pinned: Bool?
    let reportStatus: String?
    let authorRole: String?
    let ownedByCurrentUser: Bool?
    let attachments: [RemoteClassPostAttachment]?
    let createdAt: String?
    enum CodingKeys: String, CodingKey {
        case id = "postId", displayName, content, status, visibilityScope, moderationStatus, pinned, reportStatus, authorRole, ownedByCurrentUser, attachments, createdAt
        case schoolID = "schoolId", classID = "classId"
    }
}

struct RemoteClassPostAttachment: Decodable, Identifiable {
    let id: String
    let type: String
    let objectID: String?
    let thumbnailObjectID: String?
    enum CodingKeys: String, CodingKey { case id, type; case objectID = "objectId"; case thumbnailObjectID = "thumbnailObjectId" }
}

/// Family observation transport kept separate from the school assessment
/// endpoints. The app stores structured answers only; no camera media is sent.
struct HealthObservationApi {
    let client: ApiClient
    init(client: ApiClient = .shared) { self.client = client }

    func list(studentID: String) async throws -> [RemoteHealthObservation] {
        try await client.request(path: "v1/students/\(studentID)/health-observations", type: [RemoteHealthObservation].self)
    }

    func submit(studentID: String, category: String, formVersion: String, answers: [RemoteHealthObservationAnswer], frequency: String?, severity: String?, note: String?, expectedVersion: Int?) async throws -> RemoteHealthObservation {
        try await client.request(
            path: "v1/students/\(studentID)/health-observations",
            method: "POST",
            body: HealthObservationRequest(category: category, formVersion: formVersion, answers: answers, frequency: frequency, severity: severity, note: note, expectedVersion: expectedVersion),
            type: RemoteHealthObservation.self
        )
    }
}

struct RemoteHealthObservation: Decodable, Identifiable, Equatable {
    let id: String
    let childID: String
    let category: String
    let formVersion: String
    let answers: [RemoteHealthObservationAnswer]
    let frequency: String?
    let severity: String?
    let note: String?
    let version: Int?
    let submittedAt: String?
    let updatedAt: String?

    enum CodingKeys: String, CodingKey {
        case id, category, formVersion, answers, frequency, severity, note, version, submittedAt, updatedAt
        case childID = "childId"
    }
}

struct RemoteHealthObservationAnswer: Codable, Equatable {
    let questionID: String
    let questionType: String
    let selectedOptionIDs: [String]
    let note: String?
    let required: Bool

    enum CodingKeys: String, CodingKey {
        case questionType, note, required
        case questionID = "questionId"
        case selectedOptionIDs = "selectedOptionIds"
    }
}

struct RemoteActivity: Decodable, Identifiable, Equatable {
    let activityID: String
    let schoolID: String?
    let title: String
    let description: String?
    let startsAt: String?
    let endsAt: String?
    let capacity: Int?
    let registrationStartAt: String?
    let registrationEndAt: String?
    let status: String
    let version: Int?
    let registeredCount: Int?
    let remainingCapacity: Int?
    let registrationID: String?
    let registrationStatus: String?
    let childID: String?

    var id: String { activityID }

    enum CodingKeys: String, CodingKey {
        case title, description, startsAt, endsAt, capacity, registrationStartAt, registrationEndAt, status, version, registeredCount, remainingCapacity, registrationStatus
        case activityID = "activityId"
        case schoolID = "schoolId"
        case registrationID = "registrationId"
        case childID = "childId"
    }
}

struct RemoteExpert: Decodable, Identifiable, Equatable {
    let expertID: String
    let schoolID: String?
    let name: String
    let title: String?
    let bio: String?
    let status: String?

    var id: String { expertID }

    enum CodingKeys: String, CodingKey {
        case name, title, bio, status
        case expertID = "expertId"
        case schoolID = "schoolId"
    }
}

struct ExpertAvailableSlot: Decodable, Identifiable, Equatable {
    let slotID: String
    let expertID: String
    let serviceID: String?
    let scheduledStartAt: String
    let scheduledEndAt: String
    let capacity: Int?
    let version: Int?
    let remainingCapacity: Int?

    var id: String { slotID }

    enum CodingKeys: String, CodingKey {
        case capacity, version, remainingCapacity, scheduledStartAt, scheduledEndAt
        case slotID = "slotId"
        case expertID = "expertId"
        case serviceID = "serviceId"
    }
}

struct ActivityRegistrationAck: Decodable, Identifiable, Equatable {
    let registrationID: String
    let activityID: String
    let childID: String?
    let contactName: String?
    let phone: String?
    let status: String
    let version: Int?
    let createdAt: String?
    let updatedAt: String?
    let cancelledAt: String?
    let activityTitle: String?
    let startsAt: String?
    let endsAt: String?

    var id: String { registrationID }

    enum CodingKeys: String, CodingKey {
        case registrationID = "registrationId"
        case activityID = "activityId"
        case childID = "childId"
        case contactName, phone, status, version, createdAt, updatedAt, cancelledAt, activityTitle, startsAt, endsAt
    }
}

struct ExpertAppointmentAck: Decodable, Identifiable, Equatable {
    let appointmentID: String
    let expertID: String?
    let serviceID: String?
    let slotID: String?
    let childID: String?
    let expertName: String?
    let preferredDate: String?
    let scheduledStartAt: String?
    let scheduledEndAt: String?
    let status: String
    let version: Int?
    let note: String?
    let createdAt: String?
    let updatedAt: String?
    let cancelledAt: String?

    var id: String { appointmentID }

    enum CodingKeys: String, CodingKey {
        case appointmentID = "appointmentId"
        case expertID = "expertId"
        case serviceID = "serviceId"
        case slotID = "slotId"
        case childID = "childId"
        case expertName, preferredDate, scheduledStartAt, scheduledEndAt, status, version, note, createdAt, updatedAt, cancelledAt
    }
}

private struct ActivityRegistrationRequest: Encodable {
    enum CodingKeys: String, CodingKey { case childID = "childId", contactName, phone }
    let childID: String?
    let contactName: String
    let phone: String
}
private struct ActivityRegistrationUpdateRequest: Encodable {
    enum CodingKeys: String, CodingKey { case childID = "childId", contactName, phone, expectedVersion }
    let childID: String?
    let contactName: String
    let phone: String
    let expectedVersion: Int?
}
private struct ExpertAppointmentRequest: Encodable {
    enum CodingKeys: String, CodingKey { case expertID = "expertId", serviceID = "serviceId", slotID = "slotId", childID = "childId", expertName, preferredDate, note }
    let expertID: String?
    let serviceID: String?
    let slotID: String?
    let childID: String?
    let expertName: String
    let preferredDate: String
    let note: String
}
private struct ExpertRescheduleRequest: Encodable { let slotID: String; let expectedVersion: Int?; enum CodingKeys: String, CodingKey { case slotID = "slotId", expectedVersion } }
private struct CancellationRequest: Encodable { let expectedVersion: Int? }
private struct HealthObservationRequest: Encodable {
    let category: String
    let formVersion: String
    let answers: [RemoteHealthObservationAnswer]
    let frequency: String?
    let severity: String?
    let note: String?
    let expectedVersion: Int?
}
private struct CourseUploadRequest: Encodable { let taskID: String; let attendanceCount: Int; let notes: String; let attachmentName: String; let attachmentFileID: String }
private struct ClassPostRequest: Encodable {
    let author: String; let content: String; let schoolID: String?; let classID: String?; let attachments: [ClassPostAttachmentRequest]
    enum CodingKeys: String, CodingKey { case author, content, schoolID = "schoolId", classID = "classId", attachments }
}
private struct ClassPostCreateReceipt: Decodable {
    let postID: String?
    enum CodingKeys: String, CodingKey { case postID = "postId" }
}
private struct ClassPostAttachmentRequest: Encodable {
    let id: String
    let type: String
    let objectID: String
    let thumbnailObjectID: String?
    enum CodingKeys: String, CodingKey { case id, type; case objectID = "objectId"; case thumbnailObjectID = "thumbnailObjectId" }
}
private struct SupportMessageRequest: Encodable { let content: String }

private extension Array {
    func asyncMap<T>(_ transform: (Element) async throws -> T) async rethrows -> [T] {
        var values: [T] = []
        values.reserveCapacity(count)
        for element in self {
            values.append(try await transform(element))
        }
        return values
    }
}
