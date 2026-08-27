import XCTest
@testable import XiangshangYouth

private final class IncompleteRemoteRepository: YouthRepository {
    let supportsRemoteAcknowledgement = true
    func loadDashboard() async throws -> DashboardData { try await MockRepository.shared.loadDashboard() }
    func report(for student: Student) -> DiagnosisReport { MockRepository.shared.report(for: student) }
}

@MainActor
final class LocalFeatureStateTests: XCTestCase {
    private func authorizeTeacherFixture(_ state: AppState) {
        state.profile = UserProfile(
            id: "teacher-test", name: "测试教师", phone: "13800138000", role: .teacher,
            schoolName: "向上实验小学", avatarInitials: "教",
            authorizedClassIDs: ["c31", "c32"],
            capabilities: ["VIEW_CLASS_DASHBOARD", "VIEW_TEST_TASKS", "UPDATE_TEST_STATUS", "REVIEW_RESULT", "REQUEST_RETEST"]
        )
        state.selectedRole = .teacher
    }

    func testLegalPolicyVersionsAreConcreteAndCameraWordingMatchesLocalProcessing() {
        XCTAssertNotEqual(LegalPolicy.privacyPolicyVersion, "v1")
        XCTAssertNotEqual(LegalPolicy.cameraConsentVersion, "v1")
        XCTAssertTrue(LegalDocument.privacy.content.contains("不保存原始照片或视频"))
        XCTAssertTrue(LegalDocument.userAgreement.content.hasPrefix("向上少年身心健康用户服务协议"))
        XCTAssertTrue(LegalDocument.userAgreement.content.contains("十八、联系我们"))
        XCTAssertTrue(LegalDocument.childPrivacy.content.hasPrefix("向上少年身心健康儿童个人信息保护声明"))
        XCTAssertTrue(LegalDocument.childPrivacy.content.contains("十、联系我们"))
        XCTAssertTrue(LegalDocument.childPrivacy.content.contains("不保存身份证照片及人脸原始图像"))
        XCTAssertFalse(LegalDocument.childPrivacy.content.contains("原始影像按学校配置"))
        XCTAssertTrue(LegalDocument.privacy.content.contains("发送匿名使用情况"))
    }

    func testProductEventContractContainsNoIdentityOrHealthFields() throws {
        XCTAssertFalse(LocalAppSettings().analyticsEnabled)
        let event = ProductEventInput(
            eventID: UUID(uuidString: "11111111-1111-4111-8111-111111111111")!,
            eventName: FrontendEvent.growthReportOpened.rawValue,
            coarseValue: "本周", platform: "ios", appVersion: "1.0",
            clientSessionID: UUID(uuidString: "22222222-2222-4222-8222-222222222222")!,
            occurredAt: "2026-08-26T08:00:00Z"
        )
        let json = String(decoding: try JSONEncoder().encode(event), as: UTF8.self)
        XCTAssertTrue(json.contains("clientSessionId"))
        XCTAssertFalse(json.contains("childId"))
        XCTAssertFalse(json.contains("studentId"))
        XCTAssertFalse(json.contains("userId"))
        XCTAssertFalse(json.contains("health"))
    }
    func testWriteFingerprintIsDeterministicAndContentSensitive() {
        XCTAssertEqual(StableWriteFingerprint.make("内容举报"), StableWriteFingerprint.make("内容举报"))
        XCTAssertNotEqual(StableWriteFingerprint.make("内容举报"), StableWriteFingerprint.make("其他原因"))
        XCTAssertEqual(StableWriteFingerprint.make("hello"), "a430d84680aabd0b")
    }
    func testMissingRemoteEnvelopePayloadIsNotRenderedAsEmptyContent() throws {
        let missing = #"{"code":"OK","message":"ok"}"#.data(using: .utf8)!
        XCTAssertThrowsError(try ApiClient.decodePayload(missing, type: [String].self)) { error in
            guard case ApiError.invalidResponse = error else {
                return XCTFail("Expected invalid response, got \(error)")
            }
        }
        let empty = #"{"code":"OK","message":"ok","data":[]}"#.data(using: .utf8)!
        XCTAssertEqual(try ApiClient.decodePayload(empty, type: [String].self), [])
    }

    func testIncompleteRemoteRepositoryCannotUseMockOnlyDefaults() async {
        do {
            _ = try await IncompleteRemoteRepository().loadActivities()
            XCTFail("Remote defaults must not return bundled activities")
        } catch let error as ApiError {
            guard case .notConfigured = error else {
                return XCTFail("Expected notConfigured, got \(error)")
            }
        } catch {
            XCTFail("Expected notConfigured, got \(error)")
        }
    }

    func testRemoteGuardianBindingsPopulateANewDeviceWithoutLocalBindingCache() async throws {
        let suite = "xiangshang.youth.remote-child-scope.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defaults.removePersistentDomain(forName: suite)
        let state = AppState(
            repository: IncompleteRemoteRepository(),
            featureStore: LocalFeatureStore(defaults: defaults)
        )
        let dashboard = try await MockRepository.shared.loadDashboard()
        state.profile = UserProfile(
            id: "remote-parent", name: "远程家长", phone: "13800000000", role: .parent,
            schoolName: dashboard.school.name, avatarInitials: "家"
        )
        state.data = dashboard

        XCTAssertTrue(state.localFeatures.boundChildIDs.isEmpty)
        state.reconcileSelectedChildFromDashboard()

        let serverChildIDs = Set(dashboard.parentChildren.map(\.student.id))
        XCTAssertEqual(state.localFeatures.boundChildIDs, serverChildIDs)
        XCTAssertEqual(state.selectedChild?.id, dashboard.parentChildren.first?.student.id)
        XCTAssertEqual(Set(state.boundChildren.map(\.id)), serverChildIDs)
    }

    func testTeacherOverviewContextRejectsAStaleClassOrTaskResponse() {
        let current = TeacherOverviewContext(schoolID: "school-a", classID: "class-a", taskID: "task-a", standardVersion: "standard-v1")
        XCTAssertNotEqual(current, TeacherOverviewContext(schoolID: "school-b", classID: "class-a", taskID: "task-a", standardVersion: "standard-v1"))
        XCTAssertNotEqual(current, TeacherOverviewContext(schoolID: "school-a", classID: "class-b", taskID: "task-a", standardVersion: "standard-v1"))
        XCTAssertNotEqual(current, TeacherOverviewContext(schoolID: "school-a", classID: "class-a", taskID: "task-b", standardVersion: "standard-v1"))
        XCTAssertNotEqual(current, TeacherOverviewContext(schoolID: "school-a", classID: "class-a", taskID: "task-a", standardVersion: "standard-v2"))
    }

    func testRemoteTaskStatusRequiresCompositeTaskIdentity() async {
        do {
            _ = try await RemoteRepository().updateTaskStatus(taskID: "", studentID: "student-1", status: .checkedIn, note: nil, expectedVersion: 1)
            XCTFail("A remote task status write must require a task ID")
        } catch let ApiError.message(message) {
            XCTAssertTrue(message.contains("任务编号"))
        } catch {
            XCTFail("Expected missing-task error, got \(error)")
        }
    }

    func testReportCourseSuggestionDecodesStableCourseAndLessonIDs() throws {
        let payload = #"{"id":"suggestion-1","courseId":"course-1","lessonId":"lesson-1","title":"协调训练","duration":"12分钟","focus":"平衡","isPublicBenefit":true}"#.data(using: .utf8)!
        let suggestion = try JSONDecoder().decode(CourseSuggestion.self, from: payload)

        XCTAssertEqual(suggestion.courseID, "course-1")
        XCTAssertEqual(suggestion.lessonID, "lesson-1")
        XCTAssertNotEqual(
            CourseRecommendationTarget(childID: "child-a", courseID: suggestion.courseID, lessonID: suggestion.lessonID, title: suggestion.title),
            CourseRecommendationTarget(childID: "child-b", courseID: suggestion.courseID, lessonID: suggestion.lessonID, title: suggestion.title)
        )
    }

    func testStudentClassScopeDecodesFromStableClassID() throws {
        let payload = #"{"id":"student-1","name":"同学","gender":"男","grade":"三年级","className":"三年级1班","classId":"c31","region":"南湖区","isPovertyArea":false,"taskStatus":"已完成","totalScore":30}"#.data(using: .utf8)!
        XCTAssertEqual(try JSONDecoder().decode(Student.self, from: payload).classID, "c31")
    }

    func testTeacherTaskScopeRejectsStudentsOutsideAuthorizedClassIDs() async throws {
        let base = MockRepository.shared
        let defaults = UserDefaults(suiteName: "xiangshang.teacher-task-scope-test")!
        defaults.removePersistentDomain(forName: "xiangshang.teacher-task-scope-test")
        let state = AppState(repository: base, featureStore: LocalFeatureStore(defaults: defaults))
        state.data = try await base.loadDashboard()
        state.profile = UserProfile(id: "teacher-scope", name: "同名教师", phone: "13800138000", role: .teacher, schoolName: base.school.name, avatarInitials: "教", authorizedClassIDs: ["c31"])
        state.selectedRole = .teacher

        XCTAssertTrue(state.canManageTaskStudent(try XCTUnwrap(state.data?.students.first(where: { $0.classID == "c31" }))))
        XCTAssertFalse(state.canManageTaskStudent(try XCTUnwrap(state.data?.students.first(where: { $0.classID == "c32" }))))
    }

    func testStudentAndLocalStateCarryServerTaskVersionForConflictSafeEdits() {
        let student = Student(id: "s-version", name: "测试学生", gender: "男", grade: "三年级", className: "三年级1班", region: "南湖区", isPovertyArea: false, taskStatus: .checkedIn, totalScore: nil, birthDate: "2017-01-01", taskVersion: 7)
        var local = LocalFeatureState()
        local.taskScopedStatusVersions["t1|\(student.id)"] = student.taskVersion

        XCTAssertEqual(student.taskVersion, 7)
        XCTAssertEqual(local.taskScopedStatusVersions["t1|\(student.id)"], 7)
    }

    func testMobileRolePickerOnlyExposesParentAndTeacherWorkbenches() {
        XCTAssertEqual(UserRole.mobileRoles, [.parent, .teacher])
        XCTAssertFalse(UserRole.mobileRoles.contains(.principal))
    }

    func testPublishedReportGateScopesThePublishedBatchToTheStudent() {
        let base = MockRepository.shared
        let fourthGradeStudent = Student(id: "fourth", name: "四年级学生", gender: "男", grade: "四年级", className: "四年级1班", region: base.school.region, isPovertyArea: false, taskStatus: .completed, totalScore: 30, birthDate: "2016-01-01", classID: "c41")
        let fifthGradeStudent = Student(id: "fifth", name: "五年级学生", gender: "女", grade: "五年级", className: "五年级1班", region: base.school.region, isPovertyArea: false, taskStatus: .completed, totalScore: 30, birthDate: "2015-01-01", classID: "c51")
        let sourceTask = base.tasks.first { $0.id == "t2" }!
        // This fixture deliberately exercises the stable class scope path; a
        // production response normally includes studentIds as well.
        let task = TestTask(id: sourceTask.id, title: sourceTask.title, date: sourceTask.date, location: sourceTask.location, gradeName: sourceTask.gradeName, className: sourceTask.className, items: sourceTask.items, completedCount: sourceTask.completedCount, totalCount: sourceTask.totalCount, status: sourceTask.status, ruleVersion: sourceTask.ruleVersion, classIDs: ["c41"], studentIDs: [])
        let dashboard = DashboardData(school: base.school, students: [fourthGradeStudent, fifthGradeStudent], classes: base.classes, grades: base.grades, tasks: [task], parentChildren: [], messages: [])
        let defaults = UserDefaults(suiteName: "xiangshang.report-gate-test")!
        defaults.removePersistentDomain(forName: "xiangshang.report-gate-test")
        let state = AppState(repository: base, featureStore: LocalFeatureStore(defaults: defaults))
        state.data = dashboard

        XCTAssertTrue(state.hasPublishedSchoolReport(for: fourthGradeStudent))
        XCTAssertFalse(state.hasPublishedSchoolReport(for: fifthGradeStudent))
    }

