import Foundation

/// One source of truth for every consent-facing document shipped in the app.
/// Versions are persisted with guardian consent and must change whenever the
/// corresponding processing purpose or text materially changes.
enum LegalPolicy {
    static let effectiveDate = "2026年8月26日"
    static let userAgreementVersion = "terms-2026-08-26"
    static let privacyPolicyVersion = "privacy-2026-08-26-r2"
    static let cameraConsentVersion = "camera-local-processing-2026-08-26"
    static let algorithmNoticeVersion = "posture-screening-2026-08-26"
}

enum LegalDocument: String, Identifiable {
    case userAgreement = "用户协议"
    case privacy = "隐私政策"
    case childPrivacy = "儿童隐私政策"

    var id: String { rawValue }

    var version: String {
        switch self {
        case .userAgreement: LegalPolicy.userAgreementVersion
        case .privacy, .childPrivacy: LegalPolicy.privacyPolicyVersion
        }
    }

    var content: String {
        switch self {
        case .userAgreement:
            """
            《用户协议》
            版本：\(version)　生效日期：\(LegalPolicy.effectiveDate)

            一、服务范围
            向上少年为学校、教师和家长提供学生运动能力记录、测评报告、训练建议与通知服务。账号仅限本人使用，不得转让、出租或用于批量抓取数据。

            二、账号与安全
            请使用真实、可验证的手机号或学校提供的账号，并妥善保管验证码、密码和设备。发现异常登录时，请立即联系所属学校管理员或平台客服。

            三、学校数据
            学校体测成绩、报告及任务状态由学校授权人员和合规场地端录入。家长只能访问已绑定孩子的数据，教师只能访问账号授权班级和任务。

            四、服务边界
            平台提供家庭运动健康筛查和训练建议，不构成医疗诊断、治疗或急救意见。训练过程中出现疼痛、眩晕或其他不适时，应立即停止并咨询专业人员。

            五、联系我们
            账号、数据或未成年人权益问题由所属学校管理员和平台隐私联系人受理。正式运营主体、地址、电话、邮箱和争议处理渠道以同版本官方网站公示信息为准。
            """
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
            """
            《儿童隐私政策》
            版本：\(version)　生效日期：\(LegalPolicy.effectiveDate)

            儿童账号和健康测评由家长、学校或依法授权人员管理。我们只收集完成运动测评、报告和训练所需的最少信息，不使用儿童数据进行个性化广告或与服务无关的画像。

            App内姿态采集仅用于在设备上生成结构化测评指标。原始摄像头照片、视频和帧不保存、不上传；只保存测量值、质量分、动作结果及必要的结构化摘要。质量不足时由用户主动重新采集。

            监护人可以撤回同意、查询处理记录并申请导出、更正或删除。授权版本变化后，需要重新确认才能开始新的身体测评。撤回同意不会影响撤回前处理行为的合法性，但相关测评功能可能无法继续。

            如发现儿童信息被误用，请联系所属学校管理员或平台隐私联系人，我们会优先处理。正式联系方式以同版本官方网站完整政策为准。
            """
        }
    }
}
