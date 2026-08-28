import Foundation

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
    let validationStatus: AlgorithmValidationStatus
    let screeningDecision: BodyScreeningDecision?

    var canPublishClassification: Bool { validationStatus.allowsClassification }

    private enum CodingKeys: String, CodingKey {
        case generatedAt, algorithm, snapshots, overallLevel, reasons, disclaimer, riskScore, qualityScore, calibrationVersion, rulesSourceVersion, validationStatus, screeningDecision
    }

    init(generatedAt: Date, algorithm: String, snapshots: [BodyAssessmentRecord.CaptureTask: PostureMetricSnapshot], overallLevel: BodyAssessmentRecord.AttentionLevel, reasons: [String], disclaimer: String, riskScore: Int = 0, qualityScore: Int = 0, calibrationVersion: String = PostureAssessmentReport.calibrationVersion, rulesSourceVersion: String = PostureScreeningRules.rulesSourceVersion, validationStatus: AlgorithmValidationStatus = AlgorithmReleaseGate.posture, screeningDecision: BodyScreeningDecision? = nil) {
        self.generatedAt = generatedAt
        self.algorithm = algorithm
        self.snapshots = snapshots
        self.validationStatus = validationStatus
        self.overallLevel = validationStatus.allowsClassification ? overallLevel : .pending
        self.reasons = reasons
        self.disclaimer = disclaimer
        self.riskScore = validationStatus.allowsClassification ? min(100, max(0, riskScore)) : 0
        self.qualityScore = min(100, max(0, qualityScore))
        self.calibrationVersion = calibrationVersion
        self.rulesSourceVersion = rulesSourceVersion
        self.screeningDecision = screeningDecision
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        generatedAt = try container.decode(Date.self, forKey: .generatedAt)
        algorithm = try container.decode(String.self, forKey: .algorithm)
        snapshots = try container.decode([BodyAssessmentRecord.CaptureTask: PostureMetricSnapshot].self, forKey: .snapshots)
        validationStatus = try container.decodeIfPresent(AlgorithmValidationStatus.self, forKey: .validationStatus) ?? .pendingHumanValidation
        let decodedLevel = try container.decode(BodyAssessmentRecord.AttentionLevel.self, forKey: .overallLevel)
        overallLevel = validationStatus.allowsClassification ? decodedLevel : .pending
        reasons = try container.decode([String].self, forKey: .reasons)
        disclaimer = try container.decode(String.self, forKey: .disclaimer)
        riskScore = validationStatus.allowsClassification ? min(100, max(0, try container.decodeIfPresent(Int.self, forKey: .riskScore) ?? 0)) : 0
        qualityScore = min(100, max(0, try container.decodeIfPresent(Int.self, forKey: .qualityScore) ?? 0))
        calibrationVersion = try container.decodeIfPresent(String.self, forKey: .calibrationVersion) ?? PostureAssessmentReport.calibrationVersion
        rulesSourceVersion = try container.decodeIfPresent(String.self, forKey: .rulesSourceVersion) ?? PostureScreeningRules.rulesSourceVersion
        screeningDecision = try container.decodeIfPresent(BodyScreeningDecision.self, forKey: .screeningDecision)
    }

    /// A report is complete only when every task has enough reliable frames;
    /// a persisted placeholder snapshot must not make the UI look finished.
    var isComplete: Bool {
        BodyAssessmentRecord.CaptureTask.allCases.allSatisfy { task in
            guard let snapshot = snapshots[task] else { return false }
            let numeric: [Double?]
            switch snapshot.task {
            case .standingFront:
                numeric = [snapshot.shoulderHeightDifferenceCm, snapshot.pelvicHeightDifferenceCm, snapshot.headTiltDegrees, snapshot.kneeAlignmentProxyRatio, snapshot.lowerLimbAxisAsymmetryDegrees]
            case .standingBack:
                numeric = [snapshot.shoulderHeightDifferenceCm, snapshot.pelvicHeightDifferenceCm, snapshot.headTiltDegrees]
            case .standingSide:
                numeric = [snapshot.forwardHeadAngleDegrees, snapshot.thoracicRoundingDegrees, snapshot.shoulderProtractionProxyDegrees, snapshot.pelvicTiltProxyDegrees]
            case .forwardBend:
                numeric = [snapshot.spinalMidlineDeviationCm, snapshot.thoracicRoundingDegrees, snapshot.forwardHeadAngleDegrees, snapshot.cameraProxyAtrDegrees, snapshot.cameraProxyRibProminenceCm, snapshot.instrumentAtrDegrees, snapshot.thoracicAtrDegrees, snapshot.lumbarAtrDegrees, snapshot.thoracicAtrFirstDegrees, snapshot.thoracicAtrSecondDegrees, snapshot.lumbarAtrFirstDegrees, snapshot.lumbarAtrSecondDegrees, snapshot.seatedForwardBendAtrDegrees]
            case .dynamicKneeControl:
                numeric = [snapshot.leftKneeValgusProxyDegrees, snapshot.rightKneeValgusProxyDegrees, snapshot.kneeTrackingAsymmetryRatio, snapshot.squatDepthRatio, snapshot.movementRepetitionCount]
            case .seatedPosture:
                numeric = [snapshot.shoulderHeightDifferenceCm, snapshot.spinalMidlineDeviationCm, snapshot.thoracicRoundingDegrees, snapshot.forwardHeadAngleDegrees, snapshot.occiputWallDistanceCm]
            case .gaitVideo:
                numeric = [snapshot.gaitShoulderSwingDifferenceCm, snapshot.gaitPelvicSwingDifferenceCm, snapshot.gaitTrunkSwayCm]
            case .footArch:
                numeric = [snapshot.footArchVisibilityScore, snapshot.leftArchProxyIndex, snapshot.rightArchProxyIndex, snapshot.heelAlignmentProxyDegrees]
            }
            let hasStructuredObservation = snapshot.adamsObservedResult != nil || snapshot.gaitObservedAbnormal != nil || snapshot.seatedThoracicKyphosisObserved != nil
            let hasEvidence = numeric.contains { $0?.isFinite == true } || snapshot.adamsResult != nil || hasStructuredObservation
            return hasEvidence && snapshot.sampleCount >= PostureScreeningRules.minimumSamples && snapshot.confidence.isFinite && snapshot.confidence >= PostureScreeningRules.minimumConfidence && snapshot.confidence <= 1
        }
    }

    static func make(snapshots: [BodyAssessmentRecord.CaptureTask: PostureMetricSnapshot], generatedAt: Date = .now, ageMonths: Int? = nil, validationStatus: AlgorithmValidationStatus = AlgorithmReleaseGate.posture) -> PostureAssessmentReport {
        let profile = PostureScreeningRules.profile(ageMonths: ageMonths)
        let standingFront = snapshots[.standingFront]
        let standing = snapshots[.standingBack]
        let standingSide = snapshots[.standingSide]
        let forward = snapshots[.forwardBend]
        let dynamicKnee = snapshots[.dynamicKneeControl]
        let seated = snapshots[.seatedPosture]
        let gait = snapshots[.gaitVideo]
        let footArch = snapshots[.footArch]
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
                valid(snapshot.shoulderProtractionProxyDegrees, max: 180) &&
                valid(snapshot.pelvicTiltProxyDegrees, max: 90) &&
                valid(snapshot.kneeAlignmentProxyRatio, max: 2) &&
                valid(snapshot.lowerLimbAxisAsymmetryDegrees, max: 90) &&
                valid(snapshot.leftKneeValgusProxyDegrees, max: 90) &&
                valid(snapshot.rightKneeValgusProxyDegrees, max: 90) &&
                valid(snapshot.kneeTrackingAsymmetryRatio, max: 3) &&
                valid(snapshot.squatDepthRatio, max: 2) &&
                valid(snapshot.movementRepetitionCount, max: 20) &&
                valid(snapshot.footArchVisibilityScore, max: 1) &&
                valid(snapshot.leftArchProxyIndex, max: 1) &&
                valid(snapshot.rightArchProxyIndex, max: 1) &&
                valid(snapshot.heelAlignmentProxyDegrees, max: 90) &&
                valid(snapshot.instrumentAtrDegrees, max: 180) &&
                valid(snapshot.thoracicAtrDegrees, max: 180) &&
                valid(snapshot.lumbarAtrDegrees, max: 180) &&
                valid(snapshot.thoracicAtrFirstDegrees, max: 180) &&
                valid(snapshot.thoracicAtrSecondDegrees, max: 180) &&
                valid(snapshot.lumbarAtrFirstDegrees, max: 180) &&
                valid(snapshot.lumbarAtrSecondDegrees, max: 180) &&
                valid(snapshot.seatedForwardBendAtrDegrees, max: 180) &&
                valid(snapshot.occiputWallDistanceCm, max: 50) &&
                valid(snapshot.gaitShoulderSwingDifferenceCm, max: 20) &&
                valid(snapshot.gaitPelvicSwingDifferenceCm, max: 20) &&
                valid(snapshot.gaitTrunkSwayCm, max: 20)
        }
        func hasMetricEvidence(_ snapshot: PostureMetricSnapshot?) -> Bool {
            guard let snapshot else { return false }
            let numeric: [Double?]
            switch snapshot.task {
            case .standingFront:
                numeric = [snapshot.shoulderHeightDifferenceCm, snapshot.pelvicHeightDifferenceCm, snapshot.headTiltDegrees, snapshot.kneeAlignmentProxyRatio, snapshot.lowerLimbAxisAsymmetryDegrees]
            case .standingBack:
                numeric = [snapshot.shoulderHeightDifferenceCm, snapshot.pelvicHeightDifferenceCm, snapshot.headTiltDegrees]
            case .standingSide:
                numeric = [snapshot.forwardHeadAngleDegrees, snapshot.thoracicRoundingDegrees, snapshot.shoulderProtractionProxyDegrees, snapshot.pelvicTiltProxyDegrees]
            case .forwardBend:
                numeric = [snapshot.spinalMidlineDeviationCm, snapshot.thoracicRoundingDegrees, snapshot.forwardHeadAngleDegrees, snapshot.cameraProxyAtrDegrees, snapshot.cameraProxyRibProminenceCm, snapshot.instrumentAtrDegrees, snapshot.thoracicAtrDegrees, snapshot.lumbarAtrDegrees]
            case .dynamicKneeControl:
                numeric = [snapshot.leftKneeValgusProxyDegrees, snapshot.rightKneeValgusProxyDegrees, snapshot.kneeTrackingAsymmetryRatio, snapshot.squatDepthRatio, snapshot.movementRepetitionCount]
            case .seatedPosture:
                numeric = [snapshot.shoulderHeightDifferenceCm, snapshot.spinalMidlineDeviationCm, snapshot.thoracicRoundingDegrees, snapshot.forwardHeadAngleDegrees, snapshot.occiputWallDistanceCm]
            case .gaitVideo:
                numeric = [snapshot.gaitShoulderSwingDifferenceCm, snapshot.gaitPelvicSwingDifferenceCm, snapshot.gaitTrunkSwayCm]
            case .footArch:
                numeric = [snapshot.footArchVisibilityScore, snapshot.leftArchProxyIndex, snapshot.rightArchProxyIndex, snapshot.heelAlignmentProxyDegrees]
            }
            return numeric.contains { $0?.isFinite == true } || snapshot.adamsResult != nil || snapshot.gaitObservedAbnormal != nil || snapshot.seatedThoracicKyphosisObserved != nil
        }
        let metricsValid = snapshots.values.allSatisfy(validMetrics)
        // Reports can be restored from older/local payloads. Treat non-finite
        // or negative geometry as missing instead of allowing NaN to bypass a
        // threshold or leak into a family-facing reason string.
        func magnitude(_ value: Double?) -> Double {
            guard let value, value.isFinite else { return 0 }
            return abs(value)
        }
        let standingShoulder = magnitude(standing?.shoulderHeightDifferenceCm)
        let seatedShoulder = magnitude(seated?.shoulderHeightDifferenceCm)
        let frontShoulder = magnitude(standingFront?.shoulderHeightDifferenceCm)
        let shoulder = max(frontShoulder, max(standingShoulder, seatedShoulder))
        let pelvis = max(magnitude(standingFront?.pelvicHeightDifferenceCm), magnitude(standing?.pelvicHeightDifferenceCm))
        let shoulderRed = standingShoulder > SpineScreeningStandard.shoulderMarkedCentimeters
        let pelvisRed = pelvis > SpineScreeningStandard.pelvisMarkedCentimeters
        let shoulderYellow = standingShoulder > SpineScreeningStandard.shoulderNormalCentimeters
        let pelvisYellow = pelvis > SpineScreeningStandard.pelvisNormalCentimeters
        // Use the age-specific profile when a numeric rib-prominence proxy is
        // present. The snapshot convenience property keeps legacy/static
        // thresholds for display, but report scoring must match the server.
        let adams: AdamsScreeningResult? = {
            if forward?.adamsObservedResult != nil { return forward?.adamsResult }
            guard let value = forward?.cameraProxyRibProminenceCm, value.isFinite else { return forward?.adamsResult }
            let prominence = abs(value)
            if prominence >= profile.ribProminencePositiveCentimeters { return .positive }
            if prominence >= profile.ribProminenceEquivocalCentimeters { return .equivocal }
            return .negative
        }()
        let instrumentATR = [forward?.instrumentAtrDegrees, forward?.thoracicAtrDegrees, forward?.lumbarAtrDegrees]
            .compactMap { $0.flatMap { $0.isFinite ? max(0, $0) : nil } }
            .max() ?? 0
        let seatedReviewATR = forward?.seatedForwardBendAtrDegrees.flatMap { $0.isFinite ? max(0, $0) : nil }
        let atrDrop = seatedReviewATR.map { instrumentATR - $0 }
        let fixedATRConcern = instrumentATR >= SpineScreeningStandard.atrAttentionDegrees && atrDrop.map { $0 < 3 } == true
        let atrRed = instrumentATR >= SpineScreeningStandard.atrReferralDegrees || fixedATRConcern
        let atrYellow = instrumentATR >= SpineScreeningStandard.atrAttentionDegrees && !atrRed
        let occiputWallAbnormal = seated?.occiputWallDistanceCm.flatMap { $0.isFinite ? max(0, $0) : nil }.map { $0 > SpineScreeningStandard.occiputWallDistanceAbnormalCentimeters } ?? false
        let gaitAbnormal = gait?.gaitObservedAbnormal == true || max(magnitude(gait?.gaitShoulderSwingDifferenceCm), max(magnitude(gait?.gaitPelvicSwingDifferenceCm), magnitude(gait?.gaitTrunkSwayCm))) >= SpineScreeningStandard.gaitShoulderDifferenceCentimeters
        let seatedMidline = magnitude(seated?.spinalMidlineDeviationCm)
        let seatedRounding = max(magnitude(seated?.thoracicRoundingDegrees), magnitude(standingSide?.thoracicRoundingDegrees))
        let seatedForwardHead = max(magnitude(seated?.forwardHeadAngleDegrees), magnitude(standingSide?.forwardHeadAngleDegrees))
        let headTilt = magnitude(standing?.headTiltDegrees)
        let headTiltYellow = headTilt > SpineScreeningStandard.headTiltNormalDegrees
        let seatedAbnormal = seatedMidline > SpineScreeningStandard.seatedMidlineNormalCentimeters || seatedShoulder > SpineScreeningStandard.shoulderNormalCentimeters || seated?.seatedThoracicKyphosisObserved == true || occiputWallAbnormal
        let seatedAbnormalYellow = seatedAbnormal
        let ageApplicable = SpineScreeningStandard.isApplicable(ageMonths: ageMonths)
        let complete = ageApplicable && BodyAssessmentRecord.CaptureTask.allCases.allSatisfy { task in
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
        let qualitySnapshots = [standingFront, standing, standingSide, forward, dynamicKnee, gait, seated, footArch]
        let quality = qualitySnapshots.map(evidence).reduce(0, +) / Double(qualitySnapshots.count)
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
        else if atrRed || (adams == .positive && (gaitAbnormal || seatedAbnormal)) { level = .red }
        else if atrYellow || occiputWallAbnormal || shoulderRed || pelvisRed || adams == .positive || gaitAbnormal || seatedAbnormal || headTiltYellow { level = .yellow }
        else if shoulderYellow || pelvisYellow || adams == .equivocal || seatedAbnormalYellow { level = .yellow }
        else { level = .green }

        var reasons: [String] = []
        if let value = standing?.shoulderHeightDifferenceCm, value.isFinite { reasons.append(String(format: "站姿双肩高度差 %.1f cm", abs(value))) }
        if let value = standing?.pelvicHeightDifferenceCm, value.isFinite { reasons.append(String(format: "站姿骨盆高度差 %.1f cm", abs(value))) }
        if let value = forward?.cameraProxyAtrDegrees, value.isFinite { reasons.append(String(format: "前屈姿态代偿角 %.1f°（用于观察提示）", abs(value))) }
        if let value = [forward?.instrumentAtrDegrees, forward?.thoracicAtrDegrees, forward?.lumbarAtrDegrees].compactMap({ $0.flatMap { $0.isFinite ? max(0, $0) : nil } }).max() { reasons.append(String(format: "Bunnell 脊柱侧弯计 ATR 最大值 %.1f°", value)) }
        if let seatedReviewATR, let atrDrop {
            reasons.append(String(format: "坐位前屈 ATR %.1f°，较站位变化 %.1f°（%@）", seatedReviewATR, atrDrop, atrDrop >= 3 ? "功能性偏斜可能" : "结构异常复核提示"))
        }
        if let value = standing?.headTiltDegrees, value.isFinite { reasons.append(String(format: "头部侧倾角 %.1f°", abs(value))) }
        if !metricsValid { reasons.append("检测到异常测量值，请重新拍摄并保持设备稳定。") }
        if let adams { reasons.append("前屈背部不对称：\(adams.label)") }
        if let side = forward?.adamsProminenceSide, side == "左" || side == "右" { reasons.append("前屈隆起侧：\(side)侧") }
        if let value = seated?.spinalMidlineDeviationCm, value.isFinite { reasons.append(String(format: "坐姿躯干中线偏移 %.1f cm", abs(value))) }
        if let value = seated?.thoracicRoundingDegrees, value.isFinite { reasons.append(String(format: "坐姿胸椎圆背观察角度 %.1f°", abs(value))) }
        if let value = seated?.forwardHeadAngleDegrees, value.isFinite { reasons.append(String(format: "坐姿头前伸观察角度 %.1f°", abs(value))) }
        if let value = gait?.gaitTrunkSwayCm, value.isFinite { reasons.append(String(format: "步态躯干侧向摆动 %.1f cm", abs(value))) }
        if let observed = gait?.gaitObservedAbnormal { reasons.append(observed ? "步态人工观察：存在异常" : "步态人工观察：未见异常") }
        if let note = gait?.gaitObservationNote, !note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { reasons.append("步态备注：\(note)") }
        if let observed = seated?.seatedThoracicKyphosisObserved { reasons.append(observed ? "坐姿观察：存在圆肩驼背表现" : "坐姿观察：未见明显圆肩驼背") }
        if let value = seated?.occiputWallDistanceCm, value.isFinite, value >= 0 { reasons.append(String(format: "枕墙距 %.1f cm", value)) }
        if !ageApplicable { reasons.append("本五项脊柱筛查手册仅适用于 6–12 岁，请核对孩子出生日期和测量日期。") }
        if reasons.isEmpty { reasons.append(complete ? "记录已完成，可供后续人工复核与算法验证使用。" : "请完成 8 段相机采集，并按每段提示通过画面质量检查。") }
        if !validationStatus.allowsClassification {
            reasons.insert(AlgorithmReleaseGate.pendingPostureNotice, at: 0)
        }
        return PostureAssessmentReport(
            generatedAt: generatedAt,
            algorithm: algorithmVersion,
            snapshots: snapshots,
            overallLevel: level,
            reasons: reasons,
            disclaimer: "当前手机二维视觉仅用于家庭姿态观察和采集质量检查，不输出肋峰、ATR或Cobb角，也不替代学校筛查、体检或影像检查。出现持续疼痛、活动受限或明显异常体征，请停止测试并咨询专业人员。",
            riskScore: min(100, max(0, Int((evidenceAdjustedScore * 100).rounded(.down)))),
            qualityScore: min(100, max(0, Int((quality * 100).rounded(.down)))),
            validationStatus: validationStatus
        )
    }

    /// Test/evaluation-only entry point. Product flows must use `make`, whose
    /// default release gate remains pending until signed human validation.
    static func makeValidatedFixture(snapshots: [BodyAssessmentRecord.CaptureTask: PostureMetricSnapshot], generatedAt: Date = .now, ageMonths: Int? = nil) -> PostureAssessmentReport {
        make(snapshots: snapshots, generatedAt: generatedAt, ageMonths: ageMonths ?? 108, validationStatus: .humanValidated)
    }
}
