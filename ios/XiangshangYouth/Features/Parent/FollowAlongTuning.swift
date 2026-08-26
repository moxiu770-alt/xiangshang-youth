import SwiftUI
import AVKit
import AVFoundation
import UIKit
import Vision
import Darwin

enum ChildFollowAlongTuning {
    static let algorithmVersion = "UY-FOLLOW-CV-1.0"
    static let calibrationVersion = "UY-CAL-BASELINE-1.0"
    static let canonicalAssetVersion = "android-child-precision-2026-09-16-child-motion-research-v4.1"
    struct Profile: Equatable {
        let minLandmarkConfidence: Float
        let minAverageConfidence: Double
        let calibrationFrames: Int
        let stablePeakFrames: Int
        let stableReturnFrames: Int
        let minRepInterval: TimeInterval
        let amplitudeScale: Double
        let activeGateRatio: Double
        let lowGateRatio: Double
        let qualityAmplitudeWeight: Double
        let signalToleranceScale: Double
        let intervalScale: Double
        let smoothScale: Double
        let outlierTrimRatio: Double
        let stabilityGateScale: Double
        let dynamicGateFloor: Double
        let dynamicGateCeiling: Double
        let confidenceWindowFrames: Int
    }

    /// Action-specific hysteresis keeps small, slow exercises from sharing
    /// the same gate as fast jumping actions. The values mirror the Android
    /// action policy at the contract level; age-specific intervals are still
    /// supplied by the native age profile below.
    struct ActionProfile: Equatable {
        let highGateRatio: Double
        let lowGateRatio: Double
        let activeGateRatio: Double
        let stablePeakFrames: Int
        let stableReturnFrames: Int
        let minDropRatio: Double
        let minDropAbsolute: Double
        let rangeNoiseMultiplier: Double
        let minRepInterval: TimeInterval
        let maxRepInterval: TimeInterval
        let minSignalRange: Double?
        let historyLen: Int
        let minHistory: Int
        let smoothAlpha: Double
        let minConfidencePenalty: Double
        let derivativeMin: Double
        let derivativeScale: Double
        let qualityStabilityWeight: Double
        let settlingFrames: Int
        let requiredSignalHistoryFrames: Int
        let confidenceTrim: Double
        let topHoldFrames: Int
        let returnHoldFrames: Int
        let returnSlopeMinRatio: Double
        let returnConfidenceFloor: Double

        init(highGateRatio: Double, lowGateRatio: Double, activeGateRatio: Double, stablePeakFrames: Int, stableReturnFrames: Int, minDropRatio: Double, minDropAbsolute: Double, rangeNoiseMultiplier: Double, minRepInterval: TimeInterval, maxRepInterval: TimeInterval, minSignalRange: Double? = nil, historyLen: Int = 40, minHistory: Int = 6, smoothAlpha: Double = 0.35, minConfidencePenalty: Double = 0, derivativeMin: Double = 0.008, derivativeScale: Double = 1, qualityStabilityWeight: Double = 0.28, settlingFrames: Int = 2, requiredSignalHistoryFrames: Int = 20, confidenceTrim: Double = 0.22, topHoldFrames: Int = 2, returnHoldFrames: Int = 2, returnSlopeMinRatio: Double = 0.82, returnConfidenceFloor: Double = 0.78) {
            self.highGateRatio = highGateRatio
            self.lowGateRatio = lowGateRatio
            self.activeGateRatio = activeGateRatio
            self.stablePeakFrames = stablePeakFrames
            self.stableReturnFrames = stableReturnFrames
            self.minDropRatio = minDropRatio
            self.minDropAbsolute = minDropAbsolute
            self.rangeNoiseMultiplier = rangeNoiseMultiplier
            self.minRepInterval = minRepInterval
            self.maxRepInterval = maxRepInterval
            self.minSignalRange = minSignalRange
            self.historyLen = historyLen
            self.minHistory = minHistory
            self.smoothAlpha = smoothAlpha
            self.minConfidencePenalty = minConfidencePenalty
            self.derivativeMin = derivativeMin
            self.derivativeScale = derivativeScale
            self.qualityStabilityWeight = qualityStabilityWeight
            self.settlingFrames = settlingFrames
            self.requiredSignalHistoryFrames = requiredSignalHistoryFrames
            self.confidenceTrim = confidenceTrim
            self.topHoldFrames = topHoldFrames
            self.returnHoldFrames = returnHoldFrames
            self.returnSlopeMinRatio = returnSlopeMinRatio
            self.returnConfidenceFloor = returnConfidenceFloor
        }
    }

