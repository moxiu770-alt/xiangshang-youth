package com.xiangshang.youth.core.model

import android.content.Context

/** Versioned, consent-facing documents bundled with the Android app. */
object LegalPolicy {
    const val EFFECTIVE_DATE = "2026年8月26日"
    const val USER_AGREEMENT_VERSION = "terms-2026-08-12"
    const val PRIVACY_POLICY_VERSION = "privacy-2026-08-26-r2"
    const val CHILD_PRIVACY_VERSION = "child-privacy-2026-08-12"
    const val CAMERA_CONSENT_VERSION = "camera-local-processing-2026-08-26"
    const val ALGORITHM_NOTICE_VERSION = "posture-screening-2026-08-26"

    const val USER_AGREEMENT_TITLE = "用户服务协议"
    const val PRIVACY_POLICY_TITLE = "隐私政策"
    const val CHILD_PRIVACY_TITLE = "儿童个人信息保护声明"

    @Volatile private var applicationContext: Context? = null

    fun initialize(context: Context) {
        applicationContext = context.applicationContext
    }

    fun document(document: String, reader: ((String) -> String)? = null): String {
        if (document == PRIVACY_POLICY_TITLE) return privacyPolicyText
        val assetName = when (document) {
            USER_AGREEMENT_TITLE -> "user_service_agreement.txt"
            CHILD_PRIVACY_TITLE -> "child_personal_information_protection.txt"
            else -> error("Unsupported legal document: $document")
        }
        return reader?.invoke(assetName)
            ?: applicationContext?.assets?.open(assetName)?.bufferedReader(Charsets.UTF_8)?.use { it.readText() }
            ?: error("LegalPolicy.initialize(context) must run before displaying legal documents")
    }

    private val privacyPolicyText = """
            《隐私政策》
            版本：$PRIVACY_POLICY_VERSION　生效日期：$EFFECTIVE_DATE

            我们仅在提供学校运动管理、测评报告、训练反馈、课程进度和消息通知所必需的范围内处理账号、学校关系、设备安全日志及健康测评数据。

            健康数据包括身高、体重、BMI、姿态结构化指标、运动成绩和报告。处理前会展示用途并记录监护人同意；访问受学校和家庭关系约束，网络传输使用加密连接，敏感凭证保存在系统安全存储中。

            App内家庭身体测评的摄像头帧只在设备内实时处理，不保存原始照片或视频，也不向服务器上传原始摄像头帧；服务器仅接收测量值、质量分、动作结果和必要的结构化摘要。学校场地端如为复核留存证据，必须使用独立告知、授权和保存规则，不与App家庭测评授权混用。

            “发送匿名使用情况”默认关闭。主动开启后，仅发送固定页面事件、App版本和每次启动随机生成的会话标识；服务端只保存该标识的不可逆摘要，不接收账户、孩子、学校、手机号、健康数值、自由文本或摄像头内容，并在90天后自动删除。您可以随时在设置中关闭。

            我们不出售儿童数据，也不使用儿童数据进行个性化广告。家长可以查看、导出、更正或申请删除已绑定孩子的数据；删除申请完成身份和学校关系核验后，相关记录会按法定及业务保留规则删除或匿名化。

            正式运营主体、第三方处理者清单、具体保存期限、隐私联系人和投诉渠道以同版本官方网站完整政策为准。
        """.trimIndent()
}
