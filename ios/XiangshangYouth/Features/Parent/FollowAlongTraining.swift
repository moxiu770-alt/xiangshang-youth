import SwiftUI
import AVKit
import AVFoundation
import UIKit
import Vision
import Darwin

private final class FollowAlongVoiceCoach {
    static let shared = FollowAlongVoiceCoach()
    private let speaker = AVSpeechSynthesizer()

    func say(_ text: String) {
        DispatchQueue.main.async {
            self.speaker.stopSpeaking(at: .immediate)
            let utterance = AVSpeechUtterance(string: text)
            utterance.voice = AVSpeechSynthesisVoice(language: "zh-CN")
            utterance.rate = 0.48
            self.speaker.speak(utterance)
        }
    }

    func stop() { speaker.stopSpeaking(at: .immediate) }
}

enum FollowAlongStage: String, Equatable {
    case setup = "起始位"
    case exertion = "发力位"
    case returnPhase = "回位"
}

enum FollowAlongCaptureState: String, Equatable {
    case waiting = "等待取景"
    case ready = "已就绪"
    case occluded = "关键点被遮挡"
    case outOfFrame = "请全身入框"
    case multiplePeople = "检测到多人"
    case error = "识别暂不可用"
}

enum FollowAlongSide: String, Equatable {
    case left = "左侧"
    case right = "右侧"
    case both = "双侧"
    case unknown = "待确认"
}

struct FollowAlongPoseFeedback: Equatable {
    let visible: Bool
    let active: Bool
    let message: String
    let confidence: Double
    let repCount: Int
    let qualityScore: Int
    /// Accumulated time while the pose stays inside the active movement gate.
    /// Keeping this in the analyzer (instead of deriving it from UI callbacks)
    /// makes timed exercises deterministic across dropped camera frames.
    let activeSeconds: Int
    let stage: FollowAlongStage
    let captureState: FollowAlongCaptureState
    let side: FollowAlongSide
    let rangePercent: Int
    let tempoScore: Int
    let comboCount: Int

    init(visible: Bool, active: Bool, message: String, confidence: Double, repCount: Int, qualityScore: Int, activeSeconds: Int = 0, stage: FollowAlongStage = .setup, captureState: FollowAlongCaptureState = .waiting, side: FollowAlongSide = .unknown, rangePercent: Int = 0, tempoScore: Int = 0, comboCount: Int = 0) {
        self.visible = visible
        self.active = active
        self.message = message
        self.confidence = confidence
        self.repCount = repCount
        self.qualityScore = qualityScore
        self.activeSeconds = activeSeconds
        self.stage = stage
        self.captureState = captureState
        self.side = side
        self.rangePercent = min(max(rangePercent, 0), 100)
        self.tempoScore = min(max(tempoScore, 0), 100)
        self.comboCount = max(comboCount, 0)
    }

    static let waiting = FollowAlongPoseFeedback(
        visible: false,
        active: false,
        message: "打开摄像头后，系统会给出动作提示",
        confidence: 0,
        repCount: 0,
        qualityScore: 0
    )
}

/// Evidence-informed child tuning. RepCount Part-B contains junior-school
/// simulated examination clips with cycle-level labels, but no universal
/// numeric threshold. We lower amplitude modestly for smaller bodies while
/// requiring stronger temporal confirmation and average confidence.
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
enum FollowAlongMotionMath {
    static func finite(_ values: [Double]) -> [Double] { values.filter { $0.isFinite } }

    static func median(_ values: [Double]) -> Double? {
        let sorted = finite(values).sorted()
        guard !sorted.isEmpty else { return nil }
        let middle = sorted.count / 2
        return sorted.count.isMultiple(of: 2) ? (sorted[middle - 1] + sorted[middle]) / 2 : sorted[middle]
    }

    static func trimmedRange(_ values: [Double], trimRatio: Double = 0.18) -> Double {
        let sorted = finite(values).sorted()
        guard sorted.count >= 2 else { return 0 }
        let trim = min(sorted.count / 2 - 1, max(0, Int((Double(sorted.count) * trimRatio).rounded(.down))))
        return max(0, sorted[sorted.count - 1 - trim] - sorted[trim])
    }

    static func robustMean(_ values: [Double], trimRatio: Double = 0.18) -> Double {
        let sorted = finite(values).sorted()
        guard !sorted.isEmpty else { return 0 }
        let trim = min(max(0, (sorted.count - 1) / 2), max(0, Int((Double(sorted.count) * trimRatio).rounded(.down))))
        let kept = Array(sorted.dropFirst(trim).dropLast(trim))
        return kept.isEmpty ? (median(sorted) ?? 0) : kept.reduce(0, +) / Double(kept.count)
    }

    static func qualityScore(confidence: Double, amplitude: Double, threshold: Double, noise: Double) -> Int {
        guard confidence.isFinite, amplitude.isFinite, threshold.isFinite, noise.isFinite, threshold > 0 else { return 0 }
        let amplitudeScore = min(1, max(0, amplitude / max(threshold, 0.01)))
        let stabilityScore = min(1, max(0, 1 - noise / max(threshold, 0.01)))
        return Int(min(100, max(0, (amplitudeScore * 52 + min(1, max(0, confidence)) * 38 + stabilityScore * 10).rounded())))
    }
}

/// Lightweight native equivalent of the source project's real-time motion
/// signal. It runs entirely on camera frames in memory and uses an adaptive
/// hysteresis gate to avoid counting noise as a repetition.
private final class FollowAlongPoseAnalyzer {
    private let request = VNDetectHumanBodyPoseRequest()
    private var category = "unknown"
    private var ageMonths: Int?
    private var profile = ChildFollowAlongTuning.profile(ageMonths: nil)
    private var actionProfile = ChildFollowAlongTuning.actionProfile(for: "unknown", profile: ChildFollowAlongTuning.profile(ageMonths: nil))
    private var callback: ((FollowAlongPoseFeedback) -> Void)?
    private var smoothedSignal: Double?
    private var stateReady = true
    private var lowConfidenceStreak = 0
    private var droppedSignalFrames = 0
    private var stableFrames = 0
    private var returnDropValidated = false
    private var returnSlopeValidated = false
    private var topSignalValue = 0.0
    private var reps = 0
    private var comboCount = 0
    private var lastRepAt = Date.distantPast
    private var lastTempoScore = 0
    private var topReachedAt: Date?
    private var returnTimeoutHintAt = Date.distantPast
    private var lastPublishAt = Date.distantPast
    private var signalHistory: [Double] = []
    private var derivativeHistory: [Double] = []
    private var confidenceHistory: [Double] = []
    private var previousSignal: Double?
    private var activeWindowStart: Date?
    private var activeAccumulated: TimeInterval = 0
    private var wasActive = false

    func update(category: String, ageMonths: Int?, callback: @escaping (FollowAlongPoseFeedback) -> Void) {
        let nextProfile = ChildFollowAlongTuning.profile(ageMonths: ageMonths)
        let nextActionProfile = ChildFollowAlongTuning.actionProfile(for: category, profile: nextProfile, ageMonths: ageMonths)
        if self.category != category || self.ageMonths != ageMonths || self.profile != nextProfile || self.actionProfile != nextActionProfile { reset() }
        self.category = category
        self.ageMonths = ageMonths
        self.profile = nextProfile
        self.actionProfile = nextActionProfile
        self.callback = callback
    }

    func reset() {
        resetSignal()
        lowConfidenceStreak = 0
        droppedSignalFrames = 0
        reps = 0
        comboCount = 0
        lastRepAt = .distantPast
        lastTempoScore = 0
        publish(FollowAlongPoseFeedback(visible: false, active: false, message: "准备开始动作记录…", confidence: 0, repCount: 0, qualityScore: 0), force: true)
    }

