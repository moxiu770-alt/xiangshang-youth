package com.xiangshang.youth.core.service

import android.content.Context
import retrofit2.http.GET
import retrofit2.http.Query

data class MobileContentManifest(
    val dataAvailable: Boolean,
    val changed: Boolean,
    val version: Int
)

interface ContentManifestApi {
    @GET("v1/mobile/content-manifest")
    suspend fun manifest(
        @Query("schoolId") schoolId: String?,
        @Query("channel") channel: String,
        @Query("knownVersion") knownVersion: Int
    ): ApiEnvelope<MobileContentManifest>
}

/** Stores version watermarks, never catalogue records or permissions. */
class ContentManifestVersionStore(context: Context) {
    private val preferences = context.applicationContext.getSharedPreferences("content_manifest_versions", Context.MODE_PRIVATE)

    fun version(schoolId: String?, channel: String): Int =
        preferences.getInt("${schoolId ?: "global"}|$channel", 0).coerceAtLeast(0)

    fun acknowledge(schoolId: String?, channel: String, version: Int) {
        val key = "${schoolId ?: "global"}|$channel"
        if (version >= preferences.getInt(key, 0)) preferences.edit().putInt(key, version).apply()
    }
}
