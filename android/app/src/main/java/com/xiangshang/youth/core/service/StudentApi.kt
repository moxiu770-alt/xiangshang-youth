package com.xiangshang.youth.core.service

import com.xiangshang.youth.core.model.ParentChild
import com.xiangshang.youth.core.model.Student
import retrofit2.http.GET
import retrofit2.http.POST
import retrofit2.http.Path
import retrofit2.http.Query

interface StudentApi {
    @GET("v1/schools/{schoolId}/students")
    suspend fun students(@Path("schoolId") schoolId: String, @Query("classId") classId: String? = null): List<Student>

    @POST("v1/students/{studentId}/bind")
    suspend fun bindChild(@Path("studentId") studentId: String, @Query("code") bindingCode: String): ParentChild
}