    func process(_ pixelBuffer: CVPixelBuffer, position: AVCaptureDevice.Position) {
        do {
                let orientation: CGImagePropertyOrientation = position == .front ? .leftMirrored : .right
                try VNImageRequestHandler(cvPixelBuffer: pixelBuffer, orientation: orientation).perform([self.request])
                let observations = self.request.results ?? []
                guard let observation = observations.first else {
                    self.resetSignal()
                    self.publish(FollowAlongPoseFeedback(visible: false, active: false, message: "请全身入镜，保持镜头稳定", confidence: 0, repCount: self.reps, qualityScore: 0, captureState: .outOfFrame))
                    return
                }
                if observations.count > 1 {
                    self.resetSignal()
                    self.publish(FollowAlongPoseFeedback(visible: false, active: false, message: "检测到多人，请只保留一名孩子在镜头内", confidence: 0, repCount: self.reps, qualityScore: 0, captureState: .multiplePeople), force: true)
                    return
                }
                let points = try observation.recognizedPoints(.all)
                let required = ChildFollowAlongTuning.requiredJoints(for: self.category)
                let confidenceValues = required.map { points[$0]?.confidence ?? 0 }
                let confidence = confidenceValues.isEmpty ? 0 : Double(confidenceValues.reduce(0, +)) / Double(confidenceValues.count)
                guard confidence.isFinite, (0...1).contains(confidence), confidence >= self.profile.minAverageConfidence,
                      required.allSatisfy({
                          let value = points[$0]?.confidence ?? 0
                          return value.isFinite && (0...1).contains(value) && value >= self.profile.minLandmarkConfidence
                      }) else {
                    if confidence < self.profile.minAverageConfidence * 0.85 || required.contains(where: { (points[$0]?.confidence ?? 0) < self.profile.minLandmarkConfidence * 0.85 }) {
                        if self.lowConfidenceStreak < 9 { self.lowConfidenceStreak += 1 } else { self.droppedSignalFrames += 1 }
                    } else { self.lowConfidenceStreak = 0 }
                    self.resetSignal()
                    let message = self.droppedSignalFrames >= 4 || self.lowConfidenceStreak >= 6 ? "姿态点波动较大，建议把身体离镜头远一些并站在画面正中" : "请让头、肩、髋和双脚完整入镜，站稳后开始确认动作"
                    self.publish(FollowAlongPoseFeedback(visible: false, active: false, message: message, confidence: confidence, repCount: self.reps, qualityScore: 0, captureState: confidence > 0.1 ? .occluded : .outOfFrame))
                    return
                }
                self.lowConfidenceStreak = 0
                self.confidenceHistory.append(confidence)
                if self.confidenceHistory.count > self.profile.confidenceWindowFrames { self.confidenceHistory.removeFirst(self.confidenceHistory.count - self.profile.confidenceWindowFrames) }
                let trimmedConfidence = FollowAlongMotionMath.robustMean(self.confidenceHistory, trimRatio: self.actionProfile.confidenceTrim)
                let rawSignal = self.signal(points)
                guard rawSignal.isFinite else {
                    self.publish(FollowAlongPoseFeedback(visible: false, active: false, message: "画面边界不完整，请调整位置后重试", confidence: confidence, repCount: self.reps, qualityScore: 0))
                    return
                }
                let smoothing = min(0.52, max(0.18, self.actionProfile.smoothAlpha))
                let signal = self.smoothedSignal.map { $0 * (1 - smoothing) + rawSignal * smoothing } ?? rawSignal
                self.smoothedSignal = signal
                let delta = (self.previousSignal.map { signal - $0 } ?? 0) * self.actionProfile.derivativeScale
                self.previousSignal = signal
                self.signalHistory.append(signal)
                self.derivativeHistory.append(abs(delta))
                let historyLimit = max(self.actionProfile.historyLen, self.actionProfile.requiredSignalHistoryFrames)
                if self.signalHistory.count > historyLimit { self.signalHistory.removeFirst(self.signalHistory.count - historyLimit) }
                if self.derivativeHistory.count > historyLimit { self.derivativeHistory.removeFirst(self.derivativeHistory.count - historyLimit) }
                guard self.signalHistory.count >= self.actionProfile.requiredSignalHistoryFrames && self.signalHistory.count >= self.actionProfile.minHistory else {
                    self.updateActiveWindow(active: false, now: .now)
                    self.publish(FollowAlongPoseFeedback(visible: true, active: false, message: "请保持预备姿势，正在确认动作范围…", confidence: confidence, repCount: self.reps, qualityScore: 0))
                    return
                }
                let (minimum, maximum) = self.robustBounds(self.signalHistory, trimScale: self.profile.outlierTrimRatio)
                let rawRange = maximum - minimum
                let rangeNoise = self.robustDerivative(self.derivativeHistory, trim: self.actionProfile.confidenceTrim)
                let rangeNoisePenalty = min(rangeNoise * self.actionProfile.rangeNoiseMultiplier, max(rawRange, 0.05) * 0.35)
                let noiseFloorRange = self.actionProfile.rangeNoiseMultiplier * rangeNoise
                let minRange = max(self.actionProfile.minSignalRange ?? self.minimumAmplitude, (self.actionProfile.minSignalRange ?? self.minimumAmplitude) * self.profile.dynamicGateFloor) + noiseFloorRange
                let dynamicRange = min(max(rawRange, minRange), (self.actionProfile.minSignalRange ?? self.minimumAmplitude) * self.profile.dynamicGateCeiling)
                let noiseRatio = rawRange > 0 ? rangeNoise / rawRange : 0
                let jitterGate = 1 + min(max(noiseRatio, 0), 0.55) * 0.55
                let jitterPadding = min(rangeNoisePenalty, dynamicRange * 0.28)
                if rawRange < minRange {
                    self.stateReady = true
                    self.stableFrames = 0
                    self.updateActiveWindow(active: false, now: .now)
                    let hint = self.category == "plank" ? "请保持标准支撑位，避免身体晃动" : (rawRange < minRange * 0.7 ? "先稳住站姿再做动作幅度，确认动作到位后开始下一次" : "动作幅度不够，请抬得更高/下蹲更稳")
                    self.publish(FollowAlongPoseFeedback(visible: true, active: false, message: hint, confidence: confidence, repCount: self.reps, qualityScore: 0))
                    return
                }
                let mean = self.signalHistory.reduce(0, +) / Double(self.signalHistory.count)
                let highGate = mean + dynamicRange * self.actionProfile.highGateRatio * jitterGate + jitterPadding
                let lowGate = mean - dynamicRange * self.actionProfile.lowGateRatio * jitterGate - jitterPadding
                let amplitude = abs(signal - mean)
                let activeThreshold = dynamicRange * self.actionProfile.activeGateRatio * jitterGate + jitterPadding
                let active = amplitude >= activeThreshold
                let quality = self.dynamicQualityScore(confidence: trimmedConfidence, amplitude: amplitude, range: dynamicRange, lowGate: lowGate, highGate: highGate, signal: signal)
                self.updateActiveWindow(active: active, now: .now)
                let now = Date()
                if !self.stateReady, let top = self.topReachedAt {
                    let maxWait = max(self.actionProfile.maxRepInterval, 0.9)
                    if now.timeIntervalSince(top) > maxWait {
                        self.stateReady = true; self.stableFrames = 0; self.topReachedAt = nil; self.returnDropValidated = false; self.returnSlopeValidated = false
                        if now.timeIntervalSince(self.returnTimeoutHintAt) > 1.8 { self.returnTimeoutHintAt = now; self.publish(FollowAlongPoseFeedback(visible: true, active: true, message: "先回到起始位并停1秒后再发起下一次。保持节奏", confidence: trimmedConfidence, repCount: self.reps, qualityScore: quality), force: true) }
                    }
                }
                if self.advanceGate(current: signal, highGate: highGate, lowGate: lowGate, now: now, delta: delta, trimmedConfidence: trimmedConfidence) {
                    if self.lastRepAt != .distantPast {
                        let interval = now.timeIntervalSince(self.lastRepAt)
                        let expected = max(self.actionProfile.minRepInterval, 0.45)
                        self.lastTempoScore = Int(min(max(1 - abs(interval - expected) / expected, 0), 1) * 100)
                        self.comboCount = interval <= expected * 1.8 ? self.comboCount + 1 : 1
                    } else {
                        self.comboCount = 1
                    }
                    self.reps += 1
                    self.lastRepAt = now
                    self.publish(FollowAlongPoseFeedback(visible: true, active: true, message: "动作完成 \(self.reps) 次 · 连击 \(self.comboCount)", confidence: confidence, repCount: self.reps, qualityScore: quality, activeSeconds: self.activeSeconds(at: now), stage: .returnPhase, captureState: .ready, side: self.dominantSide(points), rangePercent: Int(min(max(amplitude / max(dynamicRange, 0.001), 0), 1) * 100), tempoScore: self.lastTempoScore, comboCount: self.comboCount), force: true)
                }
                let text = self.correctionHint(points) ?? (active ? "动作进行中，保持动作到底再回位" : "请按示范幅度完成标准动作")
                self.publish(FollowAlongPoseFeedback(visible: true, active: active, message: text, confidence: confidence, repCount: self.reps, qualityScore: quality, activeSeconds: self.activeSeconds(at: now), stage: self.stateReady ? (active ? .exertion : .setup) : .returnPhase, captureState: .ready, side: self.dominantSide(points), rangePercent: Int(min(max(amplitude / max(dynamicRange, 0.001), 0), 1) * 100), tempoScore: self.lastTempoScore, comboCount: self.comboCount))
        } catch {
            resetSignal()
            publish(FollowAlongPoseFeedback(visible: false, active: false, message: "动作记录暂不可用，可继续手动记录", confidence: 0, repCount: reps, qualityScore: 0, captureState: .error))
        }
    }