    static func actionProfile(for category: String, profile: Profile, ageMonths: Int? = nil) -> ActionProfile {
        let base: ActionProfile
        switch category {
        case "front_raise", "lateral_raise":
            base = ActionProfile(highGateRatio: 0.25, lowGateRatio: 0.18, activeGateRatio: 0.56, stablePeakFrames: 2, stableReturnFrames: 2, minDropRatio: 0.26, minDropAbsolute: 0.006, rangeNoiseMultiplier: 3.8, minRepInterval: 0.62, maxRepInterval: 1.9)
        case "squat":
            base = ActionProfile(highGateRatio: 0.20, lowGateRatio: 0.17, activeGateRatio: 0.40, stablePeakFrames: 2, stableReturnFrames: 2, minDropRatio: 0.26, minDropAbsolute: 0.004, rangeNoiseMultiplier: 3.0, minRepInterval: 0.82, maxRepInterval: 2.5)
        case "squat_challenge":
            base = ActionProfile(highGateRatio: 0.21, lowGateRatio: 0.17, activeGateRatio: 0.41, stablePeakFrames: 2, stableReturnFrames: 3, minDropRatio: 0.28, minDropAbsolute: 0.005, rangeNoiseMultiplier: 3.25, minRepInterval: 1.02, maxRepInterval: 3.0)
        case "lunge":
            base = ActionProfile(highGateRatio: 0.20, lowGateRatio: 0.17, activeGateRatio: 0.40, stablePeakFrames: 2, stableReturnFrames: 2, minDropRatio: 0.27, minDropAbsolute: 0.005, rangeNoiseMultiplier: 3.25, minRepInterval: 0.98, maxRepInterval: 2.9)
        case "jumping_jack":
            base = ActionProfile(highGateRatio: 0.15, lowGateRatio: 0.13, activeGateRatio: 0.33, stablePeakFrames: 6, stableReturnFrames: 6, minDropRatio: 0.52, minDropAbsolute: 0.0118, rangeNoiseMultiplier: 2.6, minRepInterval: 0.56, maxRepInterval: 1.98)
        case "high_knee":
            base = ActionProfile(highGateRatio: 0.11, lowGateRatio: 0.11, activeGateRatio: 0.34, stablePeakFrames: 6, stableReturnFrames: 6, minDropRatio: 0.48, minDropAbsolute: 0.0135, rangeNoiseMultiplier: 2.9, minRepInterval: 0.56, maxRepInterval: 1.76)
        case "sit_up":
            base = ActionProfile(highGateRatio: 0.18, lowGateRatio: 0.16, activeGateRatio: 0.37, stablePeakFrames: 2, stableReturnFrames: 2, minDropRatio: 0.26, minDropAbsolute: 0.005, rangeNoiseMultiplier: 3.2, minRepInterval: 0.67, maxRepInterval: 2.1)
        case "plank":
            base = ActionProfile(highGateRatio: 0.18, lowGateRatio: 0.14, activeGateRatio: 0.25, stablePeakFrames: 3, stableReturnFrames: 3, minDropRatio: 0.20, minDropAbsolute: 0.003, rangeNoiseMultiplier: 2.4, minRepInterval: 2.05, maxRepInterval: 6.0)
        case "burpee":
            base = ActionProfile(highGateRatio: 0.22, lowGateRatio: 0.17, activeGateRatio: 0.42, stablePeakFrames: 2, stableReturnFrames: 2, minDropRatio: 0.30, minDropAbsolute: 0.01, rangeNoiseMultiplier: 3.4, minRepInterval: 1.18, maxRepInterval: 3.5)
        case "jump_rope":
            base = ActionProfile(highGateRatio: 0.16, lowGateRatio: 0.13, activeGateRatio: 0.36, stablePeakFrames: 6, stableReturnFrames: 6, minDropRatio: 0.56, minDropAbsolute: 0.0158, rangeNoiseMultiplier: 2.8, minRepInterval: 0.76, maxRepInterval: 2.04)
        default:
            base = ActionProfile(highGateRatio: 0.20, lowGateRatio: 0.16, activeGateRatio: 0.36, stablePeakFrames: 3, stableReturnFrames: 3, minDropRatio: 0.26, minDropAbsolute: 0.005, rangeNoiseMultiplier: 3.2, minRepInterval: 0.68, maxRepInterval: 2.2)
        }
        let fallback = ActionProfile(
            highGateRatio: base.highGateRatio,
            lowGateRatio: base.lowGateRatio,
            activeGateRatio: base.activeGateRatio,
            stablePeakFrames: max(base.stablePeakFrames, profile.stablePeakFrames),
            stableReturnFrames: max(base.stableReturnFrames, profile.stableReturnFrames),
            minDropRatio: base.minDropRatio,
            minDropAbsolute: base.minDropAbsolute,
            rangeNoiseMultiplier: base.rangeNoiseMultiplier,
            minRepInterval: max(base.minRepInterval, profile.minRepInterval),
            maxRepInterval: max(base.maxRepInterval, profile.minRepInterval * 2.5),
            historyLen: 40,
            minHistory: 6,
            smoothAlpha: 0.35,
            minConfidencePenalty: 0,
            derivativeMin: 0.008,
            derivativeScale: 1,
            qualityStabilityWeight: 0.28,
            settlingFrames: 2,
            requiredSignalHistoryFrames: max(20, profile.calibrationFrames / 2),
            confidenceTrim: 0.22,
            topHoldFrames: base.stablePeakFrames,
            returnHoldFrames: base.stableReturnFrames,
            returnSlopeMinRatio: 0.82,
            returnConfidenceFloor: profile.minAverageConfidence
        )
        guard let ageMonths, let canonical = canonicalActionProfile(category: category, ageMonths: ageMonths) else { return fallback }
        return resolvedActionProfile(canonical, ageMonths: ageMonths, profile: profile)
    }

