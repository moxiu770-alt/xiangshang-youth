import SwiftUI
import AVKit
import AVFoundation
import UIKit
import Vision
import Darwin

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
                    Label(AlgorithmReleaseGate.pendingFollowAlongNotice, systemImage: "exclamationmark.shield.fill")
                        .font(.subheadline).foregroundStyle(ReferenceColor.navy)
                        .padding(16)
                        .background(Color.orange.opacity(0.09), in: RoundedRectangle(cornerRadius: 14))
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
                Label("家长陪同", systemImage: "person.2.fill")
                    .font(.subheadline.weight(.semibold)).foregroundStyle(ReferenceColor.blue)
            }
            Text(day.exercises.isEmpty ? "今天以恢复和身体感受记录为主，不需要强行训练。" : "先看示范，再打开摄像头跟着做。动作质量优先，出现不适请立即停止。")
                .font(.subheadline).foregroundStyle(.secondary)
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
                Text("跟做模式").font(.subheadline.weight(.semibold)).foregroundStyle(.white)
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
                                            Text(poseFeedback.visible ? "全身远景" : "取景准备")
                                        }
                                        .font(.system(size: 16, weight: .semibold))
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
                            Text("示范视频加载失败，可稍后重试").font(.subheadline)
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
                    .padding(18)
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
                        .font(.subheadline).foregroundStyle(.secondary)
                }
            }
            if cameraEnabled {
                HStack(spacing: 8) {
                    Circle()
                        .fill(poseFeedback.visible ? (poseFeedback.active ? ReferenceColor.green : .orange) : .gray)
                        .frame(width: 8, height: 8)
                    Text(poseFeedback.message).font(.subheadline).foregroundStyle(ReferenceColor.navy).lineLimit(2)
                    Spacer()
                Text("辅助计数 \(visualRepCount) 次 · 连击 \(poseFeedback.comboCount)").font(.subheadline.weight(.bold)).foregroundStyle(ReferenceColor.blue)
                }
                .padding(.horizontal, 4)
                cameraGuideCard
            }
        }
        .padding(16)
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
                            Text(exercise.cue).font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.leading)
                        }
                        Spacer()
                        Text("\(exercise.target)\(exercise.unit)").font(.subheadline.weight(.bold)).foregroundStyle(ReferenceColor.blue)
                    }
                    .padding(16)
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
                    Text("\(progress) / \(exercise.target) \(exercise.unit)").font(.subheadline.weight(.bold)).foregroundStyle(ReferenceColor.blue)
                }
                if poseFeedback.visible {
                    Label(poseFeedback.active ? "动作已开始" : "画面已就绪，等待动作幅度", systemImage: poseFeedback.active ? "viewfinder.circle.fill" : "viewfinder")
                        .font(.subheadline).foregroundStyle(poseFeedback.active ? ReferenceColor.green : .secondary)
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
                Text("家长记录用于确认实际完成量；摄像头仅显示待验证的辅助计数，不作为准确率或标准动作证明。")
                    .font(.subheadline).foregroundStyle(.secondary)
            }
            .padding(16)
            .background(ReferenceColor.green.opacity(0.08), in: RoundedRectangle(cornerRadius: 14))
        }
    }

    private var safetyCard: some View {
        Label("家长陪同提示：保持镜头稳定、留出安全距离；孩子疲劳、疼痛或头晕时马上暂停。跟做数据只用于健康习惯记录，不构成医疗诊断。", systemImage: "heart.text.square.fill")
            .font(.subheadline).foregroundStyle(ReferenceColor.navy)
            .padding(16).background(ReferenceColor.blue.opacity(0.08), in: RoundedRectangle(cornerRadius: 14))
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
                    .font(.subheadline.weight(.semibold)).foregroundStyle(poseFeedback.visible ? ReferenceColor.green : .secondary)
            }
            Text(poseFeedback.message)
                .font(.subheadline).foregroundStyle(.secondary)
                .lineLimit(2)
            phaseStrip
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text("动作范围").font(.subheadline.weight(.semibold)).foregroundStyle(ReferenceColor.navy)
                    Spacer()
                    Text("\(poseFeedback.rangePercent)% · \(poseFeedback.side.rawValue)").font(.subheadline.weight(.bold)).foregroundStyle(ReferenceColor.blue)
                }
                ProgressView(value: Double(poseFeedback.rangePercent), total: 100).tint(poseFeedback.rangePercent >= 70 ? ReferenceColor.green : ReferenceColor.blue)
                Text(poseFeedback.tempoScore > 0 ? "节奏匹配 \(poseFeedback.tempoScore)% · 跟随示范停顿后再回位" : "先跟随示范完成一整次，系统会校准你的节奏")
                    .font(.subheadline).foregroundStyle(.secondary)
            }
            if let exercise {
                TimelineView(.periodic(from: .now, by: 0.25)) { _ in
                    let position = max(player?.currentTime().seconds ?? 0, 0)
                    let cadence = max(exercise.cadenceSeconds, 0.4)
                    let beat = Int(position / cadence).quotientAndRemainder(dividingBy: 4).remainder + 1
                    Label("模板第 \(beat) 拍 · \(String(format: "%.1f", cadence)) 秒/拍 · 实时节拍同步", systemImage: "metronome")
                        .font(.subheadline.weight(.semibold)).foregroundStyle(ReferenceColor.blue)
                }
            }
            HStack(spacing: 6) {
                guideStep(number: "1", title: "竖屏", detail: "手机稳定")
                guideStep(number: "2", title: "全身", detail: "头肩髋脚")
                guideStep(number: "3", title: "准备", detail: "保持 2 秒")
            }
            if let exercise {
                Label("当前动作：\(exercise.title) · \(exercise.cue)", systemImage: "figure.run")
                    .font(.subheadline).foregroundStyle(ReferenceColor.navy)
                    .lineLimit(2)
            }
        }
        .padding(16)
        .background(ReferenceColor.blue.opacity(0.07), in: RoundedRectangle(cornerRadius: 14))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("动作引导。\(poseFeedback.message)。请竖屏、保持全身远景并静止两秒完成准备。")
    }

    private var phaseStrip: some View {
        HStack(spacing: 6) {
            ForEach([FollowAlongStage.setup, .exertion, .returnPhase], id: \.self) { stage in
                Text(stage.rawValue)
                    .font(.subheadline.weight(.bold))
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
            Text(number).font(.subheadline.bold()).foregroundStyle(.white)
                .frame(width: 18, height: 18).background(ReferenceColor.blue, in: Circle())
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(.subheadline.bold()).foregroundStyle(ReferenceColor.navy)
                Text(detail).font(.system(size: 16)).foregroundStyle(.secondary)
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
                Image(systemName: "person.crop.circle.badge.checkmark").font(.title2).foregroundStyle(ReferenceColor.green)
                Text("本次训练已由家长确认").font(.headline).foregroundStyle(ReferenceColor.navy)
                Spacer()
            }
            let total = day.exercises.reduce(0) { $0 + exerciseProgress[$1.id, default: 0] }
                Text("已记录 \(total) 个动作单位（辅助识别 \(visualUnitCount)，家长补录 \(manualUnits)）。辅助识别尚未通过人工标注验证，不作为标准动作评分。")
                .font(.subheadline).foregroundStyle(.secondary)
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
        speak("本次训练已按家长确认保存。")
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
            qualityScore: 0, cameraVerified: false,
            visualUnits: visualUnits, manualUnits: manualUnits,
            modelVersion: ChildFollowAlongTuning.algorithmVersion, mode: "parentConfirmedAssistedTraining"
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
            // Do not crop the camera feed into a close-up inside the coach
            // window. The complete frame makes foot and hand placement visible.
            layer.videoGravity = .resizeAspect
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
                    if let _ = try? device.lockForConfiguration() {
                        device.videoZoomFactor = min(max(1, device.minAvailableVideoZoomFactor), device.maxAvailableVideoZoomFactor)
                        device.unlockForConfiguration()
                    }
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
