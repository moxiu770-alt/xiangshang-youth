import Foundation

/// Two independent guided captures are required before a task can become a
/// completed posture record. This is an engineering repeatability check, not
/// a clinical accuracy or diagnostic claim.
enum PostureCaptureRepeatability {
    struct Result: Equatable {
        let passed: Bool
        let maximumDifference: Double
        let comparedMetricCount: Int
    }

    static func verify(first: PostureMetricSnapshot, second: PostureMetricSnapshot) -> Result {
        guard first.task == second.task else { return Result(passed: false, maximumDifference: .infinity, comparedMetricCount: 0) }
        let pairs: [(Double?, Double?, Double)] = [
            (first.shoulderHeightDifferenceCm, second.shoulderHeightDifferenceCm, 0.8),
            (first.pelvicHeightDifferenceCm, second.pelvicHeightDifferenceCm, 0.8),
            (first.spinalMidlineDeviationCm, second.spinalMidlineDeviationCm, 0.8),
            (first.gaitShoulderSwingDifferenceCm, second.gaitShoulderSwingDifferenceCm, 0.8),
            (first.gaitPelvicSwingDifferenceCm, second.gaitPelvicSwingDifferenceCm, 0.8),
            (first.gaitTrunkSwayCm, second.gaitTrunkSwayCm, 0.8),
            (first.headTiltDegrees, second.headTiltDegrees, 3.0),
            (first.thoracicRoundingDegrees, second.thoracicRoundingDegrees, 3.0),
            (first.forwardHeadAngleDegrees, second.forwardHeadAngleDegrees, 3.0)
            ,(first.kneeAlignmentProxyRatio, second.kneeAlignmentProxyRatio, 0.12)
            ,(first.leftKneeValgusProxyDegrees, second.leftKneeValgusProxyDegrees, 4.0)
            ,(first.rightKneeValgusProxyDegrees, second.rightKneeValgusProxyDegrees, 4.0)
            ,(first.footArchVisibilityScore, second.footArchVisibilityScore, 0.15)
        ]
        let deltas = pairs.compactMap { first, second, limit -> (Double, Double)? in
            guard let first, let second, first.isFinite, second.isFinite else { return nil }
            return (abs(first - second), limit)
        }
        let maximum = deltas.map { $0.0 }.max() ?? .infinity
        return Result(
            passed: deltas.count >= 3 && deltas.allSatisfy { $0.0 <= $0.1 },
            maximumDifference: maximum,
            comparedMetricCount: deltas.count
        )
    }

