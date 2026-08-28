import SwiftUI

@MainActor final class AppState: ObservableObject {
    @Published var isShowingSplash = true
    @Published var profile: UserProfile?
    @Published var selectedRole: UserRole?
    @Published var data: DashboardData?
    @Published var selectedChild: Student?
    @Published var loading = false
    @Published private(set) var reportLoading = false
    @Published private(set) var reportError: String?
    @Published var studentsLoadingMore = false
    @Published var studentsLoadError: String?
    @Published var teacherOverview: TeacherAnalyticsOverview?
    /// The overview payload is only valid for the class/task scope that
    /// produced it. This prevents a delayed request from repainting a newly
    /// selected class with the previous class's metrics.
    @Published var teacherOverviewContext: TeacherOverviewContext?
    /// Authoritative rows for the selected task. This is separate from the
    /// paged dashboard student directory so a task member is never hidden by
    /// the dashboard page currently loaded.
    @Published var taskRosterRecords: [String: [TaskStudentStatusRecord]] = [:]
    @Published var bodyScreeningReviews: [BodyScreeningReviewItem] = []
    @Published var bodyScreeningReviewsLoading = false
    @Published var bodyScreeningReviewsError: String?
    @Published var remoteActivities: [RemoteActivity] = []
    @Published var activitiesLoading = false
    @Published var activitiesError: String?
    @Published var activityRegistrationHistory: [ActivityRegistrationAck] = []
    @Published var remoteExperts: [RemoteExpert] = []
    @Published var expertsLoading = false
    @Published var expertsError: String?
    @Published var expertSlots: [String: [ExpertAvailableSlot]] = [:]
    @Published var expertSlotErrors: [String: String] = [:]
    @Published var expertAppointmentHistory: [ExpertAppointmentAck] = []
    @Published var classPostsLoading = false
    @Published var classPostsError: String?
    @Published var classPostsNextCursor: String?
    @Published var classPostAttachmentData: [String: Data] = [:]
    @Published var classPostAttachmentErrors: [String: String] = [:]
    @Published var remoteCourses: [RemoteLesson] = []
    @Published var notificationDrafts: [NotificationCampaign] = []
    @Published var notificationDraftsLoading = false
    @Published var notificationDraftsError: String?
    @Published var coursesLoading = false
    @Published var coursesError: String?
    @Published var remoteCoursesChildID: String?
    /// A report must be able to open the exact recommended lesson instead of
    /// merely switching the parent to the generic course tab.  This is kept in
    /// app state (rather than a title-only route) because remote catalogue
    /// entries are scoped to a child and use stable course/lesson IDs.
    @Published var courseRecommendationTarget: CourseRecommendationTarget?
    /// Pending targets from message deep-links. IDs are consumed by the list
    /// page after its remote catalogue has loaded; display titles are never
    /// used to resolve a business object.
    @Published var pendingActivityID: String?
    @Published var pendingExpertAppointmentID: String?
    @Published var workflowStates: [String: WorkflowCommandState] = [:]
    @Published private(set) var isOffline = false
    @Published private(set) var localPersistenceError: String?
    /// Session restoration happens behind the launch artwork. Keeping this separate
    /// from `loading` prevents the retry overlay from flashing before login/role
    /// selection is ready.
    @Published private(set) var restoringSession = false
    @Published var error: String?
    @Published private(set) var localFeatures: LocalFeatureState
    let repository: YouthRepository
    let featureStore: LocalFeatureStore
    var usesRemoteDataSource: Bool { repository.supportsRemoteAcknowledgement }