    func testMessageCenterRouteIsScopedToTheActiveRole() {
        XCTAssertEqual(AppRoute.messageCenter(for: .parent), .parentMessages)
        XCTAssertEqual(AppRoute.messageCenter(for: .teacher), .teacherMessages)
        XCTAssertEqual(AppRoute.messageCenter(for: .principal), .notifications)
        XCTAssertEqual(AppRoute.messageCenter(for: nil), .notifications)
    }

    func testMessageCourseTargetPreservesStableBusinessIDs() {
        let defaults = UserDefaults(suiteName: "xiangshang.message-course-target-test")!
        defaults.removePersistentDomain(forName: "xiangshang.message-course-target-test")
        let state = AppState(repository: MockRepository.shared, featureStore: LocalFeatureStore(defaults: defaults))

        state.openCourseTarget(for: "s01", courseID: "course-1", lessonID: "lesson-1", title: "开始训练")

        XCTAssertEqual(state.courseRecommendationTarget, CourseRecommendationTarget(childID: "s01", courseID: "course-1", lessonID: "lesson-1", title: "开始训练"))
    }

    func testDeepLinkNeverGrantsAnUnavailableRole() {
        XCTAssertFalse(DeepLinkAuthorization.isAuthorized(target: "report", remote: false, availableRoles: []))
        XCTAssertFalse(DeepLinkAuthorization.isAuthorized(target: "report", remote: true, availableRoles: [.teacher]))
        XCTAssertTrue(DeepLinkAuthorization.isAuthorized(target: "report", remote: true, availableRoles: [.parent]))
        XCTAssertFalse(DeepLinkAuthorization.isAuthorized(target: "review", remote: true, availableRoles: [.parent]))
        XCTAssertTrue(DeepLinkAuthorization.isAuthorized(target: "tasks", remote: true, availableRoles: [.teacher]))
        XCTAssertFalse(DeepLinkAuthorization.isAuthorized(target: "risk", remote: true, availableRoles: [.teacher]))
        XCTAssertTrue(DeepLinkAuthorization.isAuthorized(target: "risk", remote: true, availableRoles: [.principal]))
    }

    func testBodyBMIUsesOfficialHalfYearThresholdAndDoesNotUseAdultCutoffs() {
        let obese = BodyAssessmentRecord(heightCentimeters: 100, weightKilograms: 18.7, measuredAt: .now, ruleVersion: BodyAssessmentRecord.ruleVersion, completedCaptures: Set(BodyAssessmentRecord.CaptureTask.allCases), parentMarkedAsymmetric: false, parentMarkedGaitConcern: false, savedAt: .now, nextFollowUpDate: .now, completedPlanDays: [])
        let overweight = BodyAssessmentRecord(heightCentimeters: 100, weightKilograms: 17.0, measuredAt: .now, ruleVersion: BodyAssessmentRecord.ruleVersion, completedCaptures: Set(BodyAssessmentRecord.CaptureTask.allCases), parentMarkedAsymmetric: false, parentMarkedGaitConcern: false, savedAt: .now, nextFollowUpDate: .now, completedPlanDays: [])

        // Boy aged 7.0 (84 months): WS/T 586—2018 is 17.0 / 18.7.
        XCTAssertEqual(obese.bmiAttention(ageMonths: 84, gender: "男"), .red)
        XCTAssertEqual(overweight.bmiAttention(ageMonths: 84, gender: "男"), .yellow)
        XCTAssertEqual(overweight.bmiAttention(ageMonths: nil, gender: "男"), .unavailable)
        XCTAssertEqual(overweight.bmiScreeningLabel(ageMonths: 84, gender: "男"), "超重筛查关注")
        XCTAssertEqual(overweight.attention(ageMonths: 84, gender: "男").label, "建议关注")

        // 75 months uses the completed 72-month row; the standard does not
        // define a synthetic interpolated threshold.
        let halfYearYellow = BodyAssessmentRecord(heightCentimeters: 100, weightKilograms: 16.5, measuredAt: .now, ruleVersion: BodyAssessmentRecord.ruleVersion, completedCaptures: Set(BodyAssessmentRecord.CaptureTask.allCases), parentMarkedAsymmetric: false, parentMarkedGaitConcern: false, savedAt: .now, nextFollowUpDate: .now, completedPlanDays: [])
        XCTAssertEqual(halfYearYellow.bmiAttention(ageMonths: 75, gender: "男"), .yellow)
        XCTAssertEqual(halfYearYellow.bmiAttention(ageMonths: 72, gender: "男"), .yellow)
        let halfYearGreen = BodyAssessmentRecord(heightCentimeters: 100, weightKilograms: 16.3, measuredAt: .now, ruleVersion: BodyAssessmentRecord.ruleVersion, completedCaptures: Set(BodyAssessmentRecord.CaptureTask.allCases), parentMarkedAsymmetric: false, parentMarkedGaitConcern: false, savedAt: .now, nextFollowUpDate: .now, completedPlanDays: [])
        XCTAssertEqual(halfYearGreen.bmiAttention(ageMonths: 75, gender: "男"), .green)
        XCTAssertEqual(halfYearGreen.bmiAttention(ageMonths: 217, gender: "男"), .unavailable)
        XCTAssertEqual(halfYearGreen.bmiAttention(ageMonths: 75, gender: "male"), .green)
        XCTAssertEqual(halfYearYellow.bmiAttention(ageMonths: 75, gender: "F"), .yellow)
    }

    func testMalformedInfiniteMeasurementsFailSafeToUnavailable() {
        let malformed = BodyAssessmentRecord(heightCentimeters: .infinity, weightKilograms: 45, measuredAt: .now, ruleVersion: BodyAssessmentRecord.ruleVersion, completedCaptures: [], parentMarkedAsymmetric: false, parentMarkedGaitConcern: false, savedAt: .now, nextFollowUpDate: .now, completedPlanDays: [])
        XCTAssertEqual(malformed.bmi, 0)
        XCTAssertEqual(malformed.bmiAttention(ageMonths: 120, gender: "女"), .unavailable)
        XCTAssertNil(malformed.heightDevelopmentAssessment(ageMonths: 120, gender: "女"))
        XCTAssertEqual(BodyAssessmentRecord(heightCentimeters: 40, weightKilograms: 8, measuredAt: .now, ruleVersion: BodyAssessmentRecord.ruleVersion, completedCaptures: [], parentMarkedAsymmetric: false, parentMarkedGaitConcern: false, savedAt: .now, nextFollowUpDate: .now, completedPlanDays: []).bmi, 0)
        XCTAssertNil(BodyAssessmentRecord(heightCentimeters: 40, weightKilograms: 20, measuredAt: .now, ruleVersion: BodyAssessmentRecord.ruleVersion, completedCaptures: [], parentMarkedAsymmetric: false, parentMarkedGaitConcern: false, savedAt: .now, nextFollowUpDate: .now, completedPlanDays: []).heightDevelopmentAssessment(ageMonths: 108, gender: "男"))
    }

    func testPostureScoringProfilesAreNormalizedAndVersioned() {
        for age in [72, 108, 156, 192] {
            let profile = PostureScreeningRules.profile(ageMonths: age)
            let weightTotal = profile.weightedShoulder + profile.weightedPelvis + profile.weightedSpinalMidline + profile.weightedThoracicRounding + profile.weightedForwardHead + profile.weightedAdams + profile.weightedGait
            XCTAssertEqual(weightTotal, PostureScreeningRules.scoringWeightTotal, accuracy: 0.0001)
            XCTAssertLessThan(profile.yellowScore, profile.redScore)
        }
        XCTAssertEqual(PostureAssessmentReport.algorithmVersion, "UY-IMCA-CV-1.3")
        XCTAssertEqual(PostureAssessmentReport.calibrationVersion, "UY-CAL-BASELINE-1.0")
        XCTAssertEqual(AssessmentScoreRules.modelRegistryVersion, "UY-MODELS-1.0")
        XCTAssertEqual(AssessmentScoreRules.algorithmVersion, "UY-IMCA-SCORE-1.3")
        XCTAssertEqual(BodyAssessmentRecord.bmiAlgorithmVersion, "UY-IMCA-BMI-1.2")
        XCTAssertEqual(BodyAssessmentRecord.heightAlgorithmVersion, "UY-IMCA-HEIGHT-1.0")
        XCTAssertEqual(ChildFollowAlongTuning.algorithmVersion, "UY-FOLLOW-CV-1.0")
        XCTAssertEqual(GrowthInsight.algorithmVersion, "UY-GROWTH-RULE-1.1")
        let report = PostureAssessmentReport.make(snapshots: [:], generatedAt: .now)
        XCTAssertEqual(report.calibrationVersion, PostureAssessmentReport.calibrationVersion)
        XCTAssertEqual(report.rulesSourceVersion, PostureScreeningRules.rulesSourceVersion)
    }

    func testMovementAggregateUsesCanonicalHalfUpRounding() {
        XCTAssertEqual(AssessmentScoreRules.total(20.95), 21.0, accuracy: 0.0001)
        XCTAssertEqual(AssessmentScoreRules.total(.nan), 0, accuracy: 0.0001)
        XCTAssertEqual(AssessmentScoreRules.total(99), AssessmentScoreRules.totalMaximum, accuracy: 0.0001)
    }

    func testUnknownScoreReviewStatusFailsClosedDuringDecode() throws {
        let json = #"{"id":"row","item":"连续双脚障碍跳","score":4,"note":"","confidence":0.99,"reviewStatus":"futureStatus"}"#.data(using: .utf8)!
        let row = try JSONDecoder().decode(ScoreResult.self, from: json)
        XCTAssertEqual(row.reviewStatus, .pendingReview)
    }

    func testPostureProfileBoundaryAndNonFiniteConfidenceCannotPublish() {
        // 15 years (180 months) belongs to the 12–15 profile on both clients;
        // the next profile starts at 181 months.
        XCTAssertEqual(PostureScreeningRules.profile(ageMonths: 180).forwardHeadAttention, 11.5, accuracy: 0.001)
        XCTAssertEqual(PostureScreeningRules.profile(ageMonths: 181).forwardHeadAttention, 11.2, accuracy: 0.001)
        func snapshot(_ task: BodyAssessmentRecord.CaptureTask, confidence: Double) -> PostureMetricSnapshot {
            PostureMetricSnapshot(id: task.rawValue, task: task, sampleCount: 18, confidence: confidence, shoulderHeightDifferenceCm: 0.2, pelvicHeightDifferenceCm: 0.2, headTiltDegrees: 1, spinalMidlineDeviationCm: 0.2, thoracicRoundingDegrees: 10, forwardHeadAngleDegrees: 5, cameraProxyAtrDegrees: 2, cameraProxyRibProminenceCm: 0.2, gaitShoulderSwingDifferenceCm: 0.2, gaitPelvicSwingDifferenceCm: 0.2, gaitTrunkSwayCm: 0.2)
        }
        let snapshots = Dictionary(uniqueKeysWithValues: BodyAssessmentRecord.CaptureTask.allCases.map { ($0, snapshot($0, confidence: 0.82)) })
        var malformed = snapshots
        malformed[.standingBack] = snapshot(.standingBack, confidence: .infinity)
        XCTAssertEqual(PostureAssessmentReport.make(snapshots: malformed, generatedAt: .now).overallLevel, .pending)
    }

