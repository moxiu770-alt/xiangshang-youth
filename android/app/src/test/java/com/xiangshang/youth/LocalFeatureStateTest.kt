package com.xiangshang.youth

import com.xiangshang.youth.core.service.ClassPost
import com.xiangshang.youth.core.service.ActivityRegistration
import com.xiangshang.youth.core.service.CourseUploadRecord
import com.xiangshang.youth.core.service.CourseUploadValidator
import com.xiangshang.youth.core.service.ExpertAppointment
import com.xiangshang.youth.core.service.FamilyHealthRecord
import com.xiangshang.youth.core.service.LocalSubmissionStatus
import com.xiangshang.youth.core.service.LocalFeatureState
import com.xiangshang.youth.core.service.LocalAppSettings
import com.xiangshang.youth.core.service.SupportMessage
import com.xiangshang.youth.core.service.HealthCheckInRecord
import com.xiangshang.youth.core.model.TaskStatus
import com.xiangshang.youth.core.model.AssessmentRiskLevel
import com.xiangshang.youth.core.model.TestTask
import com.xiangshang.youth.core.model.TestItem
import com.xiangshang.youth.core.model.Student
import com.xiangshang.youth.core.model.UserProfile
import com.xiangshang.youth.core.model.UserRole
import com.xiangshang.youth.core.service.MeResponse
import com.xiangshang.youth.core.service.ApiEnvelope
import com.xiangshang.youth.core.service.ApiError
import com.xiangshang.youth.core.service.requireData
import com.xiangshang.youth.core.mock.MockRepository
import com.xiangshang.youth.core.repository.RemoteRepository
import com.xiangshang.youth.core.repository.RepositoryProvider
import com.xiangshang.youth.core.repository.YouthRepository
import com.xiangshang.youth.core.repository.DashboardData
import com.xiangshang.youth.app.AppUiState
import com.xiangshang.youth.app.AppViewModel
import com.xiangshang.youth.app.CourseRecommendationTarget
import com.xiangshang.youth.app.TeacherOverviewContext
import com.xiangshang.youth.feature.parent.courseProgressFraction
import com.xiangshang.youth.feature.parent.shouldCheckpoint
import com.xiangshang.youth.core.util.ChildBindingValidator
import com.xiangshang.youth.core.util.AuthIdentity
import com.xiangshang.youth.core.util.BusinessClock
import kotlinx.coroutines.runBlocking
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotEquals
import org.junit.Assert.assertTrue
import org.junit.Test
import java.util.Date

class LocalFeatureStateTest {
    @Test fun missingRemoteEnvelopePayloadIsNotRenderedAsAnEmptyState() {
        val failure = runCatching { ApiEnvelope<List<String>>("OK", "ok", null).requireData() }.exceptionOrNull()
        assertTrue(failure is ApiError.InvalidResponse)
        assertEquals(emptyList<String>(), ApiEnvelope("OK", "ok", emptyList<String>()).requireData())
    }

    @Test fun missingRemoteBatchTaskReceiptIsNotFabricatedAsSuccess() {
        val failure = runCatching {
            ApiEnvelope<com.xiangshang.youth.core.service.TaskBatchStatusAck>("OK", "ok", null).requireData()
        }.exceptionOrNull()
        assertTrue(failure is ApiError.InvalidResponse)
    }

    /** A Remote implementation that misses an endpoint must fail loudly.
     * Returning a local activity, a pending-sync receipt, or an empty result
     * here would make production screens appear to have completed an action. */
    private class IncompleteRemoteRepository : YouthRepository {
        override val supportsRemoteAcknowledgement = true
        override suspend fun dashboard(studentPage: Int?, studentPageSize: Int?): DashboardData = MockRepository().dashboard(studentPage, studentPageSize)
        override fun report(student: Student) = MockRepository().report(student)
    }