    /// The visible identity is session-owned.  Class-circle writes and edit
    /// affordances must never depend on a seeded mock name, otherwise a
    /// registered family can appear as another account after switching roles.
    var activeDisplayName: String {
        let name = profile?.name.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !name.isEmpty { return name }
        switch selectedRole {
        case .teacher: return "教师"
        case .principal: return "校长"
        default: return "家长"
        }
    }
    /// Teacher scope is derived from stable authorization claims. A class row
    /// without a teacherID is intentionally not granted by display-name match.
    var managedTeacherClasses: [ClassInfo] {
        guard selectedRole == .teacher || profile?.role == .teacher else { return [] }
        let authorized = Set(profile?.authorizedClassIDs ?? [])
        let teacherID = profile?.id
        return data?.classes.filter { authorized.contains($0.id) || ($0.teacherID != nil && $0.teacherID == teacherID) } ?? []
    }
    func teacherHasCapability(_ capability: String) -> Bool {
        guard selectedRole == .teacher || profile?.role == .teacher else { return false }
        let claims = Set(profile?.capabilities ?? [])
        // Only the bundled Mock account gets a minimal visual fallback. A
        // remote account with no claim is intentionally denied until the
        // server returns its authoritative capability set.
        return claims.isEmpty ? (!usesRemoteDataSource && capability == "VIEW_CLASS_DASHBOARD") : claims.contains(capability)
    }
    init(repository: YouthRepository = RepositoryProvider.make(), featureStore: LocalFeatureStore? = nil) {
        self.repository = repository
        let resolvedFeatureStore = featureStore ?? LocalFeatureStore()
        self.featureStore = resolvedFeatureStore
        // UI smoke tests must not inherit a developer's previous session or
        // bound-child state. This flag is inert for normal and release launches.
        if ProcessInfo.processInfo.arguments.contains("-ui-testing") {
            resolvedFeatureStore.reset()
        }
        self.localFeatures = resolvedFeatureStore.state
        self.localPersistenceError = resolvedFeatureStore.persistenceError
        if let sessionProfile = localFeatures.sessionProfile {
            profile = sessionProfile
            repository.configureSession(sessionProfile)
            // Keep the login session, but require an explicit role choice on the
            // next launch so a previously selected principal account cannot lock
            // the user out of the parent or teacher workbench.
            selectedRole = nil
            // Set this synchronously before scheduling the refresh.  Otherwise
            // SplashView can observe a brief false value and transition into a
            // half-restored role picker before the dashboard is ready.
            restoringSession = true
            loading = true
            Task { [weak self] in
                guard let self else { return }
                defer {
                    self.loading = false
                    self.restoringSession = false
                }
                do {
                    if self.repository.supportsRemoteAcknowledgement {
                        let session = try await AuthApi().currentSession()
                        self.profile = session.profile
                        self.repository.configureSession(session.profile)
                    }
                    self.data = try await repository.loadDashboard()
                    self.reconcileSelectedChildFromDashboard()
                    self.refreshSelectedChildRemoteData()
                    if self.repository.supportsRemoteAcknowledgement, !self.isOffline, self.pendingSyncCount > 0 {
                        await self.syncPendingRecords()
                    }
            } catch {
                if case ApiError.unauthorized = error {
                    self.handleDashboardError(error)
                } else {
                    // A transient network/backend failure is not evidence that
                    // the credentials are invalid. Keep the secure token,
                    // session profile and offline writes; only 401 logs out.
                    self.error = error.localizedDescription
                }
            }
            }
        }
        // Local visual-regression entry point.  It is inert unless Xcode/simctl passes
        // XS_DEBUG_ROLE, so production launch always retains splash → login → role flow.
        let debugRole: UserRole? = switch ProcessInfo.processInfo.environment["XS_DEBUG_ROLE"] {
        case "parent", UserRole.parent.rawValue: .parent
        case "teacher", UserRole.teacher.rawValue: .teacher
        case "principal", UserRole.principal.rawValue: .principal
        default: nil
        }
        if let role = debugRole {
            isShowingSplash = false
            selectedRole = role
            profile = UserProfile(id: role == .teacher ? "teacher_li" : role == .principal ? "principal_zhou" : "parent_wang", name: role == .teacher ? "李老师" : role == .principal ? "周校长" : "王女士", phone: "13800138000", role: role, schoolName: "向上实验小学", avatarInitials: role == .teacher ? "李" : role == .principal ? "周" : "王", authorizedClassIDs: role == .teacher ? ["c31", "c32"] : [], capabilities: role == .teacher ? ["VIEW_CLASS_DASHBOARD", "MANAGE_CLASS_STUDENTS", "VIEW_TEST_TASKS", "UPDATE_TEST_STATUS", "REVIEW_RESULT", "REQUEST_RETEST", "UPLOAD_AFTER_SCHOOL_COURSE", "PUBLISH_CLASS_NOTICE"] : [])
            Task { [weak self] in
                guard let self else { return }
                self.data = try? await repository.loadDashboard()
                self.reconcileSelectedChildFromDashboard()
                self.refreshSelectedChildRemoteData()
            }
        }
    }
    func setTeacherSportsWorkbench(_ enabled: Bool) { mutateLocal { $0.teacherUsesSportsWorkbench = enabled } }
    func recordHealthConsent(studentID: String, privacyVersion: String = LegalPolicy.privacyPolicyVersion, cameraVersion: String = LegalPolicy.cameraConsentVersion, algorithmVersion: String = LegalPolicy.algorithmNoticeVersion) {
        guard let profile else { return }
        mutateLocal { values in
            values.healthConsents[studentID] = HealthConsentRecord(consentID: UUID().uuidString, guardianUserID: profile.id, childID: studentID, privacyPolicyVersion: privacyVersion, cameraConsentVersion: cameraVersion, algorithmNoticeVersion: algorithmVersion, agreedAt: .now, revokedAt: nil, deviceInfo: UIDevice.current.model, dataRetentionNoticeAccepted: true)
        }
    }
    func switchAccount() { ApiClient.shared.clearSession(); featureStore.reset(); localFeatures = featureStore.state; FrontendTelemetry.configure(enabled: false); profile = nil; selectedRole = nil; selectedChild = nil; data = nil; error = nil; reportLoading = false; reportError = nil; workflowStates.removeAll(); refreshedReports.removeAll(); taskRosterRecords.removeAll(); bodyScreeningReviews.removeAll(); bodyScreeningReviewsError = nil }
    private var refreshedReports: [String: DiagnosisReport] = [:]
    func report(for student: Student) -> DiagnosisReport { refreshedReports[student.id] ?? repository.report(for: student) }
    /// Remote dashboards must never paint a bundled demonstration result before
    /// the report endpoint responds.  Mock mode intentionally remains fully
    /// usable offline; remote mode exposes only a successfully fetched cache.
    func visibleReport(for student: Student) -> DiagnosisReport? {
        repository.supportsRemoteAcknowledgement ? refreshedReports[student.id] : report(for: student)
    }
    /// A bundled Mock report is useful for completed students, but it must not
    /// make a pending field-test look like a published school result.  Keep
    /// every parent-facing entry point behind the same release condition; the
    /// remote report service will replace this once it returns publication
    /// metadata per student/task.
    func hasPublishedSchoolReport(for student: Student) -> Bool {
        guard let dashboard = data else { return false }
        let status = dashboard.tasks.first.map { taskStatus(for: student, taskID: $0.id) } ?? taskStatus(for: student)
        guard status == .completed else { return false }
        return dashboard.tasks.contains { task in
            task.hasPublishedResults && task.scopedStudents(from: dashboard.students).contains { $0.id == student.id }
        }
    }
    func refreshReport(for student: Student) async {
        guard profile != nil, !reportLoading else { return }
        reportLoading = true
        reportError = nil
        defer { reportLoading = false }
        do {
            let loadedReport = try await repository.loadReport(for: student)
            // A user can switch accounts while the request is in flight. Never
            // let a previous account's response repopulate the new session.
            guard profile != nil else { return }
            refreshedReports[student.id] = loadedReport
        } catch {
            if case ApiError.cancelled = error { return }
            if case ApiError.unauthorized = error {
                handleDashboardError(error)
                return
            }
            reportError = error.localizedDescription
        }
    }
    func clearReportError() { reportError = nil }