    func testRollCorrectionRemovesPhoneTiltFromLevelShoulderLine() throws {
        let angle = Double.pi / 6
        let dx = cos(angle)
        let dy = sin(angle)
        // Both landmarks lie on the camera-roll axis, so their corrected
        // vertical difference must be zero even though raw Y differs.
        let corrected = PostureMetricCalculator.rollCorrectedVerticalDifference(
            firstX: 0,
            firstY: 0,
            secondX: dx,
            secondY: dy,
            axisDx: dx,
            axisDy: dy
        )
        XCTAssertEqual(corrected, 0, accuracy: 0.000001)
        XCTAssertNil(PostureMetricCalculator.centimeters(.infinity, bodyHeightNormalized: 0.4, measuredHeightCm: 140))
        XCTAssertNil(PostureMetricCalculator.centimeters(0.02, bodyHeightNormalized: .nan, measuredHeightCm: 140))
        XCTAssertEqual(try XCTUnwrap(PostureMetricCalculator.range([0.2, 0.4, 0.3])), 0.2, accuracy: 0.000001)
        XCTAssertNil(PostureMetricCalculator.range([.nan, .infinity]))
    }

    func testFollowAlongAgeProfilesAndRequiredJointsAreMonotonic() {
        let child = ChildFollowAlongTuning.profile(ageMonths: 84)
        let junior = ChildFollowAlongTuning.profile(ageMonths: 120)
        let teen = ChildFollowAlongTuning.profile(ageMonths: 180)
        XCTAssertEqual(child.calibrationFrames, 30)
        XCTAssertGreaterThan(child.calibrationFrames, junior.calibrationFrames)
        XCTAssertGreaterThanOrEqual(junior.calibrationFrames, teen.calibrationFrames)
        XCTAssertGreaterThanOrEqual(child.minRepInterval, teen.minRepInterval)
        XCTAssertEqual(ChildFollowAlongTuning.requiredJoints(for: "front_raise").count, 7)
        XCTAssertEqual(ChildFollowAlongTuning.requiredJoints(for: "jumping_jack").count, 9)
    }

    func testFollowAlongActionProfilesUseActionSpecificHysteresis() {
        let age = ChildFollowAlongTuning.profile(ageMonths: 120)
        let jump = ChildFollowAlongTuning.actionProfile(for: "jumping_jack", profile: age)
        let squat = ChildFollowAlongTuning.actionProfile(for: "squat", profile: age)
        XCTAssertGreaterThan(jump.stablePeakFrames, squat.stablePeakFrames)
        XCTAssertGreaterThan(jump.stableReturnFrames, squat.stableReturnFrames)
        XCTAssertGreaterThan(jump.minDropRatio, squat.minDropRatio)
        XCTAssertLessThan(jump.activeGateRatio, squat.activeGateRatio)
    }

    func testFollowAlongMotionMathRejectsOutliersAndBoundsQuality() {
        XCTAssertEqual(FollowAlongMotionMath.trimmedRange([0, 1, 1, 1, 1, 10], trimRatio: 0.18), 0, accuracy: 0.001)
        XCTAssertEqual(FollowAlongMotionMath.robustMean([.nan, 1, 1, 1, 1, 10], trimRatio: 0.20), 1, accuracy: 0.001)
        XCTAssertEqual(FollowAlongMotionMath.qualityScore(confidence: .nan, amplitude: 1, threshold: 1, noise: 0), 0)
        XCTAssertTrue((0...100).contains(FollowAlongMotionMath.qualityScore(confidence: 0.9, amplitude: 0.2, threshold: 0.1, noise: 0.01)))
    }

    func testPostureCaptureGateUsesAgeSpecificQualityProfile() {
        let child = BodyCaptureQualityGate.profile(ageMonths: 84)
        let teen = BodyCaptureQualityGate.profile(ageMonths: 180)
        XCTAssertGreaterThan(child.staticHoldSeconds, teen.staticHoldSeconds)
        XCTAssertGreaterThan(child.staticMaximumDisplacement, teen.staticMaximumDisplacement)
        XCTAssertLessThan(child.minimumIndividualLandmarkConfidence, teen.minimumIndividualLandmarkConfidence)
        XCTAssertGreaterThan(child.gaitMinimumSeconds, teen.gaitMinimumSeconds)
    }

    func testPostureCaptureGateRejectsJitterAndIncompleteGait() {
        let profile = BodyCaptureQualityGate.profile(ageMonths: 120)
        XCTAssertFalse(BodyCaptureQualityGate.isStaticCaptureReady(elapsed: profile.staticHoldSeconds + 0.1, stableFrames: profile.staticMinimumFrames, displacement: profile.staticMaximumDisplacement * 0.4, jitter: profile.staticDisplacementJitter * 1.1, ageMonths: 120))
        XCTAssertTrue(BodyCaptureQualityGate.isStaticCaptureReady(elapsed: profile.staticHoldSeconds + 0.1, stableFrames: profile.staticMinimumFrames, displacement: profile.staticMaximumDisplacement * 0.4, jitter: profile.staticDisplacementJitter * 0.5, ageMonths: 120))
        XCTAssertFalse(BodyCaptureQualityGate.isGaitCaptureReady(elapsed: profile.gaitMinimumSeconds + 0.1, displacement: profile.gaitMinimumDisplacement * 1.2, movedFrames: 1, rawSamples: profile.minimumRawSamplesForCompletion, ageMonths: 120))
        XCTAssertFalse(BodyCaptureQualityGate.isGaitCaptureReady(elapsed: profile.gaitMinimumSeconds + 0.1, displacement: profile.gaitMinimumDisplacement * 1.2, movedFrames: profile.gaitMovementWindowFrames / 2, rawSamples: profile.minimumRawSamplesForCompletion, ageMonths: 120))
        XCTAssertTrue(BodyCaptureQualityGate.isGaitCaptureReady(elapsed: profile.gaitMinimumSeconds + 0.1, displacement: profile.gaitMinimumDisplacement * 1.2, movedFrames: profile.gaitMovementWindowFrames, rawSamples: profile.minimumRawSamplesForCompletion, ageMonths: 120))
        XCTAssertFalse(BodyCaptureQualityGate.isForwardBendCaptureReady(elapsed: profile.staticHoldSeconds + 0.1, stableFrames: profile.staticMinimumFrames, displacement: profile.staticMaximumDisplacement * 0.4, torsoTilt: -0.2))
        XCTAssertFalse(BodyCaptureQualityGate.isForwardBendCaptureReady(elapsed: profile.staticHoldSeconds + 0.1, stableFrames: profile.staticMinimumFrames, displacement: profile.staticMaximumDisplacement * 0.4, torsoTilt: 10.1))
    }

    func testBMIScreensUsingOneDecimalAndRejectsMissingSex() {
        let edge = BodyAssessmentRecord(heightCentimeters: 100, weightKilograms: 16.96, measuredAt: .now, ruleVersion: BodyAssessmentRecord.ruleVersion, completedCaptures: [], parentMarkedAsymmetric: false, parentMarkedGaitConcern: false, savedAt: .now, nextFollowUpDate: .now, completedPlanDays: [])
        XCTAssertEqual(edge.bmiForScreening, 17.0, accuracy: 0.001)
        XCTAssertEqual(edge.bmiAttention(ageMonths: 84, gender: "男"), .yellow)
        XCTAssertEqual(edge.bmiAttention(ageMonths: 84, gender: ""), .unavailable)
        XCTAssertEqual(edge.bmiScreeningLabel(ageMonths: nil, gender: "男"), "待完善出生日期")
        XCTAssertEqual(edge.bmiScreeningLabel(ageMonths: 84, gender: ""), "待完善性别")
    }

    func testHistoricalBodyAssessmentKeepsMeasurementAgeBand() {
        let record = BodyAssessmentRecord(heightCentimeters: 100, weightKilograms: 17.2, measuredAt: .now, ruleVersion: BodyAssessmentRecord.ruleVersion, completedCaptures: [], parentMarkedAsymmetric: false, parentMarkedGaitConcern: false, savedAt: .now, nextFollowUpDate: .now, completedPlanDays: [], ageMonthsAtMeasurement: 84)
        XCTAssertEqual(record.bmiAttention(ageMonths: 90, gender: "男"), .yellow)
        XCTAssertEqual(record.bmiScreeningLabel(ageMonths: 90, gender: "男"), "超重筛查关注")
    }

    func testBirthDateParsingRejectsImpossibleAndFutureDates() {
        let invalid = Student(id: "invalid", name: "测试", gender: "男", grade: "三年级", className: "三年级1班", region: "南湖区", isPovertyArea: false, taskStatus: .completed, totalScore: nil, birthDate: "2026-02-31")
        let future = Student(id: "future", name: "测试", gender: "男", grade: "三年级", className: "三年级1班", region: "南湖区", isPovertyArea: false, taskStatus: .completed, totalScore: nil, birthDate: "2999-01-01")
        let suffix = Student(id: "suffix", name: "测试", gender: "男", grade: "三年级", className: "三年级1班", region: "南湖区", isPovertyArea: false, taskStatus: .completed, totalScore: nil, birthDate: "2018-08-22junk")
        XCTAssertNil(invalid.bodyAssessmentAgeMonths)
        XCTAssertNil(future.bodyAssessmentAgeMonths)
        XCTAssertNil(suffix.bodyAssessmentAgeMonths)
    }

    func testBirthDateAgeUsesChinaCalendarAtMidnightBoundary() throws {
        let formatter = ISO8601DateFormatter()
        let beforeMidnight = try XCTUnwrap(formatter.date(from: "2026-08-22T15:59:00Z"))
        let afterMidnight = try XCTUnwrap(formatter.date(from: "2026-08-22T16:00:00Z"))
        XCTAssertEqual(Student.ageMonths(from: "2018-08-22", now: beforeMidnight), 96)
        XCTAssertEqual(Student.ageMonths(from: "2018-08-23", now: beforeMidnight), 95)
        XCTAssertEqual(Student.ageMonths(from: "2018-08-23", now: afterMidnight), 96)
    }

    func testBodyAssessmentDraftPersistsWithoutRawCameraMedia() {
        let suite = "xiangshang.youth.body-draft-tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        let store = LocalFeatureStore(defaults: defaults)
        let draft = BodyAssessmentDraft(step: 2, heightCentimeters: 133.5, weightKilograms: 31.2, completedCaptures: [.standingBack, .seatedPosture], parentMarkedAsymmetric: false, parentMarkedGaitConcern: false, visualObservationHint: "请由家长确认画面对齐提示。", captureObservationHints: [.standingBack: "站姿提示", .seatedPosture: "坐姿提示"])

        store.update { $0.bodyAssessmentDrafts["s01"] = draft }

        let restored = LocalFeatureStore(defaults: defaults).state.bodyAssessmentDrafts["s01"]
        XCTAssertEqual(restored, draft)
        XCTAssertEqual(restored?.captureObservationHints[.standingBack], "站姿提示")
        XCTAssertEqual(restored?.captureObservationHints[.seatedPosture], "坐姿提示")
    }