    @Test fun incompleteRemoteRepositoryCannotUseMockOnlyDefaults() = runBlocking {
        val repository = IncompleteRemoteRepository()
        val failure = runCatching { repository.activities() }.exceptionOrNull()
        assertTrue(failure is ApiError.NotConfigured)
    }

    @Test fun incompleteRemoteRepositoryUsesTypedFailureForAllDirectDefaults() = runBlocking {
        val repository = IncompleteRemoteRepository()
        assertTrue(runCatching { repository.bindChild("王小明", "XS-S01") }.exceptionOrNull() is ApiError.NotConfigured)
        assertTrue(runCatching { repository.lessonPlayback("lesson-1") }.exceptionOrNull() is ApiError.NotConfigured)
        assertTrue(runCatching { repository.loadClassPostAttachment("file-1") }.exceptionOrNull() is ApiError.NotConfigured)
    }

    @Test fun teacherOverviewContextRejectsAStaleClassOrTaskResponse() {
        val current = TeacherOverviewContext("school-a", "class-a", "task-a", "standard-v1")
        assertNotEquals(current, TeacherOverviewContext("school-b", "class-a", "task-a", "standard-v1"))
        assertNotEquals(current, TeacherOverviewContext("school-a", "class-b", "task-a", "standard-v1"))
        assertNotEquals(current, TeacherOverviewContext("school-a", "class-a", "task-b", "standard-v1"))
        assertNotEquals(current, TeacherOverviewContext("school-a", "class-a", "task-a", "standard-v2"))
    }

    @Test fun remoteTaskStatusRequiresCompositeTaskIdentity() = runBlocking {
        val failure = runCatching {
            RemoteRepository().updateTaskStatus("", "student-1", TaskStatus.CheckedIn, null, 1)
        }.exceptionOrNull()
        assertTrue(failure is IllegalArgumentException)
        assertTrue(failure?.message?.contains("任务编号") == true)
    }

    @Test
    fun healthCheckinsUseChildAndBusinessDateAsTheVisibleScope() {
        val first = HealthCheckInRecord("checkin-a", "child-a", "2026-08-24", "跟练", 20, "moderate")
        val sameDateOtherChild = HealthCheckInRecord("checkin-b", "child-b", "2026-08-24", "跑步", 30, "high")
        val records = listOf(first, sameDateOtherChild)
        assertEquals("跟练", records.single { it.childId == "child-a" && it.checkInDate == "2026-08-24" }.activityType)
        assertEquals("跑步", records.single { it.childId == "child-b" && it.checkInDate == "2026-08-24" }.activityType)
    }
    @Test fun reportCourseDestinationUsesStableIdsAndChildScope() {
        val first = CourseRecommendationTarget("child-a", "course-1", "lesson-1", "协调训练")
        val sameTitleDifferentLesson = CourseRecommendationTarget("child-a", "course-1", "lesson-2", "协调训练")
        val sameLessonDifferentChild = CourseRecommendationTarget("child-b", "course-1", "lesson-1", "协调训练")

        assertNotEquals(first, sameTitleDifferentLesson)
        assertNotEquals(first, sameLessonDifferentChild)
    }

    @Test fun mockRosterCarriesStableClassScopeInsteadOfUsingClassNameAsKey() = runBlocking {
        val data = MockRepository().dashboard()
        assertTrue(data.students.all { it.classId != null })
        assertEquals("c31", data.students.first { it.className == "三年级1班" }.classId)
    }

    @Test fun teacherTaskScopeRejectsStudentsOutsideAuthorizedClassIds() = runBlocking {
        val data = MockRepository().dashboard()
        val teacher = AppUiState(
            profile = UserProfile("teacher-scope", "同名教师", "13800138000", UserRole.Teacher, data.school.name, authorizedClassIds = listOf("c31")),
            role = UserRole.Teacher,
            data = data
        )
        assertTrue(teacher.isTeacherAuthorizedFor(data.students.first { it.classId == "c31" }))
        assertFalse(teacher.isTeacherAuthorizedFor(data.students.first { it.classId == "c32" }))
    }