    func workflowState(for key: String) -> WorkflowCommandState { workflowStates[key] ?? .idle }
    func clearWorkflowState(_ key: String) { workflowStates[key] = .idle }

    // Write-side progress is scoped to the active child when a family has
    // selected one.  Keeping the legacy key for an unselected child preserves
    // compatibility with older drafts while preventing two children from
    // sharing submitting/error UI state.
    func childWorkflowKey(_ prefix: String, childID: String? = nil) -> String {
        let resolved = childID ?? selectedChild?.id
        return resolved.map { "\(prefix):\($0)" } ?? prefix
    }

    /// Executes a write-side command through the repository seam. Local-first
    /// screens can show the same submitting/success/failure states in Mock and
    /// Remote modes, while the operation itself remains replaceable.
    func executeWorkflow(_ key: String, operation: @escaping () async throws -> Void) async -> Bool {
        guard !workflowState(for: key).isSubmitting else { return false }
        workflowStates[key] = .submitting
        do {
            try await operation()
            workflowStates[key] = .succeeded(repository.supportsRemoteAcknowledgement
                ? "已提交并收到学校服务确认。"
                : "已保存到本机，等待学校服务接入后同步确认。")
            return true
        } catch {
            if error is CancellationError || (error as? ApiError).map({ if case .cancelled = $0 { true } else { false } }) == true {
                workflowStates[key] = .idle
                return false
            }
            if case ApiError.unauthorized = error {
                handleDashboardError(error)
                return false
            }
            if case ApiError.conflict = error, key.hasPrefix("task-status:") {
                let encoded = String(key.dropFirst("task-status:".count))
                let parts = encoded.split(separator: "|", maxSplits: 1).map(String.init)
                let taskID = parts.first == "missing-task" ? nil : parts.first
                let studentID = parts.count > 1 ? parts[1] : encoded
                resetTaskStatusProjectionAfterConflict(studentID, taskID: taskID)
            }
            workflowStates[key] = .failed(error.localizedDescription)
            return false
        }
    }