    func testBMIAndGeneticHeightUseFamilyFormula() throws {
        let record = BodyAssessmentRecord(heightCentimeters: 150, weightKilograms: 45, measuredAt: .now, ruleVersion: BodyAssessmentRecord.ruleVersion, completedCaptures: [], parentMarkedAsymmetric: false, parentMarkedGaitConcern: false, fatherHeightCentimeters: 178, motherHeightCentimeters: 162, savedAt: .now, nextFollowUpDate: .now, completedPlanDays: [])

        XCTAssertEqual(record.bmi, 20, accuracy: 0.001)
        XCTAssertEqual(try XCTUnwrap(record.geneticHeightReference(gender: "男")), 176.5, accuracy: 0.001)
        XCTAssertEqual(try XCTUnwrap(record.geneticHeightReference(gender: "女")), 163.5, accuracy: 0.001)
        XCTAssertEqual(try XCTUnwrap(record.geneticHeightReference(gender: "male")), 176.5, accuracy: 0.001)
        let range = try XCTUnwrap(record.geneticHeightRange(gender: "男"))
        XCTAssertEqual(range.lowerBound, 171.5, accuracy: 0.001)
        XCTAssertEqual(range.upperBound, 181.5, accuracy: 0.001)
        XCTAssertNil(record.geneticHeightReference(gender: ""))
        XCTAssertEqual(record.geneticHeightFormula(gender: ""), "待完善孩子性别后计算")
        let invalidParents = BodyAssessmentRecord(heightCentimeters: 150, weightKilograms: 45, measuredAt: .now, ruleVersion: BodyAssessmentRecord.ruleVersion, completedCaptures: [], parentMarkedAsymmetric: false, parentMarkedGaitConcern: false, fatherHeightCentimeters: 90, motherHeightCentimeters: 162, savedAt: .now, nextFollowUpDate: .now, completedPlanDays: [])
        XCTAssertNil(invalidParents.geneticHeightReference(gender: "男"))
    }

    func testHeightDevelopmentUsesWS612AgeSexBands() throws {
        let middle = BodyAssessmentRecord(heightCentimeters: 135.81, weightKilograms: 30, measuredAt: .now, ruleVersion: BodyAssessmentRecord.ruleVersion, completedCaptures: [], parentMarkedAsymmetric: false, parentMarkedGaitConcern: false, savedAt: .now, nextFollowUpDate: .now, completedPlanDays: [])
        XCTAssertEqual(middle.heightDevelopmentAssessment(ageMonths: 108, gender: "男")?.level, .middle)
        XCTAssertEqual(try XCTUnwrap(middle.heightDevelopmentAssessment(ageMonths: 108, gender: "男")?.median), 135.81, accuracy: 0.001)
        XCTAssertNil(middle.heightDevelopmentAssessment(ageMonths: 83, gender: "男"))
        XCTAssertNil(middle.heightDevelopmentAssessment(ageMonths: 108, gender: ""))
    }

    func testAssessmentScoringClampsPartialAndLowConfidenceResults() throws {
        let student = Student(id: "score-test", name: "测试", gender: "男", grade: "三年级", className: "三年级1班", region: "南湖区", isPovertyArea: false, taskStatus: .completed, totalScore: nil)
        let partial = DiagnosisReport(id: "r1", student: student, assessmentDate: "2026-09-12", scores: [
            ScoreResult(id: "a", item: .obstacleJump, score: 6, note: "", confidence: 1.2, reviewStatus: .passed),
            ScoreResult(id: "b", item: .lateralSlide, score: -1, note: "", confidence: -0.2, reviewStatus: .pendingReview)
        ], abilityTags: [], riskAlerts: [], trainingAdvice: [], courseSuggestions: [], ruleVersion: "v1", regionPolicy: RegionPolicy(id: "p", region: "南湖区", povertyAreaLabel: nil, standardVersion: "v1", effectiveDate: "2026-09-01"))
        XCTAssertEqual(partial.totalScore, 5, accuracy: 0.001)
        XCTAssertEqual(partial.scoreCompletionRatio, 2.0 / 7.0, accuracy: 0.001)
        XCTAssertEqual(partial.riskLevel, .unavailable)
        XCTAssertTrue(partial.requiresReview)
        let duplicate = DiagnosisReport(id: "r-duplicate", student: student, assessmentDate: "2026-09-12", scores: [
            ScoreResult(id: "old", item: .obstacleJump, score: 1, note: "", confidence: 0.4, reviewStatus: .pendingReview),
            ScoreResult(id: "new", item: .obstacleJump, score: 4, note: "", confidence: 0.95, reviewStatus: .passed)
        ], abilityTags: [], riskAlerts: [], trainingAdvice: [], courseSuggestions: [], ruleVersion: "v1", regionPolicy: partial.regionPolicy)
        XCTAssertEqual(duplicate.normalizedScores.count, 1)
        XCTAssertEqual(duplicate.totalScore, 4, accuracy: 0.001)
        XCTAssertEqual(duplicate.conflictingItems, [.obstacleJump])
        XCTAssertTrue(duplicate.requiresReview)

        let lowConfidenceMarkedPassed = DiagnosisReport(id: "r-low-confidence", student: student, assessmentDate: "2026-09-12", scores: [
            ScoreResult(id: "low", item: .obstacleJump, score: 4, note: "", confidence: 0.6, reviewStatus: .passed)
        ], abilityTags: [], riskAlerts: [], trainingAdvice: [], courseSuggestions: [], ruleVersion: "v1", regionPolicy: partial.regionPolicy)
        XCTAssertEqual(lowConfidenceMarkedPassed.normalizedScores.first?.reviewStatus, .pendingReview)
        XCTAssertTrue(lowConfidenceMarkedPassed.requiresReview)

        let completeButPendingReview = DiagnosisReport(id: "r-complete-pending", student: student, assessmentDate: "2026-09-12", scores: TestItem.allCases.map { item in
            ScoreResult(id: item.rawValue, item: item, score: 4, note: "", confidence: 0.6, reviewStatus: .passed)
        }, abilityTags: [], riskAlerts: [], trainingAdvice: [], courseSuggestions: [], ruleVersion: "v1", regionPolicy: partial.regionPolicy)
        XCTAssertEqual(completeButPendingReview.riskLevel, .unavailable)
        XCTAssertTrue(completeButPendingReview.requiresReview)
        let reviewedButStillPending = DiagnosisReport(id: "r-reviewed-pending", student: student, assessmentDate: "2026-09-12", scores: TestItem.allCases.map { item in
            ScoreResult(id: item.rawValue, item: item, score: 4, note: "已查看证据但未批准", confidence: 0.95, reviewStatus: .pendingReview, humanReviewed: true)
        }, abilityTags: [], riskAlerts: [], trainingAdvice: [], courseSuggestions: [], ruleVersion: "v1", regionPolicy: partial.regionPolicy)
        XCTAssertEqual(reviewedButStillPending.riskLevel, .unavailable)
        XCTAssertTrue(reviewedButStillPending.requiresReview)
        let humanApproved = DiagnosisReport(id: "r-human-approved", student: student, assessmentDate: "2026-09-12", scores: TestItem.allCases.map { item in
            ScoreResult(id: item.rawValue, item: item, score: 4, note: "人工核验", confidence: 0.6, reviewStatus: .passed, humanReviewed: true)
        }, abilityTags: [], riskAlerts: [], trainingAdvice: [], courseSuggestions: [], ruleVersion: "v1", regionPolicy: partial.regionPolicy)
        XCTAssertEqual(humanApproved.riskLevel, .low)
        XCTAssertFalse(humanApproved.requiresReview)

        let tied = DiagnosisReport(id: "r-tie", student: student, assessmentDate: "2026-09-12", scores: [
            ScoreResult(id: "tie-pending", item: .obstacleJump, score: 1, note: "", confidence: 0.9, reviewStatus: .pendingReview),
            ScoreResult(id: "tie-passed", item: .obstacleJump, score: 4, note: "", confidence: 0.9, reviewStatus: .passed)
        ], abilityTags: [], riskAlerts: [], trainingAdvice: [], courseSuggestions: [], ruleVersion: "v1", regionPolicy: partial.regionPolicy)
        XCTAssertEqual(tied.normalizedScores.first?.id, "tie-passed")

        let completeScores = TestItem.allCases.enumerated().map { index, item in
            ScoreResult(id: "s\(index)", item: item, score: index == 0 ? 2.5 : 3.5, note: "", confidence: 0.95, reviewStatus: .passed)
        }
        let complete = DiagnosisReport(id: "r2", student: student, assessmentDate: "2026-09-12", scores: completeScores, abilityTags: [], riskAlerts: [], trainingAdvice: [], courseSuggestions: [], ruleVersion: "v1", regionPolicy: partial.regionPolicy)
        XCTAssertEqual(complete.riskLevel, .attention)
        XCTAssertTrue(complete.requiresFollowUp)
    }

    func testClassCompletionUsesStudentCountWeighting() {
        let classes = [
            ClassInfo(id: "small", name: "小班", gradeId: "g", teacherName: "", studentCount: 1, completionRate: 100),
            ClassInfo(id: "large", name: "大班", gradeId: "g", teacherName: "", studentCount: 9, completionRate: 0)
        ]
        let total = classes.reduce(0) { $0 + $1.studentCount }
        let completed = classes.reduce(0) { $0 + $1.completedStudentEstimate }
        XCTAssertEqual(total, 10)
        XCTAssertEqual(completed, 1)
        XCTAssertEqual(Double(completed) / Double(total), 0.1, accuracy: 0.001)
    }

    func testFamilyHealthRecordIsTheOnlySourceOfSavedFamilyEntries() async throws {
        let suite = "xiangshang.youth.family-health-source-tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        let state = AppState(featureStore: LocalFeatureStore(defaults: defaults))
        await state.login(phone: "13800138000")
        let child = try XCTUnwrap(state.data?.students.first)
        let bound = await state.bindChild(name: child.name, code: "XS-S01")
        XCTAssertTrue(bound)

        // A saved record is keyed to the actually bound child, never anonymous.
        state.completeAssessment(.vision, entries: ["基础信息": "每日户外活动 2 小时"])
        XCTAssertEqual(state.familyHealthRecord(for: child, category: .vision)?.entries["基础信息"], "每日户外活动 2 小时")
        let answer = try XCTUnwrap(state.familyHealthRecord(for: child, category: .vision)?.structuredAnswers?.first(where: { $0.questionID == "profile-confirmed" }))
        XCTAssertEqual(answer.questionType, "single")
        XCTAssertEqual(answer.selectedOptionIDs, ["每日户外活动 2 小时"])
        XCTAssertEqual(state.familyHealthRecord(for: child, category: .vision)?.formVersion, "family-observation-v2")
    }

    func testEmptyMeasurementsNeverProduceABMIClassification() {
        let empty = BodyAssessmentRecord(heightCentimeters: 0, weightKilograms: 0, measuredAt: .now, ruleVersion: BodyAssessmentRecord.ruleVersion, completedCaptures: [], parentMarkedAsymmetric: false, parentMarkedGaitConcern: false, savedAt: .now, nextFollowUpDate: .now, completedPlanDays: [])

        XCTAssertEqual(empty.bmi, 0)
        XCTAssertEqual(empty.bmiAttention(ageMonths: 108, gender: "男"), .unavailable)
        XCTAssertEqual(empty.bmiScreeningLabel(ageMonths: 108, gender: "男"), "待填写身高体重")
    }

    func testIncompleteVisualCaptureIsNotPublishedAsAHealthRisk() throws {
        let record = BodyAssessmentRecord(heightCentimeters: 130, weightKilograms: 27, measuredAt: .now, ruleVersion: BodyAssessmentRecord.ruleVersion, completedCaptures: [], parentMarkedAsymmetric: false, parentMarkedGaitConcern: false, savedAt: .now, nextFollowUpDate: .now, completedPlanDays: [])
        XCTAssertEqual(record.postureAttention(), .pending)
        XCTAssertEqual(record.attention(ageMonths: 108, gender: "男"), .pending)
        XCTAssertNotEqual(record.attention(ageMonths: 108, gender: "男"), .yellow)

        let now = try XCTUnwrap(Self.isoDay.date(from: "2026-08-11"))
        let insight = GrowthInsight.make(period: .week, checkInDates: [], planDates: [], assessmentCount: 0, bodyAttention: .pending, totalScore: nil, now: now)
        XCTAssertEqual(insight.planTitle, "完成家庭观察计划")
        XCTAssertTrue(insight.planReason.contains("不将未完成记录当作健康风险"))
        let sanitized = GrowthInsight.make(period: .week, checkInDates: [], planDates: [], assessmentCount: -4, bodyAttention: nil, totalScore: .nan, now: now)
        XCTAssertEqual(sanitized.assessmentCount, 0)
        XCTAssertEqual(sanitized.planTitle, "轻量习惯计划")
    }

