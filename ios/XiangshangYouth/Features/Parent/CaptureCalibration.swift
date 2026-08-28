import SwiftUI
import CoreMotion
import Combine

struct CaptureDeviceAlignment: Equatable {
    let rollDegrees: Double
    let pitchDegrees: Double
    let isAvailable: Bool

    static let pending = CaptureDeviceAlignment(rollDegrees: 0, pitchDegrees: 0, isAvailable: false)

    var isLevel: Bool {
        isAvailable && abs(rollDegrees) <= CaptureCalibrationRules.maximumRollDegrees
            && abs(pitchDegrees) <= CaptureCalibrationRules.maximumPitchDegrees
    }
}

struct CaptureBodyAlignment: Equatable {
    let bodyDetected: Bool
    let distanceState: BodyCaptureQualityGate.BodyScaleState
    let centered: Bool
    let headReady: Bool
    let shouldersReady: Bool
    let hipsReady: Bool
    let kneesReady: Bool
    let feetReady: Bool

    static let waiting = CaptureBodyAlignment(
        bodyDetected: false,
        distanceState: .invalid,
        centered: false,
        headReady: false,
        shouldersReady: false,
        hipsReady: false,
        kneesReady: false,
        feetReady: false
    )

    var distanceReady: Bool { distanceState == .ready }
    var isReady: Bool {
        bodyDetected && distanceReady && centered && headReady && shouldersReady && hipsReady && kneesReady && feetReady
    }
}

enum CaptureCalibrationRules {
    /// Commercial fixed-pose capture uses a deliberately tighter gate than
    /// ordinary video guidance. These bounds gate collection only; they do
    /// not make a medical or accuracy claim.
    static let maximumRollDegrees = 2.0
    static let maximumPitchDegrees = 5.0

    static func deviceAlignment(gravityX: Double, gravityY: Double, gravityZ: Double) -> CaptureDeviceAlignment {
        guard [gravityX, gravityY, gravityZ].allSatisfy(\.isFinite) else { return .pending }
        let magnitude = sqrt(gravityX * gravityX + gravityY * gravityY + gravityZ * gravityZ)
        guard magnitude >= 0.5 else { return .pending }
        let x = gravityX / magnitude
        let y = gravityY / magnitude
        let z = gravityZ / magnitude
        let roll = atan2(x, -y) * 180 / .pi
        let pitch = atan2(z, max(hypot(x, y), 0.001)) * 180 / .pi
        return CaptureDeviceAlignment(rollDegrees: roll, pitchDegrees: pitch, isAvailable: true)
    }
}

@MainActor
final class CaptureDeviceAlignmentMonitor: ObservableObject {
    @Published private(set) var alignment: CaptureDeviceAlignment = .pending
    private let motion = CMMotionManager()

    func start() {
        guard !motion.isDeviceMotionActive else { return }
        motion.deviceMotionUpdateInterval = 1.0 / 20.0
        guard motion.isDeviceMotionAvailable else {
            alignment = .pending
            return
        }
        motion.startDeviceMotionUpdates(to: .main) { [weak self] data, _ in
            guard let self, let gravity = data?.gravity else { return }
            let next = CaptureCalibrationRules.deviceAlignment(
                gravityX: gravity.x,
                gravityY: gravity.y,
                gravityZ: gravity.z
            )
            guard next.isAvailable else { return }
            if self.alignment.isAvailable {
                self.alignment = CaptureDeviceAlignment(
                    rollDegrees: self.alignment.rollDegrees * 0.72 + next.rollDegrees * 0.28,
                    pitchDegrees: self.alignment.pitchDegrees * 0.72 + next.pitchDegrees * 0.28,
                    isAvailable: true
                )
            } else {
                self.alignment = next
            }
        }
    }

    func stop() {
        motion.stopDeviceMotionUpdates()
        alignment = .pending
    }

    deinit { motion.stopDeviceMotionUpdates() }
}

struct CaptureHumanCalibrationGuide: View {
    let task: BodyAssessmentRecord.CaptureTask
    let alignment: CaptureBodyAlignment
    let device: CaptureDeviceAlignment
    let recording: Bool

