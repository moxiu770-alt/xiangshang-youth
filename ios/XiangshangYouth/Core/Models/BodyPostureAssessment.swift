import Foundation

enum AdamsScreeningResult: String, Codable, CaseIterable {
    case negative, equivocal, positive

    var label: String {
        switch self {
        case .negative: "阴性（双侧等高）"
        case .equivocal: "可疑阳性（隆起＜1 cm）"
        case .positive: "阳性（隆起≥1 cm）"
        }
    }
}

/// Evidence of how a posture capture was aligned. This is deliberately
/// metadata only: no image, video, frame, or raw landmark is persisted.
/// `.guided` is the current mobile capability; `.markerPnP` is reserved for
/// the future physical calibration-board detector and must never be inferred.
enum CaptureCalibrationMode: String, Codable, Equatable {
    case guided
    case markerPnP = "marker-pnp"
}

struct CaptureCalibrationEvidence: Codable, Equatable {
    var mode: CaptureCalibrationMode
    var boardDetected: Bool
    var boardID: String?
    var intrinsicsID: String?
    var lensID: String?
    var resolution: String?
    var reprojectionErrorPx: Double?
    /// Server-approved phone/lens/resolution profile. A native detector must
    /// populate this before it can make a Marker-PnP claim.
    var profileID: String? = nil

    static let guided = CaptureCalibrationEvidence(
        mode: .guided,
        boardDetected: false,
        boardID: nil,
        intrinsicsID: nil,
        lensID: nil,
        resolution: nil,
        reprojectionErrorPx: nil,
        profileID: nil
    )

    // Keep the wire contract lower camel case on both native clients. Swift's
    // synthesized keys would emit boardID/intrinsicsID and fail server-side
    // marker-profile validation.
    enum CodingKeys: String, CodingKey {
        case mode, boardDetected, resolution, reprojectionErrorPx
        case boardID = "boardId"
        case intrinsicsID = "intrinsicsId"
        case lensID = "lensId"
        case profileID = "profileId"
    }

    /// This only means camera geometry can be audited. It is not a medical
    /// validation or a promise that the health algorithm is publishable.
    var hasMarkerPnPEvidence: Bool {
        mode == .markerPnP && boardDetected && !(boardID?.isEmpty ?? true)
            && !(intrinsicsID?.isEmpty ?? true) && !(lensID?.isEmpty ?? true)
            && !(resolution?.isEmpty ?? true) && !(profileID?.isEmpty ?? true)
            && (reprojectionErrorPx ?? .infinity) <= 2
    }
}