    @Test fun courseProgressKeyIsolatedByChildAndLesson() {
        val first = AppViewModel.courseProgressKey("child-a", "course-1", lessonId = "lesson-1")
        assertNotEquals(first, AppViewModel.courseProgressKey("child-b", "course-1", lessonId = "lesson-1"))
        assertNotEquals(first, AppViewModel.courseProgressKey("child-a", "course-1", lessonId = "lesson-2"))
    }

    @Test
    fun coursePlayerProgressIsBoundedAndCheckpointedByPlaybackTime() {
        assertEquals(0f, courseProgressFraction(5_000, 0, completed = false))
        assertEquals(.5f, courseProgressFraction(15_000, 30_000, completed = false))
        assertEquals(1f, courseProgressFraction(90_000, 30_000, completed = false))
        assertEquals(1f, courseProgressFraction(0, 0, completed = true))
        assertFalse(shouldCheckpoint(0, 14_999))
        assertTrue(shouldCheckpoint(0, 15_000))
        assertTrue(shouldCheckpoint(30_000, 15_000))
    }
    @Test
    fun businessClockKeepsSchoolDayStableAcrossDeviceMidnight() {
        // 16:30 UTC is already the next school day in Shanghai, while it is
        // still the previous calendar day in a UTC device setting.
        val instant = Date(1787416200000L) // 2026-08-22T16:30:00Z
        assertEquals("2026-08-23", BusinessClock.day(instant))
        assertEquals("Asia/Shanghai", BusinessClock.timeZone.id)
    }

    @Test
    fun voiceGuidancePreferenceIsOptOutAndSurvivesStateCopies() {
        val defaults = LocalAppSettings()
        assertTrue(defaults.voiceGuidanceEnabled)
        assertFalse(defaults.analyticsEnabled)
        val muted = defaults.copy(voiceGuidanceEnabled = false)
        assertFalse(muted.voiceGuidanceEnabled)
        assertTrue(muted.notificationsEnabled)
    }

    @Test
    fun studentAndLocalStateCarryServerTaskVersionForConflictSafeEdits() {
        val student = Student(
            id = "s-version",
            name = "测试学生",
            grade = "三年级",
            className = "三年级1班",
            region = "南湖区",
            isPovertyArea = false,
            taskStatus = TaskStatus.CheckedIn,
            totalScore = null,
            gender = "男",
            birthDate = "2017-01-01",
            taskVersion = 7
        )
        val local = LocalFeatureState(taskScopedStatusVersions = mapOf("t1|${student.id}" to student.taskVersion!!))

        assertEquals(7, student.taskVersion)
        assertEquals(7, local.taskScopedStatusVersions["t1|${student.id}"])
    }

    @Test
    fun oauthOnlySessionUsesAnExplicitUnboundPhoneLabel() {
        assertEquals("未绑定手机号", MeResponse("u-oauth", "微信用户", null, "parent").displayPhone)
        assertEquals("未绑定手机号", MeResponse("u-oauth", "微信用户", "  ", "parent").displayPhone)
        assertEquals("13800000000", MeResponse("u-phone", "王女士", "13800000000", "parent").displayPhone)
    }
    @Test
    fun mobileRolePickerOnlyExposesParentAndTeacherWorkbenches() {
        assertEquals(listOf(UserRole.Parent, UserRole.Teacher), UserRole.mobileRoles)
        assertFalse(UserRole.Principal in UserRole.mobileRoles)
    }

    @Test
    fun publishedReportGateScopesThePublishedBatchToTheStudent() = runBlocking {
        val base = MockRepository().dashboard()
        val fourthGradeStudent = base.students.first { it.id == "s03" }.copy(taskStatus = TaskStatus.Completed)
        val fifthGradeStudent = base.students.first { it.id == "s05" }.copy(taskStatus = TaskStatus.Completed)
        val selectedTask = base.tasks.first { it.id == "t2" }
        val state = AppUiState(data = base.copy(students = listOf(fourthGradeStudent, fifthGradeStudent), tasks = listOf(selectedTask)))

        assertTrue(state.hasPublishedSchoolReport(fourthGradeStudent))
        assertFalse(state.hasPublishedSchoolReport(fifthGradeStudent))
    }