    func testGrowthInsightRejectsPartiallyParsedDatesButTrimsWhitespace() throws {
        let now = try XCTUnwrap(Self.isoDay.date(from: "2026-08-11"))
        let insight = GrowthInsight.make(period: .week, checkInDates: ["2026-08-10junk", " 2026-08-10 "], planDates: [], assessmentCount: 0, bodyAttention: nil, totalScore: nil, now: now)
        XCTAssertEqual(insight.activeDays, 1)
    }

    func testMeasurementInputNormalizesRangeAndPrecision() {
        XCTAssertEqual(BodyMeasurementInput.normalized(133.26, range: 90...190, step: 0.5), 133.5, accuracy: 0.001)
        XCTAssertEqual(BodyMeasurementInput.normalized(31.24, range: 15...90, step: 0.1), 31.2, accuracy: 0.001)
        XCTAssertEqual(BodyMeasurementInput.normalized(-10, range: 15...90, step: 0.1), 15, accuracy: 0.001)
        XCTAssertEqual(BodyMeasurementInput.normalized(280, range: 130...220, step: 0.5), 220, accuracy: 0.001)
        XCTAssertEqual(BodyMeasurementInput.normalized(.infinity, range: 90...190, step: 0.5), 90, accuracy: 0.001)
        XCTAssertEqual(BodyMeasurementInput.normalized(1, range: 1...2, step: 0), 1, accuracy: 0.001)
    }

    func testVisualCaptureQualityGateRequiresStablePoseAndRealGaitMovement() {
        XCTAssertTrue(BodyCaptureQualityGate.isStaticCaptureReady(elapsed: 1.5, stableFrames: 12, displacement: 0.01))
        XCTAssertFalse(BodyCaptureQualityGate.isStaticCaptureReady(elapsed: 1.5, stableFrames: 12, displacement: 0.03))
        XCTAssertFalse(BodyCaptureQualityGate.isStaticCaptureReady(elapsed: 1.4, stableFrames: 20, displacement: 0.01))
        XCTAssertTrue(BodyCaptureQualityGate.isGaitCaptureReady(elapsed: 2.5, displacement: 0.04))
        XCTAssertFalse(BodyCaptureQualityGate.isGaitCaptureReady(elapsed: 2.5, displacement: 0.02))
        XCTAssertFalse(BodyCaptureQualityGate.isForwardBendCaptureReady(elapsed: 1.5, stableFrames: 12, displacement: 0.01, torsoTilt: 0.10))
        XCTAssertTrue(BodyCaptureQualityGate.isForwardBendCaptureReady(elapsed: 1.5, stableFrames: 12, displacement: 0.01, torsoTilt: 0.45))
        XCTAssertFalse(BodyCaptureQualityGate.isForwardBendCaptureReady(elapsed: 1.5, stableFrames: 12, displacement: 0.01, torsoTilt: .infinity, ageMonths: 120))
        XCTAssertFalse(BodyCaptureQualityGate.hasUsableBodyScale(verticalCoverage: 0.30, seated: false))
        XCTAssertTrue(BodyCaptureQualityGate.hasUsableBodyScale(verticalCoverage: 0.50, seated: false))
        XCTAssertFalse(BodyCaptureQualityGate.hasUsableBodyScale(verticalCoverage: 0.12, seated: true))
        XCTAssertTrue(BodyCaptureQualityGate.hasUsableSeatedGeometry(shoulderCenterY: 0.85, hipCenterY: 0.65, verticalCoverage: 0.20))
        XCTAssertFalse(BodyCaptureQualityGate.hasUsableSeatedGeometry(shoulderCenterY: 0.65, hipCenterY: 0.85, verticalCoverage: 0.20))
        XCTAssertTrue(BodyCaptureQualityGate.hasReliableLandmarks([0.72, 0.62, 0.58, 0.60]))
        XCTAssertFalse(BodyCaptureQualityGate.hasReliableLandmarks([0.96, 0.96, 0.33, 0.34]))
        XCTAssertFalse(BodyCaptureQualityGate.hasReliableLandmarks([0.9, 0.9, 0.2, 0.9]))
        XCTAssertFalse(BodyCaptureQualityGate.hasReliableLandmarks([0.9, .infinity, 0.9, 0.9]))
        XCTAssertFalse(BodyCaptureQualityGate.hasUsableBodyScale(verticalCoverage: .infinity, seated: false))
        XCTAssertEqual(BodyCaptureQualityGate.staticProgress(elapsed: 10), 0.96, accuracy: 0.001)
    }

    func testPostureReportUsesObjectiveThresholdsAndIgnoresParentRiskCheckboxes() throws {
        func snapshot(_ task: BodyAssessmentRecord.CaptureTask, atr: Double? = 2, shoulder: Double = 0.2, sampleCount: Int = 18, rib: Double? = 0.2, gait: Double? = nil) -> PostureMetricSnapshot {
            PostureMetricSnapshot(id: task.rawValue, task: task, sampleCount: sampleCount, confidence: 0.82, shoulderHeightDifferenceCm: shoulder, pelvicHeightDifferenceCm: 0.2, headTiltDegrees: 1, spinalMidlineDeviationCm: 0.2, thoracicRoundingDegrees: 10, forwardHeadAngleDegrees: 5, cameraProxyAtrDegrees: atr, cameraProxyRibProminenceCm: rib, gaitShoulderSwingDifferenceCm: gait, gaitPelvicSwingDifferenceCm: nil, gaitTrunkSwayCm: nil)
        }
        let greenSnapshots = Dictionary(uniqueKeysWithValues: BodyAssessmentRecord.CaptureTask.allCases.map { ($0, snapshot($0)) })
        let greenReport = PostureAssessmentReport.make(snapshots: greenSnapshots, generatedAt: .now)
        let green = BodyAssessmentRecord(heightCentimeters: 150, weightKilograms: 30, measuredAt: .now, ruleVersion: BodyAssessmentRecord.ruleVersion, completedCaptures: Set(BodyAssessmentRecord.CaptureTask.allCases), parentMarkedAsymmetric: true, parentMarkedGaitConcern: true, savedAt: .now, nextFollowUpDate: .now, completedPlanDays: [], postureReport: greenReport)
        XCTAssertEqual(greenReport.overallLevel, .green)
        XCTAssertEqual(green.attention(ageMonths: 108, gender: "男"), .green)
        XCTAssertEqual(green.observations(ageMonths: 108, gender: "男").first(where: { $0.id == "shoulder" })?.level, .green)

        var redSnapshots = greenSnapshots
        redSnapshots[.standingBack] = snapshot(.standingBack, shoulder: 2.0)
        XCTAssertEqual(PostureAssessmentReport.make(snapshots: redSnapshots, generatedAt: .now).overallLevel, .yellow)
        var multiSignalSnapshots = redSnapshots
        multiSignalSnapshots[.forwardBend] = snapshot(.forwardBend, atr: nil, rib: 1.3)
        multiSignalSnapshots[.gaitVideo] = snapshot(.gaitVideo, atr: nil, rib: nil, gait: 1.4)
        XCTAssertEqual(PostureAssessmentReport.make(snapshots: multiSignalSnapshots, generatedAt: .now).overallLevel, .red)
        var proxyOnlySnapshots = greenSnapshots
        proxyOnlySnapshots[.forwardBend] = snapshot(.forwardBend, atr: 30)
        XCTAssertEqual(PostureAssessmentReport.make(snapshots: proxyOnlySnapshots, generatedAt: .now).overallLevel, .green)
        var instrumentATR = greenSnapshots
        instrumentATR[.forwardBend] = snapshot(.forwardBend, atr: nil, rib: nil)
        instrumentATR[.forwardBend] = PostureMetricSnapshot(id: "instrument", task: .forwardBend, sampleCount: 18, confidence: 0.82, shoulderHeightDifferenceCm: 0.2, pelvicHeightDifferenceCm: 0.2, headTiltDegrees: 1, spinalMidlineDeviationCm: 0.2, thoracicRoundingDegrees: 10, forwardHeadAngleDegrees: 5, cameraProxyAtrDegrees: nil, cameraProxyRibProminenceCm: nil, instrumentAtrDegrees: 7, occiputWallDistanceCm: nil, gaitShoulderSwingDifferenceCm: nil, gaitPelvicSwingDifferenceCm: nil, gaitTrunkSwayCm: nil)
        XCTAssertEqual(PostureAssessmentReport.make(snapshots: instrumentATR, generatedAt: .now).overallLevel, .red)
        var malformed = greenSnapshots
        malformed[.standingBack] = snapshot(.standingBack, shoulder: .nan)
        let malformedReport = PostureAssessmentReport.make(snapshots: malformed, generatedAt: .now)
        XCTAssertEqual(malformedReport.overallLevel, .pending)
        XCTAssertTrue(malformedReport.reasons.contains { $0.contains("异常测量值") })
        XCTAssertFalse(malformedReport.reasons.joined(separator: " ").localizedCaseInsensitiveContains("nan"))
        XCTAssertEqual(PostureAssessmentReport.make(snapshots: greenSnapshots.filter { $0.key != .seatedPosture }, generatedAt: .now).overallLevel, .pending)
        var lowQuality = greenSnapshots
        lowQuality[.seatedPosture] = snapshot(.seatedPosture, sampleCount: 3)
        XCTAssertEqual(PostureAssessmentReport.make(snapshots: lowQuality, generatedAt: .now).overallLevel, .pending)
    }

    func testPostureReportUsesHeadTiltAndBothCalibratedAtrSegments() throws {
        func snapshot(_ task: BodyAssessmentRecord.CaptureTask, headTilt: Double? = nil) -> PostureMetricSnapshot {
            PostureMetricSnapshot(id: task.rawValue, task: task, sampleCount: 18, confidence: 0.82, shoulderHeightDifferenceCm: 0.2, pelvicHeightDifferenceCm: 0.2, headTiltDegrees: headTilt ?? (task == .standingBack ? 6.5 : 1), spinalMidlineDeviationCm: 0.2, thoracicRoundingDegrees: 10, forwardHeadAngleDegrees: 5, cameraProxyAtrDegrees: 2, cameraProxyRibProminenceCm: 0.2, gaitShoulderSwingDifferenceCm: nil, gaitPelvicSwingDifferenceCm: nil, gaitTrunkSwayCm: nil)
        }
        let base = Dictionary(uniqueKeysWithValues: BodyAssessmentRecord.CaptureTask.allCases.map { ($0, snapshot($0)) })
        XCTAssertEqual(PostureAssessmentReport.make(snapshots: base, generatedAt: .now).overallLevel, .yellow)

        var thoracic = base
        thoracic[.standingBack] = snapshot(.standingBack, headTilt: 1)
        thoracic[.forwardBend] = PostureMetricSnapshot(id: "forward", task: .forwardBend, sampleCount: 18, confidence: 0.82, shoulderHeightDifferenceCm: 0.2, pelvicHeightDifferenceCm: 0.2, headTiltDegrees: 1, spinalMidlineDeviationCm: 0.2, thoracicRoundingDegrees: 10, forwardHeadAngleDegrees: 5, cameraProxyAtrDegrees: nil, cameraProxyRibProminenceCm: nil, thoracicAtrDegrees: 7, gaitShoulderSwingDifferenceCm: nil, gaitPelvicSwingDifferenceCm: nil, gaitTrunkSwayCm: nil)
        XCTAssertEqual(PostureAssessmentReport.make(snapshots: thoracic, generatedAt: .now).overallLevel, .red)

        var lumbar = thoracic
        lumbar[.forwardBend] = thoracic[.forwardBend].map { value in
            PostureMetricSnapshot(id: value.id, task: value.task, sampleCount: value.sampleCount, confidence: value.confidence, shoulderHeightDifferenceCm: value.shoulderHeightDifferenceCm, pelvicHeightDifferenceCm: value.pelvicHeightDifferenceCm, headTiltDegrees: value.headTiltDegrees, spinalMidlineDeviationCm: value.spinalMidlineDeviationCm, thoracicRoundingDegrees: value.thoracicRoundingDegrees, forwardHeadAngleDegrees: value.forwardHeadAngleDegrees, cameraProxyAtrDegrees: value.cameraProxyAtrDegrees, cameraProxyRibProminenceCm: value.cameraProxyRibProminenceCm, lumbarAtrDegrees: 5, gaitShoulderSwingDifferenceCm: value.gaitShoulderSwingDifferenceCm, gaitPelvicSwingDifferenceCm: value.gaitPelvicSwingDifferenceCm, gaitTrunkSwayCm: value.gaitTrunkSwayCm)
        }
        XCTAssertEqual(PostureAssessmentReport.make(snapshots: lumbar, generatedAt: .now).overallLevel, .yellow)
    }

