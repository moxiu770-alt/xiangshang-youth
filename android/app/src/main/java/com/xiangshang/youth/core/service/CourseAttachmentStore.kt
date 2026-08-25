package com.xiangshang.youth.core.service

import android.content.ContentResolver
import android.content.Context
import android.graphics.Bitmap
import android.net.Uri
import androidx.core.net.toUri
import android.provider.OpenableColumns
import okhttp3.MediaType.Companion.toMediaType
import okhttp3.RequestBody
import okhttp3.RequestBody.Companion.asRequestBody
import java.io.File
import java.io.FileOutputStream
import java.util.UUID

/**
 * Owns picked course and class-circle media after selection. We make a private
 * copy immediately so an expiring picker grant can never turn a saved draft
 * into a fake upload.
 */
object CourseAttachmentStore {
    private const val MAX_BYTES = 20L * 1024L * 1024L
    private const val DIRECTORY = "course_attachments"

    data class Attachment(val file: File, val mimeType: String) {
        fun requestBody(): RequestBody = file.asRequestBody(mimeType.toMediaType())
    }

    @Throws(IllegalArgumentException::class)
    fun copyPickedMedia(context: Context, source: Uri): Attachment {
        val type = context.contentResolver.getType(source).orEmpty().lowercase()
        require(type in setOf("image/jpeg", "image/png", "video/mp4")) { "仅支持 JPG、PNG 图片或 MP4 视频。" }
        val display = context.contentResolver.query(source, arrayOf(OpenableColumns.DISPLAY_NAME), null, null, null)?.use { cursor ->
            if (cursor.moveToFirst()) cursor.getString(cursor.getColumnIndexOrThrow(OpenableColumns.DISPLAY_NAME)) else null
        }
        val extension = when (type) {
            "image/png" -> "png"
            "video/mp4" -> "mp4"
            else -> "jpg"
        }
        val fallbackName = if (type == "video/mp4") "班级圈视频" else "课堂照片"
        val file = destination(context, display?.substringBeforeLast('.')?.ifBlank { null } ?: fallbackName, extension)
        try {
            context.contentResolver.openInputStream(source)?.use { input ->
                FileOutputStream(file).use { output ->
                    val buffer = ByteArray(DEFAULT_BUFFER_SIZE)
                    var total = 0L
                    while (true) {
                        val count = input.read(buffer)
                        if (count <= 0) break
                        total += count
                        require(total <= MAX_BYTES) { "附件超过 20MB，请压缩后重新选择。" }
                        output.write(buffer, 0, count)
                    }
                }
            } ?: error("附件无法读取，请重新选择。")
            return Attachment(file, type)
        } catch (error: Throwable) {
            file.delete()
            throw error
        }
    }

    /** Kept for existing course image callers. */
    fun copyPickedImage(context: Context, source: Uri): Attachment {
        val attachment = copyPickedMedia(context, source)
        require(attachment.mimeType != "video/mp4") { "课程照片仅支持 JPG 或 PNG 图片。" }
        return attachment
    }

    @Throws(IllegalArgumentException::class)
    fun createCameraFile(context: Context): Attachment = Attachment(destination(context, "课堂照片", "jpg"), "image/jpeg")

    @Throws(IllegalArgumentException::class)
    fun read(reference: String?): Attachment {
        require(!reference.isNullOrBlank()) { "请重新选择可上传的照片附件。" }
        val uri = reference.toUri()
        require(uri.scheme == ContentResolver.SCHEME_FILE) { "旧版附件已失效，请重新选择照片后提交。" }
        val file = File(uri.path ?: throw IllegalArgumentException("附件路径无效，请重新选择。"))
        require(file.exists() && file.isFile && file.length() in 1..MAX_BYTES) { "附件不存在、为空或超过 20MB，请重新选择。" }
        val mimeType = when (file.extension.lowercase()) {
            "jpg", "jpeg" -> "image/jpeg"
            "png" -> "image/png"
            "mp4" -> "video/mp4"
            else -> throw IllegalArgumentException("仅支持 JPG、PNG 图片或 MP4 视频。")
        }
        return Attachment(file, mimeType)
    }

    private fun destination(context: Context, stem: String, extension: String): File {
        val directory = File(context.filesDir, DIRECTORY).apply { mkdirs() }
        val safeStem = stem.take(48).replace(Regex("[^a-zA-Z0-9\\u4e00-\\u9fa5_-]"), "_")
        return File(directory, "$safeStem-${UUID.randomUUID()}.$extension")
    }
}
