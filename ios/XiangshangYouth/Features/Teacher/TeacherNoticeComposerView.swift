import SwiftUI

struct TeacherNoticeComposerView: View {
    @EnvironmentObject private var state: AppState
    @EnvironmentObject private var router: AppRouter
    @State private var composerShown = false

    var body: some View {
        AppScaffold(title: "发布班级通知", onBack: { router.pop() }) {
            VStack(alignment: .leading, spacing: 14) {
                Text("通知将发送给已授权的班级家长")
                    .font(.headline)
                    .foregroundStyle(ReferenceColor.navy)
                Text("请勿填写学生身份证号、联系方式等敏感信息。发布后会显示待同步或已同步状态。")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Button { composerShown = true } label: {
                    Label("新建班级通知", systemImage: "square.and.pencil")
                        .font(.system(size: 16, weight: .bold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 13)
                        .foregroundStyle(.white)
                        .background(ReferenceColor.blue, in: RoundedRectangle(cornerRadius: 12))
                }
                .buttonStyle(.plain)
                Spacer()
            }
            .padding(16)
        }
        .sheet(isPresented: $composerShown) { TeacherNoticeFormSheet() }
    }
}

private struct TeacherNoticeFormSheet: View {
    @EnvironmentObject private var state: AppState
    @Environment(\.dismiss) private var dismiss
    @State private var selectedClassIDs: Set<String> = []
    @State private var title = ""
    @State private var content = ""
    @State private var notificationID: String?
    @State private var draftVersion: Int?
    @State private var parentReceiptEnabled = false
    @State private var validationMessage: String?
    @State private var submitted = false

    private let draftKey = "teacher-notice-draft"
    private var draftWorkflow: WorkflowCommandState { state.workflowState(for: "notice:draft") }
    private var sendWorkflow: WorkflowCommandState { notificationID.map { state.workflowState(for: "notice:send:\($0)") } ?? .idle }

    var body: some View {
        NavigationStack {
            Form {
                Section("接收范围") {
                    ForEach(state.managedTeacherClasses) { item in
                        Toggle(item.name, isOn: Binding(
                            get: { selectedClassIDs.contains(item.id) },
                            set: { enabled in
                                if enabled { selectedClassIDs.insert(item.id) }
                                else { selectedClassIDs.remove(item.id) }
                            }
                        ))
                    }
                    Toggle("需要家长确认回执", isOn: $parentReceiptEnabled)
                    Text("仅可发送至当前账号已授权班级的家长。")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Section("通知内容") {
                    TextField("通知标题", text: $title)
                    TextEditor(text: $content).frame(minHeight: 140)
                }
                if let validationMessage { Section { Text(validationMessage).foregroundStyle(.red) } }
                if case .failed(let message) = draftWorkflow { Section { Text(message).foregroundStyle(.red) } }
                if case .failed(let message) = sendWorkflow { Section { Text(message).foregroundStyle(.red) } }
                if submitted { Section { Label("已提交，家长将在消息中心收到通知。", systemImage: "checkmark.circle.fill").foregroundStyle(.green) } }
                if state.notificationDraftsLoading { Section { ProgressView("正在恢复草稿…") } }
                if let error = state.notificationDraftsError { Section { Text(error).foregroundStyle(.red) } }
            }
            .navigationTitle("发布班级通知")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
                ToolbarItem(placement: .topBarLeading) {
                    if let notificationID {
                        Button("放弃草稿") {
                            Task {
                                if await state.discardNotificationDraft(notificationID: notificationID) { dismiss() }
                            }
                        }
                        .disabled(draftWorkflow.isSubmitting || sendWorkflow.isSubmitting)
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("发送") {
                        Task { await saveAndSend() }
                    }
                    .disabled(!canSubmit || draftWorkflow.isSubmitting || sendWorkflow.isSubmitting)
                }
                ToolbarItem(placement: .bottomBar) {
                    Button("保存草稿") {
                        Task { await saveDraft() }
                    }
                    .disabled(!canSubmit || draftWorkflow.isSubmitting || sendWorkflow.isSubmitting)
                }
            }
            .onAppear {
                if selectedClassIDs.isEmpty, let first = state.managedTeacherClasses.first?.id { selectedClassIDs = [first] }
                restoreLocalDraft()
                Task { await restoreRemoteDraft() }
            }
            .onChange(of: title) { _, _ in persistLocalDraft() }
            .onChange(of: content) { _, _ in persistLocalDraft() }
        }
    }

    private var canSubmit: Bool {
        !selectedClassIDs.isEmpty && title.trimmingCharacters(in: .whitespacesAndNewlines).count >= 2 && content.trimmingCharacters(in: .whitespacesAndNewlines).count >= 4
    }

    private func restoreLocalDraft() {
        let saved = state.localFeatures.drafts[draftKey] ?? ""
        guard !saved.isEmpty, let newline = saved.firstIndex(of: "\n") else { return }
        title = String(saved[..<newline])
        content = String(saved[saved.index(after: newline)...])
    }

    private func persistLocalDraft() { state.saveDraft("\(title)\n\(content)", key: draftKey) }

    @MainActor private func restoreRemoteDraft() async {
        await state.loadNotificationDrafts()
        guard notificationID == nil, let draft = state.notificationDrafts.first else { return }
        notificationID = draft.notificationID
        draftVersion = draft.draftVersion
        title = draft.title
        content = draft.content
        selectedClassIDs = Set(draft.targetClassIDs.filter { id in state.managedTeacherClasses.contains { $0.id == id } })
        parentReceiptEnabled = draft.parentReceiptEnabled
    }

    private func validate() -> Bool {
        if selectedClassIDs.isEmpty { validationMessage = "请选择接收班级。"; return false }
        if title.trimmingCharacters(in: .whitespacesAndNewlines).count < 2 { validationMessage = "请填写通知标题。"; return false }
        if content.trimmingCharacters(in: .whitespacesAndNewlines).count < 4 { validationMessage = "请填写通知内容。"; return false }
        validationMessage = nil
        return true
    }

    @MainActor private func saveDraft() async {
        guard validate() else { return }
        if let draft = await state.saveNotificationDraft(notificationID: notificationID, classIDs: Array(selectedClassIDs), title: title, content: content, draftVersion: draftVersion, parentReceiptEnabled: parentReceiptEnabled) {
            notificationID = draft.notificationID
            draftVersion = draft.draftVersion
            state.clearDraft(draftKey)
        }
    }

    @MainActor private func saveAndSend() async {
        guard validate() else { return }
        guard let draft = await state.saveNotificationDraft(notificationID: notificationID, classIDs: Array(selectedClassIDs), title: title, content: content, draftVersion: draftVersion, parentReceiptEnabled: parentReceiptEnabled) else { return }
        notificationID = draft.notificationID
        draftVersion = draft.draftVersion
        if await state.sendNotificationDraft(notificationID: draft.notificationID) {
            state.clearDraft(draftKey)
            submitted = true
        }
    }
}
