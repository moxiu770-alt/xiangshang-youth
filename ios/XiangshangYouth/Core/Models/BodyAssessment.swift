import Foundation

/// Pure capture-quality rules shared by the live camera flow and unit tests.
/// They only decide whether a guided recording is usable; they never infer a
/// medical condition from a child's body pose.
enum BodyCaptureQualityGate {
    /// The Android posture-capture JSON is the single calibration source for
    /// both native clients. Built-in values remain a safe fallback only when
    /// the bundled asset is unavailable or fails validation.
    static let canonicalAssetVersion = "android-v1-search-calibrated-2026-09-15"
    static let staticHoldSeconds = 1.5
    static let staticMinimumFrames = 12
    static let staticMaximumDisplacement = 0.025
    static let gaitMinimumSeconds = 2.5
    static let gaitMinimumDisplacement = 0.035
    /// Minimum vertical body coverage in the camera frame. Pose confidence can
    /// be high even when a person is too small for a useful family observation.
    static let fullBodyMinimumFrameCoverage = 0.42
    static let seatedMinimumFrameCoverage = 0.16
    /// Every required joint must first clear the reliable-joint bar.  A
    /// second mean-confidence bar prevents a frame with fuzzy ankles/hips
    /// from being treated as a trustworthy guided capture.
    /// This remains a *capture quality* check, never a health conclusion.
    static let minimumIndividualLandmarkConfidence = 0.50
    static let minimumMeanLandmarkConfidence = 0.55
    /// A visual-completion threshold only. The side/rear angle is intentional:
    /// a rear-only 2D camera cannot reliably tell a true forward bend from a
    /// natural standing pose. It is not a flexibility score.
    static let forwardBendMinimumTorsoTilt = 0.35

    struct PostureCaptureProfile {
        let tag: String
        let staticHoldSeconds: Double
        let staticMinimumFrames: Int
        let staticMaximumDisplacement: Double
        let staticDisplacementJitter: Double
        let gaitMinimumSeconds: Double
        let gaitMinimumDisplacement: Double
        let stabilityWindowFrames: Int
        let gaitMovementWindowFrames: Int
        let minimumRawSamplesForCompletion: Int
        let fullBodyMinimumFrameCoverage: Double
        let seatedMinimumFrameCoverage: Double
        let minimumIndividualLandmarkConfidence: Float
        let minimumMeanLandmarkConfidence: Float
        let forwardBendMinimumTorsoTilt: Double
    }

    private struct CanonicalAgeProfile: Decodable {
        let tag: String
        let minAgeMonths: Int
        let maxAgeMonths: Int
        let staticHoldMilliseconds: Int
        let staticMinimumFrames: Int
        let staticMaximumDisplacementRatio: Double
        let staticDisplacementJitterRatio: Double
        let gaitMinimumMilliseconds: Int
        let gaitMinimumDisplacementRatio: Double
        let stabilityWindowFrames: Int
        let gaitMovementWindowFrames: Int
        let minimumRawSamplesForCompletion: Int
        let fullBodyMinimumFrameCoverageRatio: Double
        let seatedMinimumFrameCoverageRatio: Double
        let minimumIndividualLandmarkConfidence: Float
        let minimumMeanLandmarkConfidence: Float
        let forwardBendMinimumTorsoTiltRatio: Double
    }

    private struct CanonicalManifest: Decodable {
        let version: String
        let ageProfiles: [CanonicalAgeProfile]
    }

    private struct CanonicalBoundedProfile {
        let minAgeMonths: Int
        let maxAgeMonths: Int
        let profile: PostureCaptureProfile
    }

    private static let canonicalLock = NSLock()
    private static var canonicalProfiles: [CanonicalBoundedProfile] = []

