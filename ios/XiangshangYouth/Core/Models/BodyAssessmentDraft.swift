import Foundation

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
    var standingShoulderDifferenceCentimeters: Double? = nil
    var standingPelvisDifferenceCentimeters: Double? = nil
    var standingHeadTiltDegrees: Double? = nil
    var adamsObservedResult: String? = nil
    var adamsProminenceSide: String? = nil
    var gaitObservedAbnormal: Bool? = nil
    var gaitObservationNote: String? = nil
    var seatedMidlineDifferenceCentimeters: Double? = nil
    var seatedShoulderDifferenceCentimeters: Double? = nil
    var seatedThoracicKyphosisObserved: Bool? = nil
    var thoracicAtrDegrees: Double? = nil
    var lumbarAtrDegrees: Double? = nil
    var thoracicAtrSide: String? = nil
    var lumbarAtrSide: String? = nil
    var atrRetestEnabled = false
    var thoracicAtrRepeatDegrees: Double? = nil
    var lumbarAtrRepeatDegrees: Double? = nil
    var seatedForwardBendAtrDegrees: Double? = nil
    var occiputWallDistanceFirstCentimeters: Double? = nil
    var occiputWallDistanceSecondCentimeters: Double? = nil
    var occiputWallDistanceCentimeters: Double? = nil

    private enum CodingKeys: String, CodingKey {
        case step, guardianReady, consentAcknowledged, environmentReady
        case heightCentimeters, weightKilograms, completedCaptures
        case parentMarkedAsymmetric, parentMarkedGaitConcern, visualObservationHint
        case captureObservationHints, fatherHeightCentimeters, motherHeightCentimeters, postureSnapshots
        case standingShoulderDifferenceCentimeters, standingPelvisDifferenceCentimeters, standingHeadTiltDegrees
        case adamsObservedResult, adamsProminenceSide, gaitObservedAbnormal, gaitObservationNote
        case seatedMidlineDifferenceCentimeters, seatedShoulderDifferenceCentimeters, seatedThoracicKyphosisObserved
        case thoracicAtrDegrees, lumbarAtrDegrees, thoracicAtrSide, lumbarAtrSide
        case atrRetestEnabled, thoracicAtrRepeatDegrees, lumbarAtrRepeatDegrees, seatedForwardBendAtrDegrees
        case occiputWallDistanceFirstCentimeters, occiputWallDistanceSecondCentimeters, occiputWallDistanceCentimeters
    }

    init(step: Int = 0, guardianReady: Bool = false, consentAcknowledged: Bool = false, environmentReady: Bool = false, heightCentimeters: Double = 0, weightKilograms: Double = 0, completedCaptures: Set<BodyAssessmentRecord.CaptureTask> = [], parentMarkedAsymmetric: Bool = false, parentMarkedGaitConcern: Bool = false, visualObservationHint: String? = nil, captureObservationHints: [BodyAssessmentRecord.CaptureTask: String] = [:], fatherHeightCentimeters: Double? = nil, motherHeightCentimeters: Double? = nil, postureSnapshots: [BodyAssessmentRecord.CaptureTask: PostureMetricSnapshot] = [:], standingShoulderDifferenceCentimeters: Double? = nil, standingPelvisDifferenceCentimeters: Double? = nil, standingHeadTiltDegrees: Double? = nil, adamsObservedResult: String? = nil, adamsProminenceSide: String? = nil, gaitObservedAbnormal: Bool? = nil, gaitObservationNote: String? = nil, seatedMidlineDifferenceCentimeters: Double? = nil, seatedShoulderDifferenceCentimeters: Double? = nil, seatedThoracicKyphosisObserved: Bool? = nil, thoracicAtrDegrees: Double? = nil, lumbarAtrDegrees: Double? = nil, thoracicAtrSide: String? = nil, lumbarAtrSide: String? = nil, atrRetestEnabled: Bool = false, thoracicAtrRepeatDegrees: Double? = nil, lumbarAtrRepeatDegrees: Double? = nil, seatedForwardBendAtrDegrees: Double? = nil, occiputWallDistanceFirstCentimeters: Double? = nil, occiputWallDistanceSecondCentimeters: Double? = nil, occiputWallDistanceCentimeters: Double? = nil) {
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
        self.standingShoulderDifferenceCentimeters = standingShoulderDifferenceCentimeters
        self.standingPelvisDifferenceCentimeters = standingPelvisDifferenceCentimeters
        self.standingHeadTiltDegrees = standingHeadTiltDegrees
        self.adamsObservedResult = adamsObservedResult
        self.adamsProminenceSide = adamsProminenceSide
        self.gaitObservedAbnormal = gaitObservedAbnormal
        self.gaitObservationNote = gaitObservationNote
        self.seatedMidlineDifferenceCentimeters = seatedMidlineDifferenceCentimeters
        self.seatedShoulderDifferenceCentimeters = seatedShoulderDifferenceCentimeters
        self.seatedThoracicKyphosisObserved = seatedThoracicKyphosisObserved
        self.thoracicAtrDegrees = thoracicAtrDegrees
        self.lumbarAtrDegrees = lumbarAtrDegrees
        self.thoracicAtrSide = thoracicAtrSide
        self.lumbarAtrSide = lumbarAtrSide
        self.atrRetestEnabled = atrRetestEnabled
        self.thoracicAtrRepeatDegrees = thoracicAtrRepeatDegrees
        self.lumbarAtrRepeatDegrees = lumbarAtrRepeatDegrees
        self.seatedForwardBendAtrDegrees = seatedForwardBendAtrDegrees
        self.occiputWallDistanceFirstCentimeters = occiputWallDistanceFirstCentimeters
        self.occiputWallDistanceSecondCentimeters = occiputWallDistanceSecondCentimeters
        self.occiputWallDistanceCentimeters = occiputWallDistanceCentimeters
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
        standingShoulderDifferenceCentimeters = try values.decodeIfPresent(Double.self, forKey: .standingShoulderDifferenceCentimeters)
        standingPelvisDifferenceCentimeters = try values.decodeIfPresent(Double.self, forKey: .standingPelvisDifferenceCentimeters)
        standingHeadTiltDegrees = try values.decodeIfPresent(Double.self, forKey: .standingHeadTiltDegrees)
        adamsObservedResult = try values.decodeIfPresent(String.self, forKey: .adamsObservedResult)
        adamsProminenceSide = try values.decodeIfPresent(String.self, forKey: .adamsProminenceSide)
        gaitObservedAbnormal = try values.decodeIfPresent(Bool.self, forKey: .gaitObservedAbnormal)
        gaitObservationNote = try values.decodeIfPresent(String.self, forKey: .gaitObservationNote)
        seatedMidlineDifferenceCentimeters = try values.decodeIfPresent(Double.self, forKey: .seatedMidlineDifferenceCentimeters)
        seatedShoulderDifferenceCentimeters = try values.decodeIfPresent(Double.self, forKey: .seatedShoulderDifferenceCentimeters)
        seatedThoracicKyphosisObserved = try values.decodeIfPresent(Bool.self, forKey: .seatedThoracicKyphosisObserved)
        thoracicAtrDegrees = try values.decodeIfPresent(Double.self, forKey: .thoracicAtrDegrees)
        lumbarAtrDegrees = try values.decodeIfPresent(Double.self, forKey: .lumbarAtrDegrees)
        thoracicAtrSide = try values.decodeIfPresent(String.self, forKey: .thoracicAtrSide)
        lumbarAtrSide = try values.decodeIfPresent(String.self, forKey: .lumbarAtrSide)
        atrRetestEnabled = try values.decodeIfPresent(Bool.self, forKey: .atrRetestEnabled) ?? false
        thoracicAtrRepeatDegrees = try values.decodeIfPresent(Double.self, forKey: .thoracicAtrRepeatDegrees)
        lumbarAtrRepeatDegrees = try values.decodeIfPresent(Double.self, forKey: .lumbarAtrRepeatDegrees)
        seatedForwardBendAtrDegrees = try values.decodeIfPresent(Double.self, forKey: .seatedForwardBendAtrDegrees)
        occiputWallDistanceFirstCentimeters = try values.decodeIfPresent(Double.self, forKey: .occiputWallDistanceFirstCentimeters)
        occiputWallDistanceSecondCentimeters = try values.decodeIfPresent(Double.self, forKey: .occiputWallDistanceSecondCentimeters)
        occiputWallDistanceCentimeters = try values.decodeIfPresent(Double.self, forKey: .occiputWallDistanceCentimeters)
    }
}
