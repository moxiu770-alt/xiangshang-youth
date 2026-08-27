import SwiftUI
import UIKit
import AVFoundation
import Vision

/// Real-time, on-device posture quality capture. Frames are analysed in memory
/// only; the app never writes a photo or a video to the user's library.
struct LiveVisionCaptureSheet: View {
    let task: BodyAssessmentRecord.CaptureTask
    let measuredHeightCm: Double
    let ageMonths: Int?
    let completed: (CaptureReview) -> Void
    let cancelled: () -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @EnvironmentObject private var appState: AppState
    @State private var usesFrontCamera = false
    @State private var guidance = "正在启动相机…"
    @State private var speaksGuidance = true
    @State private var captureProgress = 0.0
    /// A lens switch is asynchronous. Never arm the quality gate against the
    /// outgoing camera's final frames while the new input is still binding.
    @State private var cameraReady = false
    @State private var cameraError: String?
    @State private var captureArmed = false
    private var taskIndex: Int {
        (BodyAssessmentRecord.CaptureTask.allCases.firstIndex(of: task) ?? 0) + 1
    }
    private var phaseIndex: Int {
        if !captureArmed { return 0 }
        if captureProgress < 0.65 { return 1 }
        return 2
    }

    var body: some View {
        ZStack {
            LiveVisionPreview(task: task, measuredHeightCm: measuredHeightCm, ageMonths: ageMonths, usesFrontCamera: usesFrontCamera, speaksGuidance: speaksGuidance, captureArmed: $captureArmed, cameraReady: $cameraReady, guidance: $guidance, captureProgress: $captureProgress, failed: { message in
                cameraError = message
            }, interrupted: {
                captureArmed = false
                captureProgress = 0
            }) { review in
                completed(review)
                dismiss()
            }
            .ignoresSafeArea()

            LinearGradient(colors: [.black.opacity(0.52), .clear, .black.opacity(0.60)], startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea().allowsHitTesting(false)

            LiveBodyGuideOverlay(task: task)
                .allowsHitTesting(false)

            VStack(spacing: 16) {
                HStack(spacing: 10) {
                    Button {
                        cancelled()
                        dismiss()
                    } label: {
                        Image(systemName: "xmark").font(.headline).frame(width: 48, height: 48)
                            .background(.ultraThinMaterial, in: Circle())
                    }
                    .accessibilityLabel("关闭姿态记录")
                    Spacer()
                    VStack(spacing: 2) {
                        Text("动作 \(taskIndex) / \(BodyAssessmentRecord.CaptureTask.allCases.count)")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.72))
                        Text(task.title)
                            .font(.system(size: 16, weight: .bold))
                            .foregroundStyle(.white)
                    }
                    .accessibilityElement(children: .combine)
                    Spacer()
                    Button { speaksGuidance.toggle() } label: {
                        Image(systemName: speaksGuidance ? "speaker.wave.2.fill" : "speaker.slash.fill").font(.headline).frame(width: 48, height: 48)
                            .background(.ultraThinMaterial, in: Circle())
                    }
                    .accessibilityLabel(speaksGuidance ? "关闭语音指导" : "开启语音指导")
                    Button {
                        captureArmed = false
                        captureProgress = 0
                        cameraReady = false
                        usesFrontCamera.toggle()
                    } label: {
                        Image(systemName: "camera.rotate.fill").font(.headline).frame(width: 48, height: 48)
                            .background(.ultraThinMaterial, in: Circle())
                    }
                    .accessibilityLabel(usesFrontCamera ? "切换为后置摄像头" : "切换为前置摄像头")
                }
                .foregroundStyle(.white).padding(.horizontal, 16).padding(.top, 10)

                Spacer()
                VStack(spacing: 12) {
                    Text(task.instruction)
                        .font(.system(size: 15, weight: .semibold))
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                    HStack(spacing: 6) {
                        capturePhase("站位", index: 0)
                        capturePhase("保持", index: 1)
                        capturePhase("完成", index: 2)
                    }
                    HStack(alignment: .top, spacing: 9) {
                        Image(systemName: guidanceIcon)
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(.yellow)
                            .frame(width: 22)
                        Text(guidance)
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(.white)
                            .multilineTextAlignment(.leading)
                            .fixedSize(horizontal: false, vertical: true)
                        Spacer(minLength: 0)
                    }
                    .padding(11)
                    .background(.white.opacity(0.10), in: RoundedRectangle(cornerRadius: 12, style: .continuous))

                    VStack(spacing: 6) {
                        ProgressView(value: captureProgress).tint(.yellow)
                        HStack {
                            Text(!cameraReady ? "正在连接摄像头" : captureArmed ? "稳定度 \(Int(captureProgress * 100))%" : "取景完成后开始记录")
                            Spacer()
                            Label("不保存原始画面", systemImage: "lock.fill")
                        }
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.white.opacity(0.72))
                    }
                    if captureArmed {
                        HStack(spacing: 9) {
                            ProgressView().tint(.yellow)
                            Text("正在记录，请保持动作稳定")
                                .font(.system(size: 15, weight: .semibold))
                        }
                        .foregroundStyle(.yellow)
                        .frame(maxWidth: .infinity, minHeight: 50)
                    } else {
                        Button {
                            captureProgress = 0
                            captureArmed = true
                            if speaksGuidance { VoiceCoach.shared.say("开始记录，请保持当前姿势。") }
                        } label: {
                            Label("开始记录", systemImage: "record.circle.fill")
                                .font(.system(size: 16, weight: .bold))
                                .frame(maxWidth: .infinity, minHeight: 50)
                        }
                        .buttonStyle(.borderedProminent)
                        .buttonBorderShape(.roundedRectangle(radius: 13))
                        .tint(.yellow).foregroundStyle(.black)
                        .disabled(!cameraReady)
                        .accessibilityHint("确认孩子已按当前动作站好后开始记录")
                    }
                }
                .foregroundStyle(.white)
                .padding(16)
                .frame(maxWidth: .infinity)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).stroke(.white.opacity(0.18), lineWidth: 0.75))
                .padding(.horizontal, 16).padding(.bottom, 20)
            }
            .allowsHitTesting(cameraError == nil)

            if cameraError != nil {
                Color.black.opacity(0.38).ignoresSafeArea()
                VStack(spacing: 14) {
                    Image(systemName: "camera.fill.badge.ellipsis").font(.system(size: 30)).foregroundStyle(.yellow)
                    Text("暂时无法启动相机").font(.headline)
                    Text(cameraError ?? "请检查相机权限后重试。").font(.subheadline).multilineTextAlignment(.center).foregroundStyle(.secondary)
                    HStack {
                        if (cameraError ?? "").contains("权限"), let settings = URL(string: UIApplication.openSettingsURLString) {
                            Button("前往设置") { UIApplication.shared.open(settings) }.buttonStyle(.borderedProminent)
                        }
                    Button("重试") {
                        cameraError = nil
                        captureArmed = false
                        captureProgress = 0
                        cameraReady = false
                        usesFrontCamera.toggle()
                    }.buttonStyle(.bordered)
                    }
                }
                .padding(22).frame(maxWidth: 310).background(.regularMaterial, in: RoundedRectangle(cornerRadius: 24))
                .zIndex(2)
            }
        }
        .onAppear {
            speaksGuidance = appState.localFeatures.settings.voiceGuidanceEnabled
            if speaksGuidance { VoiceCoach.shared.say("开始\(task.title)。\(task.instruction)。请让孩子全身入镜。") }
        }
        .onChange(of: speaksGuidance) { _, enabled in if !enabled { VoiceCoach.shared.stop() } }
        // A capture must never span an app interruption. Returning from a
        // phone call, Control Center, or the background deliberately requires
        // the parent to confirm the child is still in the correct pose.
        .onChange(of: scenePhase) { _, phase in
            guard phase != .active else { return }
            if captureArmed {
                captureArmed = false
                captureProgress = 0
                guidance = "记录已暂停，返回后请确认动作并重新开始。"
            }
            cameraReady = false
            VoiceCoach.shared.stop()
        }
        .onDisappear { VoiceCoach.shared.stop() }
    }

    private var guidanceIcon: String {
        if !cameraReady { return "camera.aperture" }
        if guidance.contains("光线") { return "sun.max.fill" }
        if guidance.contains("多人") { return "person.2.slash.fill" }
        if guidance.contains("距离") || guidance.contains("入镜") { return "viewfinder" }
        if guidance.contains("遮挡") { return "eye.slash.fill" }
        return captureArmed ? "waveform.path.ecg" : "figure.stand"
    }

    private func capturePhase(_ title: String, index: Int) -> some View {
        HStack(spacing: 5) {
            Image(systemName: index < phaseIndex ? "checkmark.circle.fill" : index == phaseIndex ? "circle.inset.filled" : "circle")
            Text(title)
        }
        .font(.system(size: 12, weight: .semibold))
        .foregroundStyle(index <= phaseIndex ? .yellow : .white.opacity(0.52))
        .frame(maxWidth: .infinity, minHeight: 30)
        .background(.white.opacity(index == phaseIndex ? 0.12 : 0.05), in: Capsule())
        .accessibilityLabel("\(title)，\(index < phaseIndex ? "已完成" : index == phaseIndex ? "当前阶段" : "未开始")")
    }
}

