package com.xiangshang.youth

import com.xiangshang.youth.core.service.ClassPost
import com.xiangshang.youth.core.service.ActivityRegistration
import com.xiangshang.youth.core.service.CourseUploadRecord
import com.xiangshang.youth.core.service.ExpertAppointment
import com.xiangshang.youth.core.service.LocalSubmissionStatus
import com.xiangshang.youth.core.service.LocalFeatureState
import com.xiangshang.youth.core.service.SupportMessage
import com.xiangshang.youth.core.model.TaskStatus
import com.xiangshang.youth.core.model.ScoreReviewStatus
import com.xiangshang.youth.core.model.UserProfile
import com.xiangshang.youth.core.model.UserRole
import com.xiangshang.youth.core.mock.MockRepository
import com.xiangshang.youth.core.repository.RemoteRepository
import com.xiangshang.youth.app.AppUiState
import com.xiangshang.youth.core.util.ChildBindingValidator
import com.xiangshang.youth.core.util.AuthIdentity
import kotlinx.coroutines.runBlocking
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class LocalFeatureStateTest {
    @Test
    fun wechatAuthorizationIdentifierNeverBecomesAProfilePhone() {
        assertEquals("13800138000", AuthIdentity.displayPhone(AuthIdentity.wechatAuthorizationIdentifier))
        assertEquals("13800138000", AuthIdentity.displayPhone("  "))
        assertEquals("13900139000", AuthIdentity.displayPhone(" 13900139000 "))
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

        assertTrue(autumnTask.scopedStudents(data.students).all { it.grade == "三年级" })
        assertTrue(retestTask.scopedStudents(data.students).all { it.className == "四年级1班" })
        assertTrue(retestTask.scopedStudents(data.students).none { it.grade == "三年级" })
    }

    @Test
    fun featureWorkflowStateKeepsAllSubmittedOperations() {
        val state = LocalFeatureState(
            activityRegistered = true,
            activityRegistrations = listOf(ActivityRegistration(activityId = "health-growth-season-2026", contactName = "王女士", phone = "13800138000")),
            completedAssessments = setOf("s01-fitness"),
            courseProgress = mapOf("体姿改善课程" to .8f),
            supportMessages = listOf(SupportMessage("想了解课程", true)),
            classPosts = listOf(ClassPost(author = "王女士", content = "今天完成运动打卡")),
            likedPostIds = setOf("post-1", "teacher-announcement"),
            postComments = mapOf("post-1" to listOf("继续加油")),
            expertAppointments = listOf(ExpertAppointment(expertName = "张教授", preferredDate = "周五上午", note = "运动发展咨询")),
            courseUploads = listOf(CourseUploadRecord(taskId = "after-class-upload", attendanceCount = 26, notes = "已完成课程", attachmentName = "课堂.jpg", status = LocalSubmissionStatus.PendingSync)),
            uploadedTaskIds = setOf("after-class-upload"),
            checkedInToday = true,
            studentTaskStatuses = mapOf("s01" to TaskStatus.Review),
            taskStatusSyncStates = mapOf("s01" to LocalSubmissionStatus.PendingSync),
            reviewNotes = mapOf("s01" to "核验视频后建议周五补测。"),
            sessionActive = true,
            sessionPhone = "13800138000",
            sessionRoleName = "Teacher",
            selectedChildId = "s02",
            drafts = mapOf(
                "account-feedback" to "希望增加课程提醒",
                "assessment-progress-s01-fitness" to "2"
            )
        )

        assertTrue(state.activityRegistered && state.checkedInToday)
        assertEquals("王女士", state.activityRegistrations.single().contactName)
        assertTrue("s01-fitness" in state.completedAssessments)
        assertEquals(.8f, state.courseProgress["体姿改善课程"])
        assertEquals("王女士", state.classPosts.single().author)
        assertTrue("post-1" in state.likedPostIds)
        assertTrue("teacher-announcement" in state.likedPostIds)
        assertEquals("继续加油", state.postComments["post-1"]?.single())
        assertEquals("张教授", state.expertAppointments.single().expertName)
        assertEquals(LocalSubmissionStatus.PendingSync, state.courseUploads.single().status)
        assertTrue("after-class-upload" in state.uploadedTaskIds)
        assertEquals(TaskStatus.Review, state.studentTaskStatuses["s01"])
        assertEquals(LocalSubmissionStatus.PendingSync, state.taskStatusSyncStates["s01"])
        assertEquals("核验视频后建议周五补测。", state.reviewNotes["s01"])
        assertTrue(state.sessionActive)
        assertEquals("Teacher", state.sessionRoleName)
        assertEquals("s02", state.selectedChildId)
        assertEquals("希望增加课程提醒", state.drafts["account-feedback"])
        assertEquals("2", state.drafts["assessment-progress-s01-fitness"])
        assertTrue("account-feedback" !in state.copy(drafts = state.drafts - "account-feedback").drafts)
    }

    @Test
    fun remoteReportUsesSafeFallbackUntilEndpointIsConfigured() = runBlocking {
        val student = MockRepository().dashboard().students.first()
        val report = RemoteRepository().report(student)

        assertEquals(student.id, report.student.id)
        assertEquals(7, report.scores.size)
        assertTrue(report.scores.any { it.confidence < 0.8 && it.reviewStatus == ScoreReviewStatus.PendingReview })
        assertTrue(report.scores.filter { it.confidence >= 0.8 }.all { it.reviewStatus == ScoreReviewStatus.Passed })
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
    fun mockReportExposesSevenItemTotalScore() = runBlocking {
        val student = MockRepository().dashboard().students.first()
        val report = MockRepository().report(student)
        assertEquals(7, report.scores.size)
        assertEquals(28.5, report.totalScore, 0.001)
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
            taskStatusSyncStates = mapOf("s01" to LocalSubmissionStatus.PendingSync)
        )

        assertEquals(4, AppUiState(local = local).pendingSyncCount)
    }

    @Test
    fun acknowledgedWorkflowRecordsAreNotStillShownAsPendingSync() {
        val local = LocalFeatureState(
            activityRegistrations = listOf(ActivityRegistration(activityId = "health-growth-season-2026", contactName = "王女士", phone = "13800138000", status = LocalSubmissionStatus.Submitted)),
            expertAppointments = listOf(ExpertAppointment(expertName = "张教授", preferredDate = "周五上午", note = "运动发展咨询", status = LocalSubmissionStatus.Submitted)),
            courseUploads = listOf(CourseUploadRecord(taskId = "after-class-upload", attendanceCount = 20, notes = "课堂记录", attachmentName = "课堂.jpg", status = LocalSubmissionStatus.Submitted))
        )

        assertEquals(0, AppUiState(local = local).pendingSyncCount)
    }

    @Test
    fun failedWorkflowRecordsRemainVisibleForRetry() {
        val local = LocalFeatureState(
            activityRegistrations = listOf(ActivityRegistration(activityId = "health-growth-season-2026", contactName = "王女士", phone = "13800138000", status = LocalSubmissionStatus.Failed)),
            courseUploads = listOf(CourseUploadRecord(taskId = "after-class-upload", attendanceCount = 20, notes = "课堂记录", attachmentName = "课堂.jpg", status = LocalSubmissionStatus.Failed))
        )

        assertEquals(2, AppUiState(local = local).pendingSyncCount)
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
