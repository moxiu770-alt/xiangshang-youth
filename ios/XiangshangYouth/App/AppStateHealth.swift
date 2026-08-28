import Foundation

/// Child-scoped health records, body-assessment drafts and follow-along
/// receipts. Records are keyed by stable child IDs and never shared on switch.
@MainActor extension AppState {
    /// These writes belong to the child-health domain. The backend is still
    /// authoritative, but the local guard avoids a stale child selection
    /// creating a privacy request after switching accounts.
    func submitPrivacyRequest(studentID: String, type: PrivacyRequestType) async -> Bool {
        let key = "privacy:\(studentID):\(type.rawValue)"
        guard data?.students.contains(where: { $0.id == studentID }) == true else {
            workflowStates[key] = .failed("未找到孩子信息，请重新选择后再试。")
            return false
        }
        let succeeded = await executeWorkflow(key) {
            _ = try await self.repository.submitPrivacyRequest(studentID: studentID, type: type)
        }
        if succeeded {
            workflowStates[key] = .succeeded(repository.supportsRemoteAcknowledgement
                ? (type == .export ? "导出申请已提交，文件生成后会在消息中心通知。" : "删除申请已提交，需经学校/平台审核；审核前不会删除任何记录。")
                : "申请已保存到本机记录。接入学校服务后可提交审核。")
        }
        return succeeded
    }

    func revokeHealthConsent(studentID: String, version: String? = nil) async -> Bool {
        let key = "privacy:\(studentID):consent-revoke"
        guard data?.students.contains(where: { $0.id == studentID }) == true else {
            workflowStates[key] = .failed("未找到孩子信息，请重新选择后再试。")
            return false
        }
        guard let resolvedVersion = version?.nilIfBlank ?? localFeatures.healthConsents[studentID]?.privacyPolicyVersion.nilIfBlank else {
            workflowStates[key] = .failed("未找到有效的监护人授权版本，请重新完成授权。")
            return false
        }
        let succeeded = await executeWorkflow(key) {
            try await self.repository.revokeHealthConsent(studentID: studentID, version: resolvedVersion)
        }
        if succeeded {
            mutateLocal { values in
                guard var consent = values.healthConsents[studentID] else { return }
                consent.revokedAt = .now
                values.healthConsents[studentID] = consent
            }
            workflowStates[key] = .succeeded(repository.supportsRemoteAcknowledgement
                ? "已撤回身体测评数据使用同意；新的身体测评需重新授权。"
                : "撤回记录已保存在本机，接入学校服务后提交。")
        }
        return succeeded
    }

    func submitAccountDeletionRequest() async -> Bool {
        let key = "privacy:account-deletion"
        let succeeded = await executeWorkflow(key) {
            _ = try await self.repository.submitAccountDeletionRequest()
        }
        if succeeded {
            workflowStates[key] = .succeeded(repository.supportsRemoteAcknowledgement
                ? "注销申请已提交，平台审核通过后会撤销会话并匿名化账户。"
                : "注销申请已保存到本机记录，接入学校服务后提交审核。")
        }
        return succeeded
    }

    func loadFamilyHealthObservations(for student: Student) async {
        guard repository.supportsRemoteAcknowledgement else { return }
        do {
            let records = try await repository.loadHealthObservations(studentID: student.id)
            guard selectedChild?.id == student.id else { return }
            mutateLocal { values in for record in records { values.familyHealthRecords["\(student.id)-\(record.category)"] = record; values.completedAssessments.insert("\(student.id)-\(record.category)") } }
        } catch { workflowStates["health-observation-load:\(student.id)"] = .failed(error.localizedDescription) }
    }

    func loadHealthCheckins(for student: Student) async {
        guard repository.supportsRemoteAcknowledgement else { return }
        do {
            let records = try await repository.loadHealthCheckins(studentID: student.id, from: nil, to: nil)
            guard selectedChild?.id == student.id else { return }
            mutateLocal { values in let dates = Set(records.map(\.checkInDate)); values.healthCheckins = records + values.healthCheckins.filter { $0.childID != student.id || !dates.contains($0.checkInDate) }; values.checkInDates.formUnion(dates) }
        } catch { workflowStates["health-checkin-load:\(student.id)"] = .failed(error.localizedDescription) }
    }

