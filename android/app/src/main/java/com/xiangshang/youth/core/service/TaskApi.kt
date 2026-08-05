package com.xiangshang.youth.core.service

import com.xiangshang.youth.core.model.TaskStatus
import com.xiangshang.youth.core.model.TestTask
import retrofit2.http.GET
import retrofit2.http.PATCH
import retrofit2.http.Path
import retrofit2.http.Query

data class TaskStatusRequest(val status: TaskStatus, val note: String? = null)

interface TaskApi {
    @GET("v1/schools/{schoolId}/tasks")
    suspend fun tasks(@Path("schoolId") schoolId: String, @Query("gradeId") gradeId: String? = null, @Query("classId") classId: String? = null): List<TestTask>

    @PATCH("v1/tasks/{taskId}/students/{studentId}/status")
    suspend fun updateStatus(@Path("taskId") taskId: String, @Path("studentId") studentId: String, @retrofit2.http.Body body: TaskStatusRequest)
}