    private func dominantSide(_ points: [VNHumanBodyPoseObservation.JointName: VNRecognizedPoint]) -> FollowAlongSide {
        guard category == "high_knee" || category == "front_raise" || category == "lateral_raise" else { return .both }
        let left = Double(points[.leftKnee]?.location.y ?? points[.leftWrist]?.location.y ?? 0)
        let right = Double(points[.rightKnee]?.location.y ?? points[.rightWrist]?.location.y ?? 0)
        let delta = abs(left - right)
        if delta < 0.06 { return .both }
        return left < right ? .left : .right
    }

    private func correctionHint(_ points: [VNHumanBodyPoseObservation.JointName: VNRecognizedPoint]) -> String? {
        func p(_ name: VNHumanBodyPoseObservation.JointName) -> CGPoint { points[name]?.location ?? .zero }
        switch category {
        case "squat", "lunge", "squat_challenge":
            let leftKnee = p(.leftKnee); let rightKnee = p(.rightKnee)
            let leftAnkle = p(.leftAnkle); let rightAnkle = p(.rightAnkle)
            if abs(leftKnee.x - leftAnkle.x) > 0.14 || abs(rightKnee.x - rightAnkle.x) > 0.14 { return "膝盖请对准脚尖，先稳住再下蹲" }
        case "front_raise", "lateral_raise":
            if abs(p(.leftShoulder).y - p(.rightShoulder).y) > 0.10 { return "肩膀保持同高，避免一侧耸肩" }
        case "plank":
            if abs(p(.leftShoulder).y - p(.leftHip).y) > 0.22 { return "收紧核心，肩髋尽量保持一条线" }
        default: break
        }
        return nil
    }

    private func resetSignal() {
        smoothedSignal = nil
        stateReady = true
        returnDropValidated = false
        returnSlopeValidated = false
        topSignalValue = 0
        stableFrames = 0
        signalHistory.removeAll(keepingCapacity: true)
        derivativeHistory.removeAll(keepingCapacity: true)
        confidenceHistory.removeAll(keepingCapacity: true)
        previousSignal = nil
        topReachedAt = nil
        returnTimeoutHintAt = .distantPast
        activeWindowStart = nil
        activeAccumulated = 0
        wasActive = false
    }

    private var minimumAmplitude: Double {
        actionProfile.minSignalRange ?? ChildFollowAlongTuning.minimumAmplitude(for: category, profile: profile)
    }

    private func robustBounds(_ samples: [Double], trimScale: Double) -> (Double, Double) {
        let sorted = samples.filter { $0.isFinite }.sorted()
        guard !sorted.isEmpty else { return (0, 1) }
        let scale = min(max(trimScale, 0.03), 0.50)
        let trim = min(sorted.count / 3, max(0, Int((Double(sorted.count) * 0.08 * scale).rounded(.down))))
        let lower = sorted[min(trim, sorted.count - 1)]
        let upper = sorted[max(0, sorted.count - 1 - trim)]
        return upper > lower ? (lower, upper) : (lower, lower + 0.0001)
    }

    private func robustDerivative(_ values: [Double], trim: Double) -> Double {
        let sorted = values.filter { $0.isFinite }.map { abs($0) }.sorted()
        guard sorted.count >= 6 else { return 0 }
        let ratio = min(max(trim, 0), 0.48)
        let trimCount = min(sorted.count / 2, max(0, Int((Double(sorted.count) * ratio).rounded(.down))))
        guard trimCount * 2 < sorted.count else { return sorted.reduce(0, +) / Double(sorted.count) }
        let kept = Array(sorted[trimCount..<(sorted.count - trimCount)])
        guard !kept.isEmpty else { return 0 }
        let median = kept[kept.count / 2]
        let deviations = kept.map { abs($0 - median) }.sorted()
        return (deviations[deviations.count / 2] * 1.4826).isFinite ? deviations[deviations.count / 2] * 1.4826 : 0
    }

    private func advanceGate(current: Double, highGate: Double, lowGate: Double, now: Date, delta: Double, trimmedConfidence: Double) -> Bool {
        let maxReturnWindow = actionProfile.maxRepInterval > 0 ? actionProfile.maxRepInterval : actionProfile.minRepInterval * 2.7
        if stateReady {
            if current >= highGate && delta >= actionProfile.derivativeMin {
                stableFrames += 1
                if stableFrames >= max(1, actionProfile.topHoldFrames + actionProfile.settlingFrames + actionProfile.stablePeakFrames - 2) {
                    stateReady = false; stableFrames = 0; topReachedAt = now; topSignalValue = current; returnDropValidated = false; returnSlopeValidated = false
                }
            } else if stableFrames > 0 { stableFrames = 0 }
            return false
        }
        if let top = topReachedAt, now.timeIntervalSince(top) > maxReturnWindow {
            stateReady = true; stableFrames = 0; topReachedAt = nil; returnDropValidated = false; returnSlopeValidated = false
            return false
        }
        topSignalValue = max(topSignalValue, current)
        if current <= lowGate {
            let dropRatio = min(max(actionProfile.minDropRatio, 0.12), 1.12)
            let requiredDrop = max(actionProfile.minDropAbsolute, max(topSignalValue - highGate, (actionProfile.minSignalRange ?? minimumAmplitude) * 1.1) * dropRatio)
            if topSignalValue - current >= requiredDrop { returnDropValidated = true }
            if trimmedConfidence >= actionProfile.returnConfidenceFloor && delta <= -actionProfile.derivativeMin * actionProfile.returnSlopeMinRatio { returnSlopeValidated = true }
            stableFrames = returnDropValidated && returnSlopeValidated ? stableFrames + 1 : 0
            if stableFrames >= max(1, actionProfile.returnHoldFrames + actionProfile.settlingFrames + actionProfile.stableReturnFrames - 2) && now.timeIntervalSince(lastRepAt) >= actionProfile.minRepInterval && now.timeIntervalSince(topReachedAt ?? now) <= maxReturnWindow && trimmedConfidence >= actionProfile.returnConfidenceFloor {
                stateReady = true; stableFrames = 0; topReachedAt = nil; returnDropValidated = false; returnSlopeValidated = false
                return true
            }
        } else if stableFrames > 0 { stableFrames = 0 }
        return false
    }

