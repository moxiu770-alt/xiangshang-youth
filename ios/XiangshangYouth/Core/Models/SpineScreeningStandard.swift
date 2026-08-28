import Foundation

/// The professional five-item manual remains canonical. The household App
/// adds an eight-segment, camera-only acquisition protocol so one assisted
/// session can cover the agreed whole-body screening scope without pretending
/// that RGB camera proxies are instrument ATR or Cobb measurements.
enum SpineScreeningStandard {
    enum ATRBand: String, Equatable { case green, yellow, red, unavailable }
    static let version = "UY-IMCA-V1-2026-07-20"
    static let applicableAges = 6...12
    static let applicableAgeMonths = 72...155
    static let mainCameraDistanceMeters = 2.5
    static let gaitLaneMeters = 3.0
    static let atrAttentionDegrees = 5.0
    static let atrReferralDegrees = 7.0
    static let shoulderNormalCentimeters = 0.5
    static let shoulderMarkedCentimeters = 1.5
    static let pelvisNormalCentimeters = 0.5
    static let pelvisMarkedCentimeters = 1.0
    static let headTiltNormalDegrees = 3.0
    static let seatedMidlineNormalCentimeters = 1.0
    static let gaitShoulderDifferenceCentimeters = 1.0
    static let occiputWallDistanceAbnormalCentimeters = 2.0
    static let mainCameraPlacement = "正后方约 2.5 米，镜头高度与胸椎水平，后置 1× 镜头"
    static let forwardBendAuxiliaryPlacement = "完成正后方观察后，可在侧后方 45° 复核背部隆起"
    static let householdProtocolVersion = "UY-HOME-WHOLE-BODY-8-V1-2026-08-28"
    static let householdEstimatedMinutes = 8
    static let footCameraPlacement = "后置 1× 主摄，距双脚约 1–1.2 米，镜头高度与足弓齐平"

    static func isApplicable(ageMonths: Int?) -> Bool {
        guard let ageMonths else { return false }
        return applicableAgeMonths.contains(ageMonths)
    }

    static func atrBand(degrees: Double?) -> ATRBand {
        guard let degrees, degrees.isFinite, degrees >= 0 else { return .unavailable }
        if degrees >= atrReferralDegrees { return .red }
        if degrees >= atrAttentionDegrees { return .yellow }
        return .green
    }

    static func maximumOcciputWallDistance(first: Double?, second: Double?) -> Double? {
        guard let first, let second, first.isFinite, second.isFinite, first >= 0, second >= 0 else { return nil }
        return max(first, second)
    }

    struct Item: Identifiable, Equatable {
        enum Method: Equatable { case camera(BodyAssessmentRecord.CaptureTask), instrumentATR }
        let number: Int
        let title: String
        let purpose: String
        let instruction: String
        let method: Method
        var id: Int { number }
    }

    /// Professional protocol from the manual. Do not silently replace these
    /// instrument/supervised definitions with household camera estimates.
    static let items: [Item] = [
        Item(number: 1, title: "静态站姿对称观察", purpose: "头部、双肩和骨盆对称性", instruction: "双脚分开与肩同宽，赤足站在足印位置，双眼平视，双臂自然下垂，全身放松，不刻意挺胸。", method: .camera(.standingBack)),
        Item(number: 2, title: "亚当斯前屈试验", purpose: "胸腰背部隆起不对称观察", instruction: "双脚并拢，膝关节完全伸直，双手合十自然下垂，从髋部缓慢前屈，直至背部接近水平；头部自然放松，不屈膝、不弓步。", method: .camera(.forwardBend)),
        Item(number: 3, title: "躯干旋转角 ATR", purpose: "胸段 T4-T8、腰段 T12-L3 仪器读数", instruction: "维持标准前屈姿势，由校医或受训人员使用 Bunnell 型脊柱侧弯计分别读取胸段和腰段最大旋转角。", method: .instrumentATR),
        Item(number: 4, title: "动态步态姿态观察", purpose: "肩、骨盆摆动和躯干中线", instruction: "沿 3 米直线通道自然往返行走 1 次，保持日常步速，不刻意纠正姿势。", method: .camera(.gaitVideo)),
        Item(number: 5, title: "无靠背坐姿脊柱直立测试", purpose: "坐位中线、肩高、胸椎后凸与 OTWD", instruction: "坐满硬质无靠背凳面，双手平放膝盖，双脚落地，自然放松并保持直立坐姿；随后按手册完成两次枕墙距测量。", method: .camera(.seatedPosture))
    ]

    /// Commercial household protocol: eight separately auditable captures.
    /// Left and right side views are one guided segment with an in-flow turn.
    static let homeCameraItems: [Item] = [
        Item(number: 1, title: "正面自然站立", purpose: "头颈、肩髋、骨盆与双膝力线", instruction: "面向镜头赤足站立，双脚与髋同宽，双臂自然下垂，目视前方并保持自然呼吸。", method: .camera(.standingFront)),
        Item(number: 2, title: "背面自然站立", purpose: "双肩、肩胛、躯干中线与骨盆对称", instruction: "背对镜头赤足自然站立，全身放松，不刻意挺胸或收腹。", method: .camera(.standingBack)),
        Item(number: 3, title: "左右侧位姿态", purpose: "头前伸、圆肩、胸椎后凸与骨盆姿态", instruction: "先左侧面向镜头站稳，按提示转为右侧面；双次都保持全身入镜。", method: .camera(.standingSide)),
        Item(number: 4, title: "亚当斯前屈试验", purpose: "胸腰背表面旋转与隆起不对称", instruction: "双脚并拢，膝关节完全伸直，双手合十自然下垂，从髋部缓慢前屈至背部接近水平；不屈膝、不弓步。", method: .camera(.forwardBend)),
        Item(number: 5, title: "动态下肢力线", purpose: "膝内扣、膝外翻与髋膝踝控制", instruction: "面向镜头完成 3 次缓慢自重下蹲，膝盖朝向第二足趾，脚跟不离地。", method: .camera(.dynamicKneeControl)),
        Item(number: 6, title: "3 米动态步态", purpose: "步频、左右支撑、肩髋摆动与躯干对称", instruction: "沿 3 米直线自然往返行走 1 次，保持日常步速，不刻意纠正姿势。", method: .camera(.gaitVideo)),
        Item(number: 7, title: "无靠背坐姿", purpose: "坐位中线、肩高、胸椎后凸与头前伸", instruction: "坐满硬质无靠背凳面，双手平放膝盖，双脚落地，自然放松并保持直立。", method: .camera(.seatedPosture)),
        Item(number: 8, title: "足弓与足跟对齐", purpose: "足弓外观、足跟力线与左右对称", instruction: "双足赤足平行站立，先从内侧后方记录足弓与足跟，再按提示换另一侧；距离保持约 1–1.2 米。", method: .camera(.footArch))
    ]

    static func instruction(for task: BodyAssessmentRecord.CaptureTask) -> String {
        homeCameraItems.first { $0.method == .camera(task) }?.instruction
            ?? items.first { $0.method == .camera(task) }?.instruction
            ?? "请按标准动作完成。"
    }
}