    /// Called once during app startup. A malformed or version-mismatched
    /// asset is ignored so capture always falls back to the audited defaults.
    static func loadCanonicalProfilesIfAvailable(bundle: Bundle = .main) {
        guard let url = bundle.url(forResource: "body_pose_capture_profiles", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let manifest = try? JSONDecoder().decode(CanonicalManifest.self, from: data),
              manifest.version == canonicalAssetVersion,
              manifest.ageProfiles.count == 4 else { return }
        let parsed = manifest.ageProfiles.map { row in
            CanonicalBoundedProfile(
                minAgeMonths: row.minAgeMonths,
                maxAgeMonths: row.maxAgeMonths,
                profile: PostureCaptureProfile(
                    tag: row.tag,
                    staticHoldSeconds: Double(row.staticHoldMilliseconds) / 1000.0,
                    staticMinimumFrames: row.staticMinimumFrames,
                    staticMaximumDisplacement: row.staticMaximumDisplacementRatio,
                    staticDisplacementJitter: row.staticDisplacementJitterRatio,
                    gaitMinimumSeconds: Double(row.gaitMinimumMilliseconds) / 1000.0,
                    gaitMinimumDisplacement: row.gaitMinimumDisplacementRatio,
                    stabilityWindowFrames: row.stabilityWindowFrames,
                    gaitMovementWindowFrames: row.gaitMovementWindowFrames,
                    minimumRawSamplesForCompletion: row.minimumRawSamplesForCompletion,
                    fullBodyMinimumFrameCoverage: row.fullBodyMinimumFrameCoverageRatio,
                    seatedMinimumFrameCoverage: row.seatedMinimumFrameCoverageRatio,
                    minimumIndividualLandmarkConfidence: row.minimumIndividualLandmarkConfidence,
                    minimumMeanLandmarkConfidence: row.minimumMeanLandmarkConfidence,
                    forwardBendMinimumTorsoTilt: row.forwardBendMinimumTorsoTiltRatio
                )
            )
        }
        guard parsed.map(\.minAgeMonths) == [72, 97, 133, 181],
              parsed.map(\.maxAgeMonths) == [96, 132, 180, 216],
              parsed.allSatisfy({ $0.minAgeMonths <= $0.maxAgeMonths && canonicalProfileIsValid($0.profile) }) else { return }
        canonicalLock.lock(); defer { canonicalLock.unlock() }
        canonicalProfiles = parsed
    }

    private static func canonicalProfile(ageMonths: Int?) -> PostureCaptureProfile? {
        canonicalLock.lock(); defer { canonicalLock.unlock() }
        guard !canonicalProfiles.isEmpty else { return nil }
        let age = ageMonths ?? 108
        if let match = canonicalProfiles.first(where: { age >= $0.minAgeMonths && age <= $0.maxAgeMonths }) { return match.profile }
        return age < canonicalProfiles[0].minAgeMonths ? canonicalProfiles[0].profile : canonicalProfiles[canonicalProfiles.count - 1].profile
    }

    private static func canonicalProfileIsValid(_ profile: PostureCaptureProfile) -> Bool {
        func ratio(_ value: Double, upper: Double = 1) -> Bool { value.isFinite && value >= 0 && value <= upper }
        func positive(_ value: Double) -> Bool { value.isFinite && value >= 0.1 && value <= 30 }
        return positive(profile.staticHoldSeconds) && profile.staticMinimumFrames >= 3 && profile.staticMinimumFrames <= 240 &&
            ratio(profile.staticMaximumDisplacement) && ratio(profile.staticDisplacementJitter) &&
            positive(profile.gaitMinimumSeconds) && ratio(profile.gaitMinimumDisplacement) &&
            profile.stabilityWindowFrames >= 3 && profile.stabilityWindowFrames <= 240 &&
            profile.gaitMovementWindowFrames >= 2 && profile.gaitMovementWindowFrames <= 120 &&
            profile.minimumRawSamplesForCompletion >= 1 && profile.minimumRawSamplesForCompletion <= 10_000 &&
            ratio(profile.fullBodyMinimumFrameCoverage) && ratio(profile.seatedMinimumFrameCoverage) &&
            profile.minimumIndividualLandmarkConfidence.isFinite && profile.minimumIndividualLandmarkConfidence >= 0 && profile.minimumIndividualLandmarkConfidence <= 1 &&
            profile.minimumMeanLandmarkConfidence.isFinite && profile.minimumMeanLandmarkConfidence >= 0 && profile.minimumMeanLandmarkConfidence <= 1 &&
            ratio(profile.forwardBendMinimumTorsoTilt)
    }

    static func profile(ageMonths: Int?) -> PostureCaptureProfile {
        if let canonical = canonicalProfile(ageMonths: ageMonths) { return canonical }
        switch ageMonths ?? 108 {
        case ...96:
            return PostureCaptureProfile(tag: "6-8岁", staticHoldSeconds: 1.8, staticMinimumFrames: 12, staticMaximumDisplacement: 0.032, staticDisplacementJitter: 0.0088, gaitMinimumSeconds: 2.55, gaitMinimumDisplacement: 0.0365, stabilityWindowFrames: 11, gaitMovementWindowFrames: 7, minimumRawSamplesForCompletion: 6, fullBodyMinimumFrameCoverage: 0.38, seatedMinimumFrameCoverage: 0.145, minimumIndividualLandmarkConfidence: 0.47, minimumMeanLandmarkConfidence: 0.515, forwardBendMinimumTorsoTilt: 0.34)
        case 97...132:
            return PostureCaptureProfile(tag: "9-11岁", staticHoldSeconds: 1.7, staticMinimumFrames: 13, staticMaximumDisplacement: 0.031, staticDisplacementJitter: 0.0078, gaitMinimumSeconds: 2.5, gaitMinimumDisplacement: 0.0355, stabilityWindowFrames: 10, gaitMovementWindowFrames: 7, minimumRawSamplesForCompletion: 6, fullBodyMinimumFrameCoverage: 0.40, seatedMinimumFrameCoverage: 0.155, minimumIndividualLandmarkConfidence: 0.50, minimumMeanLandmarkConfidence: 0.54, forwardBendMinimumTorsoTilt: 0.35)
        case 133...180:
            return PostureCaptureProfile(tag: "12-15岁", staticHoldSeconds: 1.65, staticMinimumFrames: 14, staticMaximumDisplacement: 0.03, staticDisplacementJitter: 0.0072, gaitMinimumSeconds: 2.45, gaitMinimumDisplacement: 0.0368, stabilityWindowFrames: 10, gaitMovementWindowFrames: 6, minimumRawSamplesForCompletion: 6, fullBodyMinimumFrameCoverage: 0.42, seatedMinimumFrameCoverage: 0.16, minimumIndividualLandmarkConfidence: 0.52, minimumMeanLandmarkConfidence: 0.56, forwardBendMinimumTorsoTilt: 0.35)
        default:
            return PostureCaptureProfile(tag: "16-18岁", staticHoldSeconds: 1.6, staticMinimumFrames: 14, staticMaximumDisplacement: 0.029, staticDisplacementJitter: 0.0068, gaitMinimumSeconds: 2.4, gaitMinimumDisplacement: 0.038, stabilityWindowFrames: 10, gaitMovementWindowFrames: 6, minimumRawSamplesForCompletion: 6, fullBodyMinimumFrameCoverage: 0.43, seatedMinimumFrameCoverage: 0.16, minimumIndividualLandmarkConfidence: 0.53, minimumMeanLandmarkConfidence: 0.57, forwardBendMinimumTorsoTilt: 0.35)
        }
    }

    static func isStaticCaptureReady(elapsed: TimeInterval, stableFrames: Int, displacement: Double) -> Bool {
        elapsed.isFinite && displacement.isFinite && elapsed >= staticHoldSeconds && stableFrames >= staticMinimumFrames && displacement >= 0 && displacement < staticMaximumDisplacement
    }

    static func isStaticCaptureReady(elapsed: TimeInterval, stableFrames: Int, displacement: Double, ageMonths: Int?) -> Bool {
        let p = profile(ageMonths: ageMonths)
        return elapsed.isFinite && displacement.isFinite && elapsed >= p.staticHoldSeconds && stableFrames >= p.staticMinimumFrames && displacement >= 0 && displacement < p.staticMaximumDisplacement
    }

    static func isStaticCaptureReady(elapsed: TimeInterval, stableFrames: Int, displacement: Double, jitter: Double, ageMonths: Int?) -> Bool {
        let p = profile(ageMonths: ageMonths)
        return elapsed.isFinite && displacement.isFinite && jitter.isFinite && elapsed >= p.staticHoldSeconds && stableFrames >= p.staticMinimumFrames && displacement >= 0 && jitter >= 0 && displacement < p.staticMaximumDisplacement && jitter <= p.staticDisplacementJitter
    }

    static func isGaitCaptureReady(elapsed: TimeInterval, displacement: Double) -> Bool {
        elapsed.isFinite && displacement.isFinite && elapsed >= gaitMinimumSeconds && displacement >= gaitMinimumDisplacement
    }

    static func isGaitCaptureReady(elapsed: TimeInterval, displacement: Double, ageMonths: Int?) -> Bool {
        let p = profile(ageMonths: ageMonths)
        return elapsed.isFinite && displacement.isFinite && elapsed >= p.gaitMinimumSeconds && displacement >= p.gaitMinimumDisplacement
    }

    static func isGaitCaptureReady(elapsed: TimeInterval, displacement: Double, movedFrames: Int, rawSamples: Int, ageMonths: Int?) -> Bool {
        let p = profile(ageMonths: ageMonths)
        // Require the complete movement window, matching Android. The half
        // window is only suitable for early guidance text; accepting it as a
        // terminal gate makes the same clip pass on iOS but fail on Android.
        return elapsed.isFinite && displacement.isFinite && elapsed >= p.gaitMinimumSeconds && displacement >= p.gaitMinimumDisplacement && movedFrames >= p.gaitMovementWindowFrames && rawSamples >= p.minimumRawSamplesForCompletion
    }

    static func isForwardBendCaptureReady(elapsed: TimeInterval, stableFrames: Int, displacement: Double, torsoTilt: Double) -> Bool {
        isStaticCaptureReady(elapsed: elapsed, stableFrames: stableFrames, displacement: displacement)
            && torsoTilt.isFinite && torsoTilt >= 0 && torsoTilt <= 10 && torsoTilt >= forwardBendMinimumTorsoTilt
    }

    static func isForwardBendCaptureReady(elapsed: TimeInterval, stableFrames: Int, displacement: Double, torsoTilt: Double, ageMonths: Int?) -> Bool {
        isStaticCaptureReady(elapsed: elapsed, stableFrames: stableFrames, displacement: displacement, ageMonths: ageMonths) && torsoTilt.isFinite && torsoTilt >= 0 && torsoTilt <= 10 && torsoTilt >= profile(ageMonths: ageMonths).forwardBendMinimumTorsoTilt
    }

    static func isForwardBendCaptureReady(elapsed: TimeInterval, stableFrames: Int, displacement: Double, jitter: Double, torsoTilt: Double, ageMonths: Int?) -> Bool {
        isStaticCaptureReady(elapsed: elapsed, stableFrames: stableFrames, displacement: displacement, jitter: jitter, ageMonths: ageMonths) && torsoTilt.isFinite && torsoTilt >= 0 && torsoTilt <= 10 && torsoTilt >= profile(ageMonths: ageMonths).forwardBendMinimumTorsoTilt
    }

    static func hasUsableBodyScale(verticalCoverage: Double, seated: Bool) -> Bool {
        verticalCoverage.isFinite && (0...1).contains(verticalCoverage) && verticalCoverage >= (seated ? seatedMinimumFrameCoverage : fullBodyMinimumFrameCoverage)
    }

    static func hasUsableBodyScale(verticalCoverage: Double, seated: Bool, ageMonths: Int?) -> Bool {
        let p = profile(ageMonths: ageMonths)
        return verticalCoverage.isFinite && (0...1).contains(verticalCoverage) && verticalCoverage >= (seated ? p.seatedMinimumFrameCoverage : p.fullBodyMinimumFrameCoverage)
    }

    /// Seated capture must have a clearly vertical upper-body geometry. Vision
    /// coordinates grow upward, so shoulders must sit above hips; this rejects
    /// reclined/sideways frames that otherwise pass landmark confidence.
    static func hasUsableSeatedGeometry(shoulderCenterY: Double, hipCenterY: Double, verticalCoverage: Double) -> Bool {
        shoulderCenterY.isFinite && hipCenterY.isFinite && verticalCoverage.isFinite && (0...1).contains(verticalCoverage) && shoulderCenterY > hipCenterY && verticalCoverage >= seatedMinimumFrameCoverage
    }

    static func hasUsableSeatedGeometry(shoulderCenterY: Double, hipCenterY: Double, verticalCoverage: Double, ageMonths: Int?) -> Bool {
        shoulderCenterY.isFinite && hipCenterY.isFinite && verticalCoverage.isFinite && (0...1).contains(verticalCoverage) && shoulderCenterY > hipCenterY && verticalCoverage >= profile(ageMonths: ageMonths).seatedMinimumFrameCoverage
    }

    static func hasReliableLandmarks(_ confidences: [Float]) -> Bool {
        guard !confidences.isEmpty else { return false }
        return confidences.allSatisfy { $0.isFinite && (0...1).contains($0) && $0 >= Float(minimumIndividualLandmarkConfidence) }
            && confidences.reduce(0, +) / Float(confidences.count) >= Float(minimumMeanLandmarkConfidence)
    }

    static func hasReliableLandmarks(_ confidences: [Float], ageMonths: Int?) -> Bool {
        let p = profile(ageMonths: ageMonths)
        guard !confidences.isEmpty else { return false }
        return confidences.allSatisfy { $0.isFinite && (0...1).contains($0) && $0 >= p.minimumIndividualLandmarkConfidence } && confidences.reduce(0, +) / Float(confidences.count) >= p.minimumMeanLandmarkConfidence
    }

    static func staticProgress(elapsed: TimeInterval) -> Double { min(0.96, max(0, elapsed / staticHoldSeconds)) }
    static func staticProgress(elapsed: TimeInterval, ageMonths: Int?) -> Double { min(0.96, max(0, elapsed / profile(ageMonths: ageMonths).staticHoldSeconds)) }
    static func gaitProgress(elapsed: TimeInterval, hasMoved: Bool) -> Double { hasMoved ? min(0.96, 0.2 + elapsed / gaitMinimumSeconds * 0.8) : 0.12 }
    static func gaitProgress(elapsed: TimeInterval, hasMoved: Bool, ageMonths: Int?) -> Double { hasMoved ? min(0.96, 0.2 + elapsed / profile(ageMonths: ageMonths).gaitMinimumSeconds * 0.8) : 0.12 }
}

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

/// Converts normalized landmark geometry into the report's explainable units.
/// `bodyHeightNormalized` is the detected subject height in the frame, not a
/// guessed camera distance, so a real measured height is required for cm.
enum PostureMetricCalculator {
    /// Removes global camera roll before comparing left/right heights. A
    /// tilted phone otherwise turns a perfectly level shoulder line into a
    /// false asymmetry signal.
    static func rollCorrectedX(_ x: Double, _ y: Double, axisDx: Double, axisDy: Double) -> Double {
        let angle = rollAngle(axisDx: axisDx, axisDy: axisDy)
        return x * cos(angle) + y * sin(angle)
    }