    private func dynamicQualityScore(confidence: Double, amplitude: Double, range: Double, lowGate: Double, highGate: Double, signal: Double) -> Int {
        let amplitudeScore = range <= 0 ? 0 : min(max(amplitude / range, 0), 1) * 100
        let center = (lowGate + highGate) / 2
        let width = max(highGate - lowGate, 0.001)
        let balance = min(max(1 - abs(signal - center) / (width * 0.5), 0), 1)
        let stability = actionProfile.qualityStabilityWeight * balance * 100 + (1 - actionProfile.qualityStabilityWeight) * min(max(confidence, 0), 1) * 100 * (1 - actionProfile.minConfidencePenalty)
        return Int(min(max(amplitudeScore * (1 - actionProfile.qualityStabilityWeight) + stability, 0), 100).rounded())
    }

    private func updateActiveWindow(active: Bool, now: Date) {
        if active {
            if !wasActive { activeWindowStart = now }
            wasActive = true
        } else {
            if wasActive, let start = activeWindowStart {
                activeAccumulated += max(0, now.timeIntervalSince(start))
            }
            activeWindowStart = nil
            wasActive = false
        }
    }

    private func activeSeconds(at now: Date) -> Int {
        let running = activeAccumulated + (wasActive ? max(0, now.timeIntervalSince(activeWindowStart ?? now)) : 0)
        return max(0, Int(running.rounded(.down)))
    }

    private func publish(_ feedback: FollowAlongPoseFeedback, force: Bool = false) {
        let now = Date()
        guard force || now.timeIntervalSince(lastPublishAt) >= 0.12 else { return }
        lastPublishAt = now
        DispatchQueue.main.async { [callback] in callback?(feedback) }
    }

    private func signal(_ points: [VNHumanBodyPoseObservation.JointName: VNRecognizedPoint]) -> Double {
        func y(_ name: VNHumanBodyPoseObservation.JointName) -> Double { Double(points[name]?.location.y ?? 0) }
        func point(_ name: VNHumanBodyPoseObservation.JointName) -> CGPoint { points[name]?.location ?? .zero }
        func angle(_ a: CGPoint, _ b: CGPoint, _ c: CGPoint) -> Double {
            let v1 = CGVector(dx: a.x - b.x, dy: a.y - b.y)
            let v2 = CGVector(dx: c.x - b.x, dy: c.y - b.y)
            let denom = sqrt((v1.dx * v1.dx + v1.dy * v1.dy) * (v2.dx * v2.dx + v2.dy * v2.dy))
            guard denom > 0.001 else { return 180 }
            let cosine = max(-1.0, min(1.0, Double((v1.dx * v2.dx + v1.dy * v2.dy) / denom)))
            return Darwin.acos(cosine) * 180 / .pi
        }
        let shouldersY = (y(.leftShoulder) + y(.rightShoulder)) / 2
        let wristsY = (y(.leftWrist) + y(.rightWrist)) / 2
        let hipsY = (y(.leftHip) + y(.rightHip)) / 2
        func x(_ name: VNHumanBodyPoseObservation.JointName) -> Double { Double(points[name]?.location.x ?? 0) }
        let shoulderCenter = CGPoint(x: (point(.leftShoulder).x + point(.rightShoulder).x) / 2, y: (point(.leftShoulder).y + point(.rightShoulder).y) / 2)
        let hipCenter = CGPoint(x: (point(.leftHip).x + point(.rightHip).x) / 2, y: (point(.leftHip).y + point(.rightHip).y) / 2)
        let torsoScale = max(0.05, hypot(shoulderCenter.x - hipCenter.x, shoulderCenter.y - hipCenter.y))
        switch category {
        case "squat", "lunge", "squat_challenge":
            return (180 - (angle(point(.leftHip), point(.leftKnee), point(.leftAnkle)) + angle(point(.rightHip), point(.rightKnee), point(.rightAnkle))) / 2) / 180
        case "front_raise", "lateral_raise":
            return (wristsY - shouldersY) / torsoScale
        case "high_knee":
            let leftLift = abs(y(.leftKnee) - hipsY) / torsoScale
            let rightLift = abs(y(.rightKnee) - hipsY) / torsoScale
            return max(leftLift, rightLift)
        case "sit_up", "plank":
            return abs(shouldersY - hipsY) / torsoScale
        case "jumping_jack", "burpee":
            // Feet opening is a horizontal movement; using ankle Y made jumping
            // jacks nearly invisible when both feet stayed on the same baseline.
            return abs(wristsY - hipsY) / torsoScale + abs(x(.leftAnkle) - x(.rightAnkle)) / torsoScale * 0.5
        default:
            return (wristsY - shouldersY) / torsoScale
        }
    }
}

/// The native equivalent of the source project's weekly follow-along plan.
/// Exercise definitions live here instead of in a view so the same plan can
/// later be replaced by a remote, age-aware recommendation response.
struct FollowAlongExercise: Identifiable, Hashable {
    enum Mode: Hashable { case timed, count }

    let id: String
    let title: String
    let icon: String
    let mode: Mode
    let target: Int
    let unit: String
    let cue: String
    /// Content operations can replace the asset and cadence without changing
    /// the pose analyzer or page layout when the approved template videos land.
    let videoAssetKey: String
    let cadenceSeconds: Double
    let ageRangeMonths: ClosedRange<Int>
    let tags: [String]

    init(id: String, title: String, icon: String, mode: Mode, target: Int, unit: String, cue: String, videoAssetKey: String = "FollowAlongTraining", cadenceSeconds: Double = 1.0, ageRangeMonths: ClosedRange<Int> = 72...216, tags: [String] = []) {
        self.id = id
        self.title = title
        self.icon = icon
        self.mode = mode
        self.target = target
        self.unit = unit
        self.cue = cue
        self.videoAssetKey = videoAssetKey
        self.cadenceSeconds = cadenceSeconds
        self.ageRangeMonths = ageRangeMonths
        self.tags = tags
    }
}

struct FollowAlongDay: Identifiable, Hashable {
    let id: Int
    let title: String
    let exercises: [FollowAlongExercise]
}

