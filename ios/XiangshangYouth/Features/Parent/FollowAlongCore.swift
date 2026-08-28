import SwiftUI
import AVKit
import AVFoundation
import UIKit
import Vision
import Darwin

final class FollowAlongVoiceCoach {
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
final class FollowAlongPoseAnalyzer {
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
                let framing = self.framingSpans(points)
                guard BodyCaptureQualityGate.hasComfortableFollowAlongFraming(bodySpan: framing.body, torsoSpan: framing.torso) else {
                    self.resetSignal()
                    self.publish(FollowAlongPoseFeedback(
                        visible: false,
                        active: false,
                        message: "人物离镜头太近，请后退两步，保持头顶、双手和双脚都留有空间",
                        confidence: confidence,
                        repCount: self.reps,
                        qualityScore: 0,
                        captureState: .outOfFrame
                    ), force: true)
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
                    self.publish(FollowAlongPoseFeedback(visible: true, active: true, message: "辅助计数 \(self.reps) 次 · 连击 \(self.comboCount)（待人工验证）", confidence: confidence, repCount: self.reps, qualityScore: quality, activeSeconds: self.activeSeconds(at: now), stage: .returnPhase, captureState: .ready, side: self.dominantSide(points), rangePercent: Int(min(max(amplitude / max(dynamicRange, 0.001), 0), 1) * 100), tempoScore: self.lastTempoScore, comboCount: self.comboCount), force: true)
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

    /// Estimate camera distance without using face size. Torso span catches an
    /// upper-body close-up, while nose-to-ankle span also works for horizontal
    /// exercises such as planks and sit-ups.
    private func framingSpans(_ points: [VNHumanBodyPoseObservation.JointName: VNRecognizedPoint]) -> (body: Double?, torso: Double?) {
        func reliable(_ name: VNHumanBodyPoseObservation.JointName) -> CGPoint? {
            guard let point = points[name], point.confidence >= profile.minLandmarkConfidence * 0.75 else { return nil }
            return point.location
        }
        let shoulders = [reliable(.leftShoulder), reliable(.rightShoulder)].compactMap { $0 }
        let hips = [reliable(.leftHip), reliable(.rightHip)].compactMap { $0 }
        let torso: Double? = shoulders.isEmpty || hips.isEmpty ? nil : {
            let shoulder = CGPoint(x: shoulders.map(\.x).reduce(0, +) / CGFloat(shoulders.count), y: shoulders.map(\.y).reduce(0, +) / CGFloat(shoulders.count))
            let hip = CGPoint(x: hips.map(\.x).reduce(0, +) / CGFloat(hips.count), y: hips.map(\.y).reduce(0, +) / CGFloat(hips.count))
            return hypot(Double(shoulder.x - hip.x), Double(shoulder.y - hip.y))
        }()
        let ankles = [reliable(.leftAnkle), reliable(.rightAnkle)].compactMap { $0 }
        let body: Double? = reliable(.nose).flatMap { nose in
            guard !ankles.isEmpty else { return nil }
            let ankle = CGPoint(x: ankles.map(\.x).reduce(0, +) / CGFloat(ankles.count), y: ankles.map(\.y).reduce(0, +) / CGFloat(ankles.count))
            return hypot(Double(nose.x - ankle.x), Double(nose.y - ankle.y))
        }
        return (body, torso)
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