    static func rollCorrectedY(_ x: Double, _ y: Double, axisDx: Double, axisDy: Double) -> Double {
        let angle = rollAngle(axisDx: axisDx, axisDy: axisDy)
        return -x * sin(angle) + y * cos(angle)
    }

    private static func rollAngle(axisDx: Double, axisDy: Double) -> Double {
        guard axisDx.isFinite, axisDy.isFinite, hypot(axisDx, axisDy) > 0.0001 else { return 0 }
        return atan2(axisDy, axisDx)
    }

    static func rollCorrectedVerticalDifference(firstX: Double, firstY: Double, secondX: Double, secondY: Double, axisDx: Double, axisDy: Double) -> Double {
        abs(rollCorrectedY(firstX, firstY, axisDx: axisDx, axisDy: axisDy) - rollCorrectedY(secondX, secondY, axisDx: axisDx, axisDy: axisDy))
    }

    static func centimeters(_ normalizedDifference: Double, bodyHeightNormalized: Double, measuredHeightCm: Double) -> Double? {
        guard normalizedDifference.isFinite, bodyHeightNormalized.isFinite, measuredHeightCm.isFinite, bodyHeightNormalized > 0.05, measuredHeightCm > 0 else { return nil }
        return max(0, normalizedDifference / bodyHeightNormalized * measuredHeightCm)
    }
    static func degrees(_ radians: Double) -> Double? {
        guard radians.isFinite else { return nil }
        return abs(radians * 180 / .pi)
    }