    /// Keep the iOS gate age-aware like Android. These are conservative
    /// starting profiles; production tuning still requires labelled videos
    /// from the target device/camera matrix.
    static func profile(ageMonths: Int?) -> Profile {
        if let ageMonths, let canonical = canonicalAgeProfile(ageMonths: ageMonths) {
            return Profile(minLandmarkConfidence: Float(canonical.minLandmarkConfidence), minAverageConfidence: canonical.minAverageConfidence, calibrationFrames: canonical.calibrationFrames, stablePeakFrames: canonical.stablePeakFrames, stableReturnFrames: canonical.stableReturnFrames, minRepInterval: canonical.minRepIntervalMs / 1000, amplitudeScale: canonical.amplitudeScale, activeGateRatio: canonical.activeGateRatio, lowGateRatio: canonical.lowGateRatio, qualityAmplitudeWeight: canonical.qualityAmplitudeWeight, signalToleranceScale: canonical.signalToleranceScale, intervalScale: canonical.intervalScale, smoothScale: canonical.smoothScale, outlierTrimRatio: canonical.outlierTrimRatio, stabilityGateScale: canonical.stabilityGateScale, dynamicGateFloor: canonical.dynamicGateFloor, dynamicGateCeiling: canonical.dynamicGateCeiling, confidenceWindowFrames: canonical.confidenceWindowFrames)
        }
        guard let ageMonths else {
            return Profile(minLandmarkConfidence: 0.30, minAverageConfidence: 0.42,
                            calibrationFrames: 24, stablePeakFrames: 4,
                            stableReturnFrames: 4, minRepInterval: 0.68,
                            amplitudeScale: 0.96, activeGateRatio: 0.53, lowGateRatio: 0.34,
                            qualityAmplitudeWeight: 0.58, signalToleranceScale: 0.98,
                            intervalScale: 0.98, smoothScale: 1.02, outlierTrimRatio: 0.14,
                            stabilityGateScale: 1, dynamicGateFloor: 0.72, dynamicGateCeiling: 1.28,
                            confidenceWindowFrames: 20)
        }
        switch ageMonths {
        case ..<97: // 6–8 years
            return Profile(minLandmarkConfidence: 0.34, minAverageConfidence: 0.47,
                            calibrationFrames: 30, stablePeakFrames: 5,
                            stableReturnFrames: 5, minRepInterval: 0.80,
                            amplitudeScale: 0.70, activeGateRatio: 0.58, lowGateRatio: 0.34,
                            qualityAmplitudeWeight: 0.61, signalToleranceScale: 0.86,
                            intervalScale: 1.12, smoothScale: 0.98, outlierTrimRatio: 0.17,
                            stabilityGateScale: 1.14, dynamicGateFloor: 0.66, dynamicGateCeiling: 1.34,
                            confidenceWindowFrames: 22)
        case 97...132: // 9–11 years
            return Profile(minLandmarkConfidence: 0.33, minAverageConfidence: 0.46,
                            calibrationFrames: 26, stablePeakFrames: 5,
                            stableReturnFrames: 5, minRepInterval: 0.79,
                            amplitudeScale: 0.82, activeGateRatio: 0.57, lowGateRatio: 0.33,
                            qualityAmplitudeWeight: 0.59, signalToleranceScale: 0.92,
                            intervalScale: 1.03, smoothScale: 0.98, outlierTrimRatio: 0.14,
                            stabilityGateScale: 1.02, dynamicGateFloor: 0.68, dynamicGateCeiling: 1.31,
                            confidenceWindowFrames: 20)
        case 133...168: // 11–14 years
            return Profile(minLandmarkConfidence: 0.325, minAverageConfidence: 0.445,
                            calibrationFrames: 24, stablePeakFrames: 4,
                            stableReturnFrames: 4, minRepInterval: 0.65,
                            amplitudeScale: 0.86, activeGateRatio: 0.55, lowGateRatio: 0.32,
                            qualityAmplitudeWeight: 0.56, signalToleranceScale: 1,
                            intervalScale: 1, smoothScale: 1, outlierTrimRatio: 0.12,
                            stabilityGateScale: 1, dynamicGateFloor: 0.72, dynamicGateCeiling: 1.25,
                            confidenceWindowFrames: 18)
        default: // 14–18 years
            return Profile(minLandmarkConfidence: 0.31, minAverageConfidence: 0.43,
                            calibrationFrames: 24, stablePeakFrames: 4,
                            stableReturnFrames: 4, minRepInterval: 0.62,
                            amplitudeScale: 0.90, activeGateRatio: 0.55, lowGateRatio: 0.32,
                            qualityAmplitudeWeight: 0.55, signalToleranceScale: 1.02,
                            intervalScale: 0.98, smoothScale: 1.01, outlierTrimRatio: 0.11,
                            stabilityGateScale: 1, dynamicGateFloor: 0.74, dynamicGateCeiling: 1.24,
                            confidenceWindowFrames: 17)
        }
    }