struct PostureMetricSnapshot: Codable, Equatable, Identifiable {
    let id: String
    let task: BodyAssessmentRecord.CaptureTask
    let sampleCount: Int
    let confidence: Double
    var shoulderHeightDifferenceCm: Double?
    var pelvicHeightDifferenceCm: Double?
    var headTiltDegrees: Double?
    var spinalMidlineDeviationCm: Double?
    var thoracicRoundingDegrees: Double?
    let forwardHeadAngleDegrees: Double?
    let cameraProxyAtrDegrees: Double?
    let cameraProxyRibProminenceCm: Double?
    var shoulderProtractionProxyDegrees: Double? = nil
    var pelvicTiltProxyDegrees: Double? = nil
    var kneeAlignmentProxyRatio: Double? = nil
    var lowerLimbAxisAsymmetryDegrees: Double? = nil
    var leftKneeValgusProxyDegrees: Double? = nil
    var rightKneeValgusProxyDegrees: Double? = nil
    var kneeTrackingAsymmetryRatio: Double? = nil
    var squatDepthRatio: Double? = nil
    var movementRepetitionCount: Double? = nil
    /// Quality-only until the dedicated paediatric foot model passes the
    /// independent validation gate. Nil arch indices must never be filled by
    /// a generic body-pose heuristic.
    var footArchVisibilityScore: Double? = nil
    var leftArchProxyIndex: Double? = nil
    var rightArchProxyIndex: Double? = nil
    var heelAlignmentProxyDegrees: Double? = nil
    /// Supervised visual record from the trained examiner. These fields are
    /// kept separate from camera proxies and follow the manual's symbols.
    var adamsObservedResult: String? = nil
    var adamsProminenceSide: String? = nil
    /// Optional validated instrument/depth measurement. The current phone
    /// RGB flow never fills this field; when a calibrated field device or
    /// backend supplies it, the framework's ATR thresholds become active.
    var instrumentAtrDegrees: Double? = nil
    /// Optional calibrated chest/waist ATR readings. The maximum validated
    /// segment reading drives the 5°/7° screening gates.
    var thoracicAtrDegrees: Double? = nil
    var lumbarAtrDegrees: Double? = nil
    var thoracicAtrSide: String? = nil
    var lumbarAtrSide: String? = nil
    var thoracicAtrFirstDegrees: Double? = nil
    var thoracicAtrSecondDegrees: Double? = nil
    var lumbarAtrFirstDegrees: Double? = nil
    var lumbarAtrSecondDegrees: Double? = nil
    var seatedForwardBendAtrDegrees: Double? = nil
    /// Optional occiput-to-wall distance from a supervised measurement.
    var occiputWallDistanceCm: Double? = nil
    let gaitShoulderSwingDifferenceCm: Double?
    let gaitPelvicSwingDifferenceCm: Double?
    let gaitTrunkSwayCm: Double?
    var gaitObservedAbnormal: Bool? = nil
    var gaitObservationNote: String? = nil
    var seatedThoracicKyphosisObserved: Bool? = nil
    /// Provenance for the camera quality gate. It records the protocol and
    /// checks actually used; it deliberately does not pretend an ArUco board
    /// was detected before a native marker detector is integrated.
    var captureProtocolVersion: String? = nil
    var cameraFacing: String? = nil
    /// Describes the evidence actually used by this run. Current household
    /// capture remains RGB 2D even when the phone happens to contain LiDAR.
    var measurementMode: String? = nil
    var deviceCapabilityTier: String? = nil
    var depthAvailable: Bool? = nil
    var segmentPhaseCount: Int? = nil
    var qualityChecks: [String]? = nil
    var captureCalibration: CaptureCalibrationEvidence? = nil
    /// 1 means a usable first take is stored and a fresh re-entry is needed.
    var captureAttemptCount: Int? = nil
    var repeatabilityStatus: String? = nil
    var repeatabilityMaximumDifference: Double? = nil

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
        shoulderProtractionProxyDegrees: Double? = nil,
        pelvicTiltProxyDegrees: Double? = nil,
        kneeAlignmentProxyRatio: Double? = nil,
        lowerLimbAxisAsymmetryDegrees: Double? = nil,
        leftKneeValgusProxyDegrees: Double? = nil,
        rightKneeValgusProxyDegrees: Double? = nil,
        kneeTrackingAsymmetryRatio: Double? = nil,
        squatDepthRatio: Double? = nil,
        movementRepetitionCount: Double? = nil,
        footArchVisibilityScore: Double? = nil,
        leftArchProxyIndex: Double? = nil,
        rightArchProxyIndex: Double? = nil,
        heelAlignmentProxyDegrees: Double? = nil,
        adamsObservedResult: String? = nil,
        adamsProminenceSide: String? = nil,
        instrumentAtrDegrees: Double? = nil,
        thoracicAtrDegrees: Double? = nil,
        lumbarAtrDegrees: Double? = nil,
        thoracicAtrSide: String? = nil,
        lumbarAtrSide: String? = nil,
        thoracicAtrFirstDegrees: Double? = nil,
        thoracicAtrSecondDegrees: Double? = nil,
        lumbarAtrFirstDegrees: Double? = nil,
        lumbarAtrSecondDegrees: Double? = nil,
        seatedForwardBendAtrDegrees: Double? = nil,
        occiputWallDistanceCm: Double? = nil,
        gaitShoulderSwingDifferenceCm: Double?,
        gaitPelvicSwingDifferenceCm: Double?,
        gaitTrunkSwayCm: Double?,
        gaitObservedAbnormal: Bool? = nil,
        gaitObservationNote: String? = nil,
        seatedThoracicKyphosisObserved: Bool? = nil,
        captureProtocolVersion: String? = nil,
        cameraFacing: String? = nil,
        measurementMode: String? = nil,
        deviceCapabilityTier: String? = nil,
        depthAvailable: Bool? = nil,
        segmentPhaseCount: Int? = nil,
        qualityChecks: [String]? = nil,
        captureCalibration: CaptureCalibrationEvidence? = nil,
        captureAttemptCount: Int? = nil,
        repeatabilityStatus: String? = nil,
        repeatabilityMaximumDifference: Double? = nil
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
        self.shoulderProtractionProxyDegrees = shoulderProtractionProxyDegrees
        self.pelvicTiltProxyDegrees = pelvicTiltProxyDegrees
        self.kneeAlignmentProxyRatio = kneeAlignmentProxyRatio
        self.lowerLimbAxisAsymmetryDegrees = lowerLimbAxisAsymmetryDegrees
        self.leftKneeValgusProxyDegrees = leftKneeValgusProxyDegrees
        self.rightKneeValgusProxyDegrees = rightKneeValgusProxyDegrees
        self.kneeTrackingAsymmetryRatio = kneeTrackingAsymmetryRatio
        self.squatDepthRatio = squatDepthRatio
        self.movementRepetitionCount = movementRepetitionCount
        self.footArchVisibilityScore = footArchVisibilityScore
        self.leftArchProxyIndex = leftArchProxyIndex
        self.rightArchProxyIndex = rightArchProxyIndex
        self.heelAlignmentProxyDegrees = heelAlignmentProxyDegrees
        self.adamsObservedResult = adamsObservedResult
        self.adamsProminenceSide = adamsProminenceSide
        self.instrumentAtrDegrees = instrumentAtrDegrees
        self.thoracicAtrDegrees = thoracicAtrDegrees
        self.lumbarAtrDegrees = lumbarAtrDegrees
        self.thoracicAtrSide = thoracicAtrSide
        self.lumbarAtrSide = lumbarAtrSide
        self.thoracicAtrFirstDegrees = thoracicAtrFirstDegrees
        self.thoracicAtrSecondDegrees = thoracicAtrSecondDegrees
        self.lumbarAtrFirstDegrees = lumbarAtrFirstDegrees
        self.lumbarAtrSecondDegrees = lumbarAtrSecondDegrees
        self.seatedForwardBendAtrDegrees = seatedForwardBendAtrDegrees
        self.occiputWallDistanceCm = occiputWallDistanceCm
        self.gaitShoulderSwingDifferenceCm = gaitShoulderSwingDifferenceCm
        self.gaitPelvicSwingDifferenceCm = gaitPelvicSwingDifferenceCm
        self.gaitTrunkSwayCm = gaitTrunkSwayCm
        self.gaitObservedAbnormal = gaitObservedAbnormal
        self.gaitObservationNote = gaitObservationNote
        self.seatedThoracicKyphosisObserved = seatedThoracicKyphosisObserved
        self.captureProtocolVersion = captureProtocolVersion
        self.cameraFacing = cameraFacing
        self.measurementMode = measurementMode
        self.deviceCapabilityTier = deviceCapabilityTier
        self.depthAvailable = depthAvailable
        self.segmentPhaseCount = segmentPhaseCount
        self.qualityChecks = qualityChecks
        self.captureCalibration = captureCalibration
        self.captureAttemptCount = captureAttemptCount
        self.repeatabilityStatus = repeatabilityStatus
        self.repeatabilityMaximumDifference = repeatabilityMaximumDifference
    }

    var adamsResult: AdamsScreeningResult? {
        if let adamsObservedResult, let result = AdamsScreeningResult(rawValue: adamsObservedResult) { return result }
        guard let prominence = cameraProxyRibProminenceCm, prominence.isFinite, prominence >= 0 else { return nil }
        if prominence >= PostureScreeningRules.ribProminencePositiveCentimeters { return .positive }
        if prominence >= PostureScreeningRules.ribProminenceEquivocalCentimeters { return .equivocal }
        return .negative
    }
}

/// Engineering candidate thresholds retained for offline comparison only.
/// They are not published product or clinical cut-offs until the exact model
/// version passes the independent human-validation release gate.
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

/// Candidate posture rules used for validation. The supplied 7.20 framework
/// defines the capture procedure and professional screening path; it does not
/// validate every phone-camera proxy threshold below. Product classification
/// therefore remains fail-closed until an independent labelled evaluation is
/// approved for this exact algorithm/calibration version.
