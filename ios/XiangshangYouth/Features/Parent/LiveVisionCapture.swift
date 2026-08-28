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
    @StateObject private var deviceAlignmentMonitor = CaptureDeviceAlignmentMonitor()
    @State private var usesFrontCamera = false
    @State private var guidance = "正在启动相机…"
    @State private var speaksGuidance = true
    @State private var captureProgress = 0.0
    /// A lens switch is asynchronous. Never arm the quality gate against the
    /// outgoing camera's final frames while the new input is still binding.
    @State private var cameraReady = false
    @State private var cameraError: String?
    @State private var captureArmed = false
    @State private var bodyAlignment: CaptureBodyAlignment = .waiting
    private var calibrationReady: Bool {
        !usesFrontCamera && cameraReady && deviceAlignmentMonitor.alignment.isLevel && bodyAlignment.isReady
    }
    private var taskIndex: Int {
        SpineScreeningStandard.homeCameraItems.first(where: { $0.method == .camera(task) })?.number ?? 1
    }
    private var phaseIndex: Int {
        if !captureArmed { return 0 }
        if captureProgress < 0.25 { return 0 }
        if captureProgress < 0.85 { return 1 }
        return 2
    }

    var body: some View {
        ZStack {
            LiveVisionPreview(task: task, measuredHeightCm: measuredHeightCm, ageMonths: ageMonths, usesFrontCamera: usesFrontCamera, speaksGuidance: speaksGuidance, captureArmed: $captureArmed, cameraReady: $cameraReady, guidance: $guidance, captureProgress: $captureProgress, bodyAlignment: $bodyAlignment, failed: { message in
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

            CaptureHumanCalibrationGuide(task: task, alignment: bodyAlignment, device: deviceAlignmentMonitor.alignment, recording: captureArmed)
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
                        Text("家庭采集 \(taskIndex) / \(SpineScreeningStandard.homeCameraItems.count)")
                            .font(.system(size: 16, weight: .semibold))
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
                        bodyAlignment = .waiting
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
                    Label(capturePlacementText, systemImage: "iphone.gen3.radiowaves.left.and.right")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(.white.opacity(0.76))
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                    if captureArmed {
                        HStack(spacing: 6) {
                            ForEach(Array(capturePhaseLabels.enumerated()), id: \.offset) { index, label in
                                capturePhase(label, index: index)
                            }
                        }
                    } else {
                        CaptureCalibrationStatusRow(
                            cameraReady: cameraReady,
                            deviceReady: deviceAlignmentMonitor.alignment.isLevel,
                            bodyReady: bodyAlignment.isReady
                        )
                    }
                    HStack(alignment: .top, spacing: 9) {
                        Image(systemName: guidanceIcon)
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(.yellow)
                            .frame(width: 22)
                        Text(guidance)
                            .font(.system(size: 15, weight: .medium))
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
                        .font(.system(size: 16, weight: .medium))
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
                            guard calibrationReady else { return }
                            captureProgress = 0
                            captureArmed = true
                            if speaksGuidance {
                                VoiceCoach.shared.say(task == .forwardBend
                                    ? "开始记录。双脚并拢，膝关节完全伸直，双手合十自然下垂，缓慢向前弯腰至躯干接近水平，头部自然放松，不要屈膝或做弓步。"
                                    : "开始记录。\(task.instruction)")
                            }
                        } label: {
                            Label(calibrationReady ? "引导质量门已通过，开始记录" : calibrationBlockingText, systemImage: calibrationReady ? "record.circle.fill" : "viewfinder")
                                .font(.system(size: 16, weight: .bold))
                                .frame(maxWidth: .infinity, minHeight: 50)
                        }
                        .buttonStyle(.borderedProminent)
                        .buttonBorderShape(.roundedRectangle(radius: 13))
                        .tint(.yellow).foregroundStyle(.black)
                        .disabled(!calibrationReady)
                        .accessibilityHint("相机、手机角度和人体关键点三项全部通过后才能开始")
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
        if speaksGuidance { VoiceCoach.shared.say("开始第\(taskIndex)项，\(task.title)。\(task.instruction)。\(SpineScreeningStandard.mainCameraPlacement)。") }
        }
        .onChange(of: speaksGuidance) { _, enabled in if !enabled { VoiceCoach.shared.stop() } }
        // A capture must never span an app interruption. Returning from a
        // phone call, Control Center, or the background deliberately requires
        // the parent to confirm the child is still in the correct pose.
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { return }
            if captureArmed {
                captureArmed = false
                captureProgress = 0
                guidance = "记录已暂停，返回后请确认动作并重新开始。"
            }
            cameraReady = false
            VoiceCoach.shared.stop()
        }
        .onChange(of: deviceAlignmentMonitor.alignment) { _, alignment in
            guard alignment.isAvailable else { return }
            if !alignment.isLevel {
                if captureArmed {
                    captureArmed = false
                    captureProgress = 0
                    guidance = "手机角度发生变化，记录已暂停。请重新调平手机并完成人体对齐。"
                    if speaksGuidance { VoiceCoach.shared.say("手机角度发生变化，记录已暂停，请重新调平手机。") }
                } else {
                    guidance = "请先调平手机：左右不超过 2 度，前后不超过 5 度。"
                }
            }
        }
        .onAppear { deviceAlignmentMonitor.start() }
        .onDisappear {
            deviceAlignmentMonitor.stop()
            VoiceCoach.shared.stop()
        }
    }

    private var calibrationBlockingText: String {
        if !cameraReady { return "正在连接相机" }
        if usesFrontCamera { return "正式记录请切回后置主摄" }
        if !deviceAlignmentMonitor.alignment.isLevel { return "请将左右调至 2°、前后调至 5°内" }
        if !bodyAlignment.bodyDetected { return "请进入人型框" }
        if !bodyAlignment.distanceReady { return "请调整拍摄距离" }
        return "请对齐头肩髋膝脚"
    }

    private var guidanceIcon: String {
        if !cameraReady { return "camera.aperture" }
        if guidance.contains("光线") { return "sun.max.fill" }
        if guidance.contains("多人") { return "person.2.slash.fill" }
        if guidance.contains("距离") || guidance.contains("入镜") { return "viewfinder" }
        if guidance.contains("遮挡") { return "eye.slash.fill" }
        return captureArmed ? "waveform.path.ecg" : "figure.stand"
    }

    private var capturePlacementText: String {
        switch task {
        case .gaitVideo: "后置主摄固定机位 · 3 米直线自然往返 1 次"
        case .footArch: SpineScreeningStandard.footCameraPlacement
        default: "后置 1× 主摄 · \(SpineScreeningStandard.mainCameraPlacement)"
        }
    }

    private var capturePhaseLabels: [String] {
        switch task {
        case .forwardBend: ["起始位", "前屈位", "完成"]
        case .dynamicKneeControl: ["站稳", "下蹲", "回位"]
        case .standingSide: ["左侧", "右侧", "完成"]
        case .footArch: ["左足", "右足", "完成"]
        default: ["站稳", "保持", "完成"]
        }
    }

    private func capturePhase(_ title: String, index: Int) -> some View {
        HStack(spacing: 5) {
            Image(systemName: index < phaseIndex ? "checkmark.circle.fill" : index == phaseIndex ? "circle.inset.filled" : "circle")
            Text(title)
        }
        .font(.system(size: 16, weight: .semibold))
        .foregroundStyle(index <= phaseIndex ? .yellow : .white.opacity(0.52))
        .frame(maxWidth: .infinity, minHeight: 30)
        .background(.white.opacity(index == phaseIndex ? 0.12 : 0.05), in: Capsule())
        .accessibilityLabel("\(title)，\(index < phaseIndex ? "已完成" : index == phaseIndex ? "当前阶段" : "未开始")")
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
    @Binding var bodyAlignment: CaptureBodyAlignment
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
        controller.onBodyAlignment = { value in
            DispatchQueue.main.async { bodyAlignment = value }
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
    private var dynamicRepetitionCount = 0
    private var dynamicWasDown = false
    private var segmentPhaseIndex = 0
    private var completedPhaseSamples: [PoseMetricSample] = []

    var onGuidance: ((String) -> Void)?
    var onProgress: ((Double) -> Void)?
    var onCameraReady: ((Bool) -> Void)?
    var onBodyAlignment: ((CaptureBodyAlignment) -> Void)?
    var onFailure: ((String) -> Void)?
    var onInterrupted: (() -> Void)?
    var onCompleted: ((CaptureReview) -> Void)?

    override func viewDidLoad() {
        super.viewDidLoad()
        // Show the complete sensor frame. Aspect-fill cropped the top/bottom
        // and made a correctly positioned child look like a close-up.
        previewLayer.videoGravity = .resizeAspect
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
        resetStability(clearCompletedPhases: true)
        onCameraReady?(false)
        onBodyAlignment?(.waiting)
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
        resetStability(clearCompletedPhases: true)
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
            resetStability(clearCompletedPhases: true)
        }
        let position: AVCaptureDevice.Position = usesFrontCamera ? .front : .back
        guard currentPosition != position else { return }
        currentPosition = position
        resetStability(clearCompletedPhases: true)
        onCameraReady?(false)
        onBodyAlignment?(.waiting)
        sessionQueue.async { self.configureSession(position: position) }
    }

    private func requestCamera() {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized: sessionQueue.async { self.session.startRunning() }
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { granted in
                if granted {
                    // `configure` may run before the system permission sheet
                    // resolves. In that state the input can be prepared, but
                    // the controller deliberately cannot publish readiness.
                    // Reconfigure after authorization so the committed,
                    // running session emits `onCameraReady` for first-time
                    // users as well as returning users.
                    self.sessionQueue.async {
                        if let position = self.currentPosition {
                            self.configureSession(position: position)
                        } else {
                            self.session.startRunning()
                        }
                    }
                }
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
        // Never inherit a digital zoom factor from another capture session.
        // The calibrated posture flow deliberately uses the undistorted 1×
        // wide camera and asks the child to move back instead of zooming out
        // with an ultra-wide lens.
        if let _ = try? device.lockForConfiguration() {
            device.videoZoomFactor = min(max(1, device.minAvailableVideoZoomFactor), device.maxAvailableVideoZoomFactor)
            device.unlockForConfiguration()
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
            guard let pose = poseRequest.results?.first else {
                onBodyAlignment?(.waiting)
                updateGuidance("暂未看清全身，请退后一步并确保全身入镜。"); resetStability(); return
            }
            let points = try pose.recognizedPoints(.all)
            if task == .footArch {
                processFootCloseUp(points)
                return
            }
            let required: [VNHumanBodyPoseObservation.JointName]
            switch task {
            case .seatedPosture:
                required = [.nose, .leftEar, .rightEar, .leftShoulder, .rightShoulder, .leftHip, .rightHip]
            case .standingFront, .standingBack:
                // Head tilt is reported from this task, so both ears must be
                // genuinely observed instead of silently turning a missing
                // landmark into a repeatable but false zero.
                required = [.nose, .leftEar, .rightEar, .leftShoulder, .rightShoulder, .leftHip, .rightHip, .leftKnee, .rightKnee, .leftAnkle, .rightAnkle]
            default:
                required = [.nose, .leftShoulder, .rightShoulder, .leftHip, .rightHip, .leftKnee, .rightKnee, .leftAnkle, .rightAnkle]
            }
            let confidences = required.map { points[$0]?.confidence ?? 0 }
            let forwardBendCoreConfidences = [VNHumanBodyPoseObservation.JointName.nose, .leftShoulder, .rightShoulder, .leftHip, .rightHip, .leftKnee, .rightKnee].map { points[$0]?.confidence ?? 0 }
            let forwardBendAnkleConfidences = [VNHumanBodyPoseObservation.JointName.leftAnkle, .rightAnkle].map { points[$0]?.confidence ?? 0 }
            let hasReliablePose: Bool
            if task == .forwardBend {
                hasReliablePose = captureArmed
                    ? BodyCaptureQualityGate.hasReliableForwardBendLandmarks(core: forwardBendCoreConfidences, ankles: forwardBendAnkleConfidences, ageMonths: ageMonths)
                    : BodyCaptureQualityGate.hasReliableLandmarks(confidences, ageMonths: ageMonths)
            } else {
                hasReliablePose = BodyCaptureQualityGate.hasReliableLandmarks(confidences, ageMonths: ageMonths)
            }
            guard hasReliablePose else {
                onBodyAlignment?(.waiting)
                let prompt = task == .seatedPosture
                    ? "请让肩部和髋部清晰入镜，保持光线充足。"
                    : task == .forwardBend
                        ? "请背对镜头，让头、双肩、双髋、双膝和双脚清晰入镜。"
                        : "请让头、肩、髋和双脚完整入镜，保持光线充足。"
                updateGuidance(prompt); resetStability(); return
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
                  task == .seatedPosture || (points[.leftKnee] != nil && points[.rightKnee] != nil),
                  task == .seatedPosture || task == .forwardBend || (points[.leftAnkle] != nil && points[.rightAnkle] != nil) else {
                updateGuidance("暂未看清关键点，请保持光线充足并重新取景。"); resetStability(); return
            }
            let leftKnee = points[.leftKnee]
            let rightKnee = points[.rightKnee]
            let leftAnkle = points[.leftAnkle]
            let rightAnkle = points[.rightAnkle]
            let verticalCoverage: Double
            var alignmentAnkleLocations: [CGPoint] = []
            if task == .seatedPosture {
                verticalCoverage = abs((leftShoulder.location.y + rightShoulder.location.y) / 2 - (leftHip.location.y + rightHip.location.y) / 2)
            } else {
                let ankleConfidenceFloor = BodyCaptureQualityGate.profile(ageMonths: ageMonths).minimumIndividualLandmarkConfidence
                let visibleAnkleLocations = [leftAnkle, rightAnkle].compactMap { ankle -> CGPoint? in
                    guard let ankle, ankle.confidence >= ankleConfidenceFloor else { return nil }
                    return ankle.location
                }
                let requiredVisibleAnkles = task == .forwardBend && captureArmed ? 1 : 2
                guard visibleAnkleLocations.count >= requiredVisibleAnkles else {
                    onBodyAlignment?(.waiting)
                    updateGuidance(task == .forwardBend ? "请让双脚完整入镜并保持并拢。" : "暂未看清双脚，请退后一步并确保全身入镜。"); resetStability(); return
                }
                alignmentAnkleLocations = visibleAnkleLocations
                let ankleY = visibleAnkleLocations.map(\.y).reduce(0, +) / CGFloat(visibleAnkleLocations.count)
                verticalCoverage = abs(nose.location.y - ankleY)
            }
            let scaleState = BodyCaptureQualityGate.bodyScaleState(verticalCoverage: verticalCoverage, seated: task == .seatedPosture, ageMonths: ageMonths)
            let shoulderCenterX = (leftShoulder.location.x + rightShoulder.location.x) / 2
            let hipCenterX = (leftHip.location.x + rightHip.location.x) / 2
            let bodyCenterX = (shoulderCenterX + hipCenterX) / 2
            let ankleCenterX = alignmentAnkleLocations.isEmpty ? bodyCenterX : alignmentAnkleLocations.map(\.x).reduce(0, +) / CGFloat(alignmentAnkleLocations.count)
            let kneeConfidenceFloor = BodyCaptureQualityGate.profile(ageMonths: ageMonths).minimumIndividualLandmarkConfidence
            let kneesVisible = (leftKnee?.confidence ?? 0) >= kneeConfidenceFloor && (rightKnee?.confidence ?? 0) >= kneeConfidenceFloor
            let kneeAngles: [Double] = [
                (leftHip, leftKnee, leftAnkle),
                (rightHip, rightKnee, rightAnkle)
            ].compactMap { hip, knee, ankle in
                guard let knee, let ankle, knee.confidence >= kneeConfidenceFloor, ankle.confidence >= kneeConfidenceFloor else { return nil }
                return BodyCaptureQualityGate.jointAngle(first: hip.location, joint: knee.location, third: ankle.location)
            }
            let shoulderWidth = abs(leftShoulder.location.x - rightShoulder.location.x)
            let ankleGap = (leftAnkle?.confidence ?? 0) >= kneeConfidenceFloor && (rightAnkle?.confidence ?? 0) >= kneeConfidenceFloor
                ? abs((leftAnkle?.location.x ?? 0) - (rightAnkle?.location.x ?? 0))
                : nil
            let adamsLowerBodyReady = task != .forwardBend || BodyCaptureQualityGate.hasAdamsLowerBodyPosition(
                kneeAngles: kneeAngles,
                ankleGap: ankleGap.map(Double.init),
                shoulderWidth: Double(shoulderWidth),
                requiresBothFeet: !captureArmed
            )
            let alignment = CaptureBodyAlignment(
                bodyDetected: true,
                distanceState: scaleState,
                centered: (0.39...0.61).contains(bodyCenterX),
                headReady: (0.27...0.73).contains(nose.location.x) && (0.08...0.94).contains(nose.location.y),
                shouldersReady: (0.31...0.69).contains(shoulderCenterX),
                hipsReady: (0.33...0.67).contains(hipCenterX),
                kneesReady: task == .seatedPosture || (kneesVisible && adamsLowerBodyReady),
                feetReady: task == .seatedPosture || ((0.27...0.73).contains(ankleCenterX) && !alignmentAnkleLocations.isEmpty && adamsLowerBodyReady)
            )
            onBodyAlignment?(alignment)
            switch scaleState {
            case .ready:
                break
            case .tooClose:
                resetStability()
                updateGuidance(task == .seatedPosture
                    ? "镜头太近，请把手机向后移，让肩部到髋部约占画面三分之一。"
                    : "人物离镜头太近，请后退两步，让全身约占画面一半到三分之二。")
                return
            case .tooFar:
                resetStability()
                updateGuidance(task == .seatedPosture
                    ? "距离稍远，请向前半步，仍保持头部、肩部和髋部完整入镜。"
                    : "距离稍远，请向前半步，保持头顶和双脚完整入镜。")
                return
            case .invalid:
                resetStability()
                updateGuidance("暂时无法判断取景距离，请保持手机竖直并重新站位。")
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
            if task == .forwardBend, !adamsLowerBodyReady {
                resetStability()
                updateGuidance("请保持双脚并拢、膝关节完全伸直；不要屈膝或做弓步。"); return
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
            let correctedHipCenterX = (correctedHip0.x + correctedHip1.x) / 2
            let hipCenterY = (correctedHip0.y + correctedHip1.y) / 2
            let correctedShoulderCenterX = (correctedShoulder0.x + correctedShoulder1.x) / 2
            let shoulderCenterY = (correctedShoulder0.y + correctedShoulder1.y) / 2
            let hipCenter = CGPoint(x: CGFloat(correctedHipCenterX), y: CGFloat(hipCenterY))
            let shoulderCenter = CGPoint(x: CGFloat(correctedShoulderCenterX), y: CGFloat(shoulderCenterY))
            let rawHipCenterY = (leftHipY + rightHipY) / 2
            let forwardBendCompletionScore = BodyCaptureQualityGate.adamsForwardBendCompletionScore(
                leftShoulderX: leftShoulderX,
                leftShoulderY: leftShoulderY,
                rightShoulderX: rightShoulderX,
                rightShoulderY: rightShoulderY,
                hipCenterY: rawHipCenterY
            ) ?? 0
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
                return PostureMetricCalculator.degrees(atan2(abs(earCenterX - correctedShoulderCenterX), max(abs(earCenterY - shoulderCenterY), 0.001)))
            } }
            let trunkOffset = abs(correctedShoulderCenterX - correctedHipCenterX)
            let shoulderGapCm = PostureMetricCalculator.centimeters(shoulderGap, bodyHeightNormalized: bodyHeightNormalized, measuredHeightCm: measuredHeightCm)
            let pelvicGapCm = PostureMetricCalculator.centimeters(pelvicGap, bodyHeightNormalized: bodyHeightNormalized, measuredHeightCm: measuredHeightCm)
            let trunkOffsetCm = PostureMetricCalculator.centimeters(trunkOffset, bodyHeightNormalized: bodyHeightNormalized, measuredHeightCm: measuredHeightCm)
            let hipWidth = max(abs(leftHipX - rightHipX), 0.001)
            let kneeGap = leftKnee.flatMap { left in rightKnee.map { abs(Double(left.location.x - $0.location.x)) } }
            let ankleGapValue = leftAnkle.flatMap { left in rightAnkle.map { abs(Double(left.location.x - $0.location.x)) } }
            let kneeAlignmentProxy = kneeGap.flatMap { knees in ankleGapValue.map { (knees - $0) / hipWidth } }
            let leftKneeValgus: Double? = {
                guard let knee = leftKnee, let ankle = leftAnkle,
                      let angle = BodyCaptureQualityGate.jointAngle(first: leftHip.location, joint: knee.location, third: ankle.location) else { return nil }
                return 180 - angle
            }()
            let rightKneeValgus: Double? = {
                guard let knee = rightKnee, let ankle = rightAnkle,
                      let angle = BodyCaptureQualityGate.jointAngle(first: rightHip.location, joint: knee.location, third: ankle.location) else { return nil }
                return 180 - angle
            }()
            let lowerLimbAxisAsymmetry = leftKneeValgus.flatMap { left in rightKneeValgus.map { abs(left - $0) } }
            let kneeCenterY = leftKnee.flatMap { left in rightKnee.map { Double((left.location.y + $0.location.y) / 2) } }
            let squatDepthRatio = kneeCenterY.map { abs(rawHipCenterY - $0) / max(bodyHeightNormalized, 0.001) }
            let heelAlignmentProxy = leftKnee.flatMap { left in leftAnkle.flatMap { leftFoot in
                rightKnee.flatMap { right in rightAnkle.map { rightFoot in
                    let leftAngle = PostureMetricCalculator.degrees(atan2(abs(Double(left.location.x - leftFoot.location.x)), max(abs(Double(left.location.y - leftFoot.location.y)), 0.001))) ?? 0
                    let rightAngle = PostureMetricCalculator.degrees(atan2(abs(Double(right.location.x - rightFoot.location.x)), max(abs(Double(right.location.y - rightFoot.location.y)), 0.001))) ?? 0
                    return (leftAngle + rightAngle) / 2
                } }
            } }
            // A single RGB/2D camera cannot measure rib prominence or ATR.
            // The previous midpoint-distance formula was mathematically zero
            // by construction, so retaining it would create a false medical
            // signal. Leave these fields unavailable until a validated depth/
            // 3D or scoliometer-backed pipeline is integrated.
            metricSamples.append(PoseMetricSample(confidence: Double(confidences.reduce(0, +) / Float(confidences.count)), bodyHeightNormalized: bodyHeightNormalized, shoulderHeightDifferenceCm: shoulderGapCm ?? 0, pelvicHeightDifferenceCm: pelvicGapCm ?? 0, headTiltDegrees: headTilt ?? 0, spinalMidlineDeviationCm: trunkOffsetCm ?? 0, thoracicRoundingDegrees: PostureMetricCalculator.degrees(atan2(abs(shoulderCenter.x - hipCenter.x), max(abs(shoulderCenter.y - hipCenter.y), 0.001))) ?? 0, forwardHeadAngleDegrees: forwardHeadAngle ?? 0, forwardBendCompletionScore: forwardBendCompletionScore, kneeAlignmentProxyRatio: kneeAlignmentProxy ?? 0, lowerLimbAxisAsymmetryDegrees: lowerLimbAxisAsymmetry ?? 0, leftKneeValgusProxyDegrees: leftKneeValgus ?? 0, rightKneeValgusProxyDegrees: rightKneeValgus ?? 0, squatDepthRatio: squatDepthRatio ?? 0, footArchVisibilityScore: task == .footArch ? Double([leftAnkle?.confidence, rightAnkle?.confidence].compactMap { $0 }.reduce(0, +) / 2) : 0, heelAlignmentProxyDegrees: heelAlignmentProxy ?? 0))
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
            if task != .gaitVideo, task != .dynamicKneeControl,
               windowDisplacement >= captureProfile.staticMaximumDisplacement || windowJitter > captureProfile.staticDisplacementJitter {
                resetStability()
                firstHipLocation = hipCenter
                updateGuidance("请保持自然不动，画面稳定后开始计时。")
                return
            }
            stableFrames += 1
            if stableSince == nil { stableSince = .now }
            let elapsed = Date.now.timeIntervalSince(stableSince ?? .now)
            if task == .dynamicKneeControl {
                let kneeFlexion = [leftKneeValgus, rightKneeValgus].compactMap { $0 }.reduce(0, +) / Double(max([leftKneeValgus, rightKneeValgus].compactMap { $0 }.count, 1))
                if kneeFlexion >= 30 {
                    dynamicWasDown = true
                    updateGuidance("已识别下蹲位，请保持双膝朝向脚尖并自然站起。")
                } else if dynamicWasDown, kneeFlexion <= 18 {
                    dynamicWasDown = false
                    dynamicRepetitionCount += 1
                    updateGuidance(dynamicRepetitionCount >= 3 ? "三次动作已完成，请保持站立。" : "已完成 \(dynamicRepetitionCount) 次，请继续下一次下蹲。")
                } else {
                    updateGuidance(dynamicRepetitionCount == 0 ? "请正对镜头，缓慢下蹲后回到站立，共完成三次。" : "已完成 \(dynamicRepetitionCount) 次，请继续完成下蹲和回位。")
                }
                publishProgress(min(0.98, (Double(dynamicRepetitionCount) + (dynamicWasDown ? 0.5 : 0)) / 3.0))
                guard dynamicRepetitionCount >= 3 else { return }
            } else if task == .gaitVideo {
                let movedFrames = gaitMotionWindow.filter { $0 }.count
                let moved = movedFrames >= captureProfile.gaitMovementWindowFrames / 2
                updateGuidance(moved ? "动作已进入判定口径，请继续自然走完三步。" : "请固定手机，沿直线自然走三步。")
                publishProgress(BodyCaptureQualityGate.gaitProgress(elapsed: elapsed, hasMoved: moved, ageMonths: ageMonths))
                guard BodyCaptureQualityGate.isGaitCaptureReady(elapsed: elapsed, displacement: displacement, movedFrames: movedFrames, rawSamples: metricSamples.count, ageMonths: ageMonths) else { return }
            } else {
                let remaining = max(0, Int(ceil(captureProfile.staticHoldSeconds - elapsed)))
                if task == .forwardBend, forwardBendCompletionScore < captureProfile.forwardBendMinimumTorsoTilt {
                    resetStability()
                    firstHipLocation = hipCenter
                    updateGuidance("请背对镜头，双脚并拢、膝盖完全伸直、双手合十下垂，继续缓慢前屈至躯干接近水平。")
                    return
                }
                updateGuidance(task == .forwardBend
                    ? (remaining > 0 ? "前屈动作已识别，请保持 \(remaining) 秒。" : "前屈记录完成，请保持不动。")
                    : (remaining > 0 ? "画面稳定，请保持自然姿势 \(remaining) 秒。" : "记录完成，请保持不动。"))
                publishProgress(BodyCaptureQualityGate.staticProgress(elapsed: elapsed, ageMonths: ageMonths))
                let ready = task == .forwardBend
                    ? BodyCaptureQualityGate.isForwardBendCaptureReady(elapsed: elapsed, stableFrames: stableFrames, displacement: windowDisplacement, jitter: windowJitter, torsoTilt: forwardBendCompletionScore, ageMonths: ageMonths)
                    : BodyCaptureQualityGate.isStaticCaptureReady(elapsed: elapsed, stableFrames: stableFrames, displacement: windowDisplacement, jitter: windowJitter, ageMonths: ageMonths)
                guard ready else { return }
            }
                guard metricSamples.count >= captureProfile.minimumRawSamplesForCompletion else {
                    updateGuidance("请继续保持，正在采集更多稳定样本。")
                    return
                }
                if task != .gaitVideo, task != .dynamicKneeControl,
                   !staticMetricSeriesAreStable(minimumSamples: captureProfile.minimumRawSamplesForCompletion) {
                    resetStability()
                    firstHipLocation = hipCenter
                    updateGuidance("本次关键点波动较大，请固定手机并重新保持动作。")
                    return
                }
                if requiresBilateralPhases, segmentPhaseIndex == 0 {
                    completedPhaseSamples = metricSamples
                    segmentPhaseIndex = 1
                    resetStability(clearCompletedPhases: false)
                    updateGuidance(task == .standingSide
                        ? "左侧记录完成。请让孩子转身，以右侧对准镜头，重新进入人型框后保持自然站立。"
                        : "左足记录完成。请按引导调整站位，让右足完整进入近景框。")
                    return
                }
                if requiresBilateralPhases, !completedPhaseSamples.isEmpty {
                    metricSamples = completedPhaseSamples + metricSamples
                }
                let hint = gap >= 0.07 ? "观察到左右高度差异，已写入姿态报告；如有持续不适建议结合体检。" : nil
                finish(CaptureReview(accepted: true, message: "已完成姿态记录，可查看本次家庭观察指标。", observationHint: hint, postureSnapshot: makeSnapshot()))
        } catch { resetStability(); updateGuidance(task == .footArch ? "正在重新确认足部近景，请保持膝部以下完整入镜。" : "正在重试判定，请保持全身入镜。") }
    }

    private func processFootCloseUp(_ points: [VNHumanBodyPoseObservation.JointName: VNRecognizedPoint]) {
        let jointNames: [VNHumanBodyPoseObservation.JointName] = [.leftKnee, .rightKnee, .leftAnkle, .rightAnkle]
        let confidences = jointNames.map { points[$0]?.confidence ?? 0 }
        guard BodyCaptureQualityGate.hasReliableLandmarks(confidences, ageMonths: ageMonths),
              let leftKnee = points[.leftKnee], let rightKnee = points[.rightKnee],
              let leftAnkle = points[.leftAnkle], let rightAnkle = points[.rightAnkle] else {
            onBodyAlignment?(.waiting)
            resetStability()
            updateGuidance("请只拍摄膝部以下，让双膝、双踝和双脚完整进入近景框。")
            return
        }

        let kneeCenter = CGPoint(x: (leftKnee.location.x + rightKnee.location.x) / 2, y: (leftKnee.location.y + rightKnee.location.y) / 2)
        let ankleCenter = CGPoint(x: (leftAnkle.location.x + rightAnkle.location.x) / 2, y: (leftAnkle.location.y + rightAnkle.location.y) / 2)
        let lowerLegCoverage = abs(kneeCenter.y - ankleCenter.y)
        let scaleState = BodyCaptureQualityGate.footScaleState(lowerLegCoverage: lowerLegCoverage)
        let lowerBodyCenterX = (kneeCenter.x + ankleCenter.x) / 2
        let centered = (0.34...0.66).contains(lowerBodyCenterX)
        let jointsReady = centered && scaleState == .ready
        onBodyAlignment?(CaptureBodyAlignment(
            bodyDetected: true,
            distanceState: scaleState,
            centered: centered,
            headReady: true,
            shouldersReady: true,
            hipsReady: true,
            kneesReady: jointsReady,
            feetReady: jointsReady
        ))

        switch scaleState {
        case .tooFar:
            resetStability(); updateGuidance("足部画面太小，请把手机移近半步，保持膝部以下完整入镜。")
            return
        case .tooClose:
            resetStability(); updateGuidance("足部画面过近，请把手机后移半步，让双膝到双脚都在近景框内。")
            return
        case .invalid:
            resetStability(); updateGuidance("暂时无法判断足部取景距离，请保持手机竖直并重新对准双脚。")
            return
        case .ready:
            break
        }
        guard centered else {
            resetStability(); updateGuidance("请将双膝和双脚整体移到近景框中央。")
            return
        }
        guard captureArmed else {
            resetStability(); updateGuidance("足部近景已就绪，请确认赤足站稳后点击开始记录。")
            return
        }

        let lowerLegCenter = CGPoint(x: lowerBodyCenterX, y: (kneeCenter.y + ankleCenter.y) / 2)
        if firstHipLocation == nil { firstHipLocation = lowerLegCenter }
        let start = firstHipLocation ?? lowerLegCenter
        let displacement = hypot(lowerLegCenter.x - start.x, lowerLegCenter.y - start.y)
        let leftHeelLine = PostureMetricCalculator.degrees(atan2(abs(Double(leftKnee.location.x - leftAnkle.location.x)), max(abs(Double(leftKnee.location.y - leftAnkle.location.y)), 0.001))) ?? 0
        let rightHeelLine = PostureMetricCalculator.degrees(atan2(abs(Double(rightKnee.location.x - rightAnkle.location.x)), max(abs(Double(rightKnee.location.y - rightAnkle.location.y)), 0.001))) ?? 0
        metricSamples.append(PoseMetricSample(
            confidence: Double(confidences.reduce(0, +) / Float(confidences.count)),
            bodyHeightNormalized: lowerLegCoverage,
            shoulderHeightDifferenceCm: 0,
            pelvicHeightDifferenceCm: 0,
            headTiltDegrees: 0,
            spinalMidlineDeviationCm: 0,
            thoracicRoundingDegrees: 0,
            forwardHeadAngleDegrees: 0,
            forwardBendCompletionScore: 0,
            kneeAlignmentProxyRatio: 0,
            lowerLimbAxisAsymmetryDegrees: abs(leftHeelLine - rightHeelLine),
            leftKneeValgusProxyDegrees: 0,
            rightKneeValgusProxyDegrees: 0,
            squatDepthRatio: 0,
            footArchVisibilityScore: Double(confidences.reduce(0, +) / Float(confidences.count)),
            heelAlignmentProxyDegrees: (leftHeelLine + rightHeelLine) / 2
        ))

        let captureProfile = BodyCaptureQualityGate.profile(ageMonths: ageMonths)
        displacementWindow.append(displacement)
        if displacementWindow.count > captureProfile.stabilityWindowFrames { displacementWindow.removeFirst() }
        let windowDisplacement = PostureMetricCalculator.median(displacementWindow) ?? displacement
        let windowJitter = medianAbsoluteDeviation(displacementWindow)
        if windowDisplacement >= captureProfile.staticMaximumDisplacement || windowJitter > captureProfile.staticDisplacementJitter {
            resetStability()
            firstHipLocation = lowerLegCenter
            updateGuidance("请让孩子双脚平行站稳，并固定手机等待画面稳定。")
            return
        }
        stableFrames += 1
        if stableSince == nil { stableSince = .now }
        let elapsed = Date.now.timeIntervalSince(stableSince ?? .now)
        let remaining = max(0, Int(ceil(captureProfile.staticHoldSeconds - elapsed)))
        updateGuidance(remaining > 0 ? "足部近景稳定，请保持 (remaining) 秒。" : "本侧足部记录完成，请保持不动。")
        publishProgress(BodyCaptureQualityGate.staticProgress(elapsed: elapsed, ageMonths: ageMonths))
        guard BodyCaptureQualityGate.isStaticCaptureReady(elapsed: elapsed, stableFrames: stableFrames, displacement: windowDisplacement, jitter: windowJitter, ageMonths: ageMonths),
              metricSamples.count >= captureProfile.minimumRawSamplesForCompletion else { return }

        if segmentPhaseIndex == 0 {
            completedPhaseSamples = metricSamples
            segmentPhaseIndex = 1
            resetStability(clearCompletedPhases: false)
            updateGuidance("左足近景完成。请调整站位，让右足内侧和足跟对准近景框后再次记录。")
            return
        }
        if !completedPhaseSamples.isEmpty { metricSamples = completedPhaseSamples + metricSamples }
        finish(CaptureReview(accepted: true, message: "双侧足部近景记录完成。", observationHint: "当前仅形成足部画面质量和足跟投影记录，不输出足弓诊断。", postureSnapshot: makeSnapshot()))
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
    private var requiresBilateralPhases: Bool { task == .standingSide || task == .footArch }

    private func publishProgress(_ rawValue: Double) {
        let clamped = min(max(rawValue, 0), 1)
        onProgress?(requiresBilateralPhases ? (Double(segmentPhaseIndex) + clamped) / 2 : clamped)
    }

    private func resetStability(clearCompletedPhases: Bool = false) {
        stableFrames = 0
        stableSince = nil
        firstHipLocation = nil
        metricSamples.removeAll(keepingCapacity: true)
        displacementWindow.removeAll(keepingCapacity: true)
        gaitMotionWindow.removeAll(keepingCapacity: true)
        dynamicRepetitionCount = 0
        dynamicWasDown = false
        if clearCompletedPhases {
            segmentPhaseIndex = 0
            completedPhaseSamples.removeAll(keepingCapacity: true)
        }
        publishProgress(0)
    }

    private func medianAbsoluteDeviation(_ values: [Double]) -> Double {
        guard values.count >= 2, let center = PostureMetricCalculator.median(values) else { return 0 }
        return PostureMetricCalculator.median(values.map { abs($0 - center) }) ?? 0
    }

    private func staticMetricSeriesAreStable(minimumSamples: Int) -> Bool {
        let stableCm: (KeyPath<PoseMetricSample, Double>) -> Bool = { keyPath in
            PostureMetricCalculator.isStableSeries(self.metricSamples.map { $0[keyPath: keyPath] }, minimumSamples: minimumSamples, maximumMedianAbsoluteDeviation: 0.55)
        }
        guard stableCm(\.shoulderHeightDifferenceCm),
              stableCm(\.pelvicHeightDifferenceCm),
              stableCm(\.spinalMidlineDeviationCm) else { return false }
        switch task {
        case .standingFront, .standingBack:
            return PostureMetricCalculator.isStableSeries(metricSamples.map(\.headTiltDegrees), minimumSamples: minimumSamples, maximumMedianAbsoluteDeviation: 2.5)
        case .standingSide, .seatedPosture:
            return PostureMetricCalculator.isStableSeries(metricSamples.map(\.thoracicRoundingDegrees), minimumSamples: minimumSamples, maximumMedianAbsoluteDeviation: 3.5)
                && PostureMetricCalculator.isStableSeries(metricSamples.map(\.forwardHeadAngleDegrees), minimumSamples: minimumSamples, maximumMedianAbsoluteDeviation: 3.5)
        case .forwardBend:
            return PostureMetricCalculator.isStableSeries(metricSamples.map(\.forwardBendCompletionScore), minimumSamples: minimumSamples, maximumMedianAbsoluteDeviation: 0.05)
        case .dynamicKneeControl:
            return PostureMetricCalculator.isStableSeries(metricSamples.map(\.kneeAlignmentProxyRatio), minimumSamples: minimumSamples, maximumMedianAbsoluteDeviation: 0.08)
        case .gaitVideo, .footArch:
            return true
        }
    }

    private func makeSnapshot() -> PostureMetricSnapshot {
        let median: (KeyPath<PoseMetricSample, Double>) -> Double? = { keyPath in PostureMetricCalculator.robustMedian(self.metricSamples.map { $0[keyPath: keyPath] }) }
        let gaitShoulder = PostureMetricCalculator.robustRange(metricSamples.map { $0.shoulderHeightDifferenceCm })
        let gaitPelvic = PostureMetricCalculator.robustRange(metricSamples.map { $0.pelvicHeightDifferenceCm })
        let gaitSway = PostureMetricCalculator.robustRange(metricSamples.map { $0.spinalMidlineDeviationCm })
        let framingChecks = task == .footArch
            ? ["device-level", "foot-close-up", "lower-limb-landmarks", "single-person", "landmark-confidence", "multi-frame-robust"]
            : ["device-level", "full-body", "single-person", "landmark-confidence", "multi-frame-robust"]
        let checks = framingChecks + (task == .dynamicKneeControl ? ["three-repetition-cycle"] : [])
        return PostureMetricSnapshot(id: "\(task.rawValue)-\(Int(Date().timeIntervalSince1970))", task: task, sampleCount: metricSamples.count, confidence: PostureMetricCalculator.robustMedian(metricSamples.map(\.confidence)) ?? 0, shoulderHeightDifferenceCm: median(\.shoulderHeightDifferenceCm), pelvicHeightDifferenceCm: median(\.pelvicHeightDifferenceCm), headTiltDegrees: median(\.headTiltDegrees), spinalMidlineDeviationCm: median(\.spinalMidlineDeviationCm), thoracicRoundingDegrees: median(\.thoracicRoundingDegrees), forwardHeadAngleDegrees: median(\.forwardHeadAngleDegrees), cameraProxyAtrDegrees: nil, cameraProxyRibProminenceCm: nil, shoulderProtractionProxyDegrees: task == .standingSide ? median(\.forwardHeadAngleDegrees) : nil, pelvicTiltProxyDegrees: task == .standingSide ? median(\.thoracicRoundingDegrees) : nil, kneeAlignmentProxyRatio: task == .standingFront ? median(\.kneeAlignmentProxyRatio) : nil, lowerLimbAxisAsymmetryDegrees: task == .standingFront ? median(\.lowerLimbAxisAsymmetryDegrees) : nil, leftKneeValgusProxyDegrees: task == .dynamicKneeControl ? median(\.leftKneeValgusProxyDegrees) : nil, rightKneeValgusProxyDegrees: task == .dynamicKneeControl ? median(\.rightKneeValgusProxyDegrees) : nil, kneeTrackingAsymmetryRatio: task == .dynamicKneeControl ? median(\.kneeAlignmentProxyRatio).map(abs) : nil, squatDepthRatio: task == .dynamicKneeControl ? median(\.squatDepthRatio) : nil, movementRepetitionCount: task == .dynamicKneeControl ? Double(dynamicRepetitionCount) : nil, footArchVisibilityScore: task == .footArch ? median(\.footArchVisibilityScore) : nil, leftArchProxyIndex: nil, rightArchProxyIndex: nil, heelAlignmentProxyDegrees: task == .footArch ? median(\.heelAlignmentProxyDegrees) : nil, gaitShoulderSwingDifferenceCm: task == .gaitVideo ? gaitShoulder : nil, gaitPelvicSwingDifferenceCm: task == .gaitVideo ? gaitPelvic : nil, gaitTrunkSwayCm: task == .gaitVideo ? gaitSway : nil, captureProtocolVersion: "UY-CAPTURE-GUIDED-3.0", cameraFacing: currentPosition == .back ? "rear-1x" : "front-preview", measurementMode: "rgb-pose-2d", deviceCapabilityTier: "standard-2d", depthAvailable: false, segmentPhaseCount: requiresBilateralPhases ? 2 : 1, qualityChecks: checks, captureCalibration: .guided, captureAttemptCount: 1, repeatabilityStatus: "awaiting-second-take")
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
    let forwardBendCompletionScore: Double
    let kneeAlignmentProxyRatio: Double
    let lowerLimbAxisAsymmetryDegrees: Double
    let leftKneeValgusProxyDegrees: Double
    let rightKneeValgusProxyDegrees: Double
    let squatDepthRatio: Double
    let footArchVisibilityScore: Double
    let heelAlignmentProxyDegrees: Double
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