    /// Fuse only two already-accepted, independently re-entered captures.
    /// It preserves the latest non-numeric observation fields and never
    /// creates a value where neither capture produced one.
    static func merged(first: PostureMetricSnapshot, second: PostureMetricSnapshot, result: Result) -> PostureMetricSnapshot {
        func mean(_ left: Double?, _ right: Double?) -> Double? {
            switch (left?.isFinite == true ? left : nil, right?.isFinite == true ? right : nil) {
            case let (left?, right?): return (left + right) / 2
            case let (left?, nil): return left
            case let (nil, right?): return right
            default: return nil
            }
        }
        return PostureMetricSnapshot(
            id: second.id,
            task: second.task,
            sampleCount: first.sampleCount + second.sampleCount,
            confidence: (first.confidence + second.confidence) / 2,
            shoulderHeightDifferenceCm: mean(first.shoulderHeightDifferenceCm, second.shoulderHeightDifferenceCm),
            pelvicHeightDifferenceCm: mean(first.pelvicHeightDifferenceCm, second.pelvicHeightDifferenceCm),
            headTiltDegrees: mean(first.headTiltDegrees, second.headTiltDegrees),
            spinalMidlineDeviationCm: mean(first.spinalMidlineDeviationCm, second.spinalMidlineDeviationCm),
            thoracicRoundingDegrees: mean(first.thoracicRoundingDegrees, second.thoracicRoundingDegrees),
            forwardHeadAngleDegrees: mean(first.forwardHeadAngleDegrees, second.forwardHeadAngleDegrees),
            cameraProxyAtrDegrees: mean(first.cameraProxyAtrDegrees, second.cameraProxyAtrDegrees),
            cameraProxyRibProminenceCm: mean(first.cameraProxyRibProminenceCm, second.cameraProxyRibProminenceCm),
            shoulderProtractionProxyDegrees: mean(first.shoulderProtractionProxyDegrees, second.shoulderProtractionProxyDegrees),
            pelvicTiltProxyDegrees: mean(first.pelvicTiltProxyDegrees, second.pelvicTiltProxyDegrees),
            kneeAlignmentProxyRatio: mean(first.kneeAlignmentProxyRatio, second.kneeAlignmentProxyRatio),
            lowerLimbAxisAsymmetryDegrees: mean(first.lowerLimbAxisAsymmetryDegrees, second.lowerLimbAxisAsymmetryDegrees),
            leftKneeValgusProxyDegrees: mean(first.leftKneeValgusProxyDegrees, second.leftKneeValgusProxyDegrees),
            rightKneeValgusProxyDegrees: mean(first.rightKneeValgusProxyDegrees, second.rightKneeValgusProxyDegrees),
            kneeTrackingAsymmetryRatio: mean(first.kneeTrackingAsymmetryRatio, second.kneeTrackingAsymmetryRatio),
            squatDepthRatio: mean(first.squatDepthRatio, second.squatDepthRatio),
            movementRepetitionCount: mean(first.movementRepetitionCount, second.movementRepetitionCount),
            footArchVisibilityScore: mean(first.footArchVisibilityScore, second.footArchVisibilityScore),
            leftArchProxyIndex: mean(first.leftArchProxyIndex, second.leftArchProxyIndex),
            rightArchProxyIndex: mean(first.rightArchProxyIndex, second.rightArchProxyIndex),
            heelAlignmentProxyDegrees: mean(first.heelAlignmentProxyDegrees, second.heelAlignmentProxyDegrees),
            adamsObservedResult: second.adamsObservedResult ?? first.adamsObservedResult,
            adamsProminenceSide: second.adamsProminenceSide ?? first.adamsProminenceSide,
            instrumentAtrDegrees: mean(first.instrumentAtrDegrees, second.instrumentAtrDegrees),
            thoracicAtrDegrees: mean(first.thoracicAtrDegrees, second.thoracicAtrDegrees),
            lumbarAtrDegrees: mean(first.lumbarAtrDegrees, second.lumbarAtrDegrees),
            thoracicAtrSide: second.thoracicAtrSide ?? first.thoracicAtrSide,
            lumbarAtrSide: second.lumbarAtrSide ?? first.lumbarAtrSide,
            thoracicAtrFirstDegrees: mean(first.thoracicAtrFirstDegrees, second.thoracicAtrFirstDegrees),
            thoracicAtrSecondDegrees: mean(first.thoracicAtrSecondDegrees, second.thoracicAtrSecondDegrees),
            lumbarAtrFirstDegrees: mean(first.lumbarAtrFirstDegrees, second.lumbarAtrFirstDegrees),
            lumbarAtrSecondDegrees: mean(first.lumbarAtrSecondDegrees, second.lumbarAtrSecondDegrees),
            seatedForwardBendAtrDegrees: mean(first.seatedForwardBendAtrDegrees, second.seatedForwardBendAtrDegrees),
            occiputWallDistanceCm: mean(first.occiputWallDistanceCm, second.occiputWallDistanceCm),
            gaitShoulderSwingDifferenceCm: mean(first.gaitShoulderSwingDifferenceCm, second.gaitShoulderSwingDifferenceCm),
            gaitPelvicSwingDifferenceCm: mean(first.gaitPelvicSwingDifferenceCm, second.gaitPelvicSwingDifferenceCm),
            gaitTrunkSwayCm: mean(first.gaitTrunkSwayCm, second.gaitTrunkSwayCm),
            gaitObservedAbnormal: second.gaitObservedAbnormal ?? first.gaitObservedAbnormal,
            gaitObservationNote: second.gaitObservationNote ?? first.gaitObservationNote,
            seatedThoracicKyphosisObserved: second.seatedThoracicKyphosisObserved ?? first.seatedThoracicKyphosisObserved,
            captureProtocolVersion: second.captureProtocolVersion ?? first.captureProtocolVersion,
            cameraFacing: second.cameraFacing ?? first.cameraFacing,
            measurementMode: second.measurementMode ?? first.measurementMode,
            deviceCapabilityTier: second.deviceCapabilityTier ?? first.deviceCapabilityTier,
            depthAvailable: second.depthAvailable ?? first.depthAvailable,
            segmentPhaseCount: max(first.segmentPhaseCount ?? 1, second.segmentPhaseCount ?? 1),
            qualityChecks: Array(Set((first.qualityChecks ?? []) + (second.qualityChecks ?? []) + ["two-take-repeatability"])).sorted(),
            captureCalibration: second.captureCalibration ?? first.captureCalibration,
            captureAttemptCount: 2,
            repeatabilityStatus: "passed",
            repeatabilityMaximumDifference: result.maximumDifference
        )
    }
}

/// One aggregated, on-device pose observation. Values are derived from
/// normalized Vision landmarks and the parent's measured height; raw frames
/// are never retained. The names deliberately say "camera proxy" where a
/// 2-D phone camera cannot replace a Scoliometer or standing X-ray.