    static func minimumAmplitude(for category: String, profile: Profile) -> Double {
        let base: Double
        switch category {
        case "front_raise", "lateral_raise": base = 0.095
        case "squat": base = 0.052
        case "squat_challenge": base = 0.057
        case "lunge": base = 0.056
        case "high_knee": base = 0.102
        case "sit_up": base = 0.088
        case "plank": base = 0.034
        case "jumping_jack": base = 0.040
        case "burpee": base = 0.138
        default: base = 0.05
        }
        return base * profile.amplitudeScale
    }

    private struct CanonicalAgeProfile: Decodable {
        let minAgeMonths: Int; let maxAgeMonths: Int
        let minLandmarkConfidence: Double; let minAverageConfidence: Double
        let calibrationFrames: Int; let stablePeakFrames: Int; let stableReturnFrames: Int
        let minRepIntervalMs: Double; let amplitudeScale: Double
        let activeGateRatio: Double; let lowGateRatio: Double; let qualityAmplitudeWeight: Double
        let signalToleranceScale: Double; let intervalScale: Double; let smoothScale: Double
        let outlierTrimRatio: Double; let stabilityGateScale: Double
        let dynamicGateFloor: Double; let dynamicGateCeiling: Double
        let confidenceWindowFrames: Int
    }
    private struct CanonicalActionProfile: Decodable {
        let category: String; let minAgeMonths: Int; let maxAgeMonths: Int
        let minSignalRange: Double; let minRepIntervalMs: Double
        let highGateRatio: Double; let lowGateRatio: Double; let activeGateRatio: Double
        let rangeNoiseMultiplier: Double; let stablePeakFrames: Int; let stableReturnFrames: Int
        let historyLen: Int; let minHistory: Int; let smoothAlpha: Double
        let minConfidencePenalty: Double; let derivativeMin: Double; let derivativeScale: Double
        let qualityStabilityWeight: Double; let settlingFrames: Int; let requiredSignalHistoryFrames: Int
        let confidenceTrim: Double; let topHoldFrames: Int; let returnHoldFrames: Int
        let maxRepIntervalMs: Double; let minDropRatio: Double; let minDropAbsolute: Double
        let returnSlopeMinRatio: Double; let returnConfidenceFloor: Double
    }
    private struct CanonicalMeta: Decodable { let version: String }
    private struct CanonicalManifest: Decodable { let meta: CanonicalMeta; let ageProfiles: [CanonicalAgeProfile]; let actionProfiles: [CanonicalActionProfile] }
    private static let configLock = NSLock()
    private static var canonicalManifest: CanonicalManifest?