/// A deliberately neutral framing guide: it verifies framing quality without
/// implying that a body outline is a diagnosis or a score.
private struct LiveBodyGuideOverlay: View {
    let task: BodyAssessmentRecord.CaptureTask

    var body: some View {
        GeometryReader { proxy in
            // Keep the guide clear of the bottom guidance panel on short
            // phones and landscape. The original fixed-height target could
            // leave no visible space for the start button on compact screens.
            let aspectRatio = task == .seatedPosture ? 0.88 : 1.48
            let preferredWidth = min(proxy.size.width * 0.74, 330)
            let height = min(preferredWidth * aspectRatio, max(160, proxy.size.height * 0.43))
            let width = min(preferredWidth, height / aspectRatio)
            VStack(spacing: 10) {
                Text(task == .gaitVideo ? "从框内自然走过，完成 3 步" : "请将孩子完整置于引导框内")
                    .font(.caption.weight(.semibold))
                    .padding(.horizontal, 12).padding(.vertical, 7)
                    .background(.black.opacity(0.42), in: Capsule())
                ZStack {
                    RoundedRectangle(cornerRadius: 30)
                        .stroke(.white.opacity(0.92), style: StrokeStyle(lineWidth: 2, dash: [9, 7]))
                    VStack(spacing: 10) {
                        Image(systemName: task == .gaitVideo ? "arrow.left.and.right" : task == .forwardBend ? "figure.flexibility" : "figure.stand")
                            .font(.system(size: 46, weight: .light))
                        Text(frameInstruction)
                            .font(.caption.weight(.medium))
                    }
                    .foregroundStyle(.white.opacity(0.82))
                }
                .frame(width: width, height: height)
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .offset(y: -38)
        }
        .ignoresSafeArea()
    }

    private var frameInstruction: String {
        switch task {
        case .seatedPosture: "肩部与髋部入镜"
        case .forwardBend: "侧后方入镜，躯干前倾后停住"
        case .gaitVideo, .standingBack: "头、肩、髋与双脚入镜"
        }
    }
}

private struct LiveVisionPreview: UIViewControllerRepresentable {
    let task: BodyAssessmentRecord.CaptureTask
    let measuredHeightCm: Double
    let ageMonths: Int?
    let usesFrontCamera: Bool
    let speaksGuidance: Bool
    @Binding var captureArmed: Bool
    @Binding var cameraReady: Bool
    @Binding var guidance: String
    @Binding var captureProgress: Double
    let failed: (String) -> Void
    let interrupted: () -> Void
    let completed: (CaptureReview) -> Void

