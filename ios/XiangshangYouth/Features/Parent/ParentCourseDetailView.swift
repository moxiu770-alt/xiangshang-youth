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
    @State private var isPlaying = false
    @State private var progress = 0.0
    @State private var player: AVPlayer?
    @State private var timeObserver: Any?
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
                    if let player {
                        VideoPlayer(player: player).frame(height: 190).clipShape(RoundedRectangle(cornerRadius: 12))
                    } else if state.usesRemoteDataSource {
                        EmptyStateView(title: "课程视频待同步", detail: "学校完成课程资源配置后即可播放.")
                            .frame(maxWidth: .infinity)
                    }
                    Text(title).font(.title3.bold())
                    Text("课程播放进度会自动保存，联网后同步到孩子记录。").font(.system(size: 13)).foregroundStyle(.secondary).multilineTextAlignment(.center).padding(.horizontal, 28)
                    ProgressView(value: progress).tint(ReferenceColor.green).padding(.horizontal, 30)
                    Button { isPlaying.toggle(); if isPlaying { player?.play() } else { player?.pause() } } label: { Label(isPlaying ? "暂停学习" : "播放课程", systemImage: isPlaying ? "pause.fill" : "play.fill") }.buttonStyle(.borderedProminent).disabled(player == nil)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("关闭") { player?.pause(); dismiss() } } }
            .task {
                if title == "客服咨询" { state.clearWorkflowState("support") }
                progress = state.courseProgress(childID: childID, courseID: resolvedCourseID, lessonID: resolvedLessonID, legacyTitle: title)
                draft = state.localFeatures.drafts[supportDraftKey] ?? ""
                let localURL = state.usesRemoteDataSource ? nil : Bundle.main.url(forResource: "FollowAlongTraining", withExtension: "mp4")
                let sourceURL = remoteVideoSource.flatMap(URL.init(string:)) ?? localURL
                if title != "客服咨询", let url = sourceURL {
                    let loadedPlayer = AVPlayer(url: url)
                    player = loadedPlayer
                    timeObserver = loadedPlayer.addPeriodicTimeObserver(forInterval: CMTime(seconds: 0.5, preferredTimescale: 600), queue: .main) { time in
                        Task { @MainActor in
                            guard let duration = loadedPlayer.currentItem?.duration.seconds, duration.isFinite, duration > 0, time.seconds.isFinite else { return }
                            let value = min(max(time.seconds / duration, 0), 1)
                            progress = value
                            state.updateCourseProgress(childID: childID, courseID: resolvedCourseID, lessonID: resolvedLessonID, progress: value)
                            if value >= 0.999 { isPlaying = false }
                        }
                    }
                    if let asset = loadedPlayer.currentItem?.asset, let duration = try? await asset.load(.duration), duration.seconds.isFinite, duration.seconds > 0 {
                        let resume = initialPositionMs > 0 ? Double(initialPositionMs) / 1000 : duration.seconds * progress
                        if resume > 0 { await loadedPlayer.seek(to: CMTime(seconds: min(resume, duration.seconds), preferredTimescale: 600)) }
                    }
                }
            }
            .onDisappear {
                player?.pause()
                if let lessonID, state.usesRemoteDataSource, let player {
                    let seconds = player.currentTime().seconds
                    if seconds.isFinite { Task { try? await state.saveRemoteLessonProgress(childID: childID, lessonID: lessonID, lastPositionMs: max(0, Int(seconds * 1000)), completed: progress >= 0.999, expectedVersion: expectedProgressVersion) } }
                }
                if let timeObserver, let player { player.removeTimeObserver(timeObserver) }
                timeObserver = nil
            }
        }
    }
    private var supportDraftKey: String { "support-\(title)" }
    private func bubble(_ text: String, mine: Bool, status: LocalSubmissionStatus) -> some View { VStack(alignment: mine ? .trailing : .leading, spacing: 3) { Text(text).font(.system(size: 12)).foregroundStyle(mine ? .white : ReferenceColor.navy).padding(9).background(mine ? ReferenceColor.blue : ReferenceColor.sky, in: RoundedRectangle(cornerRadius: 10)); if mine { Text(supportSyncLabel(status)).font(.system(size: 12)).foregroundStyle(status == .failed ? .red : .secondary) } }.frame(maxWidth: .infinity, alignment: mine ? .trailing : .leading) }
    private func supportSyncLabel(_ status: LocalSubmissionStatus) -> String { switch status { case .submitted: "已同步"; case .failed: "同步失败，可在设置中重试"; case .submitting: "正在同步"; case .draft: "未完成"; case .pendingSync: "已保存，联网后自动同步" } }
}
