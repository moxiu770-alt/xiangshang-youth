package com.xiangshang.youth.core.util

import com.xiangshang.youth.core.model.Student
import java.util.Locale

/** Pure validation for the family-to-child binding form. */
object ChildBindingValidator {
    fun findMatch(students: List<Student>, name: String, code: String): Student? {
        val normalizedName = name.trim()
        val normalizedCode = code.trim().uppercase(Locale.ROOT)
        if (normalizedName.isEmpty() || normalizedCode.isEmpty()) return null
        return students.firstOrNull { student ->
            val id = student.id.uppercase(Locale.ROOT)
            val validCode = normalizedCode == id || normalizedCode == "XS-$id"
            validCode && student.name == normalizedName
        }
    }
}