    @Test
    fun familyHealthRecordKeepsParentEntriesSeparateFromCompletionMarkers() {
        val local = LocalFeatureState(
            completedAssessments = setOf("s01-vision"),
            familyHealthRecords = mapOf("s01-vision" to FamilyHealthRecord("s01", "vision", "2026-08-13 10:00", mapOf("基础信息" to "每日户外活动 2 小时")))
        )

        assertEquals("每日户外活动 2 小时", local.familyHealthRecords["s01-vision"]?.entries?.get("基础信息"))
        assertFalse(local.familyHealthRecords.containsKey("s01-oral"))
    }

    @Test
    fun repositoryProviderUsesBundledMockDataByDefault() {
        // CI and a school-demo build must remain local unless the Gradle
        // integration flag explicitly opts into the remote source.
        assertFalse(BuildConfig.USE_REMOTE_DATA_SOURCE)
        assertTrue(RepositoryProvider.create() is MockRepository)
    }

    @Test
    fun wechatAuthorizationIdentifierNeverBecomesAProfilePhone() {
        assertEquals("未绑定手机号", AuthIdentity.displayPhone(AuthIdentity.wechatAuthorizationIdentifier))
        assertEquals("未绑定手机号", AuthIdentity.displayPhone("  "))
        assertEquals("13900139000", AuthIdentity.displayPhone(" 13900139000 "))
    }

    @Test
    fun activeDisplayNameUsesTheSessionProfileInsteadOfSeededMockNames() {
        val parent = AppUiState(profile = UserProfile("u1", "陈女士", "13800138000", UserRole.Parent, "向上实验小学"), role = UserRole.Parent)
        val teacher = AppUiState(profile = UserProfile("t1", "刘老师", "13800138000", UserRole.Teacher, "向上实验小学"), role = UserRole.Teacher)
        val fallback = AppUiState(role = UserRole.Parent)

        assertEquals("陈女士", parent.activeDisplayName)
        assertEquals("刘老师", teacher.activeDisplayName)
        assertEquals("家长", fallback.activeDisplayName)
    }

    @Test
    fun mockDashboardMatchesPhaseOneDataContract() = runBlocking {
        val data = MockRepository().dashboard()
        assertEquals(20, data.students.size)
        assertEquals(6, data.classes.size)
        assertEquals(3, data.grades.size)
        assertEquals(3, data.tasks.size)
        assertEquals(2, data.children.size)
        assertTrue(data.tasks.all { it.items.size == 7 })
        assertEquals(6, data.messages.size)
        assertEquals(2, data.messages.count { it.category == "系统" })
        assertEquals(4, data.messages.count { it.category != "系统" })
        assertEquals(7, com.xiangshang.youth.core.model.TestItem.entries.size)
        assertEquals("s01", data.students.first().id)
        assertEquals("s02", data.students[1].id)
        assertTrue(data.students.any { it.isPovertyArea })
    }

    @Test
    fun selectedTaskScopesRepresentativeStudentMetricsToItsBatch() = runBlocking {
        val data = MockRepository().dashboard()
        val autumnTask = data.tasks.first { it.id == "t1" }
        val retestTask = data.tasks.first { it.id == "t2" }

        assertEquals(data.students.size, autumnTask.scopedStudents(data.students).size)
        assertEquals(setOf("三年级", "四年级", "五年级"), autumnTask.scopedStudents(data.students).map { it.grade }.toSet())
        assertTrue(retestTask.scopedStudents(data.students).all { it.className == "四年级1班" })
        assertTrue(retestTask.scopedStudents(data.students).none { it.grade == "三年级" })
    }

