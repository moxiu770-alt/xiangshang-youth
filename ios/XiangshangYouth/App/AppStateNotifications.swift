import SwiftUI

@MainActor extension AppState {
    func submitClassNotice(classID: String, title: String, content: String) async -> Bool {
        let normalizedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedContent = content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let schoolID = profile?.schoolID, !classID.isEmpty, !normalizedTitle.isEmpty, !normalizedContent.isEmpty else {
            workflowStates["notice:\(classID)"] = .failed("请填写标题、正文并选择授权班级。")
            return false
        }
        return await executeWorkflow("notice:\(classID)") { _ = try await self.repository.sendClassNotice(schoolID: schoolID, classID: classID, title: normalizedTitle, content: normalizedContent) }
    }

    func loadNotificationDrafts() async {
        guard let schoolID = profile?.schoolID else { return }
        notificationDraftsLoading = true
        notificationDraftsError = nil
        do {
            notificationDrafts = try await repository.listNotificationDrafts(schoolID: schoolID)
        } catch {
            notificationDraftsError = error.localizedDescription
        }
        notificationDraftsLoading = false
    }

    func saveNotificationDraft(notificationID: String?, classIDs: [String], title: String, content: String, draftVersion: Int?, parentReceiptEnabled: Bool, scheduledAt: String? = nil) async -> NotificationCampaign? {
        let normalizedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedContent = content.trimmingCharacters(in: .whitespacesAndNewlines)
        let targets = Array(Set(classIDs.filter { !$0.isEmpty })).sorted()
        guard let schoolID = profile?.schoolID, !targets.isEmpty, normalizedTitle.count >= 2, normalizedContent.count >= 4 else {
            workflowStates["notice:draft"] = .failed("请填写标题、正文并选择授权班级。")
            return nil
        }
        workflowStates["notice:draft"] = .submitting
        do {
            let draft: NotificationCampaign
            if let notificationID, let draftVersion {
                draft = try await repository.updateNotificationDraft(notificationID: notificationID, schoolID: schoolID, classIDs: targets, title: normalizedTitle, content: normalizedContent, draftVersion: draftVersion, recipientScope: "class", scheduledAt: scheduledAt, parentReceiptEnabled: parentReceiptEnabled)
            } else {
                draft = try await repository.createNotificationDraft(schoolID: schoolID, classIDs: targets, title: normalizedTitle, content: normalizedContent, recipientScope: "class", scheduledAt: scheduledAt, parentReceiptEnabled: parentReceiptEnabled)
            }
            notificationDrafts = [draft] + notificationDrafts.filter { $0.notificationID != draft.notificationID }
            workflowStates["notice:draft"] = .succeeded("通知草稿已保存。")
            return draft
        } catch {
            workflowStates["notice:draft"] = .failed(error.localizedDescription)
            return nil
        }
    }

    func sendNotificationDraft(notificationID: String) async -> Bool {
        let succeeded = await executeWorkflow("notice:send:\(notificationID)") {
            _ = try await self.repository.sendNotification(notificationID: notificationID)
        }
        if succeeded { notificationDrafts.removeAll { $0.notificationID == notificationID } }
        return succeeded
    }

    func discardNotificationDraft(notificationID: String) async -> Bool {
        let succeeded = await executeWorkflow("notice:discard:\(notificationID)") {
            try await self.repository.discardNotificationDraft(notificationID: notificationID)
        }
        if succeeded { notificationDrafts.removeAll { $0.notificationID == notificationID } }
        return succeeded
    }

    func loadClassNoticeDetail(notificationID: String) async -> NotificationCampaignDetail? {
        do {
            return try await repository.loadClassNotice(notificationID: notificationID)
        } catch {
            workflowStates["notice:detail:\(notificationID)"] = .failed(error.localizedDescription)
            return nil
        }
    }

    func acknowledgeClassNotice(notificationID: String) async -> Bool {
        await executeWorkflow("notice:receipt:\(notificationID)") {
            _ = try await self.repository.acknowledgeClassNotice(notificationID: notificationID)
        }
    }
}
