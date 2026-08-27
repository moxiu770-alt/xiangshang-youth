import Foundation

/// One source of truth for every consent-facing document shipped in the app.
/// Versions are persisted with guardian consent and must change whenever the
/// corresponding processing purpose or text materially changes.
enum LegalPolicy {
    static let effectiveDate = "2026年8月26日"
    static let userAgreementVersion = "terms-2026-08-12"
    static let privacyPolicyVersion = "privacy-2026-08-26-r2"
    static let childPrivacyVersion = "child-privacy-2026-08-12"
    static let cameraConsentVersion = "camera-local-processing-2026-08-26"
    static let algorithmNoticeVersion = "posture-screening-2026-08-26"

    static func bundledDocument(named name: String) -> String {
        guard let url = Bundle.main.url(forResource: name, withExtension: "txt"),
              let text = try? String(contentsOf: url, encoding: .utf8),
              !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return "协议正文加载失败，请更新应用后重试，或联系客服 023-63830757。"
        }
        return text
    }
}

enum LegalDocument: String, Identifiable {
    case userAgreement = "用户服务协议"
    case privacy = "隐私政策"
    case childPrivacy = "儿童个人信息保护声明"

    var id: String { rawValue }

    var version: String {
        switch self {
        case .userAgreement: LegalPolicy.userAgreementVersion
        case .privacy: LegalPolicy.privacyPolicyVersion
        case .childPrivacy: LegalPolicy.childPrivacyVersion
        }
    }

    var content: String {
        switch self {
        case .userAgreement:
            LegalPolicy.bundledDocument(named: "user_service_agreement")
        case .privacy:
            """
            《隐私政策》
            版本：\(version)　生效日期：\(LegalPolicy.effectiveDate)

            我们仅在提供学校运动管理、测评报告、训练反馈、课程进度和消息通知所必需的范围内处理账号、学校关系、设备安全日志及健康测评数据。

            健康数据包括身高、体重、BMI、姿态结构化指标、运动成绩和报告。处理前会展示用途并记录监护人同意；访问受学校和家庭关系约束，网络传输使用加密连接，敏感凭证保存在系统安全存储中。

            App内家庭身体测评的摄像头帧只在设备内实时处理，不保存原始照片或视频，也不向服务器上传原始摄像头帧；服务器仅接收测量值、质量分、动作结果和必要的结构化摘要。学校场地端如为复核留存证据，必须使用独立告知、授权和保存规则，不与App家庭测评授权混用。

            “发送匿名使用情况”默认关闭。主动开启后，仅发送固定页面事件、App版本和每次启动随机生成的会话标识；服务端只保存该标识的不可逆摘要，不接收账户、孩子、学校、手机号、健康数值、自由文本或摄像头内容，并在90天后自动删除。您可以随时在设置中关闭。

            我们不出售儿童数据，也不使用儿童数据进行个性化广告。家长可以查看、导出、更正或申请删除已绑定孩子的数据；删除申请完成身份和学校关系核验后，相关记录会按法定及业务保留规则删除或匿名化。

            正式运营主体、第三方处理者清单、具体保存期限、隐私联系人和投诉渠道以同版本官方网站完整政策为准。
            """
        case .childPrivacy:
            LegalPolicy.bundledDocument(named: "child_personal_information_protection")
        }
    }
}