    @Test
    fun principalSelectedTaskScopesReportsToTheSameBatch() = runBlocking {
        val repository = MockRepository()
        val data = repository.dashboard()
        val retestTask = data.tasks.first { it.id == "t2" }
        val scopedStudents = retestTask.scopedStudents(data.students)
        val completedStudents = retestTask.completedStudents(data.students) { it.taskStatus }
        val reports = completedStudents.map(repository::report)

        assertTrue(scopedStudents.all { it.grade == "四年级" && it.className == "四年级1班" })
        assertTrue(completedStudents.all { it.taskStatus == TaskStatus.Completed })
        assertEquals(completedStudents.size, reports.size)
        assertEquals(completedStudents.size * com.xiangshang.youth.core.model.TestItem.entries.size, reports.sumOf { it.scores.size })
    }

    @Test
    fun unstartedTaskDoesNotQualifyForCurrentTaskReportAverages() = runBlocking {
        val data = MockRepository().dashboard()
        val futureTask = data.tasks.first { it.id == "t3" }

        assertEquals(0, futureTask.completedCount)
        assertFalse(futureTask.hasPublishedResults)
    }

    @Test
    fun onlyCompletedStudentsCanOpenAPublishedSchoolReport() = runBlocking {
        val data = MockRepository().dashboard()
        val state = AppUiState(data = data)
        val completed = data.students.first { it.taskStatus == TaskStatus.Completed }
        val pendingReview = data.students.first { it.taskStatus == TaskStatus.Review }

        assertTrue(state.hasPublishedSchoolReport(completed))
        assertFalse(state.hasPublishedSchoolReport(pendingReview))
    }

    @Test
    fun featureWorkflowStateKeepsAllSubmittedOperations() {
        val state = LocalFeatureState(
            activityRegistered = true,
            activityRegistrations = listOf(ActivityRegistration(activityId = "health-growth-season-2026", contactName = "王女士", phone = "13800138000")),
            completedAssessments = setOf("s01-fitness"),
            familyHealthRecords = mapOf("s01-mental" to FamilyHealthRecord("s01", "mental", "2026-08-13 10:00", mapOf("家庭感受记录" to "近一周睡眠规律"))),
            courseProgress = mapOf("体姿改善课程" to .8f),
            supportMessages = listOf(SupportMessage("想了解课程", true)),
            classPosts = listOf(ClassPost(author = "王女士", content = "今天完成运动打卡")),
            likedPostIds = setOf("post-1", "teacher-announcement"),
            postComments = mapOf("post-1" to listOf("继续加油")),
            expertAppointments = listOf(ExpertAppointment(expertName = "张教授", preferredDate = "周五上午", note = "运动发展咨询")),
            courseUploads = listOf(CourseUploadRecord(taskId = "after-class-upload", attendanceCount = 26, notes = "已完成课程", attachmentName = "课堂.jpg", status = LocalSubmissionStatus.PendingSync)),
            uploadedTaskIds = setOf("after-class-upload"),
            checkedInToday = true,
            taskScopedStatuses = mapOf("t1|s01" to TaskStatus.Review),
            taskScopedSyncStates = mapOf("t1|s01" to LocalSubmissionStatus.PendingSync),
            taskScopedReviewNotes = mapOf("t1|s01" to "核验视频后建议周五补测。"),
            sessionActive = true,
            sessionPhone = "13800138000",
            sessionRoleName = "Teacher",
            parentAccountName = "王女士",
            selectedChildId = "s02",
            selectedPrincipalTaskId = "t2",
            teacherUsesSportsWorkbench = true,
            drafts = mapOf(
                "account-feedback" to "希望增加课程提醒",
                "assessment-progress-s01-fitness" to "2"
            )
        )

        assertTrue(state.activityRegistered && state.checkedInToday)
        assertEquals("王女士", state.activityRegistrations.single().contactName)
        assertTrue("s01-fitness" in state.completedAssessments)
        assertEquals("近一周睡眠规律", state.familyHealthRecords["s01-mental"]?.entries?.get("家庭感受记录"))
        assertEquals(.8f, state.courseProgress["体姿改善课程"])
        assertEquals("王女士", state.classPosts.single().author)
        assertTrue("post-1" in state.likedPostIds)
        assertTrue("teacher-announcement" in state.likedPostIds)
        assertEquals("继续加油", state.postComments["post-1"]?.single())
        assertEquals("张教授", state.expertAppointments.single().expertName)
        assertEquals(LocalSubmissionStatus.PendingSync, state.courseUploads.single().status)
        assertTrue("after-class-upload" in state.uploadedTaskIds)
        assertEquals(TaskStatus.Review, state.taskScopedStatuses["t1|s01"])
        assertEquals(LocalSubmissionStatus.PendingSync, state.taskScopedSyncStates["t1|s01"])
        assertEquals("核验视频后建议周五补测。", state.taskScopedReviewNotes["t1|s01"])
        assertTrue(state.sessionActive)
        assertEquals("Teacher", state.sessionRoleName)
        assertEquals("王女士", state.parentAccountName)
        assertEquals("s02", state.selectedChildId)
        assertEquals("t2", state.selectedPrincipalTaskId)
        assertTrue(state.teacherUsesSportsWorkbench)
        assertEquals("希望增加课程提醒", state.drafts["account-feedback"])
        assertEquals("2", state.drafts["assessment-progress-s01-fitness"])
        assertTrue("account-feedback" !in state.copy(drafts = state.drafts - "account-feedback").drafts)
    }

