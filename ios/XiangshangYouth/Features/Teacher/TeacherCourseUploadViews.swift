import SwiftUI
import UniformTypeIdentifiers
import AVFoundation
import UIKit

/// The sports-upload root is intentionally independent from the teacher
/// dashboard so attachment capture and draft persistence do not make the
/// task/analytics screen another all-purpose feature file.
struct SportsUploadDashboard: View {
    @EnvironmentObject private var state: AppState
    @State private var isUploadFormShown = false
    private var uploadTaskRecord: TestTask? { state.data?.tasks.first }
    private var taskID: String { uploadTaskRecord?.id ?? "sports-upload-local" }
    private var uploadClassName: String { uploadTaskRecord?.className ?? state.managedTeacherClasses.first?.name ?? "我的班级" }
    private var uploadTaskTitle: String { uploadTaskRecord?.title ?? "课后测评任务" }
    var body: some View { ScrollView { VStack(spacing: 10) {
        ParentPageNavigation(title: "延时课程上传")
        ReferenceCard { VStack(alignment: .leading, spacing: 9) { ReferenceSectionTitle(title: "\(uploadClassName) · 课后记录", trailing: uploadTaskRecord?.date ?? "待排期"); Label("请上传测评结果记录与课堂照片", systemImage: "camera.badge.ellipsis").font(.system(size: 16)).foregroundStyle(.secondary); HStack { uploadTile("photo.on.rectangle", "课堂照片"); uploadTile("doc.text.fill", "测评记录"); uploadTile("person.3.fill", "出勤名单") } } }.padding(.horizontal, AppTheme.pagePadding)
        ReferenceCard { VStack(alignment: .leading, spacing: 7) { Text("待上传课程").font(.system(size: 15, weight: .bold)); uploadTask(uploadTaskTitle, uploadTaskRecord == nil ? "暂无已排期任务" : "可填写并保存记录") } }.padding(.horizontal, AppTheme.pagePadding)
        let submitted = state.localFeatures.uploadedTaskIDs.contains(taskID)
        Button { isUploadFormShown = true } label: { Text(submitted ? "查看课程记录" : "填写并保存课程记录").font(.system(size: 15, weight: .bold)).frame(maxWidth: .infinity).padding(.vertical, 11).foregroundStyle(.white).background(submitted ? ReferenceColor.green : .orange, in: RoundedRectangle(cornerRadius: 10)) }.buttonStyle(.plain).padding(.horizontal, AppTheme.pagePadding)
        if let record = state.localFeatures.courseUploads.first(where: { $0.taskID == taskID }) { Text(record.status == .pendingSync ? "已保存 · 待同步：\(record.attachmentName) · 出勤 \(record.attendanceCount) 人" : record.status == .submitted ? "已同步：\(record.attachmentName) · 出勤 \(record.attendanceCount) 人" : record.status == .failed ? "同步失败，稍后可在设置中重试：\(record.attachmentName)" : "已保存草稿：\(record.notes)").font(.system(size: 16)).foregroundStyle(record.status == .failed ? .red : .secondary).padding(.horizontal, AppTheme.pagePadding) }
    }.padding(.bottom, 10) }
        .background(ReferenceColor.canvas)
        .overlay {
            if let error = state.error, state.data == nil {
                ErrorStateView(message: error) { Task { await state.refreshDashboard() } }
                    .frame(maxWidth: .infinity, maxHeight: .infinity).background(ReferenceColor.canvas)
            } else if state.loading || state.data == nil {
                ZStack { ReferenceColor.canvas.ignoresSafeArea(); LoadingStateView() }
            } else if state.data?.tasks.isEmpty == true {
                EmptyStateView(title: "暂无课程上传任务", detail: "学校发布延时课程后，上传入口会显示在这里。")
                    .frame(maxWidth: .infinity, maxHeight: .infinity).background(ReferenceColor.canvas)
            }
        }
        .sheet(isPresented: $isUploadFormShown) { CourseUploadSheet(taskID: taskID) }
    }
    private func uploadTile(_ icon: String, _ title: String) -> some View { Button { isUploadFormShown = true } label: { VStack(spacing: 5) { Image(systemName: icon).font(.system(size: 18)).foregroundStyle(ReferenceColor.blue); Text(title).font(.system(size: 16, weight: .medium)) }.frame(maxWidth: .infinity).padding(.vertical, 8).background(ReferenceColor.sky, in: RoundedRectangle(cornerRadius: 8)) }.buttonStyle(.plain).accessibilityLabel("上传\(title)") }
    private func uploadTask(_ title: String, _ status: String) -> some View { Button { isUploadFormShown = true } label: { HStack { Image(systemName: "figure.run").foregroundStyle(ReferenceColor.green); VStack(alignment: .leading) { Text(title).font(.system(size: 16, weight: .bold)); Text(status).font(.system(size: 16)).foregroundStyle(.secondary) }; Spacer(); Image(systemName: "chevron.right").font(.system(size: 16)).foregroundStyle(.secondary) }.padding(.vertical, 4) }.buttonStyle(.plain).accessibilityLabel("查看\(title)\(status)") }
}