    func makeUIViewController(context: Context) -> LiveVisionCaptureController {
        let controller = LiveVisionCaptureController()
        controller.onGuidance = { value in
            DispatchQueue.main.async { guidance = value }
        }
        controller.onProgress = { value in
            DispatchQueue.main.async { captureProgress = value }
        }
        controller.onCameraReady = { value in
            DispatchQueue.main.async { cameraReady = value }
        }
        controller.onFailure = { message in DispatchQueue.main.async { failed(message) } }
        controller.onInterrupted = { DispatchQueue.main.async { interrupted() } }
        controller.onCompleted = { review in DispatchQueue.main.async { completed(review) } }
        controller.configure(task: task, measuredHeightCm: measuredHeightCm, ageMonths: ageMonths, usesFrontCamera: usesFrontCamera, speaksGuidance: speaksGuidance, captureArmed: captureArmed)
        return controller
    }
    func updateUIViewController(_ controller: LiveVisionCaptureController, context: Context) {
        controller.configure(task: task, measuredHeightCm: measuredHeightCm, ageMonths: ageMonths, usesFrontCamera: usesFrontCamera, speaksGuidance: speaksGuidance, captureArmed: captureArmed)
    }
}

private final class LiveVisionCaptureController: UIViewController, AVCaptureVideoDataOutputSampleBufferDelegate {
    private let session = AVCaptureSession()
    private let sessionQueue = DispatchQueue(label: "youth.vision.capture")
    private let visionQueue = DispatchQueue(label: "youth.vision.analysis")
    private let previewLayer = AVCaptureVideoPreviewLayer()
    private var currentPosition: AVCaptureDevice.Position?
    private var stableFrames = 0
    private var stableSince: Date?
    private var firstHipLocation: CGPoint?
    private var didFinish = false
    private var lastGuidance = ""
    private var lastGuidanceSpokenAt = Date.distantPast
    private var lifecycleObservers: [NSObjectProtocol] = []
    private var task: BodyAssessmentRecord.CaptureTask = .standingBack
    private var measuredHeightCm: Double = 0
    private var ageMonths: Int?
    private var speaksGuidance = true
    private var captureArmed = false
    // AVCapture delivers to a serial Vision queue. Reusing the request avoids
    // allocating a pose request for every video frame during a short task.
    private let poseRequest = VNDetectHumanBodyPoseRequest()
    private var metricSamples: [PoseMetricSample] = []
    private var displacementWindow: [Double] = []
    private var gaitMotionWindow: [Bool] = []