    func selectChild(_ student: Student) {
        // Clear the previous child's visible record before loading the new
        // scope so a fast child switch never flashes stale health data.
        selectedChild = student
        persistSelectedChild()
        if repository.supportsRemoteAcknowledgement {
            refreshSelectedChildRemoteData()
            Task { @MainActor in await loadClassPosts() }
            Task { @MainActor in await loadActivities() }
        }
    }
    /// Reconciles the device cache with the authenticated guardian scope.
    /// A newly signed-in parent may already have server-side bindings created
    /// by a school or another device; requiring a locally cached binding made
    /// those children disappear and incorrectly showed the binding prompt.
    func reconcileSelectedChildFromDashboard() {
        guard let dashboard = data else { selectedChild = nil; return }
        if repository.supportsRemoteAcknowledgement, profile?.role == .parent {
            let authorizedStudents = dashboard.parentChildren.map(\.student)
            let authorizedIDs = Set(authorizedStudents.map(\.id))
            let preferredID = localFeatures.selectedChildID.flatMap { authorizedIDs.contains($0) ? $0 : nil }
            let resolved = preferredID.flatMap { id in authorizedStudents.first(where: { $0.id == id }) }
                ?? authorizedStudents.first
            mutateLocal { values in
                values.boundChildIDs = authorizedIDs
                values.selectedChildID = resolved?.id
            }
            selectedChild = resolved
            return
        }
        selectedChild = dashboard.students.first(where: {
            $0.id == localFeatures.selectedChildID && localFeatures.boundChildIDs.contains($0.id)
        })
    }
    func refreshSelectedChildRemoteData() {
        guard repository.supportsRemoteAcknowledgement, let student = selectedChild else { return }
        Task { @MainActor in
            await loadFamilyHealthObservations(for: student)
            await loadHealthCheckins(for: student)
        }
    }
    var boundChildren: [Student] {
        guard let data else { return [] }
        if repository.supportsRemoteAcknowledgement, profile?.role == .parent {
            return data.parentChildren.map(\.student)
        }
        return data.students.filter { localFeatures.boundChildIDs.contains($0.id) }
    }
    var unreadMessageCount: Int {
        guard localFeatures.settings.notificationsEnabled else { return 0 }
        return (data?.messages ?? []).filter { !$0.isRead && !localFeatures.readMessageIDs.contains($0.id) }.count
    }
    /// Local writes that have not been acknowledged by a remote service yet.
    var pendingSyncCount: Int {
        let activity = localFeatures.activityRegistrations.count(where: { $0.status == .pendingSync || $0.status == .failed })
        let experts = localFeatures.expertAppointments.count(where: { $0.status == .pendingSync || $0.status == .failed })
        let uploads = localFeatures.courseUploads.count(where: { $0.status == .pendingSync || $0.status == .failed })
        let posts = localFeatures.classPosts.count(where: { $0.status == .pendingSync || $0.status == .failed })
        let support = localFeatures.supportMessages.count(where: { $0.isMine && ($0.status == .pendingSync || $0.status == .failed) })
        let taskStatuses = localFeatures.taskScopedSyncStates.values.count(where: { $0 == .pendingSync || $0 == .failed })
        let bodyAssessments = localFeatures.bodyAssessmentSyncStates.values.count(where: { $0 == .pendingSync || $0 == .failed })
        let followAlong = localFeatures.followAlongSyncStates.values.count(where: { $0 == .pendingSync || $0 == .failed })
        let observations = localFeatures.healthObservationSyncStates.values.count(where: { $0 == .pendingSync || $0 == .failed })
        let checkins = localFeatures.healthCheckinSyncStates.values.count(where: { $0 == .pendingSync || $0 == .failed })
        return activity + experts + uploads + posts + support + taskStatuses + bodyAssessments + followAlong + observations + checkins
    }