    static func median(_ values: [Double]) -> Double? {
        let sorted = values.filter { $0.isFinite }.sorted()
        guard !sorted.isEmpty else { return nil }
        let middle = sorted.count / 2
        return sorted.count.isMultiple(of: 2) ? (sorted[middle - 1] + sorted[middle]) / 2 : sorted[middle]
    }

    /// Motion amplitude around the camera baseline. A range avoids treating
    /// a child who walks slightly off-centre as exaggerated trunk sway.
    static func range(_ values: [Double]) -> Double? {
        let finite = values.filter { $0.isFinite }
        guard let minimum = finite.min(), let maximum = finite.max() else { return nil }
        return max(0, maximum - minimum)
    }
}

/// Keeps every family-entered measurement in the same safe range and precision
/// whether it was changed by the ruler, +/- controls, or keyboard input.
/// Historical records are intentionally not rewritten by this UI helper.
enum BodyMeasurementInput {
    static func normalized(_ value: Double, range: ClosedRange<Double>, step: Double) -> Double {
        guard range.lowerBound.isFinite, range.upperBound.isFinite, range.lowerBound <= range.upperBound, step.isFinite, step > 0 else { return range.lowerBound }
        guard value.isFinite else { return range.lowerBound }
        let clamped = min(range.upperBound, max(range.lowerBound, value))
        let snapped = (clamped / step).rounded() * step
        return min(range.upperBound, max(range.lowerBound, snapped))
    }
}

/// Current-height classification from WS/T 612—2018. This is a growth
/// reference for ages 7–18, not an adult-height prediction or diagnosis.
enum HeightDevelopmentLevel: String, Codable, CaseIterable {
    case low, lower, middle, upper, high

    var label: String {
        switch self {
        case .low: "下等"
        case .lower: "中下等"
        case .middle: "中等"
        case .upper: "中上等"
        case .high: "上等"
        }
    }
}

struct HeightDevelopmentAssessment: Codable, Equatable {
    let ageYears: Int
    let heightCentimeters: Double
    let level: HeightDevelopmentLevel
    let lowerTwoSD: Double
    let lowerOneSD: Double
    let median: Double
    let upperOneSD: Double
    let upperTwoSD: Double
    let ruleVersion: String
}

/// Family-side body assessment.  This is deliberately a health-management
/// record, not a medical diagnosis or a replacement for a school screening.
struct BodyAssessmentRecord: Codable, Equatable {
    enum AttentionLevel: String, Codable, CaseIterable {
        /// The family has not yet completed every camera-guided task. This is
        /// a data-completeness state, never a health-risk classification.
        case pending
        case green, yellow, red, unavailable

        var label: String {
            switch self {
            case .pending: "待完成拍摄记录"
            case .green: "本次观察已完成"
            case .yellow: "建议关注"
            case .red: "建议进一步评估"
            case .unavailable: "待完善生日"
            }
        }
    }

    enum CaptureTask: String, Codable, CaseIterable, Identifiable {
        case standingBack, forwardBend, seatedPosture, gaitVideo

