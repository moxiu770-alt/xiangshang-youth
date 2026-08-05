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
import com.xiangshang.youth.core.mock.MockRepository
import com.xiangshang.youth.core.repository.RemoteRepository
import kotlinx.coroutines.runBlocking
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class LocalFeatureStateTest {
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
    fun featureWorkflowStateKeepsAllSubmittedOperations() {
        val state = LocalFeatureState(
            activityRegistered = true,
            activityRegistrations = listOf(ActivityRegistration(activityId = "health-growth-season-2026", contactName = "王女士", phone = "13800138000")),
            completedAssessments = setOf("s01-fitness"),
            courseProgress = mapOf("体姿改善课程" to .8f),
            supportMessages = listOf(SupportMessage("想了解课程", true)),
            classPosts = listOf(ClassPost(author = "王女士", content = "今天完成运动打卡")),
            expertAppointments = listOf(ExpertAppointment(expertName = "张教授", preferredDate = "周五上午", note = "运动发展咨询")),
            courseUploads = listOf(CourseUploadRecord(taskId = "after-class-upload", attendanceCount = 26, notes = "已完成课程", attachmentName = "课堂.jpg", status = LocalSubmissionStatus.Submitted)),
            uploadedTaskIds = setOf("after-class-upload"),
            checkedInToday = true,
            studentTaskStatuses = mapOf("s01" to TaskStatus.Review),
            reviewNotes = mapOf("s01" to "核验视频后建议周五补测。"),
            sessionActive = true,
            sessionPhone = "13800138000",
            sessionRoleName = "Teacher",
            selectedChildId = "s02"
        )

        assertTrue(state.activityRegistered && state.checkedInToday)
        assertEquals("王女士", state.activityRegistrations.single().contactName)
        assertTrue("s01-fitness" in state.completedAssessments)
        assertEquals(.8f, state.courseProgress["体姿改善课程"])
        assertEquals("王女士", state.classPosts.single().author)
        assertEquals("张教授", state.expertAppointments.single().expertName)
        assertEquals(LocalSubmissionStatus.Submitted, state.courseUploads.single().status)
        assertTrue("after-class-upload" in state.uploadedTaskIds)
        assertEquals(TaskStatus.Review, state.studentTaskStatuses["s01"])
        assertEquals("核验视频后建议周五补测。", state.reviewNotes["s01"])
        assertTrue(state.sessionActive)
        assertEquals("Teacher", state.sessionRoleName)
        assertEquals("s02", state.selectedChildId)
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
}
