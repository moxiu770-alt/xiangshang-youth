import SwiftUI
import AVKit

/// Course playback and family support entry. Progress resolves by courseId / lessonId.
struct CourseDetailSheet: View {
    let title: String
    /// Remote course cards pass their immutable id; legacy local cards fall
    /// back to a namespaced id until the catalogue is fully server-backed.
    var courseID: String? = nil
    var lessonID: String? = nil
    var remoteVideoSource: String? = nil
    var initialPositionMs: Int = 0
    var expectedProgressVersion: Int? = nil
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var state: AppState
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    @Environment(\.scenePhase) private var scenePhase
    @State private var isPlaying = false
    @State private var progress = 0.0
    @State private var player: AVPlayer?
    @State private var timeObserver: Any?
    @State private var playbackLoading = false
    @State private var playbackError: String?
    @State private var playbackRetryToken = 0
    @State private var playbackNotice: String?
    @State private var bufferingStartedAt: Date?
    @State private var credentialRefreshTask: Task<Void, Never>?
    @State private var resumeOverrideMs: Int?
    @State private var captionCount = 0
    @State private var lastRemoteCheckpointMs = 0
    @State private var remoteSaveInFlight = false
    @State private var draft = ""
    @State private var replyError: String?
    private var reduceMotion: Bool { state.localFeatures.settings.reduceMotion || systemReduceMotion }
    private var resolvedCourseID: String { courseID ?? "legacy-\(title.unicodeScalars.map { String($0.value, radix: 16) }.joined(separator: "-"))" }
    private var resolvedLessonID: String { lessonID ?? "legacy-lesson-\(resolvedCourseID)" }
    private var childID: String { state.selectedChild?.id ?? "unselected-child" }
    var body: some View {
        let commandState = state.workflowState(for: "support")
        return NavigationStack {
            VStack(spacing: 14) {
                if title == "客服咨询" {
                    Image(systemName: "message.fill").font(.system(size: 42)).foregroundStyle(ReferenceColor.blue)
                    Text("课程咨询").font(.title3.bold())
                    Text("咨询内容会自动保存并同步，提交后由服务团队跟进。", comment: "Support explanation").font(.system(size: 12)).foregroundStyle(.secondary).multilineTextAlignment(.center).padding(.horizontal, 22)
                    ScrollView { VStack(alignment: .leading, spacing: 8) { ForEach(state.localFeatures.supportMessages) { message in bubble(message.text, mine: message.isMine, status: message.status) } }.frame(maxWidth: .infinity, alignment: .leading) }.frame(maxHeight: 220).padding(.horizontal, 18)
                    HStack { TextField("输入咨询内容", text: $draft).textFieldStyle(.roundedBorder).onChange(of: draft) { _, value in state.saveDraft(value, key: supportDraftKey) }; Button { let text = draft.trimmingCharacters(in: .whitespacesAndNewlines); guard !text.isEmpty else { replyError = "请输入咨询内容。"; return }; Task { if await state.submitSupportCommand(text) { state.clearDraft(supportDraftKey); draft = ""; replyError = nil } } } label: { HStack(spacing: 4) { if commandState.isSubmitting { ProgressView() }; Text(commandState.isSubmitting ? "发送中" : "发送") } }.buttonStyle(.borderedProminent).disabled(commandState.isSubmitting || draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty) }.padding(.horizontal, 18)
                    if let replyError { Text(replyError).font(.system(size: 12)).foregroundStyle(.red) }
                    if case let .failed(message) = commandState { Text(message).font(.system(size: 12)).foregroundStyle(.red) }
                } else {
                    if playbackLoading {
                        ProgressView("正在加载课程…").frame(height: 190).frame(maxWidth: .infinity)
                    } else if let player {
                        NativeCoursePlayerView(player: player).frame(height: 190).clipShape(RoundedRectangle(cornerRadius: 12))
                    } else if state.usesRemoteDataSource {
                        EmptyStateView(title: "课程暂时无法播放", detail: playbackError ?? "学校完成课程资源配置后即可播放。")
                            .frame(maxWidth: .infinity)
                        Button("重新加载") { playbackRetryToken += 1 }.buttonStyle(.bordered)
                    }
                    Text(title).font(.title3.bold())
                    Text("课程播放进度会自动保存，联网后同步到孩子记录。").font(.system(size: 13)).foregroundStyle(.secondary).multilineTextAlignment(.center).padding(.horizontal, 28)
                    ProgressView(value: progress).tint(ReferenceColor.green).padding(.horizontal, 30)
                    if let playbackNotice { Text(playbackNotice).font(.footnote).foregroundStyle(.secondary).multilineTextAlignment(.center) }
                    if captionCount > 0 { Label("字幕可在播放器控制中选择", systemImage: "captions.bubble").font(.footnote).foregroundStyle(.secondary) }
                    Button { isPlaying.toggle(); if isPlaying { player?.play() } else { player?.pause() } } label: { Label(isPlaying ? "暂停学习" : "播放课程", systemImage: isPlaying ? "pause.fill" : "play.fill") }.buttonStyle(.borderedProminent).disabled(player == nil)
                    if let playbackError, player != nil {
                        Text(playbackError).font(.footnote).foregroundStyle(.red).multilineTextAlignment(.center)
                        Button("重试同步进度") { Task { await saveRemoteCheckpoint(completed: progress >= 0.999) } }.buttonStyle(.bordered).disabled(remoteSaveInFlight)
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("关闭") { player?.pause(); dismiss() } } }
            .task(id: "\(resolvedLessonID)|\(playbackRetryToken)") {
                if title == "客服咨询" { state.clearWorkflowState("support") }
                progress = state.courseProgress(childID: childID, courseID: resolvedCourseID, lessonID: resolvedLessonID, legacyTitle: title)
                draft = state.localFeatures.drafts[supportDraftKey] ?? ""
                if title != "客服咨询" { await preparePlayer() }
            }
            .onReceive(NotificationCenter.default.publisher(for: .AVPlayerItemDidPlayToEndTime)) { note in
                guard let item = player?.currentItem, note.object as AnyObject === item else { return }
                progress = 1; isPlaying = false
                state.updateCourseProgress(childID: childID, courseID: resolvedCourseID, lessonID: resolvedLessonID, progress: 1)
                Task { await saveRemoteCheckpoint(completed: true) }
            }
            .onReceive(NotificationCenter.default.publisher(for: .AVPlayerItemFailedToPlayToEndTime)) { note in
                guard let item = player?.currentItem, note.object as AnyObject === item else { return }
                isPlaying = false; playbackError = "课程播放中断，请检查网络后重新加载。"
            }
            .onChange(of: scenePhase) { _, phase in
                guard title != "客服咨询", phase != .active else { return }
                player?.pause(); isPlaying = false
                Task { await saveRemoteCheckpoint(completed: progress >= 0.999) }
            }
            .onDisappear {
                player?.pause()
                Task { await saveRemoteCheckpoint(completed: progress >= 0.999) }
                clearPlayer()
            }
        }
    }
    private var supportDraftKey: String { "support-\(title)" }
    @MainActor private func preparePlayer() async {
        clearPlayer(); playbackError = nil; playbackLoading = true
        defer { playbackLoading = false }
        let sourceURL: URL?
        var refreshAfterSeconds: Int?
        if state.usesRemoteDataSource {
            guard let lessonID else { playbackError = "课程缺少有效课时编号，请返回后刷新课程。"; return }
            do {
                let source = try await state.loadLessonPlayback(lessonID: lessonID)
                sourceURL = URL(string: source.videoSource)
                captionCount = source.captions?.count ?? 0
                refreshAfterSeconds = source.refreshAfterSeconds
            } catch {
                playbackError = error.localizedDescription
                return
            }
        } else {
            sourceURL = remoteVideoSource.flatMap(URL.init(string:)) ?? Bundle.main.url(forResource: "FollowAlongTraining", withExtension: "mp4")
        }
        guard let sourceURL else { playbackError = "课程视频地址无效，请联系学校更新课程资源。"; return }
        do {
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .moviePlayback)
            try AVAudioSession.sharedInstance().setActive(true)
        } catch {
            playbackNotice = "系统音频暂时不可用，可检查静音和播放设置。"
        }
        let loadedPlayer = AVPlayer(url: sourceURL)
        player = loadedPlayer
        timeObserver = loadedPlayer.addPeriodicTimeObserver(forInterval: CMTime(seconds: 0.5, preferredTimescale: 600), queue: .main) { time in
            Task { @MainActor in
                guard let duration = loadedPlayer.currentItem?.duration.seconds, duration.isFinite, duration > 0, time.seconds.isFinite else { return }
                let value = min(max(time.seconds / duration, 0), 1)
                let positionMs = max(0, Int(time.seconds * 1000))
                if loadedPlayer.timeControlStatus == .waitingToPlayAtSpecifiedRate {
                    if bufferingStartedAt == nil { bufferingStartedAt = Date() }
                    if let startedAt = bufferingStartedAt, Date().timeIntervalSince(startedAt) >= 4 {
                        playbackNotice = Date().timeIntervalSince(startedAt) >= 12 ? "网络连接不稳定，可暂停后重新加载。" : "网络较慢，正在继续缓冲…"
                    }
                } else {
                    bufferingStartedAt = nil
                    if playbackNotice?.contains("网络") == true { playbackNotice = nil }
                }
                progress = value
                state.updateCourseProgress(childID: childID, courseID: resolvedCourseID, lessonID: resolvedLessonID, progress: value)
                if positionMs - lastRemoteCheckpointMs >= 15_000 {
                    lastRemoteCheckpointMs = positionMs
                    await saveRemoteCheckpoint(completed: value >= 0.999)
                }
                if value >= 0.999 { isPlaying = false }
            }
        }
        if let asset = loadedPlayer.currentItem?.asset, let duration = try? await asset.load(.duration), duration.seconds.isFinite, duration.seconds > 0 {
            let requestedResume = resumeOverrideMs ?? initialPositionMs
            let resume = requestedResume > 0 ? Double(requestedResume) / 1000 : duration.seconds * progress
            if resume > 0 { await loadedPlayer.seek(to: CMTime(seconds: min(resume, duration.seconds), preferredTimescale: 600)) }
        }
        if let refreshAfterSeconds, refreshAfterSeconds > 0 {
            credentialRefreshTask = Task {
                try? await Task.sleep(for: .seconds(refreshAfterSeconds))
                guard !Task.isCancelled else { return }
                await MainActor.run {
                    let seconds = loadedPlayer.currentTime().seconds
                    resumeOverrideMs = seconds.isFinite ? max(0, Int(seconds * 1000)) : nil
                    playbackRetryToken += 1
                }
            }
        }
    }
    @MainActor private func saveRemoteCheckpoint(completed: Bool) async {
        guard state.usesRemoteDataSource, let lessonID, let player, !remoteSaveInFlight else { return }
        let seconds = player.currentTime().seconds
        guard seconds.isFinite, seconds > 0 || completed else { return }
        remoteSaveInFlight = true
        defer { remoteSaveInFlight = false }
        let currentVersion = state.remoteCourses.first(where: { $0.lessonID == lessonID })?.version ?? expectedProgressVersion
        do {
            try await state.saveRemoteLessonProgress(childID: childID, lessonID: lessonID, lastPositionMs: max(0, Int(seconds * 1000)), completed: completed, expectedVersion: currentVersion)
            playbackError = nil
        } catch {
            playbackError = "播放进度暂未同步：\(error.localizedDescription)"
        }
    }
    @MainActor private func clearPlayer() {
        credentialRefreshTask?.cancel(); credentialRefreshTask = nil
        if let timeObserver, let player { player.removeTimeObserver(timeObserver) }
        timeObserver = nil; player = nil; isPlaying = false; bufferingStartedAt = nil
    }
    private func bubble(_ text: String, mine: Bool, status: LocalSubmissionStatus) -> some View { VStack(alignment: mine ? .trailing : .leading, spacing: 3) { Text(text).font(.system(size: 12)).foregroundStyle(mine ? .white : ReferenceColor.navy).padding(9).background(mine ? ReferenceColor.blue : ReferenceColor.sky, in: RoundedRectangle(cornerRadius: 10)); if mine { Text(supportSyncLabel(status)).font(.system(size: 12)).foregroundStyle(status == .failed ? .red : .secondary) } }.frame(maxWidth: .infinity, alignment: mine ? .trailing : .leading) }
    private func supportSyncLabel(_ status: LocalSubmissionStatus) -> String { switch status { case .submitted: "已同步"; case .failed: "同步失败，可在设置中重试"; case .submitting: "正在同步"; case .draft: "未完成"; case .pendingSync: "已保存，联网后自动同步" } }
}