    @Test
    fun remoteReportNeverFallsBackToBundledMockBeforeEndpointLoads() = runBlocking {
        val student = MockRepository().dashboard().students.first()
        val report = RemoteRepository().report(student)

        assertEquals(student.id, report.student.id)
        assertTrue(report.scores.isEmpty())
        assertEquals(AssessmentRiskLevel.Unavailable, report.riskLevel)
        assertTrue(report.riskAlerts.single().contains("尚未从学校服务返回"))
    }

    @Test
    fun mockReportRiskRulesMatchStudentScores() = runBlocking {
        val students = MockRepository().dashboard().students
        assertEquals(listOf("暂无高风险提示"), MockRepository().report(students.first()).riskAlerts)
        assertEquals(listOf("倒退平衡项目偏弱，建议4周后复测"), MockRepository().report(students[1]).riskAlerts)
    }

    @Test
    fun mockStudentStatusesMatchReferenceTaskBoardSequence() = runBlocking {
        val statuses = MockRepository().dashboard().students.take(10).map { it.taskStatus }
        assertEquals(
            listOf(
                TaskStatus.Completed,
                TaskStatus.Completed,
                TaskStatus.Review,
                TaskStatus.Retest,
                TaskStatus.Waiting,
                TaskStatus.NotCheckedIn,
                TaskStatus.Completed,
                TaskStatus.Testing,
                TaskStatus.Absent,
                TaskStatus.CheckedIn
            ),
            statuses
        )
    }

    @Test
    fun taskStatusStateMachineRejectsImpossibleQueueJumps() {
        assertEquals(listOf(TaskStatus.CheckedIn, TaskStatus.Absent), TaskStatus.NotCheckedIn.allowedNextStatuses())
        assertTrue(TaskStatus.NotCheckedIn.allowsTransitionTo(TaskStatus.CheckedIn))
        assertTrue(!TaskStatus.NotCheckedIn.allowsTransitionTo(TaskStatus.Completed))
        assertTrue(TaskStatus.Testing.allowsTransitionTo(TaskStatus.Review))
        assertTrue(TaskStatus.Review.allowsTransitionTo(TaskStatus.Retest))
        assertTrue(!TaskStatus.Completed.allowsTransitionTo(TaskStatus.Waiting))
    }

