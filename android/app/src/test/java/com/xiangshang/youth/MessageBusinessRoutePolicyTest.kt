package com.xiangshang.youth

import com.xiangshang.youth.core.model.MessageItem
import com.xiangshang.youth.core.util.MessageBusinessRoutePolicy
import java.time.Instant
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class MessageBusinessRoutePolicyTest {
    @Test fun expiredMessagesDoNotRoute() {
        assertTrue(MessageBusinessRoutePolicy.isExpired("2026-01-01T00:00:00Z", Instant.parse("2026-08-24T00:00:00Z")))
        assertFalse(MessageBusinessRoutePolicy.isExpired("2026-12-01T00:00:00Z", Instant.parse("2026-08-24T00:00:00Z")))
        assertFalse(MessageBusinessRoutePolicy.isExpired(null, Instant.parse("2026-08-24T00:00:00Z")))
    }

    @Test fun courseMessagesRequireStableChildAndCourseOrLessonIds() {
        val target = MessageBusinessRoutePolicy.courseTarget(
            MessageItem(
                id = "m1",
                title = "今日课程",
                content = "打开课节",
                time = "刚刚",
                category = "课程",
                isRead = false,
                businessRoute = "lesson",
                businessId = "lesson-1",
                childId = "s01",
                courseId = "course-1",
                actionLabel = "开始训练"
            )
        )

        assertNotNull(target)
        assertEquals("s01", target?.childId)
        assertEquals("course-1", target?.courseId)
        assertEquals("lesson-1", target?.lessonId)
        assertEquals("开始训练", target?.title)
        assertNull(MessageBusinessRoutePolicy.courseTarget(MessageItem("m2", "缺孩子", "", "刚刚", "课程", false, businessRoute = "course", businessId = "course-1")))
        assertNull(MessageBusinessRoutePolicy.courseTarget(MessageItem("m3", "缺课程", "", "刚刚", "课程", false, businessRoute = "course", childId = "s01")))
    }

    @Test fun activityAndAppointmentRequireBusinessId() {
        assertTrue(MessageBusinessRoutePolicy.hasRequiredBusinessId(MessageItem("m4", "活动", "", "刚刚", "活动", false, businessRoute = "activity", businessId = "activity-1")))
        assertFalse(MessageBusinessRoutePolicy.hasRequiredBusinessId(MessageItem("m5", "活动", "", "刚刚", "活动", false, businessRoute = "activity")))
        assertTrue(MessageBusinessRoutePolicy.hasRequiredBusinessId(MessageItem("m6", "班级通知", "", "刚刚", "班级通知", false, businessRoute = "classNotice", businessId = "notice-1")))
        assertFalse(MessageBusinessRoutePolicy.hasRequiredBusinessId(MessageItem("m7", "班级通知", "", "刚刚", "班级通知", false, businessRoute = "classNotice")))
    }

    @Test fun routeNamesAreNormalizedAcrossBackendConventions() {
        assertEquals("expertappointment", MessageBusinessRoutePolicy.normalizeRoute("expert_appointment"))
        assertEquals("expertappointment", MessageBusinessRoutePolicy.normalizeRoute("expert-appointment"))
        assertEquals("classnotice", MessageBusinessRoutePolicy.normalizeRoute("classNotice"))
        assertEquals("lesson", MessageBusinessRoutePolicy.normalizeRoute(" Lesson "))

        val target = MessageBusinessRoutePolicy.courseTarget(
            MessageItem(
                id = "m6",
                title = "课程建议",
                content = "打开课节",
                time = "刚刚",
                category = "课程",
                isRead = false,
                businessRoute = "lesson_recommendation",
                businessId = "lesson-2",
                childId = "s01"
            )
        )
        assertNull(target)
    }
}
