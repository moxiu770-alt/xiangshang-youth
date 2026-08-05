import XCTest
@testable import XiangshangYouth

@MainActor
final class LocalFeatureStateTests: XCTestCase {
    func testMockDashboardMatchesPhaseOneDataContract() async throws {
        let data = try await MockRepository.shared.loadDashboard()
        XCTAssertEqual(data.students.count, 20)
        XCTAssertEqual(data.classes.count, 6)
        XCTAssertEqual(data.grades.count, 3)
        XCTAssertEqual(data.tasks.count, 3)
        XCTAssertEqual(data.parentChildren.count, 2)
        XCTAssertEqual(data.tasks.first?.items.count, 7)
        XCTAssertEqual(data.students.first?.id, "s01")
        XCTAssertEqual(data.students.dropFirst().first?.id, "s02")
        XCTAssertTrue(data.students.contains(where: \.isPovertyArea))
    }

    func testLoginRoleSwitchAndTaskStatusAreKeptInAppState() async {
        let suite = "xiangshang.youth.login-tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        let state = AppState(featureStore: LocalFeatureStore(defaults: defaults))

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

    func testFeatureStorePersistsCommercialWorkflowRecords() {
        let suite = "xiangshang.youth.tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        let store = LocalFeatureStore(defaults: defaults)

        store.update { value in
            value.registeredActivities.insert("health-growth-season-2026")
            value.activityRegistrations.append(ActivityRegistration(id: UUID(), activityID: "health-growth-season-2026", contactName: "王女士", phone: "13800138000", status: .submitted, createdAt: .now))
            value.drafts["assessment-s01-fitness-0"] = "身高132cm，体重30kg"
            value.expertAppointments.append(ExpertAppointment(id: UUID(), expertName: "张教授", preferredDate: "周五上午", note: "运动发展咨询", status: .submitted, createdAt: .now))
            value.courseUploads.append(CourseUploadRecord(id: UUID(), taskID: "after-class-upload", attendanceCount: 26, notes: "已完成课程", attachmentName: "课堂.jpg", status: .submitted, createdAt: .now))
            value.studentTaskStatuses["s01"] = .review
            value.reviewNotes["s01"] = "核验视频后建议周五补测。"
            value.settings.reduceMotion = true
            let postID = UUID()
            value.likedClassPostIDs.insert(postID)
            value.classPostComments.append(ClassPostComment(id: UUID(), postID: postID, author: "王女士", text: "继续加油", createdAt: .now))
        }

        let restored = LocalFeatureStore(defaults: defaults).state
        XCTAssertTrue(restored.registeredActivities.contains("health-growth-season-2026"))
        XCTAssertEqual(restored.activityRegistrations.first?.contactName, "王女士")
        XCTAssertEqual(restored.drafts["assessment-s01-fitness-0"], "身高132cm，体重30kg")
        XCTAssertEqual(restored.expertAppointments.first?.status, .submitted)
        XCTAssertEqual(restored.courseUploads.first?.attachmentName, "课堂.jpg")
        XCTAssertEqual(restored.studentTaskStatuses["s01"], .review)
        XCTAssertEqual(restored.reviewNotes["s01"], "核验视频后建议周五补测。")
        XCTAssertTrue(restored.settings.reduceMotion)
        XCTAssertEqual(restored.classPostComments.first?.text, "继续加油")
        XCTAssertEqual(restored.likedClassPostIDs.count, 1)
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
        let router = AppRouter()

        router.receiveDeepLink(URL(string: "xiangshang-youth://open?target=report&studentId=s02")!)
        router.activatePendingDeepLink(using: state)

        XCTAssertEqual(state.selectedRole, .parent)
        XCTAssertEqual(state.selectedChild?.id, "s02")
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
        defaults.set(try JSONSerialization.data(withJSONObject: legacy), forKey: "xiangshang.local-feature-state.v1")

        let restored = LocalFeatureStore(defaults: defaults).state
        XCTAssertEqual(restored.drafts["publish"], "已保存的班级动态")
        XCTAssertEqual(restored.studentTaskStatuses["s01"], .review)
        XCTAssertTrue(restored.reviewNotes.isEmpty)
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
}

private struct FailingRepository: YouthRepository {
    func loadDashboard() async throws -> DashboardData { throw ApiError.network }
    func report(for student: Student) -> DiagnosisReport { MockRepository.shared.report(for: student) }
}
