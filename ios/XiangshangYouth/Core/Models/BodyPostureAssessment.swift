import Foundation

enum AdamsScreeningResult: String, Codable, CaseIterable {
    case negative, equivocal, positive

    var label: String {
        switch self {
        case .negative: "阴性（未见明显不对称）"
        case .equivocal: "可疑阳性（建议复测）"
        case .positive: "阳性代理信号（建议专科复核）"
        }
    }
}

/// One aggregated, on-device pose observation. Values are derived from
/// normalized Vision landmarks and the parent's measured height; raw frames
/// are never retained. The names deliberately say "camera proxy" where a
/// 2-D phone camera cannot replace a Scoliometer or standing X-ray.
struct PostureMetricSnapshot: Codable, Equatable, Identifiable {
    let id: String
    let task: BodyAssessmentRecord.CaptureTask
    let sampleCount: Int
    let confidence: Double
    let shoulderHeightDifferenceCm: Double?
    let pelvicHeightDifferenceCm: Double?
    let headTiltDegrees: Double?
    let spinalMidlineDeviationCm: Double?
    let thoracicRoundingDegrees: Double?
    let forwardHeadAngleDegrees: Double?
    let cameraProxyAtrDegrees: Double?
    let cameraProxyRibProminenceCm: Double?
    /// Optional validated instrument/depth measurement. The current phone
    /// RGB flow never fills this field; when a calibrated field device or
    /// backend supplies it, the framework's ATR thresholds become active.
    var instrumentAtrDegrees: Double? = nil
    /// Optional calibrated chest/waist ATR readings. The maximum validated
    /// segment reading drives the 5°/7° screening gates.
    var thoracicAtrDegrees: Double? = nil
    var lumbarAtrDegrees: Double? = nil
    /// Optional occiput-to-wall distance from a supervised measurement.
    var occiputWallDistanceCm: Double? = nil
    let gaitShoulderSwingDifferenceCm: Double?
    let gaitPelvicSwingDifferenceCm: Double?
    let gaitTrunkSwayCm: Double?

    // Keep a stable, explicit initializer for persisted records and capture
    // adapters. Swift's synthesized memberwise initializer moves defaulted
    // properties to the end, which makes it impossible for older call sites
    // to add optional calibrated fields without an ambiguous argument list.
    init(
        id: String,
        task: BodyAssessmentRecord.CaptureTask,
        sampleCount: Int,
        confidence: Double,
        shoulderHeightDifferenceCm: Double?,
        pelvicHeightDifferenceCm: Double?,
        headTiltDegrees: Double?,
        spinalMidlineDeviationCm: Double?,
        thoracicRoundingDegrees: Double?,
        forwardHeadAngleDegrees: Double?,
        cameraProxyAtrDegrees: Double?,
        cameraProxyRibProminenceCm: Double?,
        instrumentAtrDegrees: Double? = nil,
        thoracicAtrDegrees: Double? = nil,
        lumbarAtrDegrees: Double? = nil,
        occiputWallDistanceCm: Double? = nil,
        gaitShoulderSwingDifferenceCm: Double?,
        gaitPelvicSwingDifferenceCm: Double?,
        gaitTrunkSwayCm: Double?
    ) {
        self.id = id
        self.task = task
        self.sampleCount = sampleCount
        self.confidence = confidence
        self.shoulderHeightDifferenceCm = shoulderHeightDifferenceCm
        self.pelvicHeightDifferenceCm = pelvicHeightDifferenceCm
        self.headTiltDegrees = headTiltDegrees
        self.spinalMidlineDeviationCm = spinalMidlineDeviationCm
        self.thoracicRoundingDegrees = thoracicRoundingDegrees
        self.forwardHeadAngleDegrees = forwardHeadAngleDegrees
        self.cameraProxyAtrDegrees = cameraProxyAtrDegrees
        self.cameraProxyRibProminenceCm = cameraProxyRibProminenceCm
        self.instrumentAtrDegrees = instrumentAtrDegrees
        self.thoracicAtrDegrees = thoracicAtrDegrees
        self.lumbarAtrDegrees = lumbarAtrDegrees
        self.occiputWallDistanceCm = occiputWallDistanceCm
        self.gaitShoulderSwingDifferenceCm = gaitShoulderSwingDifferenceCm
        self.gaitPelvicSwingDifferenceCm = gaitPelvicSwingDifferenceCm
        self.gaitTrunkSwayCm = gaitTrunkSwayCm
    }

