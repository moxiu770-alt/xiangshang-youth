package com.xiangshang.youth.core.model

enum class BodyAttentionLevel(val label: String) {
    /** A data-completeness state, not a health-risk classification. */
    Pending("待完成拍摄记录"),
    Green("本次观察已完成"),
    Yellow("建议关注"),
    Red("建议进一步评估"),
    Unavailable("待完善生日")
}
enum class AdamsScreeningResult(val label: String) {
    Negative("阴性（双侧等高）"),
    Equivocal("可疑阳性（隆起＜1 cm）"),
    Positive("阳性（隆起≥1 cm）")
}