enum FollowAlongPlan {
    static let contentManifestVersion = "UY-CONTENT-MANIFEST-1.0"
    static let contentPolicy = "template-video-v1"
    static let days: [FollowAlongDay] = [
        FollowAlongDay(id: 1, title: "上肢唤醒", exercises: [
            .init(id: "front_raise", title: "前平举", icon: "figure.arms.open", mode: .count, target: 15, unit: "次", cue: "手臂抬到肩膀高度，保持呼吸平稳"),
            .init(id: "lateral_raise", title: "侧平举", icon: "figure.arms.open", mode: .count, target: 12, unit: "次", cue: "肩膀放松，手臂沿身体两侧打开")
        ]),
        FollowAlongDay(id: 2, title: "下肢基础", exercises: [
            .init(id: "squat", title: "深蹲", icon: "figure.strengthtraining.traditional", mode: .count, target: 20, unit: "次", cue: "膝盖对准脚尖，臀部向后坐"),
            .init(id: "lunge", title: "交替弓步", icon: "figure.walk", mode: .count, target: 12, unit: "次/腿", cue: "前脚踩稳，后膝缓慢下沉")
        ]),
        FollowAlongDay(id: 3, title: "恢复日", exercises: []),
        FollowAlongDay(id: 4, title: "全身燃脂", exercises: [
            .init(id: "jumping_jack", title: "开合跳", icon: "figure.jumprope", mode: .timed, target: 60, unit: "秒", cue: "手脚同时打开，落地时膝盖微屈"),
            .init(id: "high_knee", title: "高抬腿", icon: "figure.run", mode: .timed, target: 45, unit: "秒", cue: "上身保持挺直，膝盖抬到舒适高度")
        ]),
        FollowAlongDay(id: 5, title: "核心稳定", exercises: [
            .init(id: "plank", title: "平板支撑", icon: "figure.core.training", mode: .timed, target: 30, unit: "秒", cue: "肩、髋、脚踝保持一条线"),
            .init(id: "sit_up", title: "仰卧起坐", icon: "figure.core.training", mode: .count, target: 15, unit: "次", cue: "用腹部发力，颈部保持放松")
        ]),
        FollowAlongDay(id: 6, title: "综合挑战", exercises: [
            .init(id: "burpee", title: "波比跳", icon: "figure.highintensity.intervaltraining", mode: .count, target: 10, unit: "次", cue: "动作连贯，按孩子体力调整节奏"),
            .init(id: "squat_challenge", title: "深蹲挑战", icon: "figure.strengthtraining.traditional", mode: .count, target: 25, unit: "次", cue: "动作质量优先，不追求速度")
        ]),
        FollowAlongDay(id: 7, title: "恢复日", exercises: [])
    ]

    static func day(at index: Int) -> FollowAlongDay { days[((index % days.count) + days.count) % days.count] }
}

/// A native, video-led training session. It intentionally keeps the camera
/// optional: the child can follow the demonstration without granting camera
/// access, or turn on a self-preview for the same picture-in-picture workflow
/// used by the source project.
struct FollowAlongTrainingView: View {
    let studentID: String
    let studentName: String
    let dayIndex: Int
    let ageMonths: Int?
    let onComplete: () -> Void

    init(studentID: String = "", studentName: String, dayIndex: Int, ageMonths: Int? = nil, onComplete: @escaping () -> Void) {
        self.studentID = studentID
        self.studentName = studentName
        self.dayIndex = dayIndex
        self.ageMonths = ageMonths
        self.onComplete = onComplete
    }

    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @EnvironmentObject private var appState: AppState
    @State private var player: AVPlayer?
    @State private var selectedExercise = 0
    @State private var cameraEnabled = false
    @State private var cameraFront = true
    @State private var cameraPermissionMessage: String?
    @State private var isPlaying = false
    @State private var completed = false
    @State private var completionPulse = false
    @State private var startedAt: Date?
    @State private var exerciseProgress: [String: Int] = [:]
    @State private var poseFeedback = FollowAlongPoseFeedback.waiting
    @State private var visualRepCount = 0
    @State private var visualActiveSince: Date?
    @State private var speakerEnabled = true
    @State private var lastSpokenGuide = ""
    @State private var lastSpokenGuideAt = Date.distantPast
    @State private var exerciseQualityScores: [String: Int] = [:]
    @State private var showPartialCompletionAlert = false
    @State private var cameraUsedDuringSession = false
    @State private var visualUnits: [String: Int] = [:]
    @State private var manualUnits = 0
    @State private var sessionSaved = false