    var adamsResult: AdamsScreeningResult? {
        guard let prominence = cameraProxyRibProminenceCm, prominence.isFinite, prominence >= 0 else { return nil }
        if prominence >= PostureScreeningRules.ribProminencePositiveCentimeters { return .positive }
        if prominence >= PostureScreeningRules.ribProminenceEquivocalCentimeters { return .equivocal }
        return .negative
    }
}

/// Product screening thresholds for the on-device posture proxy. These are
/// referral guardrails, not diagnostic scoliosis cut-offs.
enum PostureScreeningRules {
    static let rulesSourceVersion = "UY-IMCA-SCOLIOSIS-FRAMEWORK-V1-2026-07-20"
    // Profile weights are kept in the human-readable policy values below;
    // their total is normalized during aggregation so a future profile cannot
    // accidentally push the explainable risk score above 100.
    static let scoringWeightTotal = 1.10
    // Keep the publication gate aligned with Android. A report must have
    // enough stable frames and reliable landmarks before it can influence a
    // family risk level.
    static let minimumSamples = 10
    static let minimumConfidence = 0.56
    static let headTiltAttentionDegrees = 3.0
    static let headTiltReferralDegrees = 6.0
    static let shoulderAttentionCentimeters = 1.0
    static let shoulderReferralCentimeters = 1.6
    static let pelvisAttentionCentimeters = 0.5
    static let pelvisReferralCentimeters = 1.0
    static let seatedMidlineAttentionCentimeters = 1.3
    static let seatedRoundingAttentionDegrees = 24.0
    static let forwardHeadAttentionDegrees = 12.0
    static let forwardHeadReferralDegrees = 16.0
    static let gaitAttentionCentimeters = 1.0
    static let proxyAtrAttentionDegrees = 5.0
    static let proxyAtrReferralDegrees = 7.0
    // Keep the optional 3-D/depth adapter thresholds aligned with Android.
    // The current RGB camera flow intentionally leaves these values nil.
    static let ribProminenceEquivocalCentimeters = 0.8
    static let ribProminencePositiveCentimeters = 1.2

    struct ScoringProfile {
        let shoulderAttention: Double
        let shoulderReferral: Double
        let pelvisAttention: Double
        let pelvisReferral: Double
        let seatedMidlineAttention: Double
        let seatedRoundingAttention: Double
        let forwardHeadAttention: Double
        let forwardHeadReferral: Double
        let gaitAttention: Double
        let proxyAtrAttention: Double
        let proxyAtrReferral: Double
        let ribProminenceEquivocalCentimeters: Double
        let ribProminencePositiveCentimeters: Double
        let weightedShoulder: Double
        let weightedPelvis: Double
        let weightedSpinalMidline: Double
        let weightedThoracicRounding: Double
        let weightedForwardHead: Double
        let weightedAdams: Double
        let weightedGait: Double
        let yellowScore: Double
        let redScore: Double
    }