    func completeAssessment(_ category: AssessmentCategory, entries: [String: String] = [:], structuredAnswers suppliedAnswers: [HealthObservationAnswer]? = nil) {
        let childID = selectedChild?.id ?? "anonymous"
        var recordToSync: FamilyHealthRecord?
        mutateLocal { values in
            values.completedAssessments.insert("\(childID)-\(category.rawValue)")
            guard category != .fitness else { return }
            let answers = suppliedAnswers ?? Self.makeStructuredObservationAnswers(category: category, entries: entries)
            let record = FamilyHealthRecord(childID: childID, category: category.rawValue, completedAt: .now, entries: entries, formVersion: "family-observation-v2", submittedAt: .now, version: (values.familyHealthRecords["\(childID)-\(category.rawValue)"]?.version ?? 0) + 1, frequency: entries["频率"], severity: entries["严重程度"], structuredAnswers: answers)
            values.familyHealthRecords["\(childID)-\(category.rawValue)"] = record
            values.healthObservationSyncStates["\(childID):\(category.rawValue)"] = repository.supportsRemoteAcknowledgement ? .pendingSync : .submitted
            recordToSync = record
        }
        guard repository.supportsRemoteAcknowledgement, let recordToSync else { return }
        let key = "health-observation:\(childID):\(category.rawValue)"
        Task { @MainActor in
            _ = await executeWorkflow(key) {
                let canonical = try await self.repository.submitHealthObservation(studentID: childID, category: category.rawValue, record: recordToSync)
                guard self.selectedChild?.id == childID else { return }
                self.mutateLocal { values in
                    values.familyHealthRecords["\(childID)-\(category.rawValue)"] = canonical
                    values.completedAssessments.insert("\(childID)-\(category.rawValue)")
                    values.healthObservationSyncStates["\(childID):\(category.rawValue)"] = .submitted
                }
            }
            if case .failed = workflowState(for: key) { mutateLocal { $0.healthObservationSyncStates["\(childID):\(category.rawValue)"] = .failed } }
        }
    }

    /// Converts legacy display-value drafts into stable question identifiers
    /// before a health-observation write reaches the service.
    private static func makeStructuredObservationAnswers(category: AssessmentCategory, entries: [String: String]) -> [HealthObservationAnswer] {
        let questionIDs: [String: String] = [
            "基础信息": "profile-confirmed", "用眼习惯": "vision-screen-time", "视力筛查": "vision-screening",
            "口腔习惯": "oral-hygiene", "口腔筛查": "oral-screening", "开始说明": "mental-consent",
            "家庭感受记录": "mental-observations", "家庭观察结果": "mental-follow-up",
            "频率": "observation-frequency", "严重程度": "observation-severity", "补充说明": "observation-note"
        ]
        return entries.keys.sorted { (questionIDs[$0] ?? $0) < (questionIDs[$1] ?? $1) }.compactMap { key in
            let raw = entries[key]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            guard !raw.isEmpty else { return nil }
            let parts = raw.split(separator: "｜", maxSplits: 1, omittingEmptySubsequences: false).map(String.init)
            let selection = parts.first?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let note = parts.count > 1 ? parts[1].trimmingCharacters(in: .whitespacesAndNewlines).nilIfBlank : nil
            let type: String; let required: Bool
            switch key {
            case "频率": type = "frequency"; required = false
            case "严重程度": type = "severity"; required = false
            case "补充说明": type = "text"; required = false
            case "家庭感受记录": type = "multiple"; required = true
            default: type = "single"; required = true
            }
            let selected = type == "text" ? [] : selection.split(whereSeparator: { $0 == "、" || $0 == "," || $0 == "，" }).map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
            return HealthObservationAnswer(questionID: questionIDs[key] ?? "\(category.rawValue)-\(key)", questionType: type, selectedOptionIDs: selected, note: type == "text" ? (selection.nilIfBlank ?? note) : note, required: required)
        }
    }

    func familyHealthRecord(for student: Student, category: AssessmentCategory) -> FamilyHealthRecord? { localFeatures.familyHealthRecords["\(student.id)-\(category.rawValue)"] }
    func bodyAssessment(for student: Student) -> BodyAssessmentRecord? { localFeatures.bodyAssessments[student.id] }
    func bodyAssessmentHistory(for student: Student) -> [BodyAssessmentRecord] { localFeatures.bodyAssessmentHistory[student.id] ?? [] }
    func bodyAssessmentDraft(for student: Student) -> BodyAssessmentDraft? { localFeatures.bodyAssessmentDrafts[student.id] }
    func saveBodyAssessmentDraft(_ draft: BodyAssessmentDraft, for student: Student) { mutateLocal { $0.bodyAssessmentDrafts[student.id] = draft } }
    func clearBodyAssessmentDraft(for student: Student) { mutateLocal { $0.bodyAssessmentDrafts.removeValue(forKey: student.id) } }

