import Foundation

/// Class-circle draft, moderation and comment lifecycle.
@MainActor extension AppState {
    @discardableResult func publishClassPost(_ text: String, author: String, attachments: [ClassPostAttachment] = []) -> ClassPostDraft {
        let text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return ClassPostDraft(id: UUID(), author: author, content: text, status: .failed, createdAt: .now, authorRole: selectedRole == .teacher ? "teacher" : "parent") }
        let post = ClassPostDraft(id: UUID(), author: author, content: text, status: .pendingSync, createdAt: .now, classID: profile?.authorizedClassIDs.first ?? selectedChild?.classID, displayName: privacyDisplayName(author), visibilityScope: "class", moderationStatus: "pending_review", isPinned: false, reportStatus: nil, attachments: attachments, authorRole: selectedRole == .teacher ? "teacher" : "parent")
        mutateLocal { $0.classPosts.insert(post, at: 0) }; return post
    }
    func updateClassPost(id: UUID, text: String) { guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }; mutateLocal { if let index = $0.classPosts.firstIndex(where: { $0.id == id }) { $0.classPosts[index].content = text; $0.classPosts[index].status = .pendingSync } } }
    func submitClassPostCommand(_ content: String, author: String, attachments: [ClassPostAttachment] = []) async -> Bool {
        let key = "post:\(profile?.id ?? "session")"; guard !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { workflowStates[key] = .failed("动态内容不能为空。"); return false }
        let post = publishClassPost(content, author: author, attachments: attachments); var serverID: String?
        let succeeded = await executeWorkflow(key) { serverID = try await self.repository.publishClassPost(author: author, content: content, schoolID: self.profile?.schoolID, classID: post.classID, attachments: attachments) }
        if succeeded { updateClassPostSyncStatus(post.id, to: repository.supportsRemoteAcknowledgement ? .submitted : .pendingSync, serverPostID: serverID) } else if case .failed = workflowState(for: key) { updateClassPostSyncStatus(post.id, to: .failed) }; return succeeded
    }
    func deleteClassPostCommand(_ post: ClassPostDraft) async -> Bool { guard let postID = post.postID else { mutateLocal { $0.classPosts.removeAll { $0.id == post.id } }; return true }; let ok = await executeWorkflow("class-post:delete:\(postID)") { try await self.repository.deleteClassPost(postID: postID) }; if ok { mutateLocal { $0.classPosts.removeAll { $0.id == post.id || $0.postID == postID } } }; return ok }
    func reportClassPostCommand(_ post: ClassPostDraft, reason: String = "不适合班级圈展示") async -> Bool { let reason = reason.trimmingCharacters(in: .whitespacesAndNewlines); guard let postID = post.postID, !reason.isEmpty else { return false }; let ok = await executeWorkflow("class-post:report:\(postID)") { try await self.repository.reportClassPost(postID: postID, reason: reason) }; if ok { mutateLocal { if let index = $0.classPosts.firstIndex(where: { $0.postID == postID || $0.id == post.id }) { $0.classPosts[index].reportStatus = "reported" } } }; return ok }
    func setClassPostPinnedCommand(_ post: ClassPostDraft, pinned: Bool) async -> Bool { guard let postID = post.postID else { return false }; let ok = await executeWorkflow("class-post:pin:\(postID)") { try await self.repository.setClassPostPinned(postID: postID, pinned: pinned) }; if ok { mutateLocal { if let index = $0.classPosts.firstIndex(where: { $0.postID == postID || $0.id == post.id }) { $0.classPosts[index].isPinned = pinned } } }; return ok }
    func toggleClassPostLike(_ id: UUID) { mutateLocal { if $0.likedClassPostIDs.contains(id) { $0.likedClassPostIDs.remove(id) } else { $0.likedClassPostIDs.insert(id) } } }
    func addClassPostComment(postID: UUID, text: String, author: String? = nil) {
        let text = text.trimmingCharacters(in: .whitespacesAndNewlines); guard !text.isEmpty else { return }; let author = author?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfBlank ?? activeDisplayName; let serverID = localFeatures.classPosts.first { $0.id == postID || $0.postID == postID.uuidString }?.postID; let id = UUID(); mutateLocal { $0.classPostComments.append(ClassPostComment(id: id, postID: postID, author: author, text: text, createdAt: .now)) }
        guard repository.supportsRemoteAcknowledgement, let serverID, !serverID.isEmpty else { return }; Task { let ok = await executeWorkflow("class-post:comment:\(serverID)") { _ = try await self.repository.addClassPostComment(postID: serverID, content: text) }; if !ok { mutateLocal { if let index = $0.classPostComments.firstIndex(where: { $0.id == id }) { $0.classPostComments[index] = ClassPostComment(id: id, postID: postID, author: author, text: "\(text)（同步失败）", createdAt: .now) } } } }
    }
    func updateClassPostSyncStatus(_ id: UUID, to status: LocalSubmissionStatus, serverPostID: String? = nil) { mutateLocal { if let index = $0.classPosts.firstIndex(where: { $0.id == id }) { $0.classPosts[index].status = status; if let serverPostID, !serverPostID.isEmpty { $0.classPosts[index].postID = serverPostID; $0.classPosts[index].ownedByCurrentUser = true } } } }
    private func privacyDisplayName(_ value: String) -> String { guard let first = value.trimmingCharacters(in: .whitespacesAndNewlines).first else { return "本班家长" }; return "\(first)同学家长" }
}