    /// Replays safely persisted writes after connectivity returns or when the
    /// user taps “立即同步”. Each successful record is acknowledged locally;
    /// failed ones remain pending for a later retry.
    func syncPendingRecords() async {
        guard profile != nil else {
            workflowStates["sync-pending"] = .failed("请登录后再同步本机记录。")
            return
        }
        guard !isOffline else {
            workflowStates["sync-pending"] = .failed("当前网络不可用，记录会继续保存在本机。")
            return
        }
        guard repository.supportsRemoteAcknowledgement else {
            workflowStates["sync-pending"] = .succeeded("本机记录已安全保留，学校服务接入后可统一同步。")
            return
        }
        guard !workflowState(for: "sync-pending").isSubmitting else { return }
        let activities = localFeatures.activityRegistrations.filter { $0.status == .pendingSync || $0.status == .failed }
        let experts = localFeatures.expertAppointments.filter { $0.status == .pendingSync || $0.status == .failed }
        let uploads = localFeatures.courseUploads.filter { $0.status == .pendingSync || $0.status == .failed }
        let posts = localFeatures.classPosts.filter { $0.status == .pendingSync || $0.status == .failed }
        let supportMessages = localFeatures.supportMessages.filter { $0.isMine && ($0.status == .pendingSync || $0.status == .failed) }
        let bodyAssessments = localFeatures.bodyAssessmentSyncStates.filter { $0.value == .pendingSync || $0.value == .failed }
        let followAlong = localFeatures.followAlongSyncStates.filter { $0.value == .pendingSync || $0.value == .failed }
        let observations = localFeatures.healthObservationSyncStates.filter { $0.value == .pendingSync || $0.value == .failed }
        let checkins = localFeatures.healthCheckinSyncStates.filter { $0.value == .pendingSync || $0.value == .failed }
        let taskStatuses = localFeatures.taskScopedSyncStates.filter { $0.value == .pendingSync || $0.value == .failed }
        guard !(activities.isEmpty && experts.isEmpty && uploads.isEmpty && posts.isEmpty && supportMessages.isEmpty && bodyAssessments.isEmpty && followAlong.isEmpty && observations.isEmpty && checkins.isEmpty && taskStatuses.isEmpty) else {
            workflowStates["sync-pending"] = .succeeded("当前没有等待同步的本机记录。")
            return
        }
        workflowStates["sync-pending"] = .submitting
        var synchronized = 0
        var failed = 0
        for record in activities {
            updateActivitySyncStatus(record.id, to: .submitting)
            do { let ack = try await repository.submitActivity(record); updateActivityProjection(record.id, ack: ack, fallbackStatus: .submitted); synchronized += 1 }
            catch {
                if case ApiError.unauthorized = error { handleDashboardError(error); return }
                updateActivitySyncStatus(record.id, to: .failed); failed += 1
            }
        }
        for record in experts {
            updateExpertSyncStatus(record.id, to: .submitting)
            do { let ack = try await repository.bookExpert(record); updateExpertProjection(record.id, ack: ack, fallbackStatus: .submitted); synchronized += 1 }
            catch {
                if case ApiError.unauthorized = error { handleDashboardError(error); return }
                updateExpertSyncStatus(record.id, to: .failed); failed += 1
            }
        }
        for record in uploads {
            updateCourseSyncStatus(record.id, to: .submitting)
            do { try await repository.uploadCourse(record); updateCourseSyncStatus(record.id, to: .submitted); synchronized += 1 }
            catch {
                if case ApiError.unauthorized = error { handleDashboardError(error); return }
                updateCourseSyncStatus(record.id, to: .failed); failed += 1
            }
        }
        for post in posts {
            updateClassPostSyncStatus(post.id, to: .submitting)
            do { let serverPostID = try await repository.publishClassPost(author: post.author, content: post.content, schoolID: profile?.schoolID, classID: post.classID, attachments: post.attachments ?? []); updateClassPostSyncStatus(post.id, to: .submitted, serverPostID: serverPostID); synchronized += 1 }
            catch {
                if case ApiError.unauthorized = error { handleDashboardError(error); return }
                updateClassPostSyncStatus(post.id, to: .failed); failed += 1
            }
        }
        for message in supportMessages {
            updateSupportSyncStatus(message.id, to: .submitting)
            do { try await repository.sendSupportMessage(message.text); updateSupportSyncStatus(message.id, to: .submitted); synchronized += 1 }
            catch {
                if case ApiError.unauthorized = error { handleDashboardError(error); return }
                updateSupportSyncStatus(message.id, to: .failed); failed += 1
            }
        }
        for (studentID, _) in bodyAssessments {
            guard let record = localFeatures.bodyAssessments[studentID] else {
                mutateLocal { $0.bodyAssessmentSyncStates[studentID] = .failed }
                failed += 1
                continue
            }
            mutateLocal { $0.bodyAssessmentSyncStates[studentID] = .submitting }
            do {
                guard let consent = localFeatures.healthConsents[studentID], consent.revokedAt == nil else { throw ApiError.message("请先完成监护人授权后再同步身体测评") }
                guard consent.privacyPolicyVersion == LegalPolicy.privacyPolicyVersion,
                      consent.cameraConsentVersion == LegalPolicy.cameraConsentVersion,
                      consent.algorithmNoticeVersion == LegalPolicy.algorithmNoticeVersion else {
                    throw ApiError.message("授权说明已更新，请重新确认后再同步身体测评")
                }
                try await repository.grantHealthConsent(consent)
                let canonicalReport = try await repository.submitBodyAssessment(studentID: studentID, record: record, consentVersion: consent.privacyPolicyVersion)
                if let canonicalReport {
                    mutateLocal { values in
                        guard var latest = values.bodyAssessments[studentID] else { return }
                        latest.postureReport = canonicalReport
                        values.bodyAssessments[studentID] = latest
                        if var history = values.bodyAssessmentHistory[studentID], !history.isEmpty {
                            history[history.count - 1].postureReport = canonicalReport
                            values.bodyAssessmentHistory[studentID] = history
                        }
                    }
                }
                mutateLocal { $0.bodyAssessmentSyncStates[studentID] = .submitted }
                synchronized += 1
            } catch {
                if case ApiError.unauthorized = error { handleDashboardError(error); return }
                mutateLocal { $0.bodyAssessmentSyncStates[studentID] = .failed }
                failed += 1
            }
        }
        for (key, _) in observations {
            let parts = key.split(separator: ":", maxSplits: 1).map(String.init)
            guard parts.count == 2, let record = localFeatures.familyHealthRecords["\(parts[0])-\(parts[1])"] else {
                mutateLocal { $0.healthObservationSyncStates[key] = .failed }; failed += 1; continue
            }
            mutateLocal { $0.healthObservationSyncStates[key] = .submitting }
            do {
                let canonical = try await repository.submitHealthObservation(studentID: parts[0], category: parts[1], record: record)
                mutateLocal { values in values.familyHealthRecords["\(parts[0])-\(parts[1])"] = canonical; values.healthObservationSyncStates[key] = .submitted }
                synchronized += 1
            } catch {
                if case ApiError.unauthorized = error { handleDashboardError(error); return }
                mutateLocal { $0.healthObservationSyncStates[key] = .failed }; failed += 1
            }
        }
        for (recordID, _) in checkins {
            guard let record = localFeatures.healthCheckins.first(where: { $0.id == recordID }) else {
                mutateLocal { $0.healthCheckinSyncStates[recordID] = .failed }; failed += 1; continue
            }
            mutateLocal { $0.healthCheckinSyncStates[recordID] = .submitting }
            do {
                let canonical = try await repository.submitHealthCheckin(record, expectedVersion: record.version > 0 ? record.version : nil)
                mutateLocal { values in values.healthCheckins.removeAll { $0.id == recordID || ($0.childID == canonical.childID && $0.checkInDate == canonical.checkInDate) }; values.healthCheckins.insert(canonical, at: 0); values.healthCheckinSyncStates[recordID] = .submitted; values.healthCheckinSyncStates[canonical.id] = .submitted }
                synchronized += 1
            } catch {
                if case ApiError.unauthorized = error { handleDashboardError(error); return }
                mutateLocal { $0.healthCheckinSyncStates[recordID] = .failed }; failed += 1
            }
        }
        for (sessionID, _) in followAlong {
            guard let record = localFeatures.followAlongSessions.first(where: { $0.id.uuidString == sessionID }) else {
                mutateLocal { $0.followAlongSyncStates[sessionID] = .failed }; failed += 1; continue
            }
            mutateLocal { $0.followAlongSyncStates[sessionID] = .submitting }
            do {
                _ = try await repository.submitFollowAlongSession(record)
                mutateLocal { $0.followAlongSyncStates[sessionID] = .submitted }
                synchronized += 1
            } catch {
                if case ApiError.unauthorized = error { handleDashboardError(error); return }
                mutateLocal { $0.followAlongSyncStates[sessionID] = .failed }; failed += 1
            }
        }
        for (key, _) in taskStatuses {
            let parts = key.split(separator: "|", maxSplits: 1).map(String.init)
            let taskID = parts.first == "missing-task" ? nil : parts.first
            let studentID = parts.count > 1 ? parts[1] : ""
            guard let taskID, !taskID.isEmpty, taskID != "missing-task" else {
                // Older installations could retain a student-only projection.
                // It has no safe target after the taskId+studentId migration, so
                // fail it visibly instead of sending it to an arbitrary task.
                if !studentID.isEmpty { updateTaskStatusSyncState(studentID, taskID: nil, to: .failed) }
                failed += 1
                continue
            }
            guard !studentID.isEmpty, let status = localFeatures.taskScopedStatuses[key] else {
                if !studentID.isEmpty { updateTaskStatusSyncState(studentID, taskID: taskID, to: .failed) }
                failed += 1
                continue
            }
            updateTaskStatusSyncState(studentID, taskID: taskID, to: .submitting)
            let expectedVersion = localFeatures.taskScopedStatusVersions[key] ?? data?.students.first(where: { $0.id == studentID })?.taskVersion
            do {
                let acknowledgedVersion = try await repository.updateTaskStatus(taskID: taskID, studentID: studentID, status: status, note: localFeatures.taskScopedReviewNotes[key], expectedVersion: expectedVersion)
                acknowledgeTaskStatusVersion(studentID, taskID: taskID, serverVersion: acknowledgedVersion)
                updateTaskStatusSyncState(studentID, taskID: taskID, to: .submitted)
                synchronized += 1
            } catch {
                if case ApiError.unauthorized = error { handleDashboardError(error); return }
                updateTaskStatusSyncState(studentID, taskID: taskID, to: .failed)
                failed += 1
            }
        }
        workflowStates["sync-pending"] = failed == 0
            ? .succeeded("已同步 \(synchronized) 条本机记录。")
            : .failed("已同步 \(synchronized) 条，仍有 \(failed) 条等待网络恢复后重试。")
    }
    func markMessageRead(_ id: String) {
        mutateLocal { $0.readMessageIDs.insert(id) }
        guard repository.supportsRemoteAcknowledgement else { return }
        Task { [weak self] in
            guard let self else { return }
            do { try await repository.markMessageRead(messageID: id) }
            catch { if case ApiError.unauthorized = error { handleDashboardError(error) } }
        }
    }
    func markAllMessagesRead() {
        let messageIDs = data?.messages.map(\.id) ?? []
        guard !messageIDs.isEmpty else { return }
        mutateLocal { $0.readMessageIDs.formUnion(messageIDs) }
        guard repository.supportsRemoteAcknowledgement else { return }
        for id in messageIDs {
            Task { [weak self] in
                guard let self else { return }
                do { try await repository.markMessageRead(messageID: id) }
                catch { if case ApiError.unauthorized = error { handleDashboardError(error) } }
            }
        }
    }
    /// Binds a child and only reports success after the repository has accepted
    /// the request.  The previous implementation returned `true` as soon as a
    /// remote request was queued, which made the sheet close before an error
    /// could be shown to the parent.
    @discardableResult
    func bindChild(name: String, code: String) async -> Bool {
        let normalizedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedCode = code.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        if repository.supportsRemoteAcknowledgement {
            guard !normalizedName.isEmpty, !normalizedCode.isEmpty else { return false }
            workflowStates["child-binding"] = .submitting
            do {
                let binding = try await repository.bindChild(name: normalizedName, code: normalizedCode)
                mutateLocal { $0.boundChildIDs.insert(binding.student.id) }
                if selectedChild == nil { selectChild(binding.student) }
                workflowStates["child-binding"] = .succeeded("孩子已绑定")
                await refreshDashboard()
                return true
            } catch {
                workflowStates["child-binding"] = .failed(error.localizedDescription)
                if case ApiError.unauthorized = error { handleDashboardError(error) }
                return false
            }
        }
        guard !normalizedName.isEmpty, !normalizedCode.isEmpty,
              let child = data?.students.first(where: { student in
                  let validCode = normalizedCode == student.id.uppercased() || normalizedCode == "XS-\(student.id.uppercased())"
                  return validCode && student.name == normalizedName
              }) else { return false }
        mutateLocal { $0.boundChildIDs.insert(child.id) }
        if selectedChild == nil { selectChild(child) }
        return true
    }