    static func profile(ageMonths: Int?) -> ScoringProfile {
        switch ageMonths ?? 108 {
        case ...96:
            return ScoringProfile(shoulderAttention: 1.05, shoulderReferral: 1.7, pelvisAttention: 0.55, pelvisReferral: 1.05, seatedMidlineAttention: 1.35, seatedRoundingAttention: 25, forwardHeadAttention: 12.5, forwardHeadReferral: 16.5, gaitAttention: 1.05, proxyAtrAttention: 5.2, proxyAtrReferral: 7.2, ribProminenceEquivocalCentimeters: 0.85, ribProminencePositiveCentimeters: 1.25, weightedShoulder: 0.20, weightedPelvis: 0.14, weightedSpinalMidline: 0.11, weightedThoracicRounding: 0.11, weightedForwardHead: 0.13, weightedAdams: 0.17, weightedGait: 0.24, yellowScore: 42, redScore: 63)
        case 97...132:
            return ScoringProfile(shoulderAttention: 1.0, shoulderReferral: 1.6, pelvisAttention: 0.5, pelvisReferral: 1.0, seatedMidlineAttention: 1.3, seatedRoundingAttention: 24, forwardHeadAttention: 12, forwardHeadReferral: 16, gaitAttention: 1.0, proxyAtrAttention: 5.0, proxyAtrReferral: 7.0, ribProminenceEquivocalCentimeters: 0.8, ribProminencePositiveCentimeters: 1.2, weightedShoulder: 0.20, weightedPelvis: 0.13, weightedSpinalMidline: 0.12, weightedThoracicRounding: 0.10, weightedForwardHead: 0.14, weightedAdams: 0.18, weightedGait: 0.23, yellowScore: 40, redScore: 61)
        case 133...180:
            return ScoringProfile(shoulderAttention: 0.95, shoulderReferral: 1.55, pelvisAttention: 0.5, pelvisReferral: 0.98, seatedMidlineAttention: 1.25, seatedRoundingAttention: 23, forwardHeadAttention: 11.5, forwardHeadReferral: 15.5, gaitAttention: 0.95, proxyAtrAttention: 4.8, proxyAtrReferral: 6.8, ribProminenceEquivocalCentimeters: 0.78, ribProminencePositiveCentimeters: 1.15, weightedShoulder: 0.18, weightedPelvis: 0.13, weightedSpinalMidline: 0.12, weightedThoracicRounding: 0.10, weightedForwardHead: 0.15, weightedAdams: 0.19, weightedGait: 0.23, yellowScore: 38, redScore: 59)
        default:
            return ScoringProfile(shoulderAttention: 0.92, shoulderReferral: 1.52, pelvisAttention: 0.48, pelvisReferral: 0.95, seatedMidlineAttention: 1.2, seatedRoundingAttention: 23, forwardHeadAttention: 11.2, forwardHeadReferral: 15, gaitAttention: 0.92, proxyAtrAttention: 4.7, proxyAtrReferral: 6.6, ribProminenceEquivocalCentimeters: 0.76, ribProminencePositiveCentimeters: 1.12, weightedShoulder: 0.17, weightedPelvis: 0.12, weightedSpinalMidline: 0.12, weightedThoracicRounding: 0.10, weightedForwardHead: 0.15, weightedAdams: 0.20, weightedGait: 0.24, yellowScore: 37, redScore: 57)
        }
    }
}

/// Report-level rules from UY-IMCA V1 (研发参考版), derived from the supplied
/// 7.20 framework. This is a screening report: red means referral advice, not
/// a scoliosis diagnosis. A clinician and imaging remain the diagnostic path.
struct PostureAssessmentReport: Codable, Equatable {
    static let algorithmVersion = "UY-IMCA-CV-1.3"
    /// Version of the threshold/calibration manifest used with the algorithm.
    /// Keep this alongside every persisted/remote report so results can be
    /// audited and safely re-scored after a calibration rollout.
    static let calibrationVersion = "UY-CAL-BASELINE-1.0"
    let generatedAt: Date
    let algorithm: String
    let snapshots: [BodyAssessmentRecord.CaptureTask: PostureMetricSnapshot]
    let overallLevel: BodyAssessmentRecord.AttentionLevel
    let reasons: [String]
    let disclaimer: String
    /// Exposed for the same dashboard contract as Android. These are
    /// explainable screening/quality scores, never a medical diagnosis.
    let riskScore: Int
    let qualityScore: Int
    let calibrationVersion: String
    let rulesSourceVersion: String

    private enum CodingKeys: String, CodingKey {
        case generatedAt, algorithm, snapshots, overallLevel, reasons, disclaimer, riskScore, qualityScore, calibrationVersion, rulesSourceVersion
    }