    private var day: FollowAlongDay { FollowAlongPlan.day(at: dayIndex) }
    private var videoURL: URL? { Bundle.main.url(forResource: "FollowAlongTraining", withExtension: "mp4") }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    header
                    if day.exercises.isEmpty {
                        recoveryCard
                    } else {
                        videoCard
                        exerciseList
                        safetyCard
                        if completed {
                            completionSummary
                        } else {
                            completeButton
                        }
                    }
                }
                .padding(16)
            }
            .background(ReferenceColor.canvas.ignoresSafeArea())
            .navigationTitle("训练跟练")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("关闭") { player?.pause(); dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        speakerEnabled.toggle()
                        appState.updateSettings(voiceGuidanceEnabled: speakerEnabled)
                        if !speakerEnabled { FollowAlongVoiceCoach.shared.stop() }
                    } label: {
                        Image(systemName: speakerEnabled ? "speaker.wave.2.fill" : "speaker.slash.fill")
                    }
                    .accessibilityLabel(speakerEnabled ? "关闭语音引导" : "开启语音引导")
                }
            }
        }
        .task {
            speakerEnabled = appState.localFeatures.settings.voiceGuidanceEnabled
            guard player == nil, let videoURL else { return }
            let item = AVPlayerItem(url: videoURL)
            let prepared = AVPlayer(playerItem: item)
            prepared.actionAtItemEnd = .none
            player = prepared
        }
        .onDisappear {
            player?.pause()
            FollowAlongVoiceCoach.shared.stop()
        }
        .onChange(of: selectedExercise) { _, _ in
            poseFeedback = .waiting
            visualRepCount = 0
            visualActiveSince = nil
            lastSpokenGuide = ""
            lastSpokenGuideAt = .distantPast
        }
        .alert("相机暂不可用", isPresented: Binding(get: { cameraPermissionMessage != nil }, set: { if !$0 { cameraPermissionMessage = nil } })) {
            Button("知道了", role: .cancel) { cameraPermissionMessage = nil }
        } message: {
            Text(cameraPermissionMessage ?? "请在系统设置中允许相机权限，或直接使用示范视频跟练。")
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("给 \(studentName) 的今日训练").font(.title3.bold()).foregroundStyle(ReferenceColor.navy)
                    Text("第 \(day.id) 天 · \(day.title)").font(.subheadline.weight(.semibold)).foregroundStyle(ReferenceColor.blue)
                }
                Spacer()
                Label("姿态友好", systemImage: "checkmark.shield.fill")
                    .font(.caption.weight(.semibold)).foregroundStyle(ReferenceColor.green)
            }
            Text(day.exercises.isEmpty ? "今天以恢复和身体感受记录为主，不需要强行训练。" : "先看示范，再打开摄像头跟着做。动作质量优先，出现不适请立即停止。")
                .font(.caption).foregroundStyle(.secondary)
        }
        .padding(16)
        .background(.white, in: RoundedRectangle(cornerRadius: 18))
    }

    private var videoCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("示范视频", systemImage: "play.rectangle.fill")
                    .font(.headline).foregroundStyle(ReferenceColor.navy)
                Spacer()
                Text("跟做模式").font(.caption.weight(.semibold)).foregroundStyle(.white)
                    .padding(.horizontal, 9).padding(.vertical, 5)
                    .background(ReferenceColor.blue, in: Capsule())
            }
            ZStack(alignment: .bottomTrailing) {
                if let player {
                    VideoPlayer(player: player)
                        .aspectRatio(9 / 16, contentMode: .fit)
                        .clipShape(RoundedRectangle(cornerRadius: 16))
                        .overlay(alignment: .topLeading) {
                            if cameraEnabled {
                                ZStack {
                                    FollowAlongCameraPreview(isFront: $cameraFront, category: selectedCategory, ageMonths: ageMonths, onFeedback: handlePoseFeedback, failed: { message in
                                        cameraEnabled = false
                                        cameraPermissionMessage = message
                                    })
                                    RoundedRectangle(cornerRadius: 10)
                                        .stroke(poseFeedback.visible ? (poseFeedback.active ? ReferenceColor.green : Color.white.opacity(0.9)) : Color.white.opacity(0.7), style: StrokeStyle(lineWidth: 1.5, dash: [5, 4]))
                                        .padding(7)
                                    VStack {
                                        HStack(spacing: 4) {
                                            Image(systemName: poseFeedback.visible ? "viewfinder.circle.fill" : "person.crop.rectangle")
                                            Text(poseFeedback.visible ? "全身入框" : "取景准备")
                                        }
                                        .font(.system(size: 12, weight: .semibold))
                                        .foregroundStyle(.white)
                                        .padding(.horizontal, 7)
                                        .padding(.vertical, 4)
                                        .background(.black.opacity(0.48), in: Capsule())
                                        Spacer()
                                    }
                                    .padding(8)
                                    .allowsHitTesting(false)
                                }
                                .frame(width: 118, height: 166)
                                .clipShape(RoundedRectangle(cornerRadius: 12))
                                .padding(10)
                                .transition(.opacity)
                            }
                        }
                } else {
                    ZStack {
                        RoundedRectangle(cornerRadius: 16).fill(ReferenceColor.navy.opacity(0.08))
                        VStack(spacing: 8) {
                            Image(systemName: "video.slash").font(.title2)
                            Text("示范视频加载失败，可稍后重试").font(.caption)
                        }.foregroundStyle(.secondary)
                    }
                    .aspectRatio(9 / 16, contentMode: .fit)
                }
                if player != nil {
                    Button {
                        togglePlayback()
                    } label: {
                        Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                            .font(.headline).foregroundStyle(.white).frame(width: 42, height: 42)
                            .background(ReferenceColor.blue, in: Circle())
                    }
                    .padding(14)
                    .accessibilityLabel(isPlaying ? "暂停示范视频" : "播放示范视频")
                }
            }
            HStack(spacing: 9) {
                Button {
                    requestCamera()
                } label: {
                    Label(cameraEnabled ? "关闭我的画面" : "打开我的画面", systemImage: cameraEnabled ? "video.slash" : "camera.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent).tint(ReferenceColor.blue)
                if cameraEnabled {
                    Button {
                        cameraFront.toggle()
                    } label: {
                        Image(systemName: "camera.rotate.fill")
                            .frame(width: 42, height: 36)
                    }
                    .buttonStyle(.bordered).tint(ReferenceColor.blue)
                    .accessibilityLabel(cameraFront ? "切换后置摄像头" : "切换前置摄像头")
                }
            }
            if startedAt != nil {
                TimelineView(.periodic(from: .now, by: 1)) { _ in
                    let elapsed = Int(player?.currentTime().seconds ?? 0)
                    Label("已跟做 \(elapsed / 60):\(String(format: "%02d", elapsed % 60))", systemImage: "timer")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            if cameraEnabled {
                HStack(spacing: 8) {
                    Circle()
                        .fill(poseFeedback.visible ? (poseFeedback.active ? ReferenceColor.green : .orange) : .gray)
                        .frame(width: 8, height: 8)
                    Text(poseFeedback.message).font(.caption).foregroundStyle(ReferenceColor.navy).lineLimit(2)
                    Spacer()
                Text("动作完成 \(visualRepCount) 次 · 连击 \(poseFeedback.comboCount) · \(poseFeedback.qualityScore)分").font(.caption.weight(.bold)).foregroundStyle(ReferenceColor.blue)
                }
                .padding(.horizontal, 4)
                cameraGuideCard
            }
        }
        .padding(12)
        .background(.white, in: RoundedRectangle(cornerRadius: 18))
    }

    private var exerciseList: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("今日动作").font(.headline).foregroundStyle(ReferenceColor.navy)
            ForEach(Array(day.exercises.enumerated()), id: \.element.id) { index, exercise in
                Button {
                    if reduceMotion { selectedExercise = index } else { withAnimation(.easeInOut(duration: 0.18)) { selectedExercise = index } }
                    speak("\(exercise.title)，目标 \(exercise.target)\(exercise.unit)。\(exercise.cue)")
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: exercise.icon).font(.title3).foregroundStyle(index == selectedExercise ? .white : ReferenceColor.blue)
                            .frame(width: 42, height: 42)
                            .background(index == selectedExercise ? ReferenceColor.blue : ReferenceColor.blue.opacity(0.10), in: RoundedRectangle(cornerRadius: 12))
                        VStack(alignment: .leading, spacing: 4) {
                            Text(exercise.title).font(.subheadline.bold()).foregroundStyle(ReferenceColor.navy)
                            Text(exercise.cue).font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.leading)
                        }
                        Spacer()
                        Text("\(exercise.target)\(exercise.unit)").font(.caption.weight(.bold)).foregroundStyle(ReferenceColor.blue)
                    }
                    .padding(12)
                    .background(index == selectedExercise ? ReferenceColor.blue.opacity(0.08) : .white, in: RoundedRectangle(cornerRadius: 14))
                    .overlay(RoundedRectangle(cornerRadius: 14).stroke(index == selectedExercise ? ReferenceColor.blue.opacity(0.35) : .clear, lineWidth: 1))
                }
                .buttonStyle(.plain)
            }
            selectedExerciseControl
        }
    }

    @ViewBuilder
    private var selectedExerciseControl: some View {
        if let exercise = day.exercises.indices.contains(selectedExercise) ? day.exercises[selectedExercise] : nil {
            let progress = exerciseProgress[exercise.id, default: 0]
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("跟做进度").font(.subheadline.bold()).foregroundStyle(ReferenceColor.navy)
                    Spacer()
                    Text("\(progress) / \(exercise.target) \(exercise.unit)").font(.caption.weight(.bold)).foregroundStyle(ReferenceColor.blue)
                }
                if poseFeedback.visible {
                    Label(poseFeedback.active ? "动作已开始" : "画面已就绪，等待动作幅度", systemImage: poseFeedback.active ? "viewfinder.circle.fill" : "viewfinder")
                        .font(.caption).foregroundStyle(poseFeedback.active ? ReferenceColor.green : .secondary)
                }
                ProgressView(value: min(Double(progress) / Double(max(exercise.target, 1)), 1)).tint(ReferenceColor.green)
                HStack(spacing: 9) {
                    Button {
                        recordExerciseProgress(exercise, amount: exercise.mode == .timed ? 10 : 1)
                    } label: {
                        Label(exercise.mode == .timed ? "手动记录 10 秒" : "手动记录 1 次", systemImage: "plus.circle.fill")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent).tint(ReferenceColor.blue)
                Button("本组完成") {
                        manualUnits += max(0, exercise.target - exerciseProgress[exercise.id, default: 0])
                        exerciseProgress[exercise.id] = exercise.target
                        startedAt = startedAt ?? .now
                        speak("\(exercise.title) 已完成，做得很好。")
                    }
                    .buttonStyle(.bordered).tint(ReferenceColor.green)
                }
                Text("手动记录仅用于补录，不计入视觉准确率。打开摄像头后会单独显示视觉确认数据。")
                    .font(.caption).foregroundStyle(.secondary)
            }
            .padding(13)
            .background(ReferenceColor.green.opacity(0.08), in: RoundedRectangle(cornerRadius: 14))
        }
    }

    private var safetyCard: some View {
        Label("家长陪同提示：保持镜头稳定、留出安全距离；孩子疲劳、疼痛或头晕时马上暂停。跟做数据只用于健康习惯记录，不构成医疗诊断。", systemImage: "heart.text.square.fill")
            .font(.caption).foregroundStyle(ReferenceColor.navy)
            .padding(13).background(ReferenceColor.blue.opacity(0.08), in: RoundedRectangle(cornerRadius: 14))
    }

    private var cameraGuideCard: some View {
        let exercise = day.exercises.indices.contains(selectedExercise) ? day.exercises[selectedExercise] : nil
        return VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 7) {
                Image(systemName: poseFeedback.visible ? "checkmark.shield.fill" : "scope")
                    .foregroundStyle(poseFeedback.visible ? ReferenceColor.green : ReferenceColor.blue)
                Text(poseFeedback.captureState == .ready ? "取景已就绪，跟随语音完成动作" : poseFeedback.captureState.rawValue)
                    .font(.subheadline.weight(.bold)).foregroundStyle(ReferenceColor.navy)
                Spacer()
                Text(poseFeedback.captureState == .ready ? "已连接" : "需调整")
                    .font(.caption.weight(.semibold)).foregroundStyle(poseFeedback.visible ? ReferenceColor.green : .secondary)
            }
            Text(poseFeedback.message)
                .font(.caption).foregroundStyle(.secondary)
                .lineLimit(2)
            phaseStrip
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text("动作范围").font(.caption.weight(.semibold)).foregroundStyle(ReferenceColor.navy)
                    Spacer()
                    Text("\(poseFeedback.rangePercent)% · \(poseFeedback.side.rawValue)").font(.caption.weight(.bold)).foregroundStyle(ReferenceColor.blue)
                }
                ProgressView(value: Double(poseFeedback.rangePercent), total: 100).tint(poseFeedback.rangePercent >= 70 ? ReferenceColor.green : ReferenceColor.blue)
                Text(poseFeedback.tempoScore > 0 ? "节奏匹配 \(poseFeedback.tempoScore)% · 跟随示范停顿后再回位" : "先跟随示范完成一整次，系统会校准你的节奏")
                    .font(.caption).foregroundStyle(.secondary)
            }
            if let exercise {
                TimelineView(.periodic(from: .now, by: 0.25)) { _ in
                    let position = max(player?.currentTime().seconds ?? 0, 0)
                    let cadence = max(exercise.cadenceSeconds, 0.4)
                    let beat = Int(position / cadence).quotientAndRemainder(dividingBy: 4).remainder + 1
                    Label("模板第 \(beat) 拍 · \(String(format: "%.1f", cadence)) 秒/拍 · 实时节拍同步", systemImage: "metronome")
                        .font(.caption.weight(.semibold)).foregroundStyle(ReferenceColor.blue)
                }
            }
            HStack(spacing: 6) {
                guideStep(number: "1", title: "竖屏", detail: "手机稳定")
                guideStep(number: "2", title: "全身", detail: "头肩髋脚")
                guideStep(number: "3", title: "准备", detail: "保持 2 秒")
            }
            if let exercise {
                Label("当前动作：\(exercise.title) · \(exercise.cue)", systemImage: "figure.run")
                    .font(.caption).foregroundStyle(ReferenceColor.navy)
                    .lineLimit(2)
            }
        }
        .padding(12)
        .background(ReferenceColor.blue.opacity(0.07), in: RoundedRectangle(cornerRadius: 14))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("动作引导。\(poseFeedback.message)。请竖屏、保持全身入框并静止两秒完成准备。")
    }

    private var phaseStrip: some View {
        HStack(spacing: 6) {
            ForEach([FollowAlongStage.setup, .exertion, .returnPhase], id: \.self) { stage in
                Text(stage.rawValue)
                    .font(.caption.weight(.bold))
                    .foregroundStyle(poseFeedback.stage == stage ? .white : ReferenceColor.navy)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
                    .background(poseFeedback.stage == stage ? ReferenceColor.blue : ReferenceColor.sky, in: Capsule())
            }
        }
        .animation(.easeInOut(duration: 0.18), value: poseFeedback.stage)
    }

    private func guideStep(number: String, title: String, detail: String) -> some View {
        HStack(spacing: 5) {
            Text(number).font(.caption.bold()).foregroundStyle(.white)
                .frame(width: 18, height: 18).background(ReferenceColor.blue, in: Circle())
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(.caption.bold()).foregroundStyle(ReferenceColor.navy)
                Text(detail).font(.system(size: 12)).foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var completeButton: some View {
        Button {
            if isPlanComplete {
                finishTraining()
            } else {
                showPartialCompletionAlert = true
            }
        } label: {
            Label(completed ? "今日跟做已完成" : "完成今日跟做", systemImage: completed ? "checkmark.circle.fill" : "flag.checkered")
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent).tint(ReferenceColor.green)
        .disabled(completed)
        .alert("还有动作未完成", isPresented: $showPartialCompletionAlert) {
            Button("继续训练", role: .cancel) { }
            Button("结束并保存") { finishTraining() }
        } message: {
            Text("当前只记录已完成的动作，确定现在结束本次跟做吗？")
        }
    }

    private var completionSummary: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "checkmark.seal.fill").font(.title2).foregroundStyle(ReferenceColor.green)
                Text("本次跟做已完成").font(.headline).foregroundStyle(ReferenceColor.navy)
                Spacer()
                Text("\(sessionQualityScore) 分").font(.headline.bold()).foregroundStyle(ReferenceColor.blue)
            }
            let total = day.exercises.reduce(0) { $0 + exerciseProgress[$1.id, default: 0] }
                Text("已记录 \(total) 个动作单位（视觉确认 \(visualUnitCount)，手动补录 \(manualUnits)）。完成度参考取景稳定度和动作幅度，仅用于训练反馈，不构成医疗判断。")
                .font(.caption).foregroundStyle(.secondary)
            Button("返回 28 天计划") { dismiss() }
                .frame(maxWidth: .infinity)
                .buttonStyle(.borderedProminent).tint(ReferenceColor.green)
        }
        .padding(15)
        .background(ReferenceColor.green.opacity(0.10), in: RoundedRectangle(cornerRadius: 16))
        .scaleEffect(completionPulse ? 1 : 0.92)
        .opacity(completionPulse ? 1 : 0.72)
        .onAppear {
            if reduceMotion {
                completionPulse = true
            } else {
                withAnimation(.spring(response: 0.45, dampingFraction: 0.72)) { completionPulse = true }
            }
        }
    }

    private var recoveryCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Image(systemName: "bed.double.fill").font(.system(size: 34)).foregroundStyle(ReferenceColor.blue)
            Text("今天是恢复日").font(.title3.bold()).foregroundStyle(ReferenceColor.navy)
            Text("做 5 分钟轻松呼吸、肩背舒展和户外散步即可。让身体恢复，是训练计划的一部分。")
                .font(.subheadline).foregroundStyle(.secondary)
            Button {
                completed = true
                saveSession()
                onComplete()
                dismiss()
            } label: {
                Label("记录今天已恢复", systemImage: "checkmark.circle.fill").frame(maxWidth: .infinity)
            }.buttonStyle(.borderedProminent).tint(ReferenceColor.green)
        }
        .padding(18).background(.white, in: RoundedRectangle(cornerRadius: 18))
    }

    private var selectedCategory: String {
        guard day.exercises.indices.contains(selectedExercise) else { return "unknown" }
        return day.exercises[selectedExercise].id
    }

    private func handlePoseFeedback(_ feedback: FollowAlongPoseFeedback) {
        poseFeedback = feedback
        if feedback.visible { cameraUsedDuringSession = true }
        speakGuide(feedback.message)
        guard let exercise = day.exercises.indices.contains(selectedExercise) ? day.exercises[selectedExercise] : nil else { return }
        exerciseQualityScores[exercise.id] = max(exerciseQualityScores[exercise.id, default: 0], feedback.qualityScore)
        if exercise.mode == .count {
            if feedback.repCount > visualRepCount {
                let delta = feedback.repCount - visualRepCount
                visualRepCount = feedback.repCount
                visualUnits[exercise.id] = max(visualUnits[exercise.id, default: 0], feedback.repCount)
                recordExerciseProgress(exercise, amount: delta, manual: false)
            }
        } else if feedback.active {
            if visualActiveSince == nil { visualActiveSince = .now; startedAt = startedAt ?? .now }
            let seconds = max(feedback.activeSeconds, Int(Date().timeIntervalSince(visualActiveSince ?? .now)))
            let next = min(exercise.target, seconds)
            visualUnits[exercise.id] = max(visualUnits[exercise.id, default: 0], next)
            if next > exerciseProgress[exercise.id, default: 0] { exerciseProgress[exercise.id] = next }
        } else {
            if exercise.mode == .timed, feedback.activeSeconds > exerciseProgress[exercise.id, default: 0] {
                exerciseProgress[exercise.id] = min(exercise.target, feedback.activeSeconds)
            }
            visualActiveSince = nil
        }
    }

    private func togglePlayback() {
        guard let player else { return }
        if isPlaying {
            player.pause()
            isPlaying = false
        } else {
            startedAt = startedAt ?? .now
            player.play()
            isPlaying = true
            speak("请跟随示范动作，保持安全距离。")
        }
    }

    private func recordExerciseProgress(_ exercise: FollowAlongExercise, amount: Int, manual: Bool = true) {
        let previous = exerciseProgress[exercise.id, default: 0]
        let next = min(exercise.target, previous + amount)
        exerciseProgress[exercise.id] = next
        if manual { manualUnits += max(0, next - previous) }
        startedAt = startedAt ?? .now
        speak(next >= exercise.target ? "\(exercise.title) 已达标，可以进入下一个动作。" : exercise.cue)
    }

    private func speak(_ message: String) {
        guard speakerEnabled else { return }
        FollowAlongVoiceCoach.shared.say(message)
    }

    private func speakGuide(_ message: String) {
        guard speakerEnabled, !message.isEmpty else { return }
        let now = Date()
        guard message != lastSpokenGuide || now.timeIntervalSince(lastSpokenGuideAt) >= 2.2 else { return }
        lastSpokenGuide = message
        lastSpokenGuideAt = now
        FollowAlongVoiceCoach.shared.say(message)
    }

    private var isPlanComplete: Bool {
        day.exercises.allSatisfy { exerciseProgress[$0.id, default: 0] >= $0.target }
    }

    private var sessionQualityScore: Int {
        let scores = day.exercises.compactMap { exerciseQualityScores[$0.id] }
        guard !scores.isEmpty else { return 0 }
        return Int((Double(scores.reduce(0, +)) / Double(scores.count)).rounded())
    }

    private var visualUnitCount: Int {
        visualUnits.values.reduce(0, +)
    }

    private func finishTraining() {
        completed = true
        saveSession()
        onComplete()
        speak("今日跟做完成，做得很好。")
    }

    private func saveSession() {
        guard !sessionSaved else { return }
        sessionSaved = true
        let totalTarget = day.exercises.reduce(0) { $0 + $1.target }
        let totalDone = day.exercises.reduce(0) { $0 + exerciseProgress[$1.id, default: 0] }
        let ratio = totalTarget > 0 ? min(max(Double(totalDone) / Double(totalTarget), 0), 1) : 1
        let duration = startedAt.map { max(0, Int(Date().timeIntervalSince($0))) } ?? 0
        let record = FollowAlongSessionRecord(
            id: UUID(), childID: studentID, dayID: day.id, completedAt: .now,
            durationSeconds: duration, completionRatio: ratio,
            qualityScore: sessionQualityScore, cameraVerified: cameraUsedDuringSession && !visualUnits.isEmpty,
            visualUnits: visualUnits, manualUnits: manualUnits,
            modelVersion: ChildFollowAlongTuning.algorithmVersion, mode: "guidedTraining"
        )
        appState.saveFollowAlongSession(record)
    }

    private func requestCamera() {
        if cameraEnabled {
            cameraEnabled = false
            return
        }
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            cameraEnabled = true
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { granted in
                DispatchQueue.main.async {
                    if granted { cameraEnabled = true }
                    else { cameraPermissionMessage = "请在系统设置中允许相机权限，或直接使用示范视频跟练。" }
                }
            }
        default:
            cameraPermissionMessage = "相机权限未开启。可前往系统设置允许相机，或直接使用示范视频跟练。"
        }
    }
}