    var body: some View {
        GeometryReader { proxy in
            let guideHeight = min(proxy.size.height * 0.46, task == .footArch ? 300 : (task == .seatedPosture ? 300 : 430))
            let guideWidth = min(proxy.size.width * (task == .footArch ? 0.78 : 0.66), task == .seatedPosture ? 280 : 300)
            VStack(spacing: 10) {
                DeviceLevelBubble(alignment: device)
                Canvas { context, size in
                    let baseColor = alignment.isReady ? Color.green : Color.white.opacity(0.82)
                    let muted = Color.white.opacity(0.34)
                    func point(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: size.width * x, y: size.height * y) }
                    func line(_ a: CGPoint, _ b: CGPoint, color: Color? = nil, width: CGFloat = 3) {
                        var path = Path(); path.move(to: a); path.addLine(to: b)
                        context.stroke(path, with: .color(color ?? baseColor), style: StrokeStyle(lineWidth: width, lineCap: .round))
                    }
                    if task == .footArch {
                        let leftKnee = point(0.34, 0.14), rightKnee = point(0.66, 0.14)
                        let leftAnkle = point(0.36, 0.72), rightAnkle = point(0.64, 0.72)
                        let leftHeel = point(0.31, 0.84), rightHeel = point(0.59, 0.84)
                        let leftToe = point(0.47, 0.90), rightToe = point(0.75, 0.90)
                        line(leftKnee, leftAnkle, color: alignment.kneesReady ? .green : baseColor, width: 5)
                        line(rightKnee, rightAnkle, color: alignment.kneesReady ? .green : baseColor, width: 5)
                        line(leftAnkle, leftHeel, color: alignment.feetReady ? .green : baseColor, width: 5)
                        line(leftHeel, leftToe, color: alignment.feetReady ? .green : baseColor, width: 5)
                        line(rightAnkle, rightHeel, color: alignment.feetReady ? .green : baseColor, width: 5)
                        line(rightHeel, rightToe, color: alignment.feetReady ? .green : baseColor, width: 5)
                        for pointValue in [leftKnee, rightKnee, leftAnkle, rightAnkle, leftHeel, rightHeel, leftToe, rightToe] {
                            context.fill(Path(ellipseIn: CGRect(x: pointValue.x - 6, y: pointValue.y - 6, width: 12, height: 12)), with: .color(alignment.isReady ? .green : .yellow))
                        }
                    } else {
                    let showsAdamsPose = task == .forwardBend && recording
                    let head = point(0.5, task == .seatedPosture ? 0.20 : (showsAdamsPose ? 0.43 : 0.12))
                    let shoulderY: CGFloat = task == .seatedPosture ? 0.38 : (showsAdamsPose ? 0.49 : 0.30)
                    let hipY: CGFloat = task == .seatedPosture ? 0.68 : 0.55
                    let footY: CGFloat = 0.91
                    let leftShoulder = point(0.34, shoulderY), rightShoulder = point(0.66, shoulderY)
                    let leftHip = point(0.42, hipY), rightHip = point(0.58, hipY)
                    let isAdams = task == .forwardBend
                    let leftKnee = point(isAdams ? 0.47 : 0.40, task == .seatedPosture ? 0.82 : 0.73)
                    let rightKnee = point(isAdams ? 0.53 : 0.60, task == .seatedPosture ? 0.82 : 0.73)
                    let leftFoot = point(isAdams ? 0.47 : 0.39, footY), rightFoot = point(isAdams ? 0.53 : 0.61, footY)
                    let headRadius = min(size.width, size.height) * 0.07
                    context.stroke(Path(ellipseIn: CGRect(x: head.x - headRadius, y: head.y - headRadius, width: headRadius * 2, height: headRadius * 2)), with: .color(alignment.headReady ? .green : baseColor), lineWidth: 3)
                    line(point(0.5, head.y / size.height + (showsAdamsPose ? 0.025 : 0.07)), point(0.5, hipY), color: alignment.centered ? .green : baseColor)
                    line(leftShoulder, rightShoulder, color: alignment.shouldersReady ? .green : baseColor)
                    line(leftShoulder, point(isAdams ? 0.49 : 0.24, isAdams ? (showsAdamsPose ? 0.70 : 0.50) : (task == .seatedPosture ? 0.58 : 0.50)), color: alignment.shouldersReady ? .green : baseColor)
                    line(rightShoulder, point(isAdams ? 0.51 : 0.76, isAdams ? (showsAdamsPose ? 0.70 : 0.50) : (task == .seatedPosture ? 0.58 : 0.50)), color: alignment.shouldersReady ? .green : baseColor)
                    line(leftHip, rightHip, color: alignment.hipsReady ? .green : baseColor)
                    if task != .seatedPosture {
                        line(leftHip, leftKnee, color: alignment.kneesReady ? .green : baseColor)
                        line(rightHip, rightKnee, color: alignment.kneesReady ? .green : baseColor)
                        line(leftKnee, leftFoot, color: alignment.feetReady ? .green : baseColor)
                        line(rightKnee, rightFoot, color: alignment.feetReady ? .green : baseColor)
                    } else {
                        line(leftHip, point(0.35, 0.88), color: muted)
                        line(rightHip, point(0.65, 0.88), color: muted)
                    }
                    for (pointValue, ready) in [(head, alignment.headReady), (leftShoulder, alignment.shouldersReady), (rightShoulder, alignment.shouldersReady), (leftHip, alignment.hipsReady), (rightHip, alignment.hipsReady), (leftKnee, alignment.kneesReady), (rightKnee, alignment.kneesReady), (leftFoot, alignment.feetReady), (rightFoot, alignment.feetReady)] {
                        context.fill(Path(ellipseIn: CGRect(x: pointValue.x - 5, y: pointValue.y - 5, width: 10, height: 10)), with: .color(ready ? .green : .yellow))
                    }
                    }
                }
                .opacity(recording ? 0.42 : 1)
                .overlay {
                    RoundedRectangle(cornerRadius: 34)
                        .stroke(alignment.distanceReady ? Color.green.opacity(0.9) : Color.white.opacity(0.72), style: StrokeStyle(lineWidth: 2, dash: [9, 7]))
                }
                .frame(width: guideWidth, height: guideHeight)
                Text(task == .footArch
                     ? (recording ? "正在记录足部近景：保持双脚平行站稳" : "仅将双膝以下、双踝、足跟和双脚放入近景框")
                     : (recording
                        ? (task == .forwardBend ? "对准前屈轮廓：双脚并拢、双膝伸直、头部放松" : "正在记录：保持手机固定，按语音完成动作")
                        : "将头、肩、髋、膝和双脚对准标定点"))
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(alignment.isReady ? .green : .white)
                    .padding(.horizontal, 12).padding(.vertical, 7)
                    .background(.black.opacity(0.50), in: Capsule())
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .offset(y: -44)
        }
        .ignoresSafeArea()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("采集标定。手机\(device.isLevel ? "已校正" : "未校正")，\(task == .footArch ? "足部近景" : "人体")\(alignment.isReady ? "已对齐" : "未完全对齐")")
    }
}