        var id: String { rawValue }
        var title: String {
            switch self {
            case .standingBack: "自然站姿"
            case .forwardBend: "前屈观察"
            case .seatedPosture: "坐姿观察"
            case .gaitVideo: "步态视频"
            }
        }
        var instruction: String {
            switch self {
            case .standingBack: "背对镜头自然站立，双脚与肩同宽。"
            case .forwardBend: "建议从侧后方拍摄；家长陪同下缓慢前屈，感到不适立即停止。"
            case .seatedPosture: "坐在无靠背椅上，双手自然放在膝盖。"
            case .gaitVideo: "沿直线自然行走 3–5 秒，镜头从后方拍摄。"
            }
        }
    }

    struct Observation: Codable, Equatable, Identifiable {
        let id: String
        let title: String
        let detail: String
        let level: AttentionLevel
    }

    var heightCentimeters: Double
    var weightKilograms: Double
    var measuredAt: Date
    var ruleVersion: String
    var completedCaptures: Set<CaptureTask>
    var parentMarkedAsymmetric: Bool
    var parentMarkedGaitConcern: Bool
    /// A non-diagnostic, on-device framing/alignment prompt. This is kept only
    /// after the parent has chosen to save the observation; raw media is never
    /// stored by the app.
    var visualObservationHint: String? = nil
    /// Task-scoped, non-diagnostic prompts. Keeping the task with each prompt
    /// makes resumed drafts and remote sync auditable without retaining media.
    var captureObservationHints: [CaptureTask: String] = [:]
    /// Parent-reported values used only for the family-height reference. They
    /// are optional so existing local records remain readable.
    var fatherHeightCentimeters: Double? = nil
    var motherHeightCentimeters: Double? = nil
    var savedAt: Date
    var nextFollowUpDate: Date
    var completedPlanDays: Set<String>
    var postureReport: PostureAssessmentReport? = nil
    /// Frozen at measurement time so historical BMI/height bands do not drift
    /// when a child crosses a half-year age boundary later.
    var ageMonthsAtMeasurement: Int? = nil

    static let ruleVersion = "WS/T 586—2018 年龄别 BMI 参考 v1.1"
    static let bmiAlgorithmVersion = "UY-IMCA-BMI-1.2"
    static let heightAlgorithmVersion = "UY-IMCA-HEIGHT-1.0"
    static let geneticHeightRangeHalfWidthCentimeters = 5.0
    // WS/T 586 child BMI tables end at the 18-year (216-month) row. Do not
    // silently reuse the adult cutoff for older ages.
    static let bmiSupportedAgeMonths = 72...216
    static let heightSupportedAgeMonths = 84...227

    /// Accept the API's Chinese labels as well as common import/remote codes.
    /// Keeping this normalization local prevents an English `male`/`female`
    /// payload from silently becoming an unavailable BMI result on iOS.
    private static func genderIsBoy(_ raw: String) -> Bool? {
        switch raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "男", "男性", "boy", "male", "m", "1": return true
        case "女", "女性", "girl", "female", "f", "2": return false
        default: return nil
        }
    }

    var bmi: Double {
        guard heightCentimeters.isFinite, weightKilograms.isFinite,
              heightCentimeters >= 90, heightCentimeters <= 190,
              weightKilograms >= 15, weightKilograms <= 90 else { return 0 }
        let value = weightKilograms / pow(heightCentimeters / 100, 2)
        return value.isFinite ? value : 0
    }

    /// WS/T 586—2018 requires BMI to be retained to one decimal place before
    /// comparing it with the age/sex screening cut-offs.
    var bmiForScreening: Double {
        guard bmi > 0 else { return 0 }
        return floor(bmi * 10 + 0.5) / 10
    }

    /// A commonly used family-height reference, not a diagnosis or a promise
    /// of adult height.  Male: (father + mother + 13cm) / 2; female:
    /// (father + mother - 13cm) / 2.
    func geneticHeightReference(gender: String) -> Double? {
        guard let fatherHeightCentimeters, let motherHeightCentimeters,
              fatherHeightCentimeters.isFinite, motherHeightCentimeters.isFinite,
              (120...230).contains(fatherHeightCentimeters),
              (120...230).contains(motherHeightCentimeters),
              let isBoy = Self.genderIsBoy(gender) else { return nil }
        let adjustment = isBoy ? 13.0 : -13.0
        return (fatherHeightCentimeters + motherHeightCentimeters + adjustment) / 2
    }

    /// Mid-parental target height with a transparent ±5 cm family range.
    /// This is a health-management estimate, not a medical guarantee.
    func geneticHeightRange(gender: String) -> ClosedRange<Double>? {
        guard let reference = geneticHeightReference(gender: gender) else { return nil }
        return (reference - Self.geneticHeightRangeHalfWidthCentimeters)...(reference + Self.geneticHeightRangeHalfWidthCentimeters)
    }

    func geneticHeightFormula(gender: String) -> String {
        if Self.genderIsBoy(gender) == true { return "（父亲身高 + 母亲身高 + 13 cm）÷ 2" }
        if Self.genderIsBoy(gender) == false { return "（父亲身高 + 母亲身高 − 13 cm）÷ 2" }
        return "待完善孩子性别后计算"
    }