    func testPostureReportRequiresTaskSpecificEvidence() {
        func sparse(_ task: BodyAssessmentRecord.CaptureTask, shoulder: Double? = nil, trunk: Double? = nil, gait: Double? = nil) -> PostureMetricSnapshot {
            PostureMetricSnapshot(id: task.rawValue, task: task, sampleCount: 18, confidence: 0.82, shoulderHeightDifferenceCm: shoulder, pelvicHeightDifferenceCm: nil, headTiltDegrees: nil, spinalMidlineDeviationCm: trunk, thoracicRoundingDegrees: nil, forwardHeadAngleDegrees: nil, cameraProxyAtrDegrees: nil, cameraProxyRibProminenceCm: nil, gaitShoulderSwingDifferenceCm: gait, gaitPelvicSwingDifferenceCm: nil, gaitTrunkSwayCm: nil)
        }
        let mismatched = Dictionary(uniqueKeysWithValues: BodyAssessmentRecord.CaptureTask.allCases.map { ($0, sparse($0, shoulder: 0.2)) })
        let mismatchedReport = PostureAssessmentReport.make(snapshots: mismatched)
        XCTAssertEqual(mismatchedReport.overallLevel, .pending)
        XCTAssertFalse(mismatchedReport.isComplete)
        let taskSpecific: [BodyAssessmentRecord.CaptureTask: PostureMetricSnapshot] = [
            .standingBack: sparse(.standingBack, shoulder: 0.2),
            .forwardBend: sparse(.forwardBend, trunk: 0.2),
            .seatedPosture: sparse(.seatedPosture, trunk: 0.2),
            .gaitVideo: sparse(.gaitVideo, gait: 0.2)
        ]
        let completeReport = PostureAssessmentReport.make(snapshots: taskSpecific)
        XCTAssertEqual(completeReport.overallLevel, .green)
        XCTAssertTrue(completeReport.isComplete)
    }

    func testPrincipalTaskScopeKeepsReportAveragesInsideSelectedBatch() async throws {
        let data = try await MockRepository.shared.loadDashboard()
        let retest = try XCTUnwrap(data.tasks.first(where: { $0.id == "t2" }))
        let scopedStudents = retest.scopedStudents(from: data.students)
        let completedStudents = retest.completedStudents(from: data.students) { $0.taskStatus }
        let scopedReports = completedStudents.map { MockRepository.shared.report(for: $0) }

        XCTAssertTrue(scopedStudents.allSatisfy { $0.classID == "c41" })
        XCTAssertTrue(completedStudents.allSatisfy { $0.taskStatus == .completed })
        XCTAssertEqual(scopedReports.count, completedStudents.count)
        XCTAssertEqual(scopedReports.flatMap(\.scores).count, completedStudents.count * TestItem.allCases.count)
    }

    func testTaskAggregatesClampMalformedCountsAndNormalizeItems() {
        let task = TestTask(id: "bad", title: "", date: "", location: "", gradeName: "全校", className: "", items: [.obstacleJump, .obstacleJump], completedCount: 99, totalCount: -2, status: .testing, ruleVersion: "v1")
        XCTAssertEqual(task.boundedTotalCount, 0)
        XCTAssertEqual(task.boundedCompletedCount, 0)
        XCTAssertEqual(task.completionRate, 0)
        XCTAssertFalse(task.hasPublishedResults)
        XCTAssertEqual(task.normalizedItems, [.obstacleJump])
    }

    func testTaskScopeUsesStableStudentIDsInsteadOfDisplayNames() async throws {
        let data = try await MockRepository.shared.loadDashboard()
        let source = try XCTUnwrap(data.students.first(where: { $0.id == "s03" }))
        let sameNamedButOutOfScope = Student(id: "different-student", name: source.name, gender: source.gender, grade: source.grade, className: source.className, region: source.region, isPovertyArea: false, taskStatus: .completed, totalScore: nil, birthDate: source.birthDate, classID: "different-class")
        let task = TestTask(id: "stable-scope", title: "", date: "", location: "", gradeName: source.grade, className: source.className, items: [], completedCount: 0, totalCount: 1, status: .notCheckedIn, ruleVersion: "v1", classIDs: ["different-class"], studentIDs: [source.id])

        XCTAssertEqual(task.scopedStudents(from: [source, sameNamedButOutOfScope]).map(\.id), [source.id])
    }

    func testUnstartedTaskDoesNotQualifyForCurrentTaskReportAverages() async throws {
        let data = try await MockRepository.shared.loadDashboard()
        let futureTask = try XCTUnwrap(data.tasks.first(where: { $0.id == "t3" }))

        XCTAssertEqual(futureTask.completedCount, 0)
        XCTAssertFalse(futureTask.hasPublishedResults)
    }

    func testOnlyCompletedStudentsCanOpenAPublishedSchoolReport() async throws {
        let suite = "xiangshang.youth.report-publication-tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        let state = AppState(featureStore: LocalFeatureStore(defaults: defaults))
        await state.login(phone: "13800138000")
        let completed = try XCTUnwrap(state.data?.students.first(where: { $0.taskStatus == .completed }))
        let pendingReview = try XCTUnwrap(state.data?.students.first(where: { $0.taskStatus == .review }))

        XCTAssertTrue(state.hasPublishedSchoolReport(for: completed))
        XCTAssertFalse(state.hasPublishedSchoolReport(for: pendingReview))
    }

    func testGrowthInsightUsesRealActivityDatesAndExplainsAdjustment() throws {
        let now = try XCTUnwrap(Self.isoDay.date(from: "2026-08-11"))
        let insight = GrowthInsight.make(
            period: .week,
            checkInDates: ["2026-08-05", "2026-08-08", "2026-08-10", "2026-07-01"],
            planDates: ["2026-08-08", "2026-08-11"],
            assessmentCount: 2,
            bodyAttention: .yellow,
            totalScore: 28.5,
            now: now
        )

        XCTAssertEqual(insight.activeDays, 4)
        XCTAssertEqual(insight.planDays, 2)
        XCTAssertEqual(insight.consistencyPercent, 100)
        XCTAssertEqual(insight.planTitle, "姿态巩固计划")
        XCTAssertTrue(insight.planReason.contains("近期记录"))
    }

    func testGrowthInsightUsesChinaBusinessTimezoneAtMidnight() throws {
        let formatter = ISO8601DateFormatter()
        formatter.timeZone = TimeZone(identifier: "Asia/Shanghai")
        let now = try XCTUnwrap(formatter.date(from: "2026-08-11T00:30:00+08:00"))
        let insight = GrowthInsight.make(period: .week, checkInDates: ["2026-08-10"], planDates: [], assessmentCount: 0, bodyAttention: nil, totalScore: nil, now: now)
        XCTAssertEqual(insight.activeDays, 1)
    }

    func testBusinessClockKeepsSchoolDayStableAcrossUTCDeviceBoundary() throws {
        let instant = try XCTUnwrap(ISO8601DateFormatter().date(from: "2026-08-22T16:30:00Z"))
        XCTAssertEqual(BusinessClock.day(instant), "2026-08-23")
        XCTAssertEqual(BusinessClock.timeZone.identifier, "Asia/Shanghai")
    }

    func testGrowthInsightDoesNotTreatAnUnpublishedSchoolScoreAsZero() throws {
        let now = try XCTUnwrap(Self.isoDay.date(from: "2026-08-11"))
        let insight = GrowthInsight.make(
            period: .week,
            checkInDates: ["2026-08-05", "2026-08-07", "2026-08-09", "2026-08-11"],
            planDates: [],
            assessmentCount: 0,
            bodyAttention: nil,
            totalScore: nil,
            now: now
        )

        XCTAssertEqual(insight.consistencyPercent, 100)
        XCTAssertEqual(insight.planTitle, "均衡成长计划")
        XCTAssertFalse(insight.planReason.contains("弱项"))
    }

    func testGrowthInsightRejectsImpossibleCalendarDates() throws {
        let now = ISO8601DateFormatter().date(from: "2026-08-22T08:00:00Z")!
        let insight = GrowthInsight.make(period: .week, checkInDates: ["2026-02-31", "not-a-date"], planDates: [], assessmentCount: 0, bodyAttention: nil, totalScore: nil, now: now)
        XCTAssertEqual(insight.activeDays, 0)
        XCTAssertEqual(insight.planDays, 0)
    }