    @Test
    fun taskAggregatesClampMalformedCountsAndNormalizeItems() {
        val task = TestTask("bad", "", "", "", "全校", "", 99, -2, TaskStatus.Testing, "v1", listOf(TestItem.ObstacleJump, TestItem.ObstacleJump))
        assertEquals(0, task.boundedTotalCount)
        assertEquals(0, task.boundedCompletedCount)
        assertEquals(0, task.completionRate)
        assertEquals(false, task.hasPublishedResults)
        assertEquals(listOf(TestItem.ObstacleJump), task.normalizedItems)
    }

    @Test
    fun taskScopeUsesStableStudentIdsInsteadOfDisplayNames() = runBlocking {
        val data = MockRepository().dashboard()
        val source = data.students.first { it.id == "s03" }
        val sameNamedButOutOfScope = source.copy(id = "different-student", classId = "different-class")
        val task = TestTask("stable-scope", "", "", "", source.grade, source.className, 0, 1, TaskStatus.NotCheckedIn, "v1", classIds = listOf("different-class"), studentIds = listOf(source.id))

        assertEquals(listOf(source.id), task.scopedStudents(listOf(source, sameNamedButOutOfScope)).map { it.id })
    }

    @Test
    fun mockReportExposesSevenItemTotalScore() = runBlocking {
        val data = MockRepository().dashboard()
        val student = data.students.first()
        val report = MockRepository().report(student)
        assertEquals(7, report.scores.size)
        assertEquals(28.5, report.totalScore, 0.001)
        assertEquals(report.totalScore, data.students[0].totalScore ?: 0.0, 0.001)
        assertTrue(data.students[2].totalScore == null)
        assertEquals("2026-08-01", report.regionPolicy.effectiveDate)
        assertEquals(student.region, report.regionPolicy.region)
        assertEquals("男", student.gender)
        assertEquals("王", UserProfile("u1", "王女士", "13800138000", UserRole.Parent, "向上实验小学").avatarInitials)
    }

    @Test
    fun asyncReportSeamKeepsMockReportRenderable() = runBlocking {
        val student = MockRepository().dashboard().students.first()
        val report = MockRepository().loadReport(student)
        assertEquals(student.id, report.student.id)
        assertEquals(7, report.scores.size)
    }

    @Test
    fun messageReadStateClearsTheSharedTeacherAndParentBadge() = runBlocking {
        val data = MockRepository().dashboard()
        val initial = AppUiState(data = data)
        assertEquals(1, initial.unreadMessageCount)
        val afterOpeningWarning = initial.copy(local = LocalFeatureState(readMessageIds = setOf("m1")))
        assertEquals(0, afterOpeningWarning.unreadMessageCount)
        val afterMarkAll = initial.copy(local = LocalFeatureState(readMessageIds = data.messages.map { it.id }.toSet()))
        assertEquals(0, afterMarkAll.unreadMessageCount)
    }

    @Test
    fun notificationsSettingSuppressesUnreadBadgeWithoutDeletingMessages() = runBlocking {
        val data = MockRepository().dashboard()
        val initial = AppUiState(data = data)
        assertEquals(1, initial.unreadMessageCount)
        val muted = initial.copy(local = LocalFeatureState(settings = com.xiangshang.youth.core.service.LocalAppSettings(notificationsEnabled = false)))
        assertEquals(0, muted.unreadMessageCount)
        assertEquals(6, muted.data?.messages?.size)
        val restored = muted.copy(local = muted.local.copy(settings = com.xiangshang.youth.core.service.LocalAppSettings(notificationsEnabled = true)))
        assertEquals(1, restored.unreadMessageCount)
    }

