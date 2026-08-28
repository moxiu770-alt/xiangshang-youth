package com.xiangshang.youth.core.model

/** Professional five-item manual plus the separate commercial household eight-segment protocol. */
object SpineScreeningStandard {
    enum class AtrBand { Green, Yellow, Red, Unavailable }
    const val version = "UY-IMCA-V1-2026-07-20"
    const val minimumAgeMonths = 72
    const val maximumAgeMonths = 155
    const val mainCameraDistanceMeters = 2.5
    const val gaitLaneMeters = 3.0
    const val atrAttentionDegrees = 5.0
    const val atrReferralDegrees = 7.0
    const val shoulderNormalCentimeters = 0.5
    const val shoulderMarkedCentimeters = 1.5
    const val pelvisNormalCentimeters = 0.5
    const val pelvisMarkedCentimeters = 1.0
    const val headTiltNormalDegrees = 3.0
    const val seatedMidlineNormalCentimeters = 1.0
    const val gaitShoulderDifferenceCentimeters = 1.0
    const val occiputWallDistanceAbnormalCentimeters = 2.0
    const val mainCameraPlacement = "正后方约 2.5 米，镜头高度与胸椎水平，后置 1× 镜头"
    const val forwardBendAuxiliaryPlacement = "完成正后方观察后，可在侧后方 45° 复核背部隆起"
    const val householdProtocolVersion = "UY-HOME-WHOLE-BODY-8-V1-2026-08-28"
    const val householdEstimatedMinutes = 8
    const val footCameraPlacement = "后置 1× 主摄，距双脚约 1–1.2 米，镜头高度与足弓齐平"

    fun isApplicable(ageMonths: Int?): Boolean = ageMonths != null && ageMonths in minimumAgeMonths..maximumAgeMonths

    fun atrBand(degrees: Double?): AtrBand = when {
        degrees == null || !degrees.isFinite() || degrees < 0.0 -> AtrBand.Unavailable
        degrees >= atrReferralDegrees -> AtrBand.Red
        degrees >= atrAttentionDegrees -> AtrBand.Yellow
        else -> AtrBand.Green
    }

    fun maximumOcciputWallDistance(first: Double?, second: Double?): Double? =
        if (first != null && second != null && first.isFinite() && second.isFinite() && first >= 0.0 && second >= 0.0) maxOf(first, second) else null

    enum class Method { Camera, InstrumentAtr }
    data class Item(val number: Int, val title: String, val purpose: String, val instruction: String, val method: Method, val task: BodyCaptureTask? = null)

    val items = listOf(
        Item(1, "静态站姿对称观察", "头部、双肩和骨盆对称性", "双脚分开与肩同宽，赤足站在足印位置，双眼平视，双臂自然下垂，全身放松，不刻意挺胸。", Method.Camera, BodyCaptureTask.StandingBack),
        Item(2, "亚当斯前屈试验", "胸腰背部隆起不对称观察", "双脚并拢，膝关节完全伸直，双手合十自然下垂，从髋部缓慢前屈，直至背部接近水平；头部自然放松，不屈膝、不弓步。", Method.Camera, BodyCaptureTask.ForwardBend),
        Item(3, "躯干旋转角 ATR", "胸段 T4-T8、腰段 T12-L3 仪器读数", "维持标准前屈姿势，由校医或受训人员使用 Bunnell 型脊柱侧弯计分别读取胸段和腰段最大旋转角。", Method.InstrumentAtr),
        Item(4, "动态步态姿态观察", "肩、骨盆摆动和躯干中线", "沿 3 米直线通道自然往返行走 1 次，保持日常步速，不刻意纠正姿势。", Method.Camera, BodyCaptureTask.GaitVideo),
        Item(5, "无靠背坐姿脊柱直立测试", "坐位中线、肩高、胸椎后凸与 OTWD", "坐满硬质无靠背凳面，双手平放膝盖，双脚落地，自然放松并保持直立坐姿；随后按手册完成两次枕墙距测量。", Method.Camera, BodyCaptureTask.Seated)
    )

    /** Eight separately auditable household captures; instrument ATR remains professional-only. */
    val homeCameraItems: List<Item> = listOf(
        Item(1, "正面自然站立", "头颈、肩髋、骨盆与双膝力线", "面向镜头赤足站立，双脚与髋同宽，双臂自然下垂，目视前方。", Method.Camera, BodyCaptureTask.StandingFront),
        Item(2, "背面自然站立", "双肩、肩胛、躯干中线与骨盆对称", "背对镜头赤足自然站立，全身放松，不刻意挺胸或收腹。", Method.Camera, BodyCaptureTask.StandingBack),
        Item(3, "左右侧位姿态", "头前伸、圆肩、胸椎后凸与骨盆姿态", "先左侧面向镜头站稳，按提示转为右侧面；两侧都保持全身入镜。", Method.Camera, BodyCaptureTask.StandingSide),
        Item(4, "亚当斯前屈试验", "胸腰背表面旋转与隆起不对称", "双脚并拢，膝关节完全伸直，双手合十自然下垂，从髋部缓慢前屈至背部接近水平；不屈膝、不弓步。", Method.Camera, BodyCaptureTask.ForwardBend),
        Item(5, "动态下肢力线", "膝内扣、膝外翻与髋膝踝控制", "面向镜头完成 3 次缓慢自重下蹲，膝盖朝向第二足趾，脚跟不离地。", Method.Camera, BodyCaptureTask.DynamicKneeControl),
        Item(6, "3 米动态步态", "步频、左右支撑、肩髋摆动与躯干对称", "沿 3 米直线自然往返行走 1 次，保持日常步速，不刻意纠正姿势。", Method.Camera, BodyCaptureTask.GaitVideo),
        Item(7, "无靠背坐姿", "坐位中线、肩高、胸椎后凸与头前伸", "坐满硬质无靠背凳面，双手平放膝盖，双脚落地，自然放松并保持直立。", Method.Camera, BodyCaptureTask.Seated),
        Item(8, "足弓与足跟对齐", "足弓外观、足跟力线与左右对称", "双足赤足平行站立，先从内侧后方记录足弓与足跟，再按提示换另一侧；距离保持约 1–1.2 米。", Method.Camera, BodyCaptureTask.FootArch)
    )

    fun instruction(task: BodyCaptureTask): String = homeCameraItems.firstOrNull { it.task == task }?.instruction
        ?: items.firstOrNull { it.task == task }?.instruction
        ?: "请按标准动作完成。"
}