    static func loadCanonicalProfilesIfAvailable(bundle: Bundle = .main) {
        guard let url = bundle.url(forResource: "follow_along_action_profiles", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let manifest = try? JSONDecoder().decode(CanonicalManifest.self, from: data),
              manifest.meta.version == canonicalAssetVersion,
              canonicalManifestIsValid(manifest) else { return }
        configLock.lock(); canonicalManifest = manifest; configLock.unlock()
    }

    private static func canonicalManifestIsValid(_ manifest: CanonicalManifest) -> Bool {
        guard manifest.ageProfiles.count == 4, manifest.actionProfiles.count == 44 else { return false }
        let expectedBands = [(72, 96), (97, 132), (133, 168), (169, 216)]
        let bands = manifest.ageProfiles.map { ($0.minAgeMonths, $0.maxAgeMonths) }
        guard bands.elementsEqual(expectedBands, by: { $0.0 == $1.0 && $0.1 == $1.1 }) else { return false }
        guard manifest.ageProfiles.allSatisfy(canonicalAgeProfileIsValid) else { return false }
        let expectedCategories: Set<String> = [
            "burpee", "front_raise", "high_knee", "jump_rope", "jumping_jack",
            "lateral_raise", "lunge", "plank", "sit_up", "squat", "squat_challenge"
        ]
        guard Set(manifest.actionProfiles.map(\.category)) == expectedCategories else { return false }
        guard manifest.actionProfiles.allSatisfy({ profile in
            expectedBands.contains { $0.0 == profile.minAgeMonths && $0.1 == profile.maxAgeMonths }
        }) else { return false }
        guard expectedCategories.allSatisfy({ category in manifest.actionProfiles.filter { $0.category == category }.count == expectedBands.count }) else { return false }
        let keys = manifest.actionProfiles.map { "\($0.category)|\($0.minAgeMonths)|\($0.maxAgeMonths)" }
        guard Set(keys).count == keys.count else { return false }
        return manifest.actionProfiles.allSatisfy(canonicalActionProfileIsValid)
    }

    private static func canonicalAgeProfileIsValid(_ profile: CanonicalAgeProfile) -> Bool {
        func ratio(_ value: Double, _ upper: Double = 2) -> Bool { value.isFinite && value >= 0 && value <= upper }
        return profile.minAgeMonths >= 72 && profile.maxAgeMonths <= 216 && profile.minAgeMonths <= profile.maxAgeMonths &&
            ratio(profile.minLandmarkConfidence, 1) && ratio(profile.minAverageConfidence, 1) &&
            profile.calibrationFrames >= 4 && profile.calibrationFrames <= 240 &&
            profile.stablePeakFrames >= 1 && profile.stablePeakFrames <= 120 && profile.stableReturnFrames >= 1 && profile.stableReturnFrames <= 120 &&
            profile.minRepIntervalMs.isFinite && profile.minRepIntervalMs >= 100 && profile.minRepIntervalMs <= 30_000 &&
            ratio(profile.amplitudeScale) && ratio(profile.activeGateRatio) && ratio(profile.lowGateRatio) && ratio(profile.qualityAmplitudeWeight, 1) &&
            ratio(profile.signalToleranceScale) && ratio(profile.intervalScale) && ratio(profile.smoothScale) && ratio(profile.outlierTrimRatio, 0.5) &&
            ratio(profile.stabilityGateScale) && ratio(profile.dynamicGateFloor) && ratio(profile.dynamicGateCeiling) && profile.dynamicGateCeiling >= profile.dynamicGateFloor &&
            profile.confidenceWindowFrames >= 4 && profile.confidenceWindowFrames <= 240
    }

    private static func canonicalActionProfileIsValid(_ profile: CanonicalActionProfile) -> Bool {
        func ratio(_ value: Double, _ upper: Double = 3) -> Bool { value.isFinite && value >= 0 && value <= upper }
        return !profile.category.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
            profile.minAgeMonths >= 72 && profile.maxAgeMonths <= 216 && profile.minAgeMonths <= profile.maxAgeMonths &&
            profile.minSignalRange.isFinite && profile.minSignalRange >= 0.001 && profile.minSignalRange <= 1.5 &&
            profile.minRepIntervalMs.isFinite && profile.minRepIntervalMs >= 100 && profile.minRepIntervalMs <= 30_000 &&
            ratio(profile.highGateRatio) && ratio(profile.lowGateRatio) && profile.historyLen >= 6 && profile.historyLen <= 240 &&
            profile.minHistory >= 3 && profile.minHistory <= profile.historyLen && ratio(profile.smoothAlpha, 1) &&
            profile.stablePeakFrames >= 1 && profile.stablePeakFrames <= 120 && profile.stableReturnFrames >= 1 && profile.stableReturnFrames <= 120 &&
            ratio(profile.minConfidencePenalty, 1) && ratio(profile.derivativeMin) && ratio(profile.derivativeScale) && ratio(profile.qualityStabilityWeight, 1) &&
            profile.settlingFrames >= 0 && profile.settlingFrames <= 120 && profile.requiredSignalHistoryFrames >= profile.minHistory && profile.requiredSignalHistoryFrames <= 240 &&
            profile.confidenceTrim >= 0 && profile.confidenceTrim <= 0.5 && profile.topHoldFrames >= 1 && profile.topHoldFrames <= 120 && profile.returnHoldFrames >= 1 && profile.returnHoldFrames <= 120 &&
            profile.maxRepIntervalMs.isFinite && profile.maxRepIntervalMs >= 0 && profile.maxRepIntervalMs <= 60_000 && ratio(profile.minDropRatio) && ratio(profile.minDropAbsolute) && ratio(profile.returnSlopeMinRatio) && ratio(profile.returnConfidenceFloor, 1)
    }

    private static func canonicalAgeProfile(ageMonths: Int) -> CanonicalAgeProfile? {
        configLock.lock(); defer { configLock.unlock() }
        return canonicalManifest?.ageProfiles.first { ageMonths >= $0.minAgeMonths && ageMonths <= $0.maxAgeMonths }
    }

    private static func canonicalActionProfile(category: String, ageMonths: Int) -> CanonicalActionProfile? {
        configLock.lock(); defer { configLock.unlock() }
        return canonicalManifest?.actionProfiles.first { $0.category == category && ageMonths >= $0.minAgeMonths && ageMonths <= $0.maxAgeMonths }
    }

    private enum FollowAgeBand { case child, junior, adolescent, teen, unknown }
    private static func ageBand(_ ageMonths: Int?) -> FollowAgeBand {
        guard let ageMonths else { return .unknown }
        switch ageMonths {
        case ...96: return .child
        case 97...132: return .junior
        case 133...168: return .adolescent
        case 169...216: return .teen
        default: return ageMonths < 72 ? .child : .teen
        }
    }
    private static func childBandBias(_ band: FollowAgeBand) -> Double { switch band { case .child: 1.0; case .junior: 0.88; case .adolescent: 0.78; case .teen: 0.72; case .unknown: 0.80 } }
    private static func jitterProtectionBonus(_ band: FollowAgeBand) -> Double { switch band { case .child: 1.20; case .junior: 1.12; case .adolescent: 1.06; case .teen: 1.0; case .unknown: 1.12 } }
    private static func repeatBoostFrames(_ band: FollowAgeBand) -> Int { switch band { case .child: 4; case .junior: 2; case .adolescent: 1; case .teen: 0; case .unknown: 2 } }
    private static func repeatBoostHold(_ band: FollowAgeBand) -> Int { switch band { case .child: 2; case .junior: 1; default: 0 } }
    private static func dropRatioBoost(_ band: FollowAgeBand) -> Double { switch band { case .child: 1.22; case .junior: 1.10; case .adolescent: 0.96; case .teen: 0.90; case .unknown: 1.0 } }
    private static func returnSlopeBoost(_ band: FollowAgeBand) -> Double { switch band { case .child: 1.24; case .junior: 1.08; case .adolescent: 0.96; case .teen: 0.92; case .unknown: 1.0 } }
    private static func confidenceFloorBoost(_ band: FollowAgeBand) -> Double { switch band { case .child: 1.12; case .junior: 1.05; case .adolescent: 1.0; case .teen: 0.96; case .unknown: 1.0 } }
    private static func actionPrecisionHoldBoost(_ band: FollowAgeBand, _ category: String) -> Int {
        switch band {
        case .child: return ["jump_rope", "jumping_jack", "high_knee"].contains(category) ? 2 : (["squat", "lunge", "squat_challenge", "burpee", "front_raise", "lateral_raise", "sit_up", "plank"].contains(category) ? 1 : 0)
        case .junior: return ["jump_rope", "jumping_jack", "high_knee", "squat", "lunge", "squat_challenge", "burpee"].contains(category) ? 1 : 0
        default: return 0
        }
    }

    private static func resolvedActionProfile(_ base: CanonicalActionProfile, ageMonths: Int, profile: Profile) -> ActionProfile {
        let band = ageBand(ageMonths)
        let childBandBoost = repeatBoostFrames(band)
        let holdBoost = repeatBoostHold(band)
        let dropBoost = dropRatioBoost(band)
        let slopeBoost = returnSlopeBoost(band)
        let confidenceBoost = confidenceFloorBoost(band)
        let jitter = jitterProtectionBonus(band)
        let resolvedMax = base.maxRepIntervalMs > 0 ? base.maxRepIntervalMs : base.minRepIntervalMs * 2.45
        let minIntervalBase = max(base.minRepIntervalMs * profile.intervalScale * childBandBias(band), 320 + (band == .child ? 40 : band == .junior ? 25 : 0))
        let minInterval = max(minIntervalBase * (actionPrecisionRepScale(band, category: base.category)), base.minRepIntervalMs)
        return ActionProfile(
            highGateRatio: min(max(base.highGateRatio * profile.smoothScale * 0.98, 0.10), 0.34),
            lowGateRatio: min(max(base.lowGateRatio * profile.smoothScale * 0.98, 0.10), 0.34),
            activeGateRatio: min(max(base.activeGateRatio * profile.activeGateRatio * profile.smoothScale * jitter, 0.18), 1.10),
            stablePeakFrames: max(Int(Double(base.stablePeakFrames) * (profile.outlierTrimRatio + 0.8) * profile.stabilityGateScale), base.stablePeakFrames),
            stableReturnFrames: max(Int(Double(base.stableReturnFrames) * (profile.outlierTrimRatio + 0.8) * profile.stabilityGateScale), base.stableReturnFrames),
            minDropRatio: min(max(base.minDropRatio * dropBoost * actionPrecisionDropScale(band, category: base.category), 0.16), 1.05),
            minDropAbsolute: base.minDropAbsolute + (band == .child ? 0.008 : band == .junior ? 0.006 : 0),
            rangeNoiseMultiplier: min(max(base.rangeNoiseMultiplier * (0.92 + profile.stabilityGateScale * 0.06) * jitter, 2.2), 4.55),
            minRepInterval: minInterval / 1000,
            maxRepInterval: max(resolvedMax * (1 + (dropBoost - 1) * 0.45), base.minRepIntervalMs * 1.6) / 1000,
            minSignalRange: base.minSignalRange * profile.amplitudeScale * profile.signalToleranceScale,
            historyLen: base.historyLen,
            minHistory: base.minHistory,
            smoothAlpha: min(max(base.smoothAlpha * profile.smoothScale, 0.18), 0.52),
            minConfidencePenalty: base.minConfidencePenalty,
            derivativeMin: min(max(base.derivativeMin * profile.smoothScale * base.derivativeScale * (1 + Double(childBandBoost) * 0.035), 0.002), 0.035),
            derivativeScale: base.derivativeScale,
            qualityStabilityWeight: base.qualityStabilityWeight,
            settlingFrames: band == .child ? 6 : band == .junior ? 4 : band == .adolescent ? 3 : band == .teen ? 2 : 4,
            requiredSignalHistoryFrames: max(base.requiredSignalHistoryFrames + childBandBoost, Int(Double(profile.calibrationFrames) * 0.55)),
            confidenceTrim: min(max(base.confidenceTrim * profile.smoothScale, 0.10), 0.35),
            topHoldFrames: max(base.topHoldFrames + holdBoost + actionPrecisionHoldBoost(band, base.category), base.topHoldFrames),
            returnHoldFrames: max(base.returnHoldFrames + holdBoost + actionPrecisionHoldBoost(band, base.category), base.returnHoldFrames),
            returnSlopeMinRatio: min(max(base.returnSlopeMinRatio * slopeBoost, 0.70), 1.28),
            returnConfidenceFloor: min(max(base.returnConfidenceFloor * confidenceBoost, profile.minAverageConfidence * 0.80), 0.92)
        )
    }

    private static func actionPrecisionRepScale(_ band: FollowAgeBand, category: String) -> Double { if band == .child { return ["jump_rope", "jumping_jack", "high_knee"].contains(category) ? 1.10 : 1.06 }; if band == .junior { return ["jump_rope", "jumping_jack", "high_knee"].contains(category) ? 1.04 : (["squat", "lunge", "squat_challenge", "burpee"].contains(category) ? 1.02 : 1.0) }; return 1.0 }
    private static func actionPrecisionDropScale(_ band: FollowAgeBand, category: String) -> Double { if band == .child { return ["jump_rope", "jumping_jack", "high_knee"].contains(category) ? 1.10 : (["squat", "lunge", "squat_challenge", "burpee"].contains(category) ? 1.08 : 1.0) }; if band == .junior && ["squat", "lunge", "squat_challenge", "burpee"].contains(category) { return 1.04 }; return 1.0 }

    static func requiredJoints(for category: String) -> [VNHumanBodyPoseObservation.JointName] {
        switch category {
        case "front_raise", "lateral_raise":
            return [.nose, .leftShoulder, .rightShoulder, .leftElbow, .rightElbow, .leftWrist, .rightWrist]
        case "jumping_jack":
            return [.nose, .leftShoulder, .rightShoulder, .leftHip, .rightHip, .leftAnkle, .rightAnkle, .leftWrist, .rightWrist]
        case "high_knee":
            return [.nose, .leftShoulder, .rightShoulder, .leftHip, .rightHip, .leftKnee, .rightKnee, .leftAnkle, .rightAnkle]
        case "sit_up":
            return [.nose, .leftShoulder, .rightShoulder, .leftHip, .rightHip, .leftKnee, .rightKnee, .leftWrist, .rightWrist]
        case "plank", "squat", "lunge", "squat_challenge", "burpee":
            return [.nose, .leftShoulder, .rightShoulder, .leftHip, .rightHip, .leftKnee, .rightKnee, .leftAnkle, .rightAnkle]
        default:
            return [.nose, .leftShoulder, .rightShoulder, .leftHip, .rightHip, .leftKnee, .rightKnee, .leftAnkle, .rightAnkle]
        }
    }
}

/// Numerically stable helpers for the live repetition model. Vision emits
/// occasional outliers when a wrist/ankle is occluded; a raw min/max or a
/// single-frame derivative would turn those into false repetitions. These
/// helpers deliberately drop non-finite samples and use a trimmed window so
/// the camera flow fails safe instead of producing a confident-looking count.
