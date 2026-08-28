import CoreGraphics
import Foundation

extension BodyCaptureQualityGate {
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

    static func adamsForwardBendCompletionScore(leftShoulderX: Double, leftShoulderY: Double, rightShoulderX: Double, rightShoulderY: Double, hipCenterY: Double) -> Double? {
        let values = [leftShoulderX, leftShoulderY, rightShoulderX, rightShoulderY, hipCenterY]
        guard values.allSatisfy(\.isFinite) else { return nil }
        let shoulderWidth = hypot(leftShoulderX - rightShoulderX, leftShoulderY - rightShoulderY)
        guard shoulderWidth >= 0.001 else { return nil }
        let shoulderCenterY = (leftShoulderY + rightShoulderY) / 2
        let verticalTorsoRatio = abs(shoulderCenterY - hipCenterY) / shoulderWidth
        return min(1, max(0, 1 - verticalTorsoRatio))
    }

    static func jointAngle(first: CGPoint, joint: CGPoint, third: CGPoint) -> Double? {
        let a = hypot(first.x - joint.x, first.y - joint.y)
        let b = hypot(third.x - joint.x, third.y - joint.y)
        let c = hypot(first.x - third.x, first.y - third.y)
        guard a.isFinite, b.isFinite, c.isFinite, a > 0.001, b > 0.001 else { return nil }
        let cosine = min(1, max(-1, (a * a + b * b - c * c) / (2 * a * b)))
        return acos(cosine) * 180 / .pi
    }

    static func hasAdamsLowerBodyPosition(kneeAngles: [Double], ankleGap: Double?, shoulderWidth: Double, requiresBothFeet: Bool) -> Bool {
        guard shoulderWidth.isFinite, shoulderWidth > 0.001,
              kneeAngles.count >= (requiresBothFeet ? 2 : 1),
              kneeAngles.allSatisfy({ $0.isFinite && $0 >= adamsMinimumKneeExtensionDegrees && $0 <= 180.5 }) else { return false }
        if requiresBothFeet && ankleGap == nil { return false }
        guard let ankleGap else { return true }
        return ankleGap.isFinite && ankleGap >= 0 && ankleGap <= max(0.045, shoulderWidth * 0.42)
    }
}
