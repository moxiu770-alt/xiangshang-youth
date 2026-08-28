package com.xiangshang.youth.core.model

enum class AlgorithmValidationStatus {
    PendingHumanValidation,
    HumanValidated;

    val allowsClassification: Boolean get() = this == HumanValidated
    val label: String get() = if (allowsClassification) "已完成人工验证" else "研发验证中"
}

/** Production model claims fail closed until the frozen version is approved. */
object AlgorithmReleaseGate {
    val posture = AlgorithmValidationStatus.PendingHumanValidation
    val followAlong = AlgorithmValidationStatus.PendingHumanValidation
    const val pendingPostureNotice = "手机姿态算法尚未完成人工标注验证。本次仅保存取景与姿态观察记录，不生成风险等级或健康结论。"
    const val pendingFollowAlongNotice = "动作识别仍在人工标注验证阶段，辅助计次和动作提示可能有误差。训练是否完成以家长确认为准。"
}