    var onGuidance: ((String) -> Void)?
    var onProgress: ((Double) -> Void)?
    var onCameraReady: ((Bool) -> Void)?
    var onFailure: ((String) -> Void)?
    var onInterrupted: (() -> Void)?
    var onCompleted: ((CaptureReview) -> Void)?

    override func viewDidLoad() {
        super.viewDidLoad()
        previewLayer.videoGravity = .resizeAspectFill
        previewLayer.frame = view.bounds
        view.layer.addSublayer(previewLayer)
        observeSystemCaptureInterruptions()
    }
    override func viewDidLayoutSubviews() { super.viewDidLayoutSubviews(); previewLayer.frame = view.bounds }
    override func viewWillAppear(_ animated: Bool) { super.viewWillAppear(animated); requestCamera() }
    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        // A dismissed sheet must never leave an armed capture or an enabled
        // button behind while AVCapture winds down on its own serial queue.
        captureArmed = false
        resetStability()
        onCameraReady?(false)
        sessionQueue.async { self.session.stopRunning() }
    }
    deinit { lifecycleObservers.forEach(NotificationCenter.default.removeObserver) }

    private func observeSystemCaptureInterruptions() {
        let center = NotificationCenter.default
        lifecycleObservers.append(center.addObserver(forName: AVCaptureSession.wasInterruptedNotification, object: session, queue: .main) { [weak self] _ in
            self?.pauseForSystemInterruption("相机记录已暂停。请恢复后确认孩子姿势，再重新开始。")
        })
        lifecycleObservers.append(center.addObserver(forName: AVCaptureSession.interruptionEndedNotification, object: session, queue: .main) { [weak self] _ in
            self?.resumePreviewAfterSystemInterruption()
        })
        lifecycleObservers.append(center.addObserver(forName: AVCaptureSession.runtimeErrorNotification, object: session, queue: .main) { [weak self] _ in
            self?.pauseForSystemInterruption("相机服务被系统中断。请恢复后重新开始记录。")
        })
    }

    private func pauseForSystemInterruption(_ message: String) {
        guard !didFinish else { return }
        captureArmed = false
        resetStability()
        onCameraReady?(false)
        VoiceCoach.shared.stop()
        onInterrupted?()
        updateGuidance(message)
        sessionQueue.async { self.session.stopRunning() }
    }

    private func resumePreviewAfterSystemInterruption() {
        guard !didFinish, let currentPosition else { return }
        // Resuming the preview never resumes an armed capture. The SwiftUI
        // binding was cleared in `pauseForSystemInterruption`, so the parent
        // still has to explicitly verify the pose and tap "开始采集" again.
        sessionQueue.async {
            guard AVCaptureDevice.authorizationStatus(for: .video) == .authorized else { return }
            self.configureSession(position: currentPosition)
        }
    }

    func configure(task: BodyAssessmentRecord.CaptureTask, measuredHeightCm: Double, ageMonths: Int?, usesFrontCamera: Bool, speaksGuidance: Bool, captureArmed: Bool) {
        self.task = task
        self.measuredHeightCm = measuredHeightCm
        self.ageMonths = ageMonths
        self.speaksGuidance = speaksGuidance
        if self.captureArmed != captureArmed {
            self.captureArmed = captureArmed
            resetStability()
        }
        let position: AVCaptureDevice.Position = usesFrontCamera ? .front : .back
        guard currentPosition != position else { return }
        currentPosition = position
        resetStability()
        onCameraReady?(false)
        sessionQueue.async { self.configureSession(position: position) }
    }

