package com.xiangshang.youth.core.model
enum class UserRole(val label: String) {
    Parent("家长"), Teacher("教师"), Principal("校长");

    val backendCode: String get() = when (this) {
        Parent -> "parent"
        Teacher -> "teacher"
        Principal -> "principal"
    }

    companion object {
        /** Mobile workbenches. School management analytics live in the backend dashboard. */
        val mobileRoles: List<UserRole> get() = listOf(Parent, Teacher)
        fun fromBackendCode(value: String?): UserRole? = when (value?.lowercase()) {
            "parent", "家长" -> Parent
            "teacher", "教师" -> Teacher
            "principal", "校长" -> Principal
            else -> null
        }
    }
}