struct CourseUploadSheet: View {
    let taskID: String
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var state: AppState
    @State private var attendance = ""
    @State private var notes = ""
    @State private var attachment = ""
    @State private var attachmentReference: String?
    @State private var error: String?
    @State private var isImporterShown = false
    @State private var isCameraShown = false
    private var draftKey: String { "course-upload-\(taskID)" }
    var body: some View {
        let commandState = state.workflowState(for: "course:\(taskID)")
        return NavigationStack {
            Form {
                Section("课程记录") {
                    TextField("出勤人数", text: $attendance).keyboardType(.numberPad)
                    TextField("课堂记录", text: $notes, axis: .vertical).lineLimit(3...5)
                    LabeledContent("课堂附件", value: attachment)
                    Button("拍摄课堂照片") { openCamera() }.accessibilityHint("需要相机权限；模拟器或无相机设备可使用文件选择")
                    Button("从文件选择照片") { isImporterShown = true }
                }
                Section {
                    Button("保存草稿") { save(submit: false) }
                    Button {
                        guard let count = Int(attendance), count > 0 else { error = "请填写大于 0 的有效出勤人数。"; return }
                        guard !notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, !attachment.isEmpty, attachmentReference?.isEmpty == false else { error = "提交前请补齐课堂记录并选择可上传的照片附件。"; return }
                        Task { if await state.submitCourseUploadCommand(taskID: taskID, attendanceCount: count, notes: notes, attachmentName: attachment, attachmentReference: attachmentReference) { state.clearDraft(draftKey); dismiss() } }
                    } label: { HStack { if commandState.isSubmitting { ProgressView() }; Text(commandState.isSubmitting ? "正在提交…" : "提交审核") } }
                    .disabled(commandState.isSubmitting || (Int(attendance) ?? 0) <= 0 || notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || attachment.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || attachmentReference?.isEmpty != false)
                    if case let .failed(message) = commandState { Text(message).foregroundStyle(.red) }
                }
                if let error { Section { Text(error).foregroundStyle(.red) } }
            }
            .navigationTitle("延时课程上传")
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("关闭") { dismiss() } } }
            .task {
                if let record = state.localFeatures.courseUploads.first(where: { $0.taskID == taskID }) { attendance = String(record.attendanceCount); notes = record.notes; attachment = record.attachmentName; attachmentReference = record.attachmentReference }
                else if let draft = state.localFeatures.drafts[draftKey]?.split(separator: "|", maxSplits: 2).map(String.init), draft.count == 3 { attendance = draft[0]; notes = draft[1]; attachment = draft[2] }
            }
            .onChange(of: attendance) { _, _ in saveDraft() }.onChange(of: notes) { _, _ in saveDraft() }.onChange(of: attachment) { _, _ in saveDraft() }
            .fileImporter(isPresented: $isImporterShown, allowedContentTypes: [.image]) { result in
                do { if case let .success(url) = result { let stored = try CourseAttachmentStore.persistImportedFile(url); attachment = stored.name; attachmentReference = stored.reference; error = nil } } catch let uploadError { error = uploadError.localizedDescription }
            }
            .sheet(isPresented: $isCameraShown) { CameraPicker(onImage: { image in
                do { let stored = try CourseAttachmentStore.persistCameraImage(image); attachment = stored.name; attachmentReference = stored.reference; error = nil } catch let cameraError { error = cameraError.localizedDescription }
                isCameraShown = false
            }, onCancel: { isCameraShown = false }) }
        }
    }
    private func saveDraft() { state.saveDraft("\(attendance)|\(notes)|\(attachment)", key: draftKey) }
    private func save(submit: Bool) { guard let count = Int(attendance), count >= 0 else { error = "请填写有效的出勤人数。"; return }; if submit && (notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || attachment.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || attachmentReference == nil) { error = "提交前请补齐课堂记录并选择可上传的照片附件。"; return }; state.saveCourseUpload(taskID: taskID, attendanceCount: count, notes: notes, attachmentName: attachment, attachmentReference: attachmentReference, submit: submit); if submit { state.clearDraft(draftKey); dismiss() } else { error = "草稿已保存，可稍后继续编辑。" } }
    private func openCamera() {
        guard UIImagePickerController.isSourceTypeAvailable(.camera) else { error = "当前设备没有可用相机，请使用文件选择照片。"; return }
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized: isCameraShown = true
        case .notDetermined: AVCaptureDevice.requestAccess(for: .video) { granted in Task { @MainActor in if granted { isCameraShown = true } else { error = "相机权限未开启，请在系统设置中允许相机，或使用文件选择。" } } }
        case .denied, .restricted: error = "相机权限未开启，请在系统设置中允许相机，或使用文件选择。"
        @unknown default: error = "暂时无法使用相机，请使用文件选择照片。"
        }
    }
}

private struct CameraPicker: UIViewControllerRepresentable {
    let onImage: (UIImage) -> Void
    let onCancel: () -> Void
    func makeCoordinator() -> Coordinator { Coordinator(onImage: onImage, onCancel: onCancel) }
    func makeUIViewController(context: Context) -> UIImagePickerController { let picker = UIImagePickerController(); picker.sourceType = .camera; picker.mediaTypes = ["public.image"]; picker.delegate = context.coordinator; return picker }
    func updateUIViewController(_ controller: UIImagePickerController, context: Context) {}
    final class Coordinator: NSObject, UINavigationControllerDelegate, UIImagePickerControllerDelegate {
        let onImage: (UIImage) -> Void; let onCancel: () -> Void
        init(onImage: @escaping (UIImage) -> Void, onCancel: @escaping () -> Void) { self.onImage = onImage; self.onCancel = onCancel }
        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) { if let image = info[.originalImage] as? UIImage { onImage(image) } else { onCancel() } }
        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) { onCancel() }
    }
}