    /// Classifies the measured height against the national 7–18 year
    /// age/sex reference. The completed age in years is used, matching the
    /// standard's annual reference rows.
    func heightDevelopmentAssessment(ageMonths: Int?, gender: String) -> HeightDevelopmentAssessment? {
        let effectiveAgeMonths = ageMonthsAtMeasurement ?? ageMonths
        guard heightCentimeters.isFinite, heightCentimeters >= 90, heightCentimeters <= 190, let effectiveAgeMonths,
              Self.heightSupportedAgeMonths.contains(effectiveAgeMonths),
              let isBoy = Self.genderIsBoy(gender) else { return nil }
        let ageYears = min(18, max(7, effectiveAgeMonths / 12))
        let row = HeightReference.row(ageYears: ageYears, isBoy: isBoy)
        let level: HeightDevelopmentLevel
        if heightCentimeters < row.minusTwoSD { level = .low }
        else if heightCentimeters < row.minusOneSD { level = .lower }
        else if heightCentimeters <= row.plusOneSD { level = .middle }
        else if heightCentimeters <= row.plusTwoSD { level = .upper }
        else { level = .high }
        return HeightDevelopmentAssessment(ageYears: ageYears, heightCentimeters: heightCentimeters, level: level, lowerTwoSD: row.minusTwoSD, lowerOneSD: row.minusOneSD, median: row.median, upperOneSD: row.plusOneSD, upperTwoSD: row.plusTwoSD, ruleVersion: "WS/T 612—2018")
    }

    /// Uses WS/T 586—2018's sex/age (half-year) screening threshold table.
    /// This is a screening result for overweight/obesity only, not a judgement
    /// of overall nutrition status or a clinical diagnosis.
    func bmiAttention(ageMonths: Int?, gender: String) -> AttentionLevel {
        let effectiveAgeMonths = ageMonthsAtMeasurement ?? ageMonths
        guard bmiForScreening > 0, let effectiveAgeMonths, Self.bmiSupportedAgeMonths.contains(effectiveAgeMonths), let isBoy = Self.genderIsBoy(gender) else { return .unavailable }
        let threshold = BMIReference.threshold(ageMonths: effectiveAgeMonths, isBoy: isBoy)
        if bmiForScreening >= threshold.1 { return .red }
        if bmiForScreening >= threshold.0 { return .yellow }
        return .green
    }

    func bmiScreeningLabel(ageMonths: Int?, gender: String) -> String {
        guard bmi > 0 else { return "待填写身高体重" }
        let effectiveAgeMonths = ageMonthsAtMeasurement ?? ageMonths
        guard let effectiveAgeMonths else { return "待完善出生日期" }
        guard Self.genderIsBoy(gender) != nil else { return "待完善性别" }
        guard Self.bmiSupportedAgeMonths.contains(effectiveAgeMonths) else { return "适用年龄为 6–18 岁" }
        switch bmiAttention(ageMonths: effectiveAgeMonths, gender: gender) {
        case .pending: return "待完成拍摄记录"
        case .green: return "未达到超重筛查界值"
        case .yellow: return "超重筛查关注"
        case .red: return "肥胖筛查关注"
        case .unavailable: return "待完善生日"
        }
    }

    func postureAttention() -> AttentionLevel {
        if parentMarkedAsymmetric && parentMarkedGaitConcern { return .red }
        if parentMarkedAsymmetric || parentMarkedGaitConcern { return .yellow }
        return completedCaptures.count == CaptureTask.allCases.count ? .green : .pending
    }

    func attention(ageMonths: Int?, gender: String) -> AttentionLevel {
        // Once the camera report exists, its objective aggregate is the source
        // of posture risk. Parent checkboxes remain safety context only and
        // must not overwrite an algorithmically generated report.
        let posture = postureReport?.overallLevel ?? postureAttention()
        let levels = [bmiAttention(ageMonths: ageMonths, gender: gender), posture]
        if levels.contains(.red) { return .red }
        if levels.contains(.yellow) { return .yellow }
        if levels.contains(.pending) { return .pending }
        if levels.contains(.unavailable) { return .unavailable }
        return .green
    }

    func observations(ageMonths: Int?, gender: String) -> [Observation] {
        let posture = postureReport?.overallLevel ?? postureAttention()
        return [
            Observation(id: "bmi", title: "BMI 年龄别筛查", detail: String(format: "BMI %.1f · %@ · %@", bmi, bmiScreeningLabel(ageMonths: ageMonths, gender: gender), ruleVersion), level: bmiAttention(ageMonths: ageMonths, gender: gender)),
            Observation(id: "shoulder", title: "姿态观察", detail: postureReport.map { "本次观察已整理为结果：\($0.overallLevel.label)。" } ?? "尚未形成完整姿态观察。", level: posture),
            Observation(id: "gait", title: "家长安全信息", detail: parentMarkedGaitConcern ? "家长补充：近期有行走困难或活动受限，请关注安全并咨询专业人员。" : "未补充行走困难或活动受限。", level: .green),
            Observation(id: "visual", title: "画面质量", detail: visualObservationSummary ?? "画面已完成质量检查。", level: postureReport?.overallLevel ?? (visualObservationSummary == nil ? .green : .yellow)),
            Observation(id: "capture", title: "记录完整度", detail: postureReport.map { _ in "本次记录已保存，可查看家庭观察结果。" } ?? "已完成 \(completedCaptures.count) / \(CaptureTask.allCases.count) 个拍摄任务，仍需完成稳定度确认。", level: postureReport == nil ? .yellow : posture)
        ]
    }

    var visualObservationSummary: String? {
        let structured = captureObservationHints.keys.sorted { $0.rawValue < $1.rawValue }
            .compactMap { task in captureObservationHints[task].map { "\(task.title)：\($0)" } }
            .joined(separator: "\n")
        return structured.isEmpty ? visualObservationHint : structured
    }
}

/// Persisted only while a family assessment is in progress.  It contains no
/// media asset and lets a parent safely leave the app before confirming a
/// result.
struct BodyAssessmentDraft: Codable, Equatable {
    var step: Int = 0
    var guardianReady = false
    var consentAcknowledged = false
    var environmentReady = false
    var heightCentimeters: Double = 0
    var weightKilograms: Double = 0
    var completedCaptures: Set<BodyAssessmentRecord.CaptureTask> = []
    var parentMarkedAsymmetric = false
    var parentMarkedGaitConcern = false
    var visualObservationHint: String? = nil
    var captureObservationHints: [BodyAssessmentRecord.CaptureTask: String] = [:]
    var fatherHeightCentimeters: Double? = nil
    var motherHeightCentimeters: Double? = nil
    var postureSnapshots: [BodyAssessmentRecord.CaptureTask: PostureMetricSnapshot] = [:]