    private func requestCamera() {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized: sessionQueue.async { self.session.startRunning() }
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { granted in
                if granted { self.sessionQueue.async { self.session.startRunning() } }
                else { self.fail("未获得相机权限，请在系统设置中允许相机后重试。") }
            }
        default: fail("未获得相机权限，请在系统设置中允许相机后重试。")
        }
    }

    private func configureSession(position: AVCaptureDevice.Position) {
        session.beginConfiguration()
        var shouldPublishReady = false
        defer {
            session.commitConfiguration()
            // Never start capture before the operating system has granted access.
            if AVCaptureDevice.authorizationStatus(for: .video) == .authorized, !session.isRunning {
                session.startRunning()
            }
            if shouldPublishReady {
                // Publish only after the session change has committed and the
                // running state is requested. A UI tap cannot race an incomplete
                // AVCapture transaction during a fast lens switch.
                DispatchQueue.main.async { [weak self] in
                    guard let self, self.currentPosition == position, !self.didFinish else { return }
                    self.previewLayer.session = self.session
                    self.onCameraReady?(true)
                }
            }
        }
        session.sessionPreset = .high
        session.inputs.forEach { session.removeInput($0) }
        guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: position),
              let input = try? AVCaptureDeviceInput(device: device), session.canAddInput(input) else {
            fail("当前设备无法打开所选摄像头，请切换前后摄像头后重试。"); return
        }
        session.addInput(input)
        if session.outputs.isEmpty {
            let output = AVCaptureVideoDataOutput()
            output.alwaysDiscardsLateVideoFrames = true
            output.setSampleBufferDelegate(self, queue: visionQueue)
            guard session.canAddOutput(output) else {
                fail("当前设备无法配置相机分析，请退出后重试。")
                return
            }
            session.addOutput(output)
        }
        shouldPublishReady = true
    }

    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        guard !didFinish, let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        do {
            // Camera buffers are sensor-oriented, not necessarily portrait-oriented.
            // Supplying the real direction makes Vision's joints stable on both
            // front (mirrored) and rear cameras in the portrait App flow.
            // Derive orientation from the frame's own connection rather than
            // reading the mutable selected lens on the Vision queue. This
            // avoids a front/back switch racing an in-flight final frame.
            let framePosition = (connection.inputPorts.first?.input as? AVCaptureDeviceInput)?.device.position
            let orientation: CGImagePropertyOrientation = framePosition == .front ? .leftMirrored : .right
            try VNImageRequestHandler(cvPixelBuffer: pixelBuffer, orientation: orientation).perform([poseRequest])
            guard let pose = poseRequest.results?.first else { updateGuidance("暂未看清全身，请退后一步并确保全身入镜。"); resetStability(); return }
            let points = try pose.recognizedPoints(.all)
            let required: [VNHumanBodyPoseObservation.JointName] = task == .seatedPosture ? [.nose, .leftEar, .rightEar, .leftShoulder, .rightShoulder, .leftHip, .rightHip] : [.nose, .leftShoulder, .rightShoulder, .leftHip, .rightHip, .leftAnkle, .rightAnkle]
            let confidences = required.map { points[$0]?.confidence ?? 0 }
            guard BodyCaptureQualityGate.hasReliableLandmarks(confidences, ageMonths: ageMonths) else {
                updateGuidance(task == .seatedPosture ? "请让肩部和髋部清晰入镜，保持光线充足。" : "请让头、肩、髋和双脚完整入镜，保持光线充足。"); resetStability(); return
            }
            // Vision observations are value snapshots, but the dictionary can
            // still omit a joint while a frame is being invalidated during a
            // camera/lens transition. Keep the analyzer fail-closed instead of
            // force-unwrapping a point after the confidence gate.
            guard let leftShoulder = points[.leftShoulder],
                  let rightShoulder = points[.rightShoulder],
                  let leftHip = points[.leftHip],
                  let rightHip = points[.rightHip],
                  let nose = points[.nose],
                  task == .seatedPosture || (points[.leftAnkle] != nil && points[.rightAnkle] != nil) else {
                updateGuidance("暂未看清关键点，请保持光线充足并重新取景。"); resetStability(); return
            }
            let leftAnkle = points[.leftAnkle]
            let rightAnkle = points[.rightAnkle]
            let verticalCoverage: Double
            if task == .seatedPosture {
                verticalCoverage = abs((leftShoulder.location.y + rightShoulder.location.y) / 2 - (leftHip.location.y + rightHip.location.y) / 2)
            } else {
                guard let leftAnkle, let rightAnkle else {
                    updateGuidance("暂未看清双脚，请退后一步并确保全身入镜。"); resetStability(); return
                }
                verticalCoverage = abs((nose.location.y - (leftAnkle.location.y + rightAnkle.location.y) / 2))
            }
            guard BodyCaptureQualityGate.hasUsableBodyScale(verticalCoverage: verticalCoverage, seated: task == .seatedPosture, ageMonths: ageMonths) else {
                resetStability()
                updateGuidance(task == .seatedPosture ? "请把手机靠近一些，让上半身占满引导框的大部分区域。" : "请让孩子靠近一些，让身体在引导框内更清晰。")
                return
            }
            if task == .seatedPosture {
                let shoulderY = (leftShoulder.location.y + rightShoulder.location.y) / 2
                let hipY = (leftHip.location.y + rightHip.location.y) / 2
                guard BodyCaptureQualityGate.hasUsableSeatedGeometry(shoulderCenterY: shoulderY, hipCenterY: hipY, verticalCoverage: verticalCoverage, ageMonths: ageMonths) else {
                    resetStability(); updateGuidance("请坐直、双脚落地，让肩部保持在髋部上方；不要斜靠椅背。")
                    return
                }
            }
            guard captureArmed else {
                resetStability()
                updateGuidance("取景已就绪，请确认动作后点击开始记录。")
                return
            }
            // Estimate global camera roll from both shoulder and hip axes,
            // then compare heights in the roll-corrected coordinate system.
            // This prevents a tilted phone from becoming a false asymmetry.
            let leftShoulderX = Double(leftShoulder.location.x), leftShoulderY = Double(leftShoulder.location.y)
            let rightShoulderX = Double(rightShoulder.location.x), rightShoulderY = Double(rightShoulder.location.y)
            let leftHipX = Double(leftHip.location.x), leftHipY = Double(leftHip.location.y)
            let rightHipX = Double(rightHip.location.x), rightHipY = Double(rightHip.location.y)
            let rollAxisDx = ((leftShoulderX - rightShoulderX) + (leftHipX - rightHipX)) / 2
            let rollAxisDy = ((leftShoulderY - rightShoulderY) + (leftHipY - rightHipY)) / 2
            let correctedHip0 = (x: PostureMetricCalculator.rollCorrectedX(leftHipX, leftHipY, axisDx: rollAxisDx, axisDy: rollAxisDy), y: PostureMetricCalculator.rollCorrectedY(leftHipX, leftHipY, axisDx: rollAxisDx, axisDy: rollAxisDy))
            let correctedHip1 = (x: PostureMetricCalculator.rollCorrectedX(rightHipX, rightHipY, axisDx: rollAxisDx, axisDy: rollAxisDy), y: PostureMetricCalculator.rollCorrectedY(rightHipX, rightHipY, axisDx: rollAxisDx, axisDy: rollAxisDy))
            let correctedShoulder0 = (x: PostureMetricCalculator.rollCorrectedX(leftShoulderX, leftShoulderY, axisDx: rollAxisDx, axisDy: rollAxisDy), y: PostureMetricCalculator.rollCorrectedY(leftShoulderX, leftShoulderY, axisDx: rollAxisDx, axisDy: rollAxisDy))
            let correctedShoulder1 = (x: PostureMetricCalculator.rollCorrectedX(rightShoulderX, rightShoulderY, axisDx: rollAxisDx, axisDy: rollAxisDy), y: PostureMetricCalculator.rollCorrectedY(rightShoulderX, rightShoulderY, axisDx: rollAxisDx, axisDy: rollAxisDy))
            let hipCenterX = (correctedHip0.x + correctedHip1.x) / 2
            let hipCenterY = (correctedHip0.y + correctedHip1.y) / 2
            let shoulderCenterX = (correctedShoulder0.x + correctedShoulder1.x) / 2
            let shoulderCenterY = (correctedShoulder0.y + correctedShoulder1.y) / 2
            let hipCenter = CGPoint(x: CGFloat(hipCenterX), y: CGFloat(hipCenterY))
            let shoulderCenter = CGPoint(x: CGFloat(shoulderCenterX), y: CGFloat(shoulderCenterY))
            let torsoTilt = abs(shoulderCenterX - hipCenterX) / max(abs(shoulderCenterY - hipCenterY), 0.001)
            if firstHipLocation == nil { firstHipLocation = hipCenter }
            let start = firstHipLocation ?? hipCenter
            let displacement = hypot(hipCenter.x - start.x, hipCenter.y - start.y)
            let bodyHeightNormalized = verticalCoverage
            let shoulderGap = PostureMetricCalculator.rollCorrectedVerticalDifference(firstX: leftShoulderX, firstY: leftShoulderY, secondX: rightShoulderX, secondY: rightShoulderY, axisDx: rollAxisDx, axisDy: rollAxisDy)
            let pelvicGap = PostureMetricCalculator.rollCorrectedVerticalDifference(firstX: leftHipX, firstY: leftHipY, secondX: rightHipX, secondY: rightHipY, axisDx: rollAxisDx, axisDy: rollAxisDy)
            let headTilt = points[.leftEar].flatMap { leftEar in points[.rightEar].flatMap { rightEar in
                let leftEarX = Double(leftEar.location.x), leftEarY = Double(leftEar.location.y)
                let rightEarX = Double(rightEar.location.x), rightEarY = Double(rightEar.location.y)
                let dy = PostureMetricCalculator.rollCorrectedVerticalDifference(firstX: leftEarX, firstY: leftEarY, secondX: rightEarX, secondY: rightEarY, axisDx: rollAxisDx, axisDy: rollAxisDy)
                let lx = PostureMetricCalculator.rollCorrectedX(leftEarX, leftEarY, axisDx: rollAxisDx, axisDy: rollAxisDy)
                let rx = PostureMetricCalculator.rollCorrectedX(rightEarX, rightEarY, axisDx: rollAxisDx, axisDy: rollAxisDy)
                return PostureMetricCalculator.degrees(atan2(dy, max(abs(lx - rx), 0.001)))
            } }
            let forwardHeadAngle = points[.leftEar].flatMap { leftEar in points[.rightEar].flatMap { rightEar in
                let leftEarX = Double(leftEar.location.x), leftEarY = Double(leftEar.location.y)
                let rightEarX = Double(rightEar.location.x), rightEarY = Double(rightEar.location.y)
                let earCenterX = (PostureMetricCalculator.rollCorrectedX(leftEarX, leftEarY, axisDx: rollAxisDx, axisDy: rollAxisDy) + PostureMetricCalculator.rollCorrectedX(rightEarX, rightEarY, axisDx: rollAxisDx, axisDy: rollAxisDy)) / 2
                let earCenterY = (PostureMetricCalculator.rollCorrectedY(leftEarX, leftEarY, axisDx: rollAxisDx, axisDy: rollAxisDy) + PostureMetricCalculator.rollCorrectedY(rightEarX, rightEarY, axisDx: rollAxisDx, axisDy: rollAxisDy)) / 2
                return PostureMetricCalculator.degrees(atan2(abs(earCenterX - shoulderCenterX), max(abs(earCenterY - shoulderCenterY), 0.001)))
            } }
            let trunkOffset = abs(shoulderCenterX - hipCenterX)
            let shoulderGapCm = PostureMetricCalculator.centimeters(shoulderGap, bodyHeightNormalized: bodyHeightNormalized, measuredHeightCm: measuredHeightCm)
            let pelvicGapCm = PostureMetricCalculator.centimeters(pelvicGap, bodyHeightNormalized: bodyHeightNormalized, measuredHeightCm: measuredHeightCm)
            let trunkOffsetCm = PostureMetricCalculator.centimeters(trunkOffset, bodyHeightNormalized: bodyHeightNormalized, measuredHeightCm: measuredHeightCm)
            // A single RGB/2D camera cannot measure rib prominence or ATR.
            // The previous midpoint-distance formula was mathematically zero
            // by construction, so retaining it would create a false medical
            // signal. Leave these fields unavailable until a validated depth/
            // 3D or scoliometer-backed pipeline is integrated.
            metricSamples.append(PoseMetricSample(confidence: Double(confidences.reduce(0, +) / Float(confidences.count)), bodyHeightNormalized: bodyHeightNormalized, shoulderHeightDifferenceCm: shoulderGapCm ?? 0, pelvicHeightDifferenceCm: pelvicGapCm ?? 0, headTiltDegrees: headTilt ?? 0, spinalMidlineDeviationCm: trunkOffsetCm ?? 0, thoracicRoundingDegrees: PostureMetricCalculator.degrees(atan2(abs(shoulderCenter.x - hipCenter.x), max(abs(shoulderCenter.y - hipCenter.y), 0.001))) ?? 0, forwardHeadAngleDegrees: forwardHeadAngle ?? 0))
            let gap = max(shoulderGap, pelvicGap)
            let captureProfile = BodyCaptureQualityGate.profile(ageMonths: ageMonths)
            displacementWindow.append(displacement)
            if displacementWindow.count > captureProfile.stabilityWindowFrames { displacementWindow.removeFirst() }
            let windowDisplacement = PostureMetricCalculator.median(displacementWindow) ?? displacement
            let windowJitter = medianAbsoluteDeviation(displacementWindow)
            if task == .gaitVideo {
                gaitMotionWindow.append(displacement >= captureProfile.gaitMinimumDisplacement)
                if gaitMotionWindow.count > captureProfile.gaitMovementWindowFrames { gaitMotionWindow.removeFirst() }
            }
            if task != .gaitVideo, windowDisplacement >= captureProfile.staticMaximumDisplacement || windowJitter > captureProfile.staticDisplacementJitter {
                resetStability()
                firstHipLocation = hipCenter
                updateGuidance("请保持自然不动，画面稳定后开始计时。")
                return
            }
            stableFrames += 1
            if stableSince == nil { stableSince = .now }
            let elapsed = Date.now.timeIntervalSince(stableSince ?? .now)
            if task == .gaitVideo {
                let movedFrames = gaitMotionWindow.filter { $0 }.count
                let moved = movedFrames >= captureProfile.gaitMovementWindowFrames / 2
                updateGuidance(moved ? "动作已进入判定口径，请继续自然走完三步。" : "请固定手机，沿直线自然走三步。")
                onProgress?(BodyCaptureQualityGate.gaitProgress(elapsed: elapsed, hasMoved: moved, ageMonths: ageMonths))
                guard BodyCaptureQualityGate.isGaitCaptureReady(elapsed: elapsed, displacement: displacement, movedFrames: movedFrames, rawSamples: metricSamples.count, ageMonths: ageMonths) else { return }
            } else {
                let remaining = max(0, Int(ceil(captureProfile.staticHoldSeconds - elapsed)))
                if task == .forwardBend, torsoTilt < captureProfile.forwardBendMinimumTorsoTilt {
                    resetStability()
                    firstHipLocation = hipCenter
                    updateGuidance("请从侧后方拍摄，缓慢前屈到舒适位置后停住；感到不适请立即停止。")
                    return
                }
                updateGuidance(remaining > 0 ? "画面稳定，请保持自然姿势 \(remaining) 秒。" : "记录完成，请保持不动。")
                onProgress?(BodyCaptureQualityGate.staticProgress(elapsed: elapsed, ageMonths: ageMonths))
                let ready = task == .forwardBend
                    ? BodyCaptureQualityGate.isForwardBendCaptureReady(elapsed: elapsed, stableFrames: stableFrames, displacement: windowDisplacement, jitter: windowJitter, torsoTilt: torsoTilt, ageMonths: ageMonths)
                    : BodyCaptureQualityGate.isStaticCaptureReady(elapsed: elapsed, stableFrames: stableFrames, displacement: windowDisplacement, jitter: windowJitter, ageMonths: ageMonths)
                guard ready else { return }
            }
                let hint = gap >= 0.07 ? "观察到左右高度差异，已写入姿态报告；如有持续不适建议结合体检。" : nil
                finish(CaptureReview(accepted: true, message: "已完成姿态记录，可查看本次家庭观察指标。", observationHint: hint, postureSnapshot: makeSnapshot()))
        } catch { resetStability(); updateGuidance("正在重试判定，请保持全身入镜。") }
    }

    private func updateGuidance(_ text: String) {
        guard text != lastGuidance else { return }
        lastGuidance = text
        onGuidance?(text)
        // Pose frames arrive many times per second. Speech must guide rather
        // than continuously interrupt the parent during difficult framing.
        if speaksGuidance && text.contains("请"), Date.now.timeIntervalSince(lastGuidanceSpokenAt) >= 2.2 {
            lastGuidanceSpokenAt = .now
            VoiceCoach.shared.say(text)
        }
    }
    private func finish(_ review: CaptureReview) {
        guard !didFinish else { return }
        didFinish = true
        onCameraReady?(false)
        onProgress?(1)
        sessionQueue.async { self.session.stopRunning() }
        onCompleted?(review)
    }
    private func fail(_ message: String) {
        sessionQueue.async { self.session.stopRunning() }
        onProgress?(0)
        onCameraReady?(false)
        onFailure?(message)
    }
    private func resetStability() { stableFrames = 0; stableSince = nil; firstHipLocation = nil; metricSamples.removeAll(keepingCapacity: true); displacementWindow.removeAll(keepingCapacity: true); gaitMotionWindow.removeAll(keepingCapacity: true); onProgress?(0) }

    private func medianAbsoluteDeviation(_ values: [Double]) -> Double {
        guard values.count >= 2, let center = PostureMetricCalculator.median(values) else { return 0 }
        return PostureMetricCalculator.median(values.map { abs($0 - center) }) ?? 0
    }

    private func makeSnapshot() -> PostureMetricSnapshot {
        let median: (KeyPath<PoseMetricSample, Double>) -> Double? = { keyPath in PostureMetricCalculator.median(self.metricSamples.map { $0[keyPath: keyPath] }) }
        let gaitShoulder = PostureMetricCalculator.range(metricSamples.map { $0.shoulderHeightDifferenceCm })
        let gaitPelvic = PostureMetricCalculator.range(metricSamples.map { $0.pelvicHeightDifferenceCm })
        let gaitSway = PostureMetricCalculator.range(metricSamples.map { $0.spinalMidlineDeviationCm })
        return PostureMetricSnapshot(id: "\(task.rawValue)-\(Int(Date().timeIntervalSince1970))", task: task, sampleCount: metricSamples.count, confidence: metricSamples.map(\.confidence).reduce(0, +) / Double(max(metricSamples.count, 1)), shoulderHeightDifferenceCm: median(\.shoulderHeightDifferenceCm), pelvicHeightDifferenceCm: median(\.pelvicHeightDifferenceCm), headTiltDegrees: median(\.headTiltDegrees), spinalMidlineDeviationCm: median(\.spinalMidlineDeviationCm), thoracicRoundingDegrees: median(\.thoracicRoundingDegrees), forwardHeadAngleDegrees: median(\.forwardHeadAngleDegrees), cameraProxyAtrDegrees: nil, cameraProxyRibProminenceCm: nil, gaitShoulderSwingDifferenceCm: task == .gaitVideo ? gaitShoulder : nil, gaitPelvicSwingDifferenceCm: task == .gaitVideo ? gaitPelvic : nil, gaitTrunkSwayCm: task == .gaitVideo ? gaitSway : nil)
    }
}

private struct PoseMetricSample {
    let confidence: Double
    let bodyHeightNormalized: Double
    let shoulderHeightDifferenceCm: Double
    let pelvicHeightDifferenceCm: Double
    let headTiltDegrees: Double
    let spinalMidlineDeviationCm: Double
    let thoracicRoundingDegrees: Double
    let forwardHeadAngleDegrees: Double
}

private final class VoiceCoach {
    static let shared = VoiceCoach()
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