    init(generatedAt: Date, algorithm: String, snapshots: [BodyAssessmentRecord.CaptureTask: PostureMetricSnapshot], overallLevel: BodyAssessmentRecord.AttentionLevel, reasons: [String], disclaimer: String, riskScore: Int = 0, qualityScore: Int = 0, calibrationVersion: String = PostureAssessmentReport.calibrationVersion, rulesSourceVersion: String = PostureScreeningRules.rulesSourceVersion) {
        self.generatedAt = generatedAt
        self.algorithm = algorithm
        self.snapshots = snapshots
        self.overallLevel = overallLevel
        self.reasons = reasons
        self.disclaimer = disclaimer
        self.riskScore = min(100, max(0, riskScore))
        self.qualityScore = min(100, max(0, qualityScore))
        self.calibrationVersion = calibrationVersion
        self.rulesSourceVersion = rulesSourceVersion
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        generatedAt = try container.decode(Date.self, forKey: .generatedAt)
        algorithm = try container.decode(String.self, forKey: .algorithm)
        snapshots = try container.decode([BodyAssessmentRecord.CaptureTask: PostureMetricSnapshot].self, forKey: .snapshots)
        overallLevel = try container.decode(BodyAssessmentRecord.AttentionLevel.self, forKey: .overallLevel)
        reasons = try container.decode([String].self, forKey: .reasons)
        disclaimer = try container.decode(String.self, forKey: .disclaimer)
        riskScore = min(100, max(0, try container.decodeIfPresent(Int.self, forKey: .riskScore) ?? 0))
        qualityScore = min(100, max(0, try container.decodeIfPresent(Int.self, forKey: .qualityScore) ?? 0))
        calibrationVersion = try container.decodeIfPresent(String.self, forKey: .calibrationVersion) ?? PostureAssessmentReport.calibrationVersion
        rulesSourceVersion = try container.decodeIfPresent(String.self, forKey: .rulesSourceVersion) ?? PostureScreeningRules.rulesSourceVersion
    }

    /// A report is complete only when every task has enough reliable frames;
    /// a persisted placeholder snapshot must not make the UI look finished.
    var isComplete: Bool {
        BodyAssessmentRecord.CaptureTask.allCases.allSatisfy { task in
            guard let snapshot = snapshots[task] else { return false }
            let numeric: [Double?]
            switch snapshot.task {
            case .standingBack:
                numeric = [snapshot.shoulderHeightDifferenceCm, snapshot.pelvicHeightDifferenceCm, snapshot.headTiltDegrees]
            case .forwardBend:
                numeric = [snapshot.spinalMidlineDeviationCm, snapshot.thoracicRoundingDegrees, snapshot.forwardHeadAngleDegrees, snapshot.cameraProxyAtrDegrees, snapshot.cameraProxyRibProminenceCm, snapshot.instrumentAtrDegrees, snapshot.thoracicAtrDegrees, snapshot.lumbarAtrDegrees]
            case .seatedPosture:
                numeric = [snapshot.shoulderHeightDifferenceCm, snapshot.spinalMidlineDeviationCm, snapshot.thoracicRoundingDegrees, snapshot.forwardHeadAngleDegrees, snapshot.occiputWallDistanceCm]
            case .gaitVideo:
                numeric = [snapshot.gaitShoulderSwingDifferenceCm, snapshot.gaitPelvicSwingDifferenceCm, snapshot.gaitTrunkSwayCm]
            }
            let hasEvidence = numeric.contains { $0?.isFinite == true } || snapshot.adamsResult != nil
            return hasEvidence && snapshot.sampleCount >= PostureScreeningRules.minimumSamples && snapshot.confidence.isFinite && snapshot.confidence >= PostureScreeningRules.minimumConfidence && snapshot.confidence <= 1
        }
    }