    @Test
    fun pendingSyncCountExposesUnacknowledgedLocalWrites() = runBlocking {
        val local = LocalFeatureState(
            activityRegistrations = listOf(ActivityRegistration(activityId = "health-growth-season-2026", contactName = "王女士", phone = "13800138000")),
            expertAppointments = listOf(ExpertAppointment(expertName = "张教授", preferredDate = "周五上午", note = "运动发展咨询")),
            courseUploads = listOf(CourseUploadRecord(taskId = "after-class-upload", attendanceCount = 20, notes = "课堂记录", attachmentName = "课堂.jpg", status = LocalSubmissionStatus.PendingSync)),
            taskScopedSyncStates = mapOf("t1|s01" to LocalSubmissionStatus.PendingSync),
            bodyAssessmentSyncStates = mapOf("s01" to LocalSubmissionStatus.PendingSync)
        )

        assertEquals(5, AppUiState(local = local).pendingSyncCount)
    }

    @Test
    fun submittedCourseUploadContractRequiresPositiveAttendanceAndAttachmentReference() {
        assertFalse(CourseUploadValidator.isValidForSubmission(0, "课堂记录", "课堂.jpg", "local://course/1"))
        assertFalse(CourseUploadValidator.isValidForSubmission(20, "课堂记录", "课堂.jpg", null))
        assertFalse(CourseUploadValidator.isValidForSubmission(20, "", "课堂.jpg", "local://course/1"))
        assertTrue(CourseUploadValidator.isValidForSubmission(20, "课堂记录", "课堂.jpg", "local://course/1"))
    }

    @Test
    fun supportMessageNeedsRemoteAcknowledgementBeforeItLeavesThePendingQueue() {
        val local = LocalFeatureState(
            supportMessages = listOf(SupportMessage("想咨询孩子姿态观察", true, status = LocalSubmissionStatus.PendingSync))
        )

        assertEquals(1, AppUiState(local = local).pendingSyncCount)
    }

    @Test
    fun acknowledgedWorkflowRecordsAreNotStillShownAsPendingSync() {
        val local = LocalFeatureState(
            activityRegistrations = listOf(ActivityRegistration(activityId = "health-growth-season-2026", contactName = "王女士", phone = "13800138000", status = LocalSubmissionStatus.Submitted)),
            expertAppointments = listOf(ExpertAppointment(expertName = "张教授", preferredDate = "周五上午", note = "运动发展咨询", status = LocalSubmissionStatus.Submitted)),
            courseUploads = listOf(CourseUploadRecord(taskId = "after-class-upload", attendanceCount = 20, notes = "课堂记录", attachmentName = "课堂.jpg", status = LocalSubmissionStatus.Submitted)),
            bodyAssessmentSyncStates = mapOf("s01" to LocalSubmissionStatus.Submitted)
        )

        assertEquals(0, AppUiState(local = local).pendingSyncCount)
    }

    @Test
    fun failedWorkflowRecordsRemainVisibleForRetry() {
        val local = LocalFeatureState(
            activityRegistrations = listOf(ActivityRegistration(activityId = "health-growth-season-2026", contactName = "王女士", phone = "13800138000", status = LocalSubmissionStatus.Failed)),
            courseUploads = listOf(CourseUploadRecord(taskId = "after-class-upload", attendanceCount = 20, notes = "课堂记录", attachmentName = "课堂.jpg", status = LocalSubmissionStatus.Failed)),
            bodyAssessmentSyncStates = mapOf("s01" to LocalSubmissionStatus.Failed)
        )

        assertEquals(3, AppUiState(local = local).pendingSyncCount)
    }

    @Test
    fun childBindingRequiresMatchingNameAndSchoolCode() = runBlocking {
        val students = MockRepository().dashboard().students
        assertEquals(null, ChildBindingValidator.findMatch(students, "王小明", "wrong-code"))
        assertEquals(null, ChildBindingValidator.findMatch(students, "其他学生", "XS-S01"))
        assertEquals("s01", ChildBindingValidator.findMatch(students, "王小明", "xs-s01")?.id)
        assertEquals("s02", ChildBindingValidator.findMatch(students, "王小雨", "s02")?.id)
    }
}