private struct FollowAlongCameraPreview: UIViewRepresentable {
    @Binding var isFront: Bool
    let category: String
    let ageMonths: Int?
    let onFeedback: (FollowAlongPoseFeedback) -> Void
    let failed: (String) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(category: category, ageMonths: ageMonths, onFeedback: onFeedback, failed: failed) }

    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        view.backgroundColor = .black
        context.coordinator.attach(to: view, isFront: isFront, category: category, ageMonths: ageMonths)
        return view
    }

    func updateUIView(_ view: UIView, context: Context) {
        context.coordinator.update(isFront: isFront, category: category, ageMonths: ageMonths, onFeedback: onFeedback)
    }

    final class Coordinator: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate {
        private let session = AVCaptureSession()
        private let queue = DispatchQueue(label: "youth.follow-along-camera")
        private let analyzer = FollowAlongPoseAnalyzer()
        private var previewLayer: AVCaptureVideoPreviewLayer?
        private var currentFront: Bool?
        private var currentPosition: AVCaptureDevice.Position = .front
        private let failed: (String) -> Void

        init(category: String, ageMonths: Int?, onFeedback: @escaping (FollowAlongPoseFeedback) -> Void, failed: @escaping (String) -> Void) {
            self.failed = failed
            super.init()
            analyzer.update(category: category, ageMonths: ageMonths, callback: onFeedback)
        }

        func attach(to view: UIView, isFront: Bool, category: String, ageMonths: Int?) {
            let layer = AVCaptureVideoPreviewLayer(session: session)
            layer.videoGravity = .resizeAspectFill
            layer.frame = view.bounds
            view.layer.addSublayer(layer)
            previewLayer = layer
            update(isFront: isFront, category: category, ageMonths: ageMonths, onFeedback: nil)
        }

        func update(isFront: Bool, category: String, ageMonths: Int?, onFeedback: ((FollowAlongPoseFeedback) -> Void)?) {
            if let onFeedback { analyzer.update(category: category, ageMonths: ageMonths, callback: onFeedback) }
            guard currentFront != isFront || !session.isRunning else { return }
            currentFront = isFront
            queue.async { [weak self] in
                guard let self else { return }
                self.session.beginConfiguration()
                self.session.inputs.forEach { self.session.removeInput($0) }
                let position: AVCaptureDevice.Position = isFront ? .front : .back
                self.currentPosition = position
                guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: position) else {
                    self.session.commitConfiguration()
                    DispatchQueue.main.async { self.failed("找不到可用摄像头，请直接使用示范视频。") }
                    return
                }
                do {
                    let input = try AVCaptureDeviceInput(device: device)
                    if self.session.canAddInput(input) { self.session.addInput(input) }
                    if self.session.outputs.isEmpty {
                        let output = AVCaptureVideoDataOutput()
                        output.alwaysDiscardsLateVideoFrames = true
                        output.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]
                        output.setSampleBufferDelegate(self, queue: self.queue)
                        guard self.session.canAddOutput(output) else {
                            self.session.commitConfiguration()
                            DispatchQueue.main.async { self.failed("当前画面尚未稳定，请先调整位置后继续，或选择手动记录。") }
                            return
                        }
                        self.session.addOutput(output)
                    }
                    self.session.commitConfiguration()
                    self.session.startRunning()
                    DispatchQueue.main.async { self.previewLayer?.frame = self.previewLayer?.superlayer?.bounds ?? .zero }
                } catch {
                    self.session.commitConfiguration()
                    DispatchQueue.main.async { self.failed("相机启动失败，请检查权限后重试。") }
                }
            }
        }

        func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
            guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
            analyzer.process(pixelBuffer, position: currentPosition)
        }

        deinit {
            if session.isRunning { session.stopRunning() }
        }
    }
}