    private static let isoDay: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()
    func testRepositoryProviderUsesBundledMockDataByDefault() {
        // A release or CI invocation without an explicit integration scheme
        // must never accidentally route student data to the placeholder API.
        XCTAssertTrue(RepositoryProvider.make() is MockRepository)
    }

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
        XCTAssertEqual(data.students[0].totalScore ?? 0, report.totalScore, accuracy: 0.001)
        XCTAssertNil(data.students[2].totalScore, "待复核学生不应展示伪造的总分")
        XCTAssertEqual(report.regionPolicy.effectiveDate, "2026-08-01")
        XCTAssertEqual(report.regionPolicy.region, report.student.region)
    }

    func testTaskScopeKeepsSelectedBatchStudentMetricsHonest() async throws {
        let data = try await MockRepository.shared.loadDashboard()
        let autumnTask = try XCTUnwrap(data.tasks.first(where: { $0.id == "t1" }))
        let retestTask = try XCTUnwrap(data.tasks.first(where: { $0.id == "t2" }))

        XCTAssertEqual(autumnTask.scopedStudents(from: data.students).count, data.students.count)
        XCTAssertEqual(Set(autumnTask.scopedStudents(from: data.students).map(\.grade)), Set(["三年级", "四年级", "五年级"]))
        XCTAssertTrue(retestTask.scopedStudents(from: data.students).allSatisfy { $0.classID == "c41" })
        XCTAssertFalse(retestTask.scopedStudents(from: data.students).contains(where: { $0.classID == "c31" }))
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

    func testFamilyLoginCannotSwitchIntoTeacherWorkbench() async {
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

        XCTAssertEqual(state.profile?.availableRoles, [.parent])
        XCTAssertFalse(state.selectRole(.teacher))
        XCTAssertNil(state.selectedRole)
        XCTAssertEqual(state.profile?.name, "王女士")
        state.selectRole(.parent)
        XCTAssertEqual(state.selectedRole, .parent)
        XCTAssertEqual(state.profile?.availableRoles, [.parent])
        state.chooseAnotherRole()
        XCTAssertNil(state.selectedRole)
    }

    func testWechatAuthorizationIdentifierIsNeverExposedAsProfilePhone() async {
        let suite = "xiangshang.youth.wechat-login-tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        let state = AppState(featureStore: LocalFeatureStore(defaults: defaults))

        await state.login(phone: "wechat_authorization")

        XCTAssertEqual(state.profile?.phone, "未绑定手机号")
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

    func testLegacyParentSessionKeepsItsNameOnFirstRoleSwitch() {
        let suite = "xiangshang.youth.legacy-parent-name-tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        let store = LocalFeatureStore(defaults: defaults)
        store.update { value in
            value.sessionProfile = UserProfile(id: "u1", name: "陈女士", phone: "13800138000", role: .parent, schoolName: "向上实验小学", avatarInitials: "陈")
            value.parentAccountName = nil
        }
        let state = AppState(featureStore: store)

        state.selectRole(.teacher)
        state.selectRole(.parent)

        XCTAssertEqual(state.profile?.name, "陈女士")
        XCTAssertEqual(state.localFeatures.parentAccountName, "陈女士")
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

    func testCourseProgressIsIsolatedByStableLessonID() {
        let suite = "xiangshang.youth.course-progress-lesson-tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        let store = LocalFeatureStore(defaults: defaults)
        let state = AppState(featureStore: store)

        state.updateCourseProgress(childID: "child-1", courseID: "course-1", lessonID: "lesson-a", progress: 0.25)
        state.updateCourseProgress(childID: "child-1", courseID: "course-1", lessonID: "lesson-b", progress: 0.75)

        XCTAssertEqual(state.courseProgress(childID: "child-1", courseID: "course-1", lessonID: "lesson-a"), 0.25, accuracy: 0.001)
        XCTAssertEqual(state.courseProgress(childID: "child-1", courseID: "course-1", lessonID: "lesson-b"), 0.75, accuracy: 0.001)
        XCTAssertNotEqual(
            AppState.courseProgressKey(childID: "child-1", courseID: "course-1", lessonID: "lesson-a"),
            AppState.courseProgressKey(childID: "child-1", courseID: "course-1", lessonID: "lesson-b")
        )
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
            value.taskScopedStatuses["t1|s01"] = .review
            value.taskScopedStatusVersions["t1|s01"] = 7
            value.taskScopedSyncStates["t1|s01"] = .pendingSync
            value.taskScopedReviewNotes["t1|s01"] = "核验视频后建议周五补测。"
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
        XCTAssertEqual(restored.taskScopedStatuses["t1|s01"], .review)
        XCTAssertEqual(restored.taskScopedStatusVersions["t1|s01"], 7)
        XCTAssertEqual(restored.taskScopedSyncStates["t1|s01"], .pendingSync)
        XCTAssertEqual(restored.taskScopedReviewNotes["t1|s01"], "核验视频后建议周五补测。")
        XCTAssertTrue(restored.settings.reduceMotion)
        XCTAssertTrue(restored.settings.voiceGuidanceEnabled)
        XCTAssertEqual(restored.classPostComments.first?.text, "继续加油")
        XCTAssertEqual(restored.likedClassPostIDs.count, 2)
        XCTAssertTrue(restored.likedClassPostIDs.contains(UUID(uuidString: "00000000-0000-0000-0000-000000000001")!))
    }

    func testLegacySettingsMigrateVoiceGuidanceToEnabled() throws {
        let suite = "xiangshang.youth.settings-migration-tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        var payload = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(LocalFeatureState())) as? [String: Any])
        payload["settings"] = ["notificationsEnabled": false, "reduceMotion": true]
        defaults.set(try JSONSerialization.data(withJSONObject: payload), forKey: "xiangshang.local-feature-state.v1")

        let restored = LocalFeatureStore(defaults: defaults).state
        XCTAssertFalse(restored.settings.notificationsEnabled)
        XCTAssertTrue(restored.settings.reduceMotion)
        XCTAssertTrue(restored.settings.voiceGuidanceEnabled)
    }

    func testMockWorkflowKeepsTheLocalRecordPendingUntilSchoolServiceIsConnected() async {
        let suite = "xiangshang.youth.sync-tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        let state = AppState(featureStore: LocalFeatureStore(defaults: defaults))

        await state.login(phone: "13800138000")
        let succeeded = await state.submitActivityCommand("health-growth-season-2026", contactName: "王女士", phone: "13800138000")
        XCTAssertTrue(succeeded)
        XCTAssertEqual(state.localFeatures.activityRegistrations.first?.status, .pendingSync)
        XCTAssertEqual(state.pendingSyncCount, 1)
        if case let .succeeded(message) = state.workflowState(for: "activity:health-growth-season-2026") {
            XCTAssertTrue(message.contains("本机"))
            XCTAssertFalse(message.contains("学校服务确认"))
        } else {
            XCTFail("Mock activity command should disclose its local-only state")
        }
    }

    func testRemoteRepositoryNeverFallsBackToBundledMockBeforeEndpointLoads() async throws {
        let student = try await MockRepository.shared.loadDashboard().students.first
        XCTAssertNotNil(student)
        guard let student else { return }

        let report = RemoteRepository().report(for: student)
        XCTAssertEqual(report.student.id, student.id)
        XCTAssertTrue(report.scores.isEmpty)
        XCTAssertEqual(report.riskLevel, .unavailable)
        XCTAssertEqual(report.riskAlerts, ["报告尚未从学校服务返回"])
    }

    func testPendingReportDeepLinkSelectsParentAndRequestedStudent() async {
        let suite = "xiangshang.youth.deep-link-tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        let state = AppState(featureStore: LocalFeatureStore(defaults: defaults))
        await state.login(phone: "13800138000")
        let bound = await state.bindChild(name: "王小雨", code: "XS-S02")
        XCTAssertTrue(bound)
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

    func testRiskDeepLinkCannotGrantRemovedPrincipalMobileWorkbench() async {
        let suite = "xiangshang.youth.risk-link-tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        let state = AppState(featureStore: LocalFeatureStore(defaults: defaults))
        await state.login(phone: "13800138000")
        let router = AppRouter()

        router.receiveDeepLink(URL(string: "xiangshang-youth://open?target=risk")!)
        router.activatePendingDeepLink(using: state)

        // 校长工作台已经迁至学校数据管理后台。风险通知不能通过深链
        // 将公开家庭账号提升为校长，也不能制造带返回按钮的伪工作台。
        XCTAssertNil(state.selectedRole)
        XCTAssertEqual(router.path.count, 0)
        XCTAssertNotEqual(state.selectedRole, .teacher, "Risk links must not silently convert a family account into a teacher workbench.")
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

    func testUnsupportedDeepLinkDoesNotDiscardActiveNavigation() async {
        let suite = "xiangshang.youth.invalid-deep-link-tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        let state = AppState(featureStore: LocalFeatureStore(defaults: defaults))
        await state.login(phone: "13800138000")
        let router = AppRouter()
        router.push(.teacherMessages)

        router.receiveDeepLink(URL(string: "xiangshang-youth://open?target=retired-screen")!)
        router.activatePendingDeepLink(using: state)

        XCTAssertEqual(router.path.count, 1)
        router.pop()
        XCTAssertTrue(router.path.isEmpty)
    }

    func testRouterResetClearsPrincipalDrillDownScopes() {
        let router = AppRouter()
        router.pendingGradeFilter = "三年级"
        router.pendingClassFilter = "三年级2班"

        router.reset()

        XCTAssertNil(router.pendingGradeFilter)
        XCTAssertNil(router.pendingClassFilter)
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
        XCTAssertTrue(restored.taskScopedStatuses.isEmpty)
        XCTAssertTrue(restored.studentTaskStatuses.isEmpty)
        XCTAssertTrue(restored.reviewNotes.isEmpty)
        XCTAssertTrue(restored.taskStatusSyncStates.isEmpty)
    }

    func testFeatureStoreMigratesStateSavedBeforeFamilyHealthRecords() throws {
        let suite = "xiangshang.youth.family-health-migration.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        let original = LocalFeatureState(completedAssessments: ["s01-心理"])
        let encoded = try JSONEncoder().encode(original)
        var legacy = try XCTUnwrap(try JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        legacy.removeValue(forKey: "familyHealthRecords")
        defaults.set(try JSONSerialization.data(withJSONObject: legacy), forKey: "xiangshang.local-feature-state.v1")

        let restored = LocalFeatureStore(defaults: defaults).state
        XCTAssertTrue(restored.completedAssessments.contains("s01-心理"))
        XCTAssertTrue(restored.familyHealthRecords.isEmpty)
    }

    func testHealthCheckinsStayIsolatedByChildAndBusinessDate() {
        let defaults = UserDefaults(suiteName: "xiangshang.health-checkin-scope-test")!
        defaults.removePersistentDomain(forName: "xiangshang.health-checkin-scope-test")
        let store = LocalFeatureStore(defaults: defaults)
        let first = HealthCheckInRecord(id: "checkin-a", childID: "child-a", checkInDate: "2026-08-24", activityType: "跟练", durationMinutes: 20, intensity: "moderate", feeling: nil, completedRecommended: true, parentNote: nil, version: 0, createdAt: nil, updatedAt: nil)
        let sameDateOtherChild = HealthCheckInRecord(id: "checkin-b", childID: "child-b", checkInDate: "2026-08-24", activityType: "跑步", durationMinutes: 30, intensity: "high", feeling: "很好", completedRecommended: false, parentNote: nil, version: 0, createdAt: nil, updatedAt: nil)
        store.update { state in
            state.healthCheckins = [first, sameDateOtherChild]
            state.healthCheckinSyncStates = [first.id: .pendingSync, sameDateOtherChild.id: .submitted]
        }
        let restored = LocalFeatureStore(defaults: defaults).state
        XCTAssertEqual(Set(restored.healthCheckins.map(\.id)), Set(["checkin-a", "checkin-b"]))
        XCTAssertEqual(restored.healthCheckinSyncStates["checkin-a"], .pendingSync)
        XCTAssertEqual(restored.healthCheckins.first(where: { $0.childID == "child-b" })?.activityType, "跑步")
    }

    func testAppStateRestoresSavedSessionBeforeDashboardRefresh() async {
        let suite = "xiangshang.youth.session-tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        let first = AppState(featureStore: LocalFeatureStore(defaults: defaults))
        await first.login(phone: "13800138000")
        if let second = first.data?.students.first(where: { $0.id == "s02" }) { first.selectChild(second) }
        let restored = AppState(featureStore: LocalFeatureStore(defaults: defaults))
        XCTAssertEqual(restored.profile?.name, "王女士")
        XCTAssertNil(restored.selectedRole, "A restored session must return to role selection instead of locking the last role.")
        XCTAssertEqual(restored.localFeatures.selectedChildID, "s02")
        XCTAssertTrue(restored.restoringSession, "Session restoration must be visible synchronously so the launch poster cannot transition to a half-restored role screen.")
    }

    func testTransientSessionRestoreFailurePreservesCredentialsAndOfflineWritesForRetry() async throws {
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

        XCTAssertEqual(state.profile?.id, "u1")
        XCTAssertNil(state.selectedRole)
        XCTAssertNil(state.data)
        XCTAssertNotNil(state.error)
        state.clearError()
        XCTAssertNil(state.error)
        XCTAssertEqual(LocalFeatureStore(defaults: defaults).state.sessionProfile?.id, "u1")
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

        let wrongCode = await state.bindChild(name: "王小明", code: "wrong-code")
        XCTAssertFalse(wrongCode)
        let wrongName = await state.bindChild(name: "其他学生", code: "XS-S01")
        XCTAssertFalse(wrongName)
        let firstChildBound = await state.bindChild(name: "王小明", code: "XS-S01")
        XCTAssertTrue(firstChildBound)
        XCTAssertEqual(state.selectedChild?.id, "s01")
        XCTAssertEqual(state.boundChildren.map(\.id), ["s01"])
        let secondChildBound = await state.bindChild(name: "王小雨", code: "s02")
        XCTAssertTrue(secondChildBound)
        XCTAssertEqual(Set(state.boundChildren.map(\.id)), ["s01", "s02"])
    }

    func testExpertBookingIsIdempotentAndCanBeCorrectedUntilRemoteSync() async {
        let suite = "xiangshang.youth.expert-idempotency-tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        let state = AppState(featureStore: LocalFeatureStore(defaults: defaults))
        await state.login(phone: "13800138000")

        let expertID = "expert-zhang-child-sports"
        state.bookExpert(name: "张教授", preferredDate: "周五上午", note: "运动发展咨询", expertID: expertID)
        state.bookExpert(name: "张教授", preferredDate: "周五上午", note: "运动发展咨询", expertID: expertID)

        XCTAssertEqual(state.localFeatures.expertAppointments.count, 1)
        XCTAssertEqual(state.localFeatures.expertAppointments.first?.status, .pendingSync)

        state.bookExpert(name: "张教授", preferredDate: "周六下午", note: "希望改为周末咨询", expertID: expertID)
        XCTAssertEqual(state.localFeatures.expertAppointments.count, 1)
        XCTAssertEqual(state.localFeatures.expertAppointments.first?.preferredDate, "周六下午")
        XCTAssertEqual(state.localFeatures.expertAppointments.first?.note, "希望改为周末咨询")
    }

    func testMockWorkflowCommandsExposeTerminalSuccessAndValidationStates() async {
        let suite = "xiangshang.youth.workflow-command-tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        let state = AppState(repository: MockRepository.shared, featureStore: LocalFeatureStore(defaults: defaults))
        await state.login(phone: "13800138000")
        authorizeTeacherFixture(state)

        let activityResult = await state.submitActivityCommand("health-growth-season-2026", contactName: "王女士", phone: "13800138000")
        XCTAssertTrue(activityResult)
        if case .succeeded = state.workflowState(for: "activity:health-growth-season-2026") {} else { XCTFail("Mock activity command should reach succeeded") }

        let invalidActivityResult = await state.submitActivityCommand("health-growth-season-2026", contactName: "", phone: "123")
        XCTAssertFalse(invalidActivityResult)
        if case .failed = state.workflowState(for: "activity:health-growth-season-2026") {} else { XCTFail("Invalid activity command should expose failure") }

        let statusResult = await state.submitTaskStatusCommand(taskID: "task-demo", studentID: "s01", status: .review, note: "请核验动作视频")
        XCTAssertTrue(statusResult)
        if case .succeeded = state.workflowState(for: "task-status:task-demo|s01") {} else { XCTFail("Mock task status command should reach succeeded") }
        XCTAssertEqual(state.taskStatus(for: state.data!.students[0], taskID: "task-demo"), .review)
        XCTAssertEqual(state.localFeatures.taskScopedSyncStates["task-demo|s01"], .pendingSync)
    }

    func testFailedTeacherStatusUpdateRemainsPersistedForRetry() async throws {
        let suite = "xiangshang.youth.task-status-retry-tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        let state = AppState(repository: TaskStatusFailingRepository(), featureStore: LocalFeatureStore(defaults: defaults))
        await state.login(phone: "13800138000")
        authorizeTeacherFixture(state)
        // s19 belongs to the fixture's authorized c31 scope and can legally
        // transition from absent to checked-in. The old s06 fixture is in c52
        // and correctly fails the production authorization guard.
        let student = try XCTUnwrap(state.data?.students.first(where: { $0.id == "s19" }))

        let succeeded = await state.submitTaskStatusCommand(taskID: "task-retry", studentID: student.id, status: .checkedIn, note: "已到场")

        XCTAssertFalse(succeeded)
        XCTAssertEqual(state.taskStatus(for: student, taskID: "task-retry"), .checkedIn)
        XCTAssertEqual(state.localFeatures.taskScopedSyncStates["task-retry|\(student.id)"], .failed)
        XCTAssertEqual(state.pendingSyncCount, 1)
        if case .failed = state.workflowState(for: "task-status:task-retry|\(student.id)") {} else { XCTFail("Failed task updates must expose a retryable command state") }
    }

    func testTaskStatusConflictClearsStaleOptimisticProjection() async throws {
        let suite = "xiangshang.youth.task-status-conflict-tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        let state = AppState(repository: TaskStatusConflictRepository(), featureStore: LocalFeatureStore(defaults: defaults))
        await state.login(phone: "13800138000")
        authorizeTeacherFixture(state)
        let student = try XCTUnwrap(state.data?.students.first(where: { $0.id == "s19" }))

        let succeeded = await state.submitTaskStatusCommand(taskID: "task-conflict", studentID: student.id, status: .checkedIn, note: "已到场")

        XCTAssertFalse(succeeded)
        XCTAssertNil(state.localFeatures.taskScopedStatuses["task-conflict|\(student.id)"], "冲突后不得继续展示本地乐观状态")
        XCTAssertNil(state.localFeatures.taskScopedStatusVersions["task-conflict|\(student.id)"], "冲突后不得复用过期版本号")
        XCTAssertEqual(state.localFeatures.taskScopedSyncStates["task-conflict|\(student.id)"], .failed)
        if case .failed = state.workflowState(for: "task-status:task-conflict|\(student.id)") {} else { XCTFail("版本冲突必须进入可刷新/重试状态") }
    }

    func testPendingSyncCountExposesUnacknowledgedLocalWrites() {
        let suite = "xiangshang.youth.pending-count-tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        let store = LocalFeatureStore(defaults: defaults)
        let state = AppState(featureStore: store)

        state.registerActivity("health-growth-season-2026", contactName: "王女士", phone: "13800138000")
        state.bookExpert(name: "张教授", preferredDate: "周五上午", note: "运动发展咨询", expertID: "expert-zhang-child-sports")
        state.saveCourseUpload(taskID: "after-class-upload", attendanceCount: 20, notes: "课堂记录", attachmentName: "课堂.jpg", attachmentReference: "local://course/1", submit: true)
        store.update { value in
            value.taskScopedSyncStates["task-pending|s01"] = .pendingSync
            value.bodyAssessmentSyncStates["s01"] = .pendingSync
        }
        let reloaded = AppState(featureStore: store)

        XCTAssertEqual(reloaded.pendingSyncCount, 5)
    }

    func testCourseUploadSubmitRequiresRealFormValuesAndAttachmentReference() {
        let suite = "xiangshang.youth.course-upload-validation-tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        let state = AppState(featureStore: LocalFeatureStore(defaults: defaults))

        state.saveCourseUpload(taskID: "after-class-upload", attendanceCount: 0, notes: "", attachmentName: "", submit: true)
        XCTAssertTrue(state.localFeatures.courseUploads.isEmpty, "Invalid shortcut data must not be persisted as a submission")

        state.saveCourseUpload(taskID: "after-class-upload", attendanceCount: 20, notes: "课堂记录", attachmentName: "课堂.jpg", attachmentReference: "local://course/1", submit: true)
        XCTAssertEqual(state.localFeatures.courseUploads.first?.status, .pendingSync)
        XCTAssertEqual(state.localFeatures.courseUploads.first?.attendanceCount, 20)
    }

    func testCourseProgressKeyIsolatedByChildAndLesson() {
        let first = AppState.courseProgressKey(childID: "child-a", courseID: "course-1", lessonID: "lesson-1")
        let otherChild = AppState.courseProgressKey(childID: "child-b", courseID: "course-1", lessonID: "lesson-1")
        let otherLesson = AppState.courseProgressKey(childID: "child-a", courseID: "course-1", lessonID: "lesson-2")
        XCTAssertNotEqual(first, otherChild)
        XCTAssertNotEqual(first, otherLesson)
    }

    func testPlaybackSourceDecodesSignedMediaAndOptionalCaptionTracks() throws {
        let payload = Data(#"{"lessonId":"lesson-1","courseId":"course-1","videoSource":"https://media.example.test/signed.m3u8","durationMs":30000,"captions":[{"url":"https://media.example.test/zh.vtt","language":"zh-CN","label":"中文","mimeType":"text/vtt"}]}"#.utf8)
        let source = try JSONDecoder().decode(PlaybackSource.self, from: payload)

        XCTAssertEqual(source.lessonID, "lesson-1")
        XCTAssertEqual(source.videoSource, "https://media.example.test/signed.m3u8")
        XCTAssertEqual(source.captions?.first?.language, "zh-CN")
        XCTAssertEqual(source.captions?.first?.mimeType, "text/vtt")
    }

    func testMockSupportMessageIsSavedLocallyWithoutInventingAServiceReply() async {
        let suite = "xiangshang.youth.support-sync-tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        let state = AppState(repository: MockRepository.shared, featureStore: LocalFeatureStore(defaults: defaults))
        await state.login(phone: "13800138000")

        let submitted = await state.submitSupportCommand("想咨询孩子的姿态观察。")
        XCTAssertTrue(submitted)
        XCTAssertEqual(state.localFeatures.supportMessages.count, 1)
        XCTAssertTrue(state.localFeatures.supportMessages[0].isMine)
        XCTAssertEqual(state.localFeatures.supportMessages[0].status, .pendingSync)
        XCTAssertEqual(state.pendingSyncCount, 1)
        if case let .succeeded(message) = state.workflowState(for: "support") {
            XCTAssertTrue(message.contains("本机"))
        } else {
            XCTFail("Mock support should clearly acknowledge local save")
        }
    }

    func testClassCircleCommentUsesTheCurrentRegisteredAccountName() async {
        let suite = "xiangshang.youth.comment-author-tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        let state = AppState(repository: MockRepository.shared, featureStore: LocalFeatureStore(defaults: defaults))
        await state.login(phone: "13800138000", displayName: "陈女士")

        state.addClassPostComment(postID: UUID(), text: "今天完成了练习")

        XCTAssertEqual(state.activeDisplayName, "陈女士")
        XCTAssertEqual(state.localFeatures.classPostComments.last?.author, "陈女士")
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
    let supportsRemoteAcknowledgement = false
    func loadDashboard() async throws -> DashboardData { throw ApiError.network }
    func report(for student: Student) -> DiagnosisReport { MockRepository.shared.report(for: student) }
}

private struct UnauthorizedRepository: YouthRepository {
    let supportsRemoteAcknowledgement = false
    func loadDashboard() async throws -> DashboardData { try await MockRepository.shared.loadDashboard() }
    func report(for student: Student) -> DiagnosisReport { MockRepository.shared.report(for: student) }
    func loadReport(for student: Student) async throws -> DiagnosisReport { throw ApiError.unauthorized }
    func submitActivity(_ value: ActivityRegistration) async throws -> ActivityRegistrationAck { throw ApiError.unauthorized }
}

private struct TaskStatusFailingRepository: YouthRepository {
    let supportsRemoteAcknowledgement = false
    func loadDashboard() async throws -> DashboardData { try await MockRepository.shared.loadDashboard() }
    func report(for student: Student) -> DiagnosisReport { MockRepository.shared.report(for: student) }
    func updateTaskStatus(taskID: String, studentID: String, status: TaskStatus, note: String?, expectedVersion: Int?) async throws -> Int? { throw ApiError.network }
}

private struct TaskStatusConflictRepository: YouthRepository {
    let supportsRemoteAcknowledgement = false
    func loadDashboard() async throws -> DashboardData { try await MockRepository.shared.loadDashboard() }
    func report(for student: Student) -> DiagnosisReport { MockRepository.shared.report(for: student) }
    func updateTaskStatus(taskID: String, studentID: String, status: TaskStatus, note: String?, expectedVersion: Int?) async throws -> Int? {
        throw ApiError.conflict("记录已被其他人更新，请刷新后重试")
    }
}