private struct DeviceLevelBubble: View {
    let alignment: CaptureDeviceAlignment

    var body: some View {
        HStack(spacing: 8) {
            ZStack {
                Circle().stroke(.white.opacity(0.55), lineWidth: 1)
                Circle().fill(alignment.isLevel ? .green : .yellow)
                    .frame(width: 9, height: 9)
                    .offset(
                        x: CGFloat(min(max(alignment.rollDegrees, -10), 10)) * 1.2,
                        y: CGFloat(min(max(alignment.pitchDegrees, -10), 10)) * 1.2
                    )
                Rectangle().fill(.white.opacity(0.45)).frame(width: 1, height: 28)
                Rectangle().fill(.white.opacity(0.45)).frame(width: 28, height: 1)
            }
            .frame(width: 34, height: 34)
            VStack(alignment: .leading, spacing: 1) {
                Text(alignment.isLevel ? "手机角度已校正" : "请调平手机")
                    .font(.system(size: 13, weight: .bold))
                Text(alignment.isAvailable ? "左右 \(Int(alignment.rollDegrees.rounded()))° · 前后 \(Int(alignment.pitchDegrees.rounded()))°" : "正在读取陀螺仪")
                    .font(.system(size: 12, weight: .medium)).opacity(0.75)
            }
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 12).padding(.vertical, 7)
        .background(.black.opacity(0.50), in: Capsule())
    }
}

struct CaptureCalibrationStatusRow: View {
    let cameraReady: Bool
    let deviceReady: Bool
    let bodyReady: Bool

    var body: some View {
        HStack(spacing: 6) {
            item("相机", ready: cameraReady, icon: "camera.fill")
            item("手机角度", ready: deviceReady, icon: "gyroscope")
            item("人体对齐", ready: bodyReady, icon: "figure.stand")
        }
    }

    private func item(_ title: String, ready: Bool, icon: String) -> some View {
        Label(title, systemImage: ready ? "checkmark.circle.fill" : icon)
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(ready ? .green : .white.opacity(0.72))
            .frame(maxWidth: .infinity, minHeight: 30)
            .background(.white.opacity(0.07), in: Capsule())
    }
}
