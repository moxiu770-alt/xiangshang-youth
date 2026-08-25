package com.xiangshang.youth.core.service

/**
 * Shared input gate for a submitted after-class course record.
 *
 * Drafts may be incomplete, but a record entering the sync queue must contain
 * real attendance, notes, a display name and an uploaded-file reference.
 */
object CourseUploadValidator {
    fun isValidForSubmission(
        attendance: Int,
        notes: String,
        attachmentName: String,
        attachmentReference: String?
    ): Boolean = attendance > 0 &&
        notes.trim().isNotEmpty() &&
        attachmentName.trim().isNotEmpty() &&
        !attachmentReference.isNullOrBlank()
}
