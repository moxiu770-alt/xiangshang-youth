package com.xiangshang.youth.core.service

import retrofit2.http.Body
import retrofit2.http.GET
import retrofit2.http.PUT
import retrofit2.http.Path

data class RemoteLesson(val courseId: String, val moduleId: String?, val lessonId: String, val title: String, val lessonTitle: String, val durationMs: Int, val videoSource: String?, val lastPositionMs: Int, val completed: Boolean, val version: Int)
data class PlaybackSource(val lessonId: String, val courseId: String, val videoSource: String, val durationMs: Int)
data class LessonProgressWrite(val lastPositionMs: Int, val completed: Boolean, val expectedVersion: Int? = null)
data class LessonProgressAck(val lessonId: String, val lastPositionMs: Int, val completed: Boolean, val version: Int)
interface CourseApi {
    @GET("v1/students/{studentId}/courses") suspend fun courses(@Path("studentId") studentId: String): ApiEnvelope<List<RemoteLesson>>
    @GET("v1/lessons/{lessonId}/playback") suspend fun playback(@Path("lessonId") lessonId: String): ApiEnvelope<PlaybackSource>
    @PUT("v1/students/{studentId}/lessons/{lessonId}/progress") suspend fun saveProgress(@Path("studentId") studentId: String, @Path("lessonId") lessonId: String, @Body body: LessonProgressWrite): ApiEnvelope<LessonProgressAck>
}