    static func make(snapshots: [BodyAssessmentRecord.CaptureTask: PostureMetricSnapshot], generatedAt: Date = .now, ageMonths: Int? = nil) -> PostureAssessmentReport {
        let profile = PostureScreeningRules.profile(ageMonths: ageMonths)
        let standing = snapshots[.standingBack]
        let forward = snapshots[.forwardBend]
        let seated = snapshots[.seatedPosture]
        let gait = snapshots[.gaitVideo]
        func valid(_ value: Double?, max: Double) -> Bool {
            guard let value else { return true }
            return value.isFinite && abs(value) <= max
        }
        func validMetrics(_ snapshot: PostureMetricSnapshot?) -> Bool {
            guard let snapshot else { return true }
            return valid(snapshot.shoulderHeightDifferenceCm, max: 20) &&
                valid(snapshot.pelvicHeightDifferenceCm, max: 20) &&
                valid(snapshot.headTiltDegrees, max: 180) &&
                valid(snapshot.spinalMidlineDeviationCm, max: 20) &&
                valid(snapshot.thoracicRoundingDegrees, max: 180) &&
                valid(snapshot.forwardHeadAngleDegrees, max: 180) &&
                valid(snapshot.cameraProxyAtrDegrees, max: 180) &&
                valid(snapshot.cameraProxyRibProminenceCm, max: 20) &&
                valid(snapshot.instrumentAtrDegrees, max: 180) &&
                valid(snapshot.thoracicAtrDegrees, max: 180) &&
                valid(snapshot.lumbarAtrDegrees, max: 180) &&
                valid(snapshot.occiputWallDistanceCm, max: 50) &&
                valid(snapshot.gaitShoulderSwingDifferenceCm, max: 20) &&
                valid(snapshot.gaitPelvicSwingDifferenceCm, max: 20) &&
                valid(snapshot.gaitTrunkSwayCm, max: 20)
        }
        func hasMetricEvidence(_ snapshot: PostureMetricSnapshot?) -> Bool {
            guard let snapshot else { return false }
            let numeric: [Double?]
            switch snapshot.task {
            case .standingBack:
                numeric = [snapshot.shoulderHeightDifferenceCm, snapshot.pelvicHeightDifferenceCm, snapshot.headTiltDegrees]
            case .forwardBend:
                numeric = [snapshot.spinalMidlineDeviationCm, snapshot.thoracicRoundingDegrees, snapshot.forwardHeadAngleDegrees, snapshot.cameraProxyAtrDegrees, snapshot.cameraProxyRibProminenceCm, snapshot.instrumentAtrDegrees, snapshot.thoracicAtrDegrees, snapshot.lumbarAtrDegrees]
            case .seatedPosture:
                numeric = [snapshot.shoulderHeightDifferenceCm, snapshot.spinalMidlineDeviationCm, snapshot.thoracicRoundingDegrees, snapshot.forwardHeadAngleDegrees, snapshot.occiputWallDistanceCm]
            case .gaitVideo:
                numeric = [snapshot.gaitShoulderSwingDifferenceCm, snapshot.gaitPelvicSwingDifferenceCm, snapshot.gaitTrunkSwayCm]
            }
            return numeric.contains { $0?.isFinite == true } || snapshot.adamsResult != nil
        }
        let metricsValid = [standing, forward, seated, gait].allSatisfy(validMetrics)
        // Reports can be restored from older/local payloads. Treat non-finite
        // or negative geometry as missing instead of allowing NaN to bypass a
        // threshold or leak into a family-facing reason string.
        func magnitude(_ value: Double?) -> Double {
            guard let value, value.isFinite else { return 0 }
            return abs(value)
        }
        let shoulder = max(magnitude(standing?.shoulderHeightDifferenceCm), magnitude(seated?.shoulderHeightDifferenceCm))
        let pelvis = magnitude(standing?.pelvicHeightDifferenceCm)
        let shoulderRed = shoulder > profile.shoulderReferral
        let pelvisRed = pelvis > profile.pelvisReferral
        let shoulderYellow = shoulder > profile.shoulderAttention
        let pelvisYellow = pelvis > profile.pelvisAttention
        // Use the age-specific profile when a numeric rib-prominence proxy is
        // present. The snapshot convenience property keeps legacy/static
        // thresholds for display, but report scoring must match the server.
        let adams: AdamsScreeningResult? = {
            guard let value = forward?.cameraProxyRibProminenceCm, value.isFinite else { return forward?.adamsResult }
            let prominence = abs(value)
            if prominence >= profile.ribProminencePositiveCentimeters { return .positive }
            if prominence >= profile.ribProminenceEquivocalCentimeters { return .equivocal }
            return .negative
        }()
        let instrumentATR = [forward?.instrumentAtrDegrees, forward?.thoracicAtrDegrees, forward?.lumbarAtrDegrees]
            .compactMap { $0.flatMap { $0.isFinite ? max(0, $0) : nil } }
            .max() ?? 0
        let atrRed = instrumentATR >= profile.proxyAtrReferral
        let atrYellow = instrumentATR >= profile.proxyAtrAttention
        let occiputWallAbnormal = seated?.occiputWallDistanceCm.flatMap { $0.isFinite ? max(0, $0) : nil }.map { $0 > 2.0 } ?? false
        let gaitAbnormal = max(magnitude(gait?.gaitShoulderSwingDifferenceCm), max(magnitude(gait?.gaitPelvicSwingDifferenceCm), magnitude(gait?.gaitTrunkSwayCm))) >= profile.gaitAttention
        let seatedMidline = magnitude(seated?.spinalMidlineDeviationCm)
        let seatedRounding = magnitude(seated?.thoracicRoundingDegrees)
        let seatedForwardHead = magnitude(seated?.forwardHeadAngleDegrees)
        let headTilt = magnitude(standing?.headTiltDegrees)
        let headTiltYellow = headTilt > PostureScreeningRules.headTiltAttentionDegrees
        let seatedAbnormal = seatedMidline > profile.seatedMidlineAttention || seatedRounding >= profile.seatedRoundingAttention || seatedForwardHead >= profile.forwardHeadReferral
        let seatedAbnormalYellow = seatedMidline > profile.seatedMidlineAttention || seatedRounding >= profile.seatedRoundingAttention || seatedForwardHead >= profile.forwardHeadAttention
        let complete = BodyAssessmentRecord.CaptureTask.allCases.allSatisfy { task in
            guard let snapshot = snapshots[task] else { return false }
            return hasMetricEvidence(snapshot) && snapshot.sampleCount >= PostureScreeningRules.minimumSamples && snapshot.confidence.isFinite && snapshot.confidence >= PostureScreeningRules.minimumConfidence && snapshot.confidence <= 1
        }
        func clamp01(_ value: Double) -> Double { min(1, max(0, value)) }
        func norm(_ value: Double, _ attention: Double, _ referral: Double) -> Double {
            guard value.isFinite, attention.isFinite, referral.isFinite, referral > attention else { return 0 }
            if value <= attention { return 0 }
            if value >= referral { return 1 }
            return clamp01((value - attention) / (referral - attention))
        }
        func evidence(_ snapshot: PostureMetricSnapshot?) -> Double {
            guard let snapshot,
                  snapshot.sampleCount >= PostureScreeningRules.minimumSamples,
                  snapshot.confidence.isFinite,
                  snapshot.confidence >= PostureScreeningRules.minimumConfidence,
                  snapshot.confidence <= 1 else { return 0 }
            let sampleFactor = min(1, max(0, Double(snapshot.sampleCount - PostureScreeningRules.minimumSamples) / Double(PostureScreeningRules.minimumSamples)))
            let confidenceFactor = min(1, max(0, (snapshot.confidence - PostureScreeningRules.minimumConfidence) / 0.44))
            return 0.55 * confidenceFactor + 0.45 * sampleFactor
        }
        let quality = [standing, forward, seated, gait].map(evidence).reduce(0, +) / 4
        let adamsValue: Double = adams == .positive ? 1 : (adams == .equivocal ? 0.48 : 0)
        let weightedScoreRaw = (
            norm(shoulder, profile.shoulderAttention, profile.shoulderReferral) * profile.weightedShoulder +
            norm(pelvis, profile.pelvisAttention, profile.pelvisReferral) * profile.weightedPelvis +
            norm(seatedMidline, profile.seatedMidlineAttention, profile.seatedMidlineAttention + 1.2) * profile.weightedSpinalMidline +
            norm(seatedRounding, profile.seatedRoundingAttention, profile.seatedRoundingAttention + 14) * profile.weightedThoracicRounding +
            norm(seatedForwardHead, profile.forwardHeadAttention, profile.forwardHeadReferral) * profile.weightedForwardHead +
            adamsValue * profile.weightedAdams +
            norm(max(magnitude(gait?.gaitShoulderSwingDifferenceCm), max(magnitude(gait?.gaitPelvicSwingDifferenceCm), magnitude(gait?.gaitTrunkSwayCm))), profile.gaitAttention, profile.gaitAttention + 1.1) * profile.weightedGait
        ) / PostureScreeningRules.scoringWeightTotal
        let evidenceAdjustedScore = weightedScoreRaw * (0.55 + 0.45 * clamp01(quality))
        let level: BodyAssessmentRecord.AttentionLevel
        if !complete || !metricsValid { level = .pending }
        else if atrRed || (adams == .positive && (gaitAbnormal || seatedAbnormal)) || evidenceAdjustedScore >= profile.redScore / 100 { level = .red }
        else if atrYellow || occiputWallAbnormal || shoulderRed || pelvisRed || adams == .positive || gaitAbnormal || seatedAbnormal || headTiltYellow || evidenceAdjustedScore >= profile.yellowScore / 100 { level = .yellow }
        else if shoulderYellow || pelvisYellow || adams == .equivocal || seatedAbnormalYellow { level = .yellow }
        else { level = .green }

        var reasons: [String] = []
        if let value = standing?.shoulderHeightDifferenceCm, value.isFinite { reasons.append(String(format: "站姿双肩高度差 %.1f cm", abs(value))) }
        if let value = standing?.pelvicHeightDifferenceCm, value.isFinite { reasons.append(String(format: "站姿骨盆高度差 %.1f cm", abs(value))) }
        if let value = forward?.cameraProxyAtrDegrees, value.isFinite { reasons.append(String(format: "前屈姿态代偿角 %.1f°（用于观察提示）", abs(value))) }
        if let value = [forward?.instrumentAtrDegrees, forward?.thoracicAtrDegrees, forward?.lumbarAtrDegrees].compactMap({ $0.flatMap { $0.isFinite ? max(0, $0) : nil } }).max() { reasons.append(String(format: "校准设备/深度 ATR 最大值 %.1f°（设备筛查证据）", value)) }
        if let value = standing?.headTiltDegrees, value.isFinite { reasons.append(String(format: "头部侧倾角 %.1f°", abs(value))) }
        if !metricsValid { reasons.append("检测到异常测量值，请重新拍摄并保持设备稳定。") }
        if let adams { reasons.append("前屈背部不对称：\(adams.label)") }
        if let value = seated?.spinalMidlineDeviationCm, value.isFinite { reasons.append(String(format: "坐姿躯干中线偏移 %.1f cm", abs(value))) }
        if let value = seated?.thoracicRoundingDegrees, value.isFinite { reasons.append(String(format: "坐姿胸椎圆背观察角度 %.1f°", abs(value))) }
        if let value = seated?.forwardHeadAngleDegrees, value.isFinite { reasons.append(String(format: "坐姿头前伸观察角度 %.1f°", abs(value))) }
        if let value = gait?.gaitTrunkSwayCm, value.isFinite { reasons.append(String(format: "步态躯干侧向摆动 %.1f cm", abs(value))) }
        if let value = seated?.occiputWallDistanceCm, value.isFinite, value >= 0 { reasons.append(String(format: "枕墙距 %.1f cm", value)) }
        if reasons.isEmpty { reasons.append(complete ? "记录不足，暂未形成完整指标。" : "请完成 4 项拍摄记录，并保持每项画面稳定、全身入镜。") }
        return PostureAssessmentReport(generatedAt: generatedAt, algorithm: algorithmVersion, snapshots: snapshots, overallLevel: level, reasons: reasons, disclaimer: "本报告用于家庭健康观察与风险提示。二维相机不输出肋峰/ATR或Cobb角度，结果不替代脊柱侧弯筛查、体检或影像检查。出现持续疼痛或异常体征请及时就医。", riskScore: min(100, max(0, Int((evidenceAdjustedScore * 100).rounded(.down)))), qualityScore: min(100, max(0, Int((quality * 100).rounded(.down)))))
    }
}