    private enum CodingKeys: String, CodingKey {
        case step, guardianReady, consentAcknowledged, environmentReady
        case heightCentimeters, weightKilograms, completedCaptures
        case parentMarkedAsymmetric, parentMarkedGaitConcern, visualObservationHint
        case captureObservationHints, fatherHeightCentimeters, motherHeightCentimeters, postureSnapshots
    }

    init(step: Int = 0, guardianReady: Bool = false, consentAcknowledged: Bool = false, environmentReady: Bool = false, heightCentimeters: Double = 0, weightKilograms: Double = 0, completedCaptures: Set<BodyAssessmentRecord.CaptureTask> = [], parentMarkedAsymmetric: Bool = false, parentMarkedGaitConcern: Bool = false, visualObservationHint: String? = nil, captureObservationHints: [BodyAssessmentRecord.CaptureTask: String] = [:], fatherHeightCentimeters: Double? = nil, motherHeightCentimeters: Double? = nil, postureSnapshots: [BodyAssessmentRecord.CaptureTask: PostureMetricSnapshot] = [:]) {
        self.step = step
        self.guardianReady = guardianReady
        self.consentAcknowledged = consentAcknowledged
        self.environmentReady = environmentReady
        self.heightCentimeters = heightCentimeters
        self.weightKilograms = weightKilograms
        self.completedCaptures = completedCaptures
        self.parentMarkedAsymmetric = parentMarkedAsymmetric
        self.parentMarkedGaitConcern = parentMarkedGaitConcern
        self.visualObservationHint = visualObservationHint
        self.captureObservationHints = captureObservationHints
        self.fatherHeightCentimeters = fatherHeightCentimeters
        self.motherHeightCentimeters = motherHeightCentimeters
        self.postureSnapshots = postureSnapshots
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        step = try values.decodeIfPresent(Int.self, forKey: .step) ?? 0
        guardianReady = try values.decodeIfPresent(Bool.self, forKey: .guardianReady) ?? false
        consentAcknowledged = try values.decodeIfPresent(Bool.self, forKey: .consentAcknowledged) ?? false
        environmentReady = try values.decodeIfPresent(Bool.self, forKey: .environmentReady) ?? false
        heightCentimeters = try values.decodeIfPresent(Double.self, forKey: .heightCentimeters) ?? 0
        weightKilograms = try values.decodeIfPresent(Double.self, forKey: .weightKilograms) ?? 0
        completedCaptures = try values.decodeIfPresent(Set<BodyAssessmentRecord.CaptureTask>.self, forKey: .completedCaptures) ?? []
        parentMarkedAsymmetric = try values.decodeIfPresent(Bool.self, forKey: .parentMarkedAsymmetric) ?? false
        parentMarkedGaitConcern = try values.decodeIfPresent(Bool.self, forKey: .parentMarkedGaitConcern) ?? false
        visualObservationHint = try values.decodeIfPresent(String.self, forKey: .visualObservationHint)
        captureObservationHints = try values.decodeIfPresent([BodyAssessmentRecord.CaptureTask: String].self, forKey: .captureObservationHints) ?? [:]
        fatherHeightCentimeters = try values.decodeIfPresent(Double.self, forKey: .fatherHeightCentimeters)
        motherHeightCentimeters = try values.decodeIfPresent(Double.self, forKey: .motherHeightCentimeters)
        postureSnapshots = try values.decodeIfPresent([BodyAssessmentRecord.CaptureTask: PostureMetricSnapshot].self, forKey: .postureSnapshots) ?? [:]
    }
}

extension Student {
    var bodyAssessmentAgeMonths: Int? {
        guard let birthDate else { return nil }
        return Self.ageMonths(from: birthDate)
    }
    /// Internal deterministic seam used by tests and import validation. The
    /// production property above always supplies the current instant.
    static func ageMonths(from rawBirthDate: String, now: Date = .now) -> Int? {
        let normalized = rawBirthDate.trimmingCharacters(in: .whitespacesAndNewlines)
        guard normalized.range(of: #"^\d{4}-\d{2}-\d{2}$"#, options: .regularExpression) != nil,
              let date = Self.birthDateFormatter.date(from: normalized),
              Self.birthDateFormatter.string(from: date) == normalized else { return nil }
        let calendar = Self.ageCalendar
        guard let months = calendar.dateComponents([.month], from: date, to: now).month,
              months >= 0, months <= 240 else { return nil }
        return months
    }
    var bodyAssessmentAgeLabel: String { bodyAssessmentAgeMonths.map { "\($0 / 12)岁\($0 % 12)个月" } ?? "待完善" }
    /// Date-only birthday semantics must be identical on device and server.
    /// Do not use the user's current timezone: a midnight boundary could move
    /// a child between two BMI reference months on different clients.
    private static let ageCalendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = Locale(identifier: "en_US_POSIX")
        calendar.timeZone = TimeZone(identifier: "Asia/Shanghai")!
        return calendar
    }()
    private static let birthDateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.calendar = ageCalendar
        f.timeZone = ageCalendar.timeZone
        f.dateFormat = "yyyy-MM-dd"
        f.isLenient = false
        return f
    }()
}

