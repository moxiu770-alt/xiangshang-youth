import XCTest
@testable import XiangshangYouth

@MainActor
final class LocalFeatureStateTests: XCTestCase {
    func testApiClientBuildsAuthenticatedReadyJSONRequest() throws {
        let client = ApiClient(baseURL: URL(string: "https://example.test/api/")!)
        let body = Data("{\"status\":\"待复核\"}".utf8)

        let request = client.makeRequest(
            path: "v1/tasks/task-1/students/s01/status",
            method: "PATCH",
            query: [URLQueryItem(name: "source", value: "teacher")],
            body: body
        )

        XCTAssertEqual(request.httpMethod, "PATCH")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Accept"), "application/json")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Content-Type"), "application/json")
        XCTAssertEqual(request.httpBody, body)
        XCTAssertEqual(request.url?.path, "/api/v1/tasks/task-1/students/s01/status")
        XCTAssertEqual(URLComponents(url: try XCTUnwrap(request.url), resolvingAgainstBaseURL: false)?.queryItems?.first?.name, "source")
        XCTAssertEqual(URLComponents(url: try XCTUnwrap(request.url), resolvingAgainstBaseURL: false)?.queryItems?.first?.value, "teacher")
    }

    func testMockDashboardMatchesPhaseOneDataContract() async throws {
        let data = try await MockRepository.shared.loadDashboard()
        XCTAssertEqual(data.students.count, 20)
        XCTAssertEqual(data.classes.count, 6)
        XCTAssertEqual(data.grades.count, 3)
        XCTAssertEqual(data.tasks.count, 3)
        XCTAssertEqual(data.parentChildren.count, 2)
        XCTAssertEqual(data.tasks.first?.items.count, 7)
        XCTAssertEqual(data.messages.count, 6)
        XCTAssertEqual(data.messages.filter { $0.category == "系统" }.count, 2)
        XCTAssertEqual(data.messages.filter { $0.category != "系统" }.count, 4)
        XCTAssertEqual(data.students.first?.id, "s01")
        XCTAssertEqual(data.students.dropFirst().first?.id, "s02")
        XCTAssertTrue(data.students.contains(where: \.isPovertyArea))
    }

    func testMockStudentStatusesAndReportTotalMatchReferenceBoard() async throws {
        let data = try await MockRepository.shared.loadDashboard()
        XCTAssertEqual(
            Array(data.students.prefix(10).map(\.taskStatus)),
            [.completed, .completed, .review, .retest, .waiting, .notCheckedIn, .completed, .testing, .absent, .checkedIn]
        )
        let report = MockRepository.shared.report(for: data.students[0])
        XCTAssertEqual(report.scores.count, 7)
        XCTAssertEqual(report.totalScore, 28.5, accuracy: 0.001)
    }

    func testTaskScopeKeepsSelectedBatchStudentMetricsHonest() async throws {
        let data = try await MockRepository.shared.loadDashboard()
        let autumnTask = try XCTUnwrap(data.tasks.first(where: { $0.id == "t1" }))
        let retestTask = try XCTUnwrap(data.tasks.first(where: { $0.id == "t2" }))

        XCTAssertEqual(autumnTask.scopedStudents(from: data.students).count, data.students.count)
        XCTAssertEqual(Set(autumnTask.scopedStudents(from: data.students).map(\.grade)), Set(["三年级", "四年级", "五年级"]))
        XCTAssertTrue(retestTask.scopedStudents(from: data.students).allSatisfy { $0.className == "四年级1班" })
        XCTAssertFalse(retestTask.scopedStudents(from: data.students).contains(where: { $0.grade == "三年级" }))
    }

    func testTaskStatusStateMachineRejectsImpossibleQueueJumps() {
        XCTAssertEqual(TaskStatus.notCheckedIn.allowedNextStatuses, [.checkedIn, .absent])
        XCTAssertTrue(TaskStatus.notCheckedIn.allowsTransition(to: .checkedIn))
        XCTAssertFalse(TaskStatus.notCheckedIn.allowsTransition(to: .completed))
        XCTAssertTrue(TaskStatus.testing.allowsTransition(to: .review))
        XCTAssertTrue(TaskStatus.review.allowsTransition(to: .retest))
        XCTAssertFalse(TaskStatus.completed.allowsTransition(to: .waiting))
    }

    func testAsyncReportSeamKeepsMockReportRenderable() async throws {
        let dashboard = try await MockRepository.shared.loadDashboard()
        let student = try XCTUnwrap(dashboard.students.first)
        let report = try await MockRepository.shared.loadReport(for: student)
        XCTAssertEqual(report.student.id, student.id)
        XCTAssertEqual(report.scores.count, 7)
    }

    func testLoginRoleSwitchAndTaskStatusAreKeptInAppState() async {
        let suite = "xiangshang.youth.login-tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        let store = LocalFeatureStore(defaults: defaults)
        let state = AppState(featureStore: store)

        await state.login(phone: "13800138000")
        XCTAssertEqual(state.profile?.role, .parent)
        XCTAssertEqual(state.data?.students.count, 20)
        XCTAssertNil(state.selectedChild, "A new family account must bind a child before child-specific data is shown.")
        XCTAssertTrue(state.boundChildren.isEmpty)

        state.selectRole(.teacher)
        XCTAssertEqual(state.selectedRole, .teacher)
        XCTAssertEqual(state.profile?.name, "李老师")
        XCTAssertEqual(state.localFeatures.sessionProfile?.role, .teacher)
        XCTAssertEqual(state.localFeatures.sessionRole, .teacher)
        if let student = state.data?.students.first {
            state.updateTaskStatus(for: student, status: .review)
            XCTAssertEqual(state.taskStatus(for: student), .review)
        } else {
            XCTFail("Mock dashboard should include students")
        }
        state.selectRole(.principal)
        XCTAssertEqual(state.selectedRole, .principal)
        XCTAssertEqual(state.profile?.name, "周校长")
        state.chooseAnotherRole()
        XCTAssertNil(state.selectedRole)
    }

    func testWechatAuthorizationIdentifierIsNeverExposedAsProfilePhone() async {
        let suite = "xiangshang.youth.wechat-login-tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        let state = AppState(featureStore: LocalFeatureStore(defaults: defaults))

        await state.login(phone: "wechat_authorization")

        XCTAssertEqual(state.profile?.phone, "13800138000")
        XCTAssertNotEqual(state.localFeatures.sessionProfile?.phone, "wechat_authorization")
    }

    func testRegistrationNameIsKeptInThePersistedParentSession() async {
        let suite = "xiangshang.youth.registration-name-tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        let store = LocalFeatureStore(defaults: defaults)
        let state = AppState(featureStore: store)

        await state.login(phone: "13900139000", displayName: "新家长")

        XCTAssertEqual(state.profile?.name, "新家长")
        XCTAssertEqual(state.profile?.avatarInitials, "新")
        XCTAssertEqual(state.localFeatures.sessionProfile?.name, "新家长")

        state.selectRole(.teacher)
        state.selectRole(.parent)
        XCTAssertEqual(state.profile?.name, "新家长")
    }

    func testCourseProgressIsPersistedWithinTheValidRange() {
        let suite = "xiangshang.youth.course-progress-tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        let store = LocalFeatureStore(defaults: defaults)
        let state = AppState(featureStore: store)

        state.updateCourseProgress("体质成长课", progress: 1.25)
        state.updateCourseProgress("视力守护课", progress: -0.2)
        state.selectPrincipalTask("t2")
        state.setTeacherSportsWorkbench(true)

        XCTAssertEqual(state.localFeatures.courseProgress["体质成长课"], 1)
        XCTAssertEqual(state.localFeatures.courseProgress["视力守护课"], 0)
        let restored = AppState(featureStore: store)
        XCTAssertEqual(restored.localFeatures.courseProgress["体质成长课"], 1)
        XCTAssertEqual(restored.localFeatures.selectedPrincipalTaskID, "t2")
        XCTAssertTrue(restored.localFeatures.teacherUsesSportsWorkbench)
    }

    func testFeatureStorePersistsCommercialWorkflowRecords() {
        let suite = "xiangshang.youth.tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        let store = LocalFeatureStore(defaults: defaults)

        store.update { value in
            value.registeredActivities.insert("health-growth-season-2026")
            value.activityRegistrations.append(ActivityRegistration(id: UUID(), activityID: "health-growth-season-2026", contactName: "王女士", phone: "13800138000", status: .pendingSync, createdAt: .now))
            value.drafts["assessment-s01-fitness-0"] = "身高132cm，体重30kg"
            value.expertAppointments.append(ExpertAppointment(id: UUID(), expertName: "张教授", preferredDate: "周五上午", note: "运动发展咨询", status: .pendingSync, createdAt: .now))
            value.courseUploads.append(CourseUploadRecord(id: UUID(), taskID: "after-class-upload", attendanceCount: 26, notes: "已完成课程", attachmentName: "课堂.jpg", status: .pendingSync, createdAt: .now))
            value.studentTaskStatuses["s01"] = .review
            value.taskStatusSyncStates["s01"] = .pendingSync
            value.reviewNotes["s01"] = "核验视频后建议周五补测。"
            value.settings.reduceMotion = true
            let postID = UUID()
            value.likedClassPostIDs.insert(postID)
            value.likedClassPostIDs.insert(UUID(uuidString: "00000000-0000-0000-0000-000000000001")!)
            value.classPostComments.append(ClassPostComment(id: UUID(), postID: postID, author: "王女士", text: "继续加油", createdAt: .now))
        }

        let restored = LocalFeatureStore(defaults: defaults).state
        XCTAssertTrue(restored.registeredActivities.contains("health-growth-season-2026"))
        XCTAssertEqual(restored.activityRegistrations.first?.contactName, "王女士")
        XCTAssertEqual(restored.drafts["assessment-s01-fitness-0"], "身高132cm，体重30kg")
        XCTAssertEqual(restored.expertAppointments.first?.status, .pendingSync)
        XCTAssertEqual(restored.courseUploads.first?.attachmentName, "课堂.jpg")
        XCTAssertEqual(restored.studentTaskStatuses["s01"], .review)
        XCTAssertEqual(restored.taskStatusSyncStates["s01"], .pendingSync)
        XCTAssertEqual(restored.reviewNotes["s01"], "核验视频后建议周五补测。")
        XCTAssertTrue(restored.settings.reduceMotion)
        XCTAssertEqual(restored.classPostComments.first?.text, "继续加油")
        XCTAssertEqual(restored.likedClassPostIDs.count, 2)
        XCTAssertTrue(restored.likedClassPostIDs.contains(UUID(uuidString: "00000000-0000-0000-0000-000000000001")!))
    }

    func testSuccessfulWorkflowAcknowledgesTheLocalPendingRecord() async {
        let suite = "xiangshang.youth.sync-tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        let state = AppState(featureStore: LocalFeatureStore(defaults: defaults))

        await state.login(phone: "13800138000")
        let succeeded = await state.submitActivityCommand("health-growth-season-2026", contactName: "王女士", phone: "13800138000")
        XCTAssertTrue(succeeded)
        XCTAssertEqual(state.localFeatures.activityRegistrations.first?.status, .submitted)
        XCTAssertEqual(state.pendingSyncCount, 0)
    }

    func testRemoteRepositoryKeepsReportRouteRenderableDuringEndpointRollout() async throws {
        let student = try await MockRepository.shared.loadDashboard().students.first
        XCTAssertNotNil(student)
        guard let student else { return }

        let report = RemoteRepository().report(for: student)
        XCTAssertEqual(report.student.id, student.id)
        XCTAssertEqual(report.scores.count, 7)
        XCTAssertTrue(report.scores.contains { $0.confidence < 0.8 && $0.reviewStatus == .pendingReview })
        XCTAssertTrue(report.scores.filter { $0.confidence >= 0.8 }.allSatisfy { $0.reviewStatus == .passed })
    }

    func testPendingReportDeepLinkSelectsParentAndRequestedStudent() async {
        let suite = "xiangshang.youth.deep-link-tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        let state = AppState(featureStore: LocalFeatureStore(defaults: defaults))
        await state.login(phone: "13800138000")
        XCTAssertTrue(state.bindChild(name: "王小雨", code: "XS-S02"))
        let router = AppRouter()

        router.receiveDeepLink(URL(string: "xiangshang-youth://open?target=report&studentId=s02")!)
        router.activatePendingDeepLink(using: state)

        XCTAssertEqual(state.selectedRole, .parent)
        XCTAssertEqual(state.selectedChild?.id, "s02")
        XCTAssertEqual(router.path.count, 1)
    }

    func testPendingReportDeepLinkCannotSelectUnboundStudent() async {
        let suite = "xiangshang.youth.deep-link-access-tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        let state = AppState(featureStore: LocalFeatureStore(defaults: defaults))
        await state.login(phone: "13800138000")
        let router = AppRouter()

        router.receiveDeepLink(URL(string: "xiangshang-youth://open?target=report&studentId=s03")!)
        router.activatePendingDeepLink(using: state)

        XCTAssertEqual(state.selectedRole, .parent)
        XCTAssertNil(state.selectedChild, "An unbound deep-link student must not become a family child selection.")
        XCTAssertEqual(router.path.count, 1, "An unbound report link should route to child binding instead of a report.")
    }

    func testRouterDeduplicatesRepeatedDestinationAndKeepsBackStackRecoverable() {
        let router = AppRouter()

        router.push(.teacherMessages)
        router.push(.teacherMessages)
        XCTAssertEqual(router.path.count, 1)

        router.pop()
        XCTAssertTrue(router.path.isEmpty)
        router.push(.teacherMessages)
        XCTAssertEqual(router.path.count, 1)
    }

    func testFeatureStoreMigratesStateSavedBeforeReviewNotes() throws {
        let suite = "xiangshang.youth.migration-tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        let original = LocalFeatureState(drafts: ["publish": "已保存的班级动态"], studentTaskStatuses: ["s01": .review])
        let encoded = try JSONEncoder().encode(original)
        var legacy = try XCTUnwrap(try JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        legacy.removeValue(forKey: "reviewNotes")
        legacy.removeValue(forKey: "taskStatusSyncStates")
        defaults.set(try JSONSerialization.data(withJSONObject: legacy), forKey: "xiangshang.local-feature-state.v1")

        let restored = LocalFeatureStore(defaults: defaults).state
        XCTAssertEqual(restored.drafts["publish"], "已保存的班级动态")
        XCTAssertEqual(restored.studentTaskStatuses["s01"], .review)
        XCTAssertTrue(restored.reviewNotes.isEmpty)
        XCTAssertTrue(restored.taskStatusSyncStates.isEmpty)
    }

    func testAppStateRestoresSavedSessionBeforeDashboardRefresh() async {
        let suite = "xiangshang.youth.session-tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        let first = AppState(featureStore: LocalFeatureStore(defaults: defaults))
        await first.login(phone: "13800138000")
        if let second = first.data?.students.first(where: { $0.id == "s02" }) { first.selectChild(second) }
        first.selectRole(.principal)

        let restored = AppState(featureStore: LocalFeatureStore(defaults: defaults))
        XCTAssertEqual(restored.profile?.name, "周校长")
        XCTAssertNil(restored.selectedRole, "A restored session must return to role selection instead of locking the last role.")
        XCTAssertEqual(restored.localFeatures.selectedChildID, "s02")
        XCTAssertTrue(restored.restoringSession, "Session restoration must be visible synchronously so the launch poster cannot transition to a half-restored role screen.")
    }

    func testSessionRestoreFailureReturnsToLoginWithRetryableError() async throws {
        let suite = "xiangshang.youth.restore-failure-tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        let store = LocalFeatureStore(defaults: defaults)
        store.update { value in
            value.sessionProfile = UserProfile(id: "u1", name: "王女士", phone: "13800138000", role: .parent, schoolName: "向上实验小学", avatarInitials: "王")
            value.sessionRole = .principal
        }

        let state = AppState(repository: FailingRepository(), featureStore: store)
        for _ in 0..<40 {
            if state.error != nil || state.profile == nil { break }
            try await Task.sleep(for: .milliseconds(10))
        }

        XCTAssertNil(state.profile)
        XCTAssertNil(state.selectedRole)
        XCTAssertNil(state.data)
        XCTAssertNotNil(state.error)
        state.clearError()
        XCTAssertNil(state.error)
        XCTAssertNil(LocalFeatureStore(defaults: defaults).state.sessionProfile)
    }

    func testMessageReadStatePersistsAndUpdatesUnreadCount() async {
        let suite = "xiangshang.youth.message-tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        let state = AppState(featureStore: LocalFeatureStore(defaults: defaults))
        await state.login(phone: "13800138000")

        XCTAssertEqual(state.unreadMessageCount, 1)
        state.markMessageRead("m1")
        XCTAssertEqual(state.unreadMessageCount, 0)
        XCTAssertTrue(LocalFeatureStore(defaults: defaults).state.readMessageIDs.contains("m1"))
        state.markAllMessagesRead()
        XCTAssertTrue(Set(state.data?.messages.map(\.id) ?? []).isSubset(of: LocalFeatureStore(defaults: defaults).state.readMessageIDs))
    }

    func testNotificationsSettingSuppressesUnreadBadgeWithoutDeletingMessages() async {
        let suite = "xiangshang.youth.notification-setting-tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        let state = AppState(featureStore: LocalFeatureStore(defaults: defaults))
        await state.login(phone: "13800138000")

        XCTAssertEqual(state.unreadMessageCount, 1)
        state.updateSettings(notificationsEnabled: false)
        XCTAssertEqual(state.unreadMessageCount, 0)
        XCTAssertEqual(state.data?.messages.count, 6)
        state.updateSettings(notificationsEnabled: true)
        XCTAssertEqual(state.unreadMessageCount, 1)
    }

    func testFamilyBindingRequiresMatchingNameAndSchoolCode() async {
        let suite = "xiangshang.youth.binding-tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        let state = AppState(featureStore: LocalFeatureStore(defaults: defaults))
        await state.login(phone: "13800138000")

        XCTAssertFalse(state.bindChild(name: "王小明", code: "wrong-code"))
        XCTAssertFalse(state.bindChild(name: "其他学生", code: "XS-S01"))
        XCTAssertTrue(state.bindChild(name: "王小明", code: "XS-S01"))
        XCTAssertEqual(state.selectedChild?.id, "s01")
        XCTAssertEqual(state.boundChildren.map(\.id), ["s01"])
        XCTAssertTrue(state.bindChild(name: "王小雨", code: "s02"))
        XCTAssertEqual(Set(state.boundChildren.map(\.id)), ["s01", "s02"])
    }

    func testExpertBookingIsIdempotentUntilRemoteSync() async {
        let suite = "xiangshang.youth.expert-idempotency-tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        let state = AppState(featureStore: LocalFeatureStore(defaults: defaults))
        await state.login(phone: "13800138000")

        state.bookExpert(name: "张教授", preferredDate: "周五上午", note: "运动发展咨询")
        state.bookExpert(name: "张教授", preferredDate: "周五上午", note: "运动发展咨询")

        XCTAssertEqual(state.localFeatures.expertAppointments.count, 1)
        XCTAssertEqual(state.localFeatures.expertAppointments.first?.status, .pendingSync)
    }

    func testMockWorkflowCommandsExposeTerminalSuccessAndValidationStates() async {
        let suite = "xiangshang.youth.workflow-command-tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        let state = AppState(repository: MockRepository.shared, featureStore: LocalFeatureStore(defaults: defaults))
        await state.login(phone: "13800138000")

        let activityResult = await state.submitActivityCommand("health-growth-season-2026", contactName: "王女士", phone: "13800138000")
        XCTAssertTrue(activityResult)
        if case .succeeded = state.workflowState(for: "activity:health-growth-season-2026") {} else { XCTFail("Mock activity command should reach succeeded") }

        let invalidActivityResult = await state.submitActivityCommand("health-growth-season-2026", contactName: "", phone: "123")
        XCTAssertFalse(invalidActivityResult)
        if case .failed = state.workflowState(for: "activity:health-growth-season-2026") {} else { XCTFail("Invalid activity command should expose failure") }

        let statusResult = await state.submitTaskStatusCommand(studentID: "s01", status: .review, note: "请核验动作视频")
        XCTAssertTrue(statusResult)
        if case .succeeded = state.workflowState(for: "task-status:s01") {} else { XCTFail("Mock task status command should reach succeeded") }
        XCTAssertEqual(state.taskStatus(for: state.data!.students[0]), .review)
        XCTAssertEqual(state.localFeatures.taskStatusSyncStates["s01"], .submitted)
    }

    func testFailedTeacherStatusUpdateRemainsPersistedForRetry() async throws {
        let suite = "xiangshang.youth.task-status-retry-tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        let state = AppState(repository: TaskStatusFailingRepository(), featureStore: LocalFeatureStore(defaults: defaults))
        await state.login(phone: "13800138000")
        let student = try XCTUnwrap(state.data?.students.first(where: { $0.id == "s06" }))

        let succeeded = await state.submitTaskStatusCommand(studentID: student.id, status: .checkedIn, note: "已到场")

        XCTAssertFalse(succeeded)
        XCTAssertEqual(state.taskStatus(for: student), .checkedIn)
        XCTAssertEqual(state.localFeatures.taskStatusSyncStates[student.id], .failed)
        XCTAssertEqual(state.pendingSyncCount, 1)
        if case .failed = state.workflowState(for: "task-status:\(student.id)") {} else { XCTFail("Failed task updates must expose a retryable command state") }
    }

    func testPendingSyncCountExposesUnacknowledgedLocalWrites() {
        let suite = "xiangshang.youth.pending-count-tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        let store = LocalFeatureStore(defaults: defaults)
        let state = AppState(featureStore: store)

        state.registerActivity("health-growth-season-2026", contactName: "王女士", phone: "13800138000")
        state.bookExpert(name: "张教授", preferredDate: "周五上午", note: "运动发展咨询")
        state.saveCourseUpload(taskID: "after-class-upload", attendanceCount: 20, notes: "课堂记录", attachmentName: "课堂.jpg", submit: true)
        store.update { value in value.taskStatusSyncStates["s01"] = .pendingSync }
        let reloaded = AppState(featureStore: store)

        XCTAssertEqual(reloaded.pendingSyncCount, 4)
    }

    func testUnauthorizedReportRefreshExpiresTheLocalSession() async throws {
        let suite = "xiangshang.youth.unauthorized-report-tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        let state = AppState(repository: UnauthorizedRepository(), featureStore: LocalFeatureStore(defaults: defaults))
        await state.login(phone: "13800138000")
        let student = try XCTUnwrap(state.data?.students.first)

        await state.refreshReport(for: student)

        XCTAssertNil(state.profile)
        XCTAssertNil(state.data)
        XCTAssertNotNil(state.error)
        XCTAssertNil(LocalFeatureStore(defaults: defaults).state.sessionProfile)
    }

    func testUnauthorizedWorkflowExpiresTheLocalSession() async {
        let suite = "xiangshang.youth.unauthorized-workflow-tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        let state = AppState(repository: UnauthorizedRepository(), featureStore: LocalFeatureStore(defaults: defaults))
        await state.login(phone: "13800138000")

        let submitted = await state.submitActivityCommand("health-growth-season-2026", contactName: "王女士", phone: "13800138000")

        XCTAssertFalse(submitted)
        XCTAssertNil(state.profile)
        XCTAssertNil(state.data)
        XCTAssertNotNil(state.error)
        XCTAssertNil(LocalFeatureStore(defaults: defaults).state.sessionProfile)
    }
}

private struct FailingRepository: YouthRepository {
    func loadDashboard() async throws -> DashboardData { throw ApiError.network }
    func report(for student: Student) -> DiagnosisReport { MockRepository.shared.report(for: student) }
}

private struct UnauthorizedRepository: YouthRepository {
    func loadDashboard() async throws -> DashboardData { try await MockRepository.shared.loadDashboard() }
    func report(for student: Student) -> DiagnosisReport { MockRepository.shared.report(for: student) }
    func loadReport(for student: Student) async throws -> DiagnosisReport { throw ApiError.unauthorized }
    func submitActivity(_ value: ActivityRegistration) async throws { throw ApiError.unauthorized }
}

private struct TaskStatusFailingRepository: YouthRepository {
    func loadDashboard() async throws -> DashboardData { try await MockRepository.shared.loadDashboard() }
    func report(for student: Student) -> DiagnosisReport { MockRepository.shared.report(for: student) }
    func updateTaskStatus(studentID: String, status: TaskStatus, note: String?) async throws { throw ApiError.network }
}