    func saveDraft(_ text: String, key: String) { mutateLocal { $0.drafts[key] = text } }
    func clearDraft(_ key: String) { mutateLocal { $0.drafts.removeValue(forKey: key) } }
    func clearDrafts(prefix: String) { mutateLocal { values in let keys = values.drafts.keys.filter { $0.hasPrefix(prefix) }; keys.forEach { values.drafts.removeValue(forKey: $0) } } }
    static func parseISODate(_ value: String) -> Date? {
        ISO8601DateFormatter().date(from: value)
    }

    func updateSettings(notificationsEnabled: Bool? = nil, reduceMotion: Bool? = nil, voiceGuidanceEnabled: Bool? = nil, analyticsEnabled: Bool? = nil) {
        mutateLocal { values in
            if let notificationsEnabled { values.settings.notificationsEnabled = notificationsEnabled }
            if let reduceMotion { values.settings.reduceMotion = reduceMotion }
            if let voiceGuidanceEnabled { values.settings.voiceGuidanceEnabled = voiceGuidanceEnabled }
            if let analyticsEnabled { values.settings.analyticsEnabled = analyticsEnabled }
        }
        FrontendTelemetry.configure(enabled: localFeatures.settings.analyticsEnabled && usesRemoteDataSource)
    }
    func setOffline(_ value: Bool) {
        isOffline = value
        // Restore/relaunch can report an online path without a preceding
        // offline transition.  Retry persisted writes whenever the app has a
        // usable session and the sync command is not already running.
        if !value && profile != nil && data == nil && !loading {
            Task { await refreshDashboard() }
        } else if !value && profile != nil && pendingSyncCount > 0 && !workflowState(for: "sync-pending").isSubmitting {
            Task { await syncPendingRecords() }
        }
    }
    /// Compatibility entry point for callers that used the old shortcut.
    /// Submission data must now come from the form; a caller cannot invent a
    /// successful upload by supplying only a task id.
    func submitUpload(taskID: String, attendanceCount: Int, notes: String, attachmentName: String, attachmentReference: String? = nil) {
        saveCourseUpload(taskID: taskID, attendanceCount: attendanceCount, notes: notes, attachmentName: attachmentName, attachmentReference: attachmentReference, submit: true)
    }
    func checkInToday(activityType: String = "家庭运动", durationMinutes: Int = 20, intensity: String = "moderate", feeling: String? = nil, completedRecommended: Bool = false, parentNote: String? = nil) {
        guard let childID = selectedChild?.id else { return }
        let date = Self.dayFormatter.string(from: .now)
        let previous = localFeatures.healthCheckins.first(where: { $0.childID == childID && $0.checkInDate == date })
        let record = HealthCheckInRecord(id: previous?.id ?? UUID().uuidString, childID: childID, checkInDate: date, activityType: activityType.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "家庭运动" : activityType.trimmingCharacters(in: .whitespacesAndNewlines), durationMinutes: min(max(durationMinutes, 1), 1440), intensity: intensity, feeling: feeling?.nilIfBlank, completedRecommended: completedRecommended, parentNote: parentNote?.nilIfBlank, version: previous?.version ?? 0, createdAt: nil, updatedAt: nil)
        mutateLocal { values in
            values.healthCheckins.removeAll { $0.childID == childID && $0.checkInDate == date }
            values.healthCheckins.insert(record, at: 0)
            values.checkInDates.insert(date)
            values.healthCheckinSyncStates[record.id] = repository.supportsRemoteAcknowledgement ? .pendingSync : .submitted
        }
        guard repository.supportsRemoteAcknowledgement, !isOffline else { return }
        let key = "health-checkin:\(record.id)"
        Task { @MainActor in
            workflowStates[key] = .submitting
            do {
                let canonical = try await repository.submitHealthCheckin(record, expectedVersion: previous?.version)
                mutateLocal { values in values.healthCheckins.removeAll { $0.id == record.id || ($0.childID == childID && $0.checkInDate == date) }; values.healthCheckins.insert(canonical, at: 0); values.healthCheckinSyncStates[record.id] = .submitted; values.healthCheckinSyncStates[canonical.id] = .submitted }
                workflowStates[key] = .succeeded("运动记录已保存")
            } catch {
                if case ApiError.unauthorized = error { handleDashboardError(error) }
                else { mutateLocal { $0.healthCheckinSyncStates[record.id] = .failed }; workflowStates[key] = .failed(error.localizedDescription) }
            }
        }
    }
    func persistSession() { mutateLocal { values in values.sessionProfile = profile; values.sessionRole = selectedRole } }
    func persistSelectedChild() { mutateLocal { values in values.selectedChildID = selectedChild?.id } }
    func handleDashboardError(_ error: Error) {
        if case ApiError.cancelled = error { return }
        if case ApiError.unauthorized = error {
            ApiClient.shared.clearSession()
            featureStore.reset()
            localFeatures = featureStore.state
            profile = nil
            selectedRole = nil
            selectedChild = nil
            data = nil
            taskRosterRecords.removeAll()
        }
        self.error = error.localizedDescription
    }
    func mutateLocal(_ body: (inout LocalFeatureState) -> Void) {
        _ = featureStore.update(body)
        localFeatures = featureStore.state
        localPersistenceError = featureStore.persistenceError
        if pendingSyncCount > 0 { BackgroundSyncScheduler.schedule() }
    }
    func clearLocalPersistenceError() { localPersistenceError = nil }
    /// School records use the product's business day rather than the device
    /// timezone, otherwise a check-in around midnight can land on a different
    /// date from the school dashboard and Android client.
    static let dayFormatter: DateFormatter = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = Locale(identifier: "en_US_POSIX")
        calendar.timeZone = TimeZone(identifier: "Asia/Shanghai")!
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.isLenient = false
        return formatter
    }()
}

extension String {
    var nilIfBlank: String? {
        let value = trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }
}