private enum BMIReference {
    /// (age months at interval start, overweight, obesity), WS/T 586—2018.
    static let boys: [(Int, Double, Double)] = [(72,16.4,17.7),(78,16.7,18.1),(84,17.0,18.7),(90,17.4,19.2),(96,17.8,19.7),(102,18.1,20.3),(108,18.5,20.8),(114,18.9,21.4),(120,19.2,21.9),(126,19.6,22.5),(132,19.9,23.0),(138,20.3,23.6),(144,20.7,24.1),(150,21.0,24.7),(156,21.4,25.2),(162,21.9,25.7),(168,22.3,26.1),(174,22.6,26.4),(180,22.9,26.6),(186,23.1,26.9),(192,23.3,27.1),(198,23.5,27.4),(204,23.7,27.6),(210,23.8,27.8),(216,24.0,28.0)]
    static let girls: [(Int, Double, Double)] = [(72,16.2,17.5),(78,16.5,18.0),(84,16.8,18.5),(90,17.2,19.0),(96,17.6,19.4),(102,18.1,19.9),(108,18.5,20.4),(114,19.0,21.0),(120,19.5,21.5),(126,20.0,22.1),(132,20.5,22.7),(138,21.1,23.3),(144,21.5,23.9),(150,21.9,24.5),(156,22.2,25.0),(162,22.6,25.6),(168,22.8,25.9),(174,23.0,26.3),(180,23.2,26.6),(186,23.4,26.9),(192,23.6,27.1),(198,23.7,27.4),(204,23.8,27.6),(210,23.9,27.8),(216,24.0,28.0)]
    static func threshold(ageMonths: Int, isBoy: Bool) -> (Double, Double) {
        let table = isBoy ? boys : girls
        // Use the completed lower half-year row from the published table.
        let bucket = (ageMonths / 6) * 6
        let row = table.first(where: { $0.0 == bucket }) ?? table.first!
        return (row.1, row.2)
    }
}

private enum HeightReference {
    struct Row { let minusTwoSD: Double; let minusOneSD: Double; let median: Double; let plusOneSD: Double; let plusTwoSD: Double }
    static let boys: [Int: Row] = [
        7: Row(minusTwoSD: 113.51, minusOneSD: 119.49, median: 125.48, plusOneSD: 131.47, plusTwoSD: 137.46),
        8: Row(minusTwoSD: 118.35, minusOneSD: 124.53, median: 130.72, plusOneSD: 136.90, plusTwoSD: 143.08),
        9: Row(minusTwoSD: 122.74, minusOneSD: 129.27, median: 135.81, plusOneSD: 142.35, plusTwoSD: 148.88),
        10: Row(minusTwoSD: 126.79, minusOneSD: 133.77, median: 140.76, plusOneSD: 147.75, plusTwoSD: 154.74),
        11: Row(minusTwoSD: 130.39, minusOneSD: 138.20, median: 146.01, plusOneSD: 153.82, plusTwoSD: 161.64),
        12: Row(minusTwoSD: 134.48, minusOneSD: 143.33, median: 152.18, plusOneSD: 161.03, plusTwoSD: 169.89),
        13: Row(minusTwoSD: 143.01, minusOneSD: 151.60, median: 160.19, plusOneSD: 168.78, plusTwoSD: 177.38),
        14: Row(minusTwoSD: 150.22, minusOneSD: 157.93, median: 165.63, plusOneSD: 173.34, plusTwoSD: 181.05),
        15: Row(minusTwoSD: 155.25, minusOneSD: 162.14, median: 169.02, plusOneSD: 175.91, plusTwoSD: 182.79),
        16: Row(minusTwoSD: 157.72, minusOneSD: 164.15, median: 170.58, plusOneSD: 177.01, plusTwoSD: 183.44),
        17: Row(minusTwoSD: 158.76, minusOneSD: 165.07, median: 171.39, plusOneSD: 177.70, plusTwoSD: 184.01),
        18: Row(minusTwoSD: 158.81, minusOneSD: 165.12, median: 171.42, plusOneSD: 177.73, plusTwoSD: 184.03)
    ]
    static let girls: [Int: Row] = [
        7: Row(minusTwoSD: 112.29, minusOneSD: 118.21, median: 124.13, plusOneSD: 130.05, plusTwoSD: 135.97),
        8: Row(minusTwoSD: 116.83, minusOneSD: 123.09, median: 129.34, plusOneSD: 135.59, plusTwoSD: 141.84),
        9: Row(minusTwoSD: 121.31, minusOneSD: 128.11, median: 134.91, plusOneSD: 141.71, plusTwoSD: 148.51),
        10: Row(minusTwoSD: 126.38, minusOneSD: 133.78, median: 141.18, plusOneSD: 148.57, plusTwoSD: 155.97),
        11: Row(minusTwoSD: 132.09, minusOneSD: 139.72, median: 147.36, plusOneSD: 154.99, plusTwoSD: 162.63),
        12: Row(minusTwoSD: 138.11, minusOneSD: 145.26, median: 152.41, plusOneSD: 159.56, plusTwoSD: 166.71),
        13: Row(minusTwoSD: 143.75, minusOneSD: 149.91, median: 156.07, plusOneSD: 162.23, plusTwoSD: 168.39),
        14: Row(minusTwoSD: 146.18, minusOneSD: 151.98, median: 157.78, plusOneSD: 163.58, plusTwoSD: 169.38),
        15: Row(minusTwoSD: 147.02, minusOneSD: 152.74, median: 158.47, plusOneSD: 164.19, plusTwoSD: 169.91),
        16: Row(minusTwoSD: 147.59, minusOneSD: 153.26, median: 158.93, plusOneSD: 164.60, plusTwoSD: 170.27),
        17: Row(minusTwoSD: 147.82, minusOneSD: 153.50, median: 159.18, plusOneSD: 164.86, plusTwoSD: 170.54),
        18: Row(minusTwoSD: 148.54, minusOneSD: 154.28, median: 160.01, plusOneSD: 165.74, plusTwoSD: 171.48)
    ]
    private static let safeBoyFallback = Row(minusTwoSD: 158.81, minusOneSD: 165.12, median: 171.42, plusOneSD: 177.73, plusTwoSD: 184.03)
    private static let safeGirlFallback = Row(minusTwoSD: 148.54, minusOneSD: 154.28, median: 160.01, plusOneSD: 165.74, plusTwoSD: 171.48)
    static func row(ageYears: Int, isBoy: Bool) -> Row {
        let table = isBoy ? boys : girls
        let safeFallback = isBoy ? safeBoyFallback : safeGirlFallback
        return table[ageYears] ?? table[18] ?? Array(table.values).last ?? safeFallback
    }
}
