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