    func saveBodyAssessment(_ record: BodyAssessmentRecord, for student: Student) {
        mutateLocal { values in
            values.bodyAssessments[student.id] = record
            values.bodyAssessmentHistory[student.id] = Array((values.bodyAssessmentHistory[student.id] ?? [] + [record]).suffix(24))
            values.bodyAssessmentDrafts.removeValue(forKey: student.id); values.completedAssessments.insert("\(student.id)-身体测评")
            values.bodyAssessmentSyncStates[student.id] = repository.supportsRemoteAcknowledgement ? .pendingSync : .submitted
        }
        guard repository.supportsRemoteAcknowledgement else { return }
        let key = "body-assessment-\(student.id)"; workflowStates[key] = .submitting
        Task { [weak self] in
            guard let self else { return }
            do {
                guard let consent = localFeatures.healthConsents[student.id], consent.revokedAt == nil else { throw ApiError.message("请先完成监护人授权后再提交身体测评") }
                guard consent.privacyPolicyVersion == LegalPolicy.privacyPolicyVersion,
                      consent.cameraConsentVersion == LegalPolicy.cameraConsentVersion,
                      consent.algorithmNoticeVersion == LegalPolicy.algorithmNoticeVersion else {
                    throw ApiError.message("授权说明已更新，请返回监护人授权步骤重新确认")
                }
                try await repository.grantHealthConsent(consent)
                if let report = try await repository.submitBodyAssessment(studentID: student.id, record: record, consentVersion: consent.privacyPolicyVersion) {
                    mutateLocal { values in
                        guard var latest = values.bodyAssessments[student.id] else { return }
                        latest.postureReport = report; values.bodyAssessments[student.id] = latest
                        if var history = values.bodyAssessmentHistory[student.id], !history.isEmpty { history[history.count - 1].postureReport = report; values.bodyAssessmentHistory[student.id] = history }
                    }
                }
                mutateLocal { $0.bodyAssessmentSyncStates[student.id] = .submitted }; workflowStates[key] = .succeeded("测评已同步学校后台")
            } catch {
                mutateLocal { $0.bodyAssessmentSyncStates[student.id] = .failed }; workflowStates[key] = .failed(error.localizedDescription)
                if case ApiError.unauthorized = error { handleDashboardError(error) }
            }
        }
    }

    /// Refreshes the server-owned screening/review status while preserving the
    /// locally captured structured measurements. Raw camera media is never
    /// requested by this endpoint.
    func refreshLatestBodyAssessment(for student: Student) async {
        guard repository.supportsRemoteAcknowledgement,
              let record = localFeatures.bodyAssessments[student.id] else { return }
        let key = "body-assessment-refresh-\(student.id)"
        workflowStates[key] = .submitting
        do {
            guard let report = try await repository.loadLatestBodyAssessment(studentID: student.id, record: record) else {
                workflowStates[key] = .failed("学校服务尚未返回身体观察结果。")
                return
            }
            guard selectedChild?.id == student.id else { return }
            mutateLocal { values in
                guard var latest = values.bodyAssessments[student.id] else { return }
                latest.postureReport = report
                values.bodyAssessments[student.id] = latest
                if var history = values.bodyAssessmentHistory[student.id], !history.isEmpty {
                    history[history.count - 1].postureReport = report
                    values.bodyAssessmentHistory[student.id] = history
                }
            }
            workflowStates[key] = .succeeded("复核状态已更新")
        } catch {
            workflowStates[key] = .failed(error.localizedDescription)
            if case ApiError.unauthorized = error { handleDashboardError(error) }
        }
    }

    func toggleBodyPlanDay(_ day: Date, for student: Student) {
        let key = Self.dayFormatter.string(from: day)
        mutateLocal { values in guard var record = values.bodyAssessments[student.id] else { return }; if record.completedPlanDays.contains(key) { record.completedPlanDays.remove(key) } else { record.completedPlanDays.insert(key) }; values.bodyAssessments[student.id] = record }
    }

    func saveFollowAlongSession(_ record: FollowAlongSessionRecord) {
        mutateLocal { values in
            values.followAlongSessions = Array((values.followAlongSessions + [record]).suffix(90)); values.followAlongSyncStates[record.id.uuidString] = repository.supportsRemoteAcknowledgement ? .pendingSync : .submitted
            let parentConfirmed = record.mode == "parentConfirmedAssistedTraining" && record.completionRatio >= 1
            guard record.cameraVerified || parentConfirmed else { return }
            let key = "follow-along-\(record.childID)"; values.courseProgress[key] = min(max(values.courseProgress[key] ?? 0, record.completionRatio), 1)
            let day = Self.dayFormatter.string(from: record.completedAt); values.checkInDates.insert(day)
            if var assessment = values.bodyAssessments[record.childID] { assessment.completedPlanDays.insert(day); values.bodyAssessments[record.childID] = assessment }
        }
        guard repository.supportsRemoteAcknowledgement, !isOffline else { return }
        Task { @MainActor in
            mutateLocal { $0.followAlongSyncStates[record.id.uuidString] = .submitting }
            do { _ = try await repository.submitFollowAlongSession(record); mutateLocal { $0.followAlongSyncStates[record.id.uuidString] = .submitted } }
            catch { if case ApiError.unauthorized = error { handleDashboardError(error) } else { mutateLocal { $0.followAlongSyncStates[record.id.uuidString] = .failed } } }
        }
    }
}
