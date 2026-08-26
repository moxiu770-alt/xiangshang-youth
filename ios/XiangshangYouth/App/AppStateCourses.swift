import Foundation

/// Course playback and teacher course-upload state. Playback is always keyed
/// by child/course/module/lesson IDs, while the legacy title key is read-only.
@MainActor extension AppState {
    static func courseProgressKey(childID: String, courseID: String, moduleID: String = "default", lessonID: String) -> String { "course|\(childID)|\(courseID)|\(moduleID)|\(lessonID)" }

    func courseProgress(childID: String, courseID: String, moduleID: String = "default", lessonID: String, legacyTitle: String? = nil) -> Double {
        let key = Self.courseProgressKey(childID: childID, courseID: courseID, moduleID: moduleID, lessonID: lessonID)
        return localFeatures.courseProgress[key] ?? legacyTitle.flatMap { localFeatures.courseProgress[$0] } ?? 0
    }
    func updateCourseProgress(_ title: String, progress: Double) { mutateLocal { $0.courseProgress[title] = min(max(progress, 0), 1) } }
    func updateCourseProgress(childID: String, courseID: String, moduleID: String = "default", lessonID: String, progress: Double) {
        let key = Self.courseProgressKey(childID: childID, courseID: courseID, moduleID: moduleID, lessonID: lessonID); mutateLocal { $0.courseProgress[key] = min(max(progress, 0), 1) }
    }

    func saveCourseUpload(taskID: String, attendanceCount: Int, notes: String, attachmentName: String, attachmentReference: String? = nil, submit: Bool) {
        let notes = notes.trimmingCharacters(in: .whitespacesAndNewlines); let attachment = attachmentName.trimmingCharacters(in: .whitespacesAndNewlines)
        let validReference = attachmentReference?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
        guard attendanceCount >= 0, (!submit || (attendanceCount > 0 && !notes.isEmpty && !attachment.isEmpty && validReference)) else { return }
        mutateLocal { values in
            let record = CourseUploadRecord(id: UUID(), taskID: taskID, attendanceCount: attendanceCount, notes: notes, attachmentName: attachment, attachmentReference: attachmentReference, status: submit ? .pendingSync : .draft, createdAt: .now)
            values.courseUploads.removeAll { $0.taskID == taskID }; values.courseUploads.insert(record, at: 0)
            if submit { values.uploadedTaskIDs.insert(taskID) }
        }
    }

    func submitCourseUploadCommand(taskID: String, attendanceCount: Int, notes: String, attachmentName: String, attachmentReference: String? = nil) async -> Bool {
        let key = "course:\(taskID)"
        guard attendanceCount > 0, !notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, !attachmentName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, let attachmentReference, !attachmentReference.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { workflowStates[key] = .failed("提交前请补齐出勤人数、课堂记录和可上传的照片附件。"); return false }
        saveCourseUpload(taskID: taskID, attendanceCount: attendanceCount, notes: notes, attachmentName: attachmentName, attachmentReference: attachmentReference, submit: true)
        guard let record = localFeatures.courseUploads.first(where: { $0.taskID == taskID }) else { workflowStates[key] = .failed("提交前请补齐出勤人数、课堂记录和附件。"); return false }
        let succeeded = await executeWorkflow(key) { try await self.repository.uploadCourse(record) }
        if succeeded { updateCourseSyncStatus(record.id, to: repository.supportsRemoteAcknowledgement ? .submitted : .pendingSync) }
        else if case .failed = workflowState(for: key) { updateCourseSyncStatus(record.id, to: .failed) }
        return succeeded
    }
}
