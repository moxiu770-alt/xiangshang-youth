import SwiftUI
import UIKit
import PhotosUI
import UniformTypeIdentifiers

struct AccountDashboard: View {
    @EnvironmentObject private var state: AppState
    @EnvironmentObject private var router: AppRouter
    @State private var dialog: String?
    @State private var legalDocument: LegalDocument?
    @State private var settingsShown = false
    var body: some View {
        ScrollView {
            VStack(spacing: 10) {
                ParentPageNavigation(title: "我的")
                Button { dialog = "个人资料" } label: {
                    HStack(spacing: 12) {
                        Image(state.selectedRole == .teacher ? "TeacherAvatar" : "ChildAvatar").resizable().scaledToFill().frame(width: 54, height: 54).background(ReferenceColor.sky, in: Circle()).clipShape(Circle())
                        VStack(alignment: .leading, spacing: 3) { Text(state.activeDisplayName).font(.system(size: 16, weight: .bold)); Text(state.profile?.schoolName ?? "学校").font(.system(size: 12)).foregroundStyle(.secondary); RoleBadge(role: state.selectedRole ?? .parent) }
                        Spacer()
                        Image(systemName: "chevron.right").foregroundStyle(.secondary)
                    }
                    .padding(14).background(.white, in: RoundedRectangle(cornerRadius: 12))
                    .contentShape(RoundedRectangle(cornerRadius: 12))
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 12)
                .accessibilityElement(children: .combine)
                .accessibilityLabel("查看个人资料")
                if state.selectedRole == .parent {
                    HStack(spacing: 8) {
                        accountMetric(title: "已绑定孩子", value: "\(state.boundChildren.count)", action: { router.push(.children(returnAfterBinding: false)) })
                        accountMetric(title: "成长报告", value: "\(state.boundChildren.filter { state.hasPublishedSchoolReport(for: $0) }.count)", action: { if let child = state.selectedChild { router.push(.report(child)) } else { router.push(.children(returnAfterBinding: true)) } })
                        accountMetric(title: "未读消息", value: "\(state.unreadMessageCount)", action: { router.push(.parentMessages) })
                    }.padding(.horizontal, 12)
                    if state.pendingSyncCount > 0 {
                        Button { settingsShown = true } label: {
                            HStack(spacing: 9) {
                                Image(systemName: "arrow.triangle.2.circlepath.circle.fill").foregroundStyle(.orange)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("有 \(state.pendingSyncCount) 条记录等待同步").font(.system(size: 12, weight: .bold))
                                    Text("已保存，联网后自动同步").font(.system(size: 12)).foregroundStyle(.secondary)
                                }
                                Spacer()
                                Text("查看").font(.system(size: 12, weight: .semibold)).foregroundStyle(ReferenceColor.blue)
                                Image(systemName: "chevron.right").font(.system(size: 12)).foregroundStyle(ReferenceColor.blue)
                            }
                            .padding(11).background(.orange.opacity(0.10), in: RoundedRectangle(cornerRadius: 10))
                        }
                        .buttonStyle(.plain)
                        .padding(.horizontal, 12)
                        .accessibilityLabel("有 \(state.pendingSyncCount) 条记录等待同步，查看同步状态")
                    }
                    ReferenceSectionTitle(title: "家庭服务", trailing: "孩子管理", action: { router.push(.children(returnAfterBinding: false)) }).padding(.horizontal, 12)
                } else {
                    let managedClassCount = min(state.data?.classes.count ?? 0, 2)
                    let reviewCount = state.data?.students.filter { state.taskStatus(for: $0) == .review || state.taskStatus(for: $0) == .retest }.count ?? 0
                    HStack(spacing: 8) {
                        accountMetric(title: "管理班级", value: "\(managedClassCount)", action: { router.push(.teacherClasses) })
                        accountMetric(title: "待处理", value: "\(reviewCount)", action: { router.push(.reviewList) })
                        accountMetric(title: "未读消息", value: "\(state.unreadMessageCount)", action: { router.push(.teacherMessages) })
                    }.padding(.horizontal, 12)
                    ReferenceSectionTitle(title: "教师工作台", trailing: "查看数据", action: { router.push(.teacherClassBoard) }).padding(.horizontal, 12)
                }
                if state.selectedRole == .teacher {
                    accountRow("个人信息", "person.text.rectangle.fill", ReferenceColor.blue) { dialog = "个人信息" }
                    accountRow("我的权限", "lock.shield.fill", ReferenceColor.green) { dialog = "我的权限" }
                    accountRow("工作数据", "chart.bar.fill", ReferenceColor.purple) { router.push(.teacherClassBoard) }
                    accountRow("设置", "gearshape.fill", .orange) { settingsShown = true }
                    accountRow("消息", "bell.fill", .red) { router.push(.teacherMessages) }
                } else {
                    accountRow("我的健康档案", "heart.text.square.fill", ReferenceColor.green) { router.push(.healthProfile) }
                    accountRow("我的课程", "play.rectangle.fill", ReferenceColor.blue) { router.push(.parentCourses) }
                    accountRow("客服咨询", "message.fill", ReferenceColor.purple) { dialog = "客服咨询" }
                    accountRow("消息", "bell.fill", .red) { router.push(.parentMessages) }
                }
                ReferenceSectionTitle(title: "服务与安全", trailing: "隐私安全").padding(.horizontal, 12)
                accountRow("通知与显示设置", "gearshape.fill", .orange) { settingsShown = true }
                accountRow("帮助与反馈", "questionmark.circle.fill", ReferenceColor.blue) { dialog = "帮助与反馈" }
                accountRow("数据与隐私", "hand.raised.fill", ReferenceColor.green) { dialog = "数据与隐私" }
                accountRow("用户服务协议", "doc.text.fill", .secondary) { legalDocument = .userAgreement }
                accountRow("隐私政策", "hand.raised.square.fill", .secondary) { legalDocument = .privacy }
                accountRow("儿童个人信息保护声明", "person.2.fill", .secondary) { legalDocument = .childPrivacy }
                Button { state.chooseAnotherRole(); router.reset() } label: { Label("切换使用角色", systemImage: "arrow.left.arrow.right").font(.system(size: 12, weight: .bold)).frame(maxWidth: .infinity).padding(.vertical, 11).foregroundStyle(ReferenceColor.blue).background(ReferenceColor.sky, in: RoundedRectangle(cornerRadius: 10)) }.buttonStyle(.plain).padding(.horizontal, 12)
                Button { state.switchAccount(); router.reset() } label: { Text("切换账号").font(.system(size: 12, weight: .bold)).frame(maxWidth: .infinity).padding(.vertical, 11).foregroundStyle(.red).background(.red.opacity(0.08), in: RoundedRectangle(cornerRadius: 10)) }.buttonStyle(.plain).padding(.horizontal, 12)
            }.padding(.bottom, 10)
        }.background(ReferenceColor.canvas)
        .sheet(item: Binding(get: { dialog.map(CourseSheetItem.init) }, set: { dialog = $0?.name })) { item in
            if ["个人资料", "个人信息", "我的权限", "帮助与反馈", "数据与隐私"].contains(item.name) {
                AccountInfoSheet(title: item.name)
            } else {
                CourseDetailSheet(title: item.name)
            }
        }
        .sheet(item: $legalDocument) { document in LegalDocumentView(document: document) }
        .sheet(isPresented: $settingsShown) { AppSettingsSheet() }
    }
    private func accountMetric(title: String, value: String, action: @escaping () -> Void) -> some View { Button(action: action) { VStack(spacing: 3) { Text(value).font(.system(size: 18, weight: .bold)).foregroundStyle(ReferenceColor.blue); Text(title).font(.system(size: 12)).foregroundStyle(.secondary) }.frame(maxWidth: .infinity).padding(.vertical, 10).background(.white, in: RoundedRectangle(cornerRadius: 10)) }.buttonStyle(.plain) }
    private func accountRow(_ title: String, _ icon: String, _ color: Color, action: @escaping () -> Void) -> some View { Button(action: action) { HStack(spacing: 10) { Image(systemName: icon).foregroundStyle(color).frame(width: 34, height: 34).background(color.opacity(0.10), in: RoundedRectangle(cornerRadius: 9)); Text(title).font(.system(size: 12, weight: .semibold)); Spacer(); Image(systemName: "chevron.right").font(.system(size: 12)).foregroundStyle(.secondary) }.foregroundStyle(ReferenceColor.navy).padding(11).background(.white, in: RoundedRectangle(cornerRadius: 10)) }.buttonStyle(.plain).padding(.horizontal, 12) }
}

struct AppSettingsSheet: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var state: AppState
    @State private var showingClearDataConfirmation = false
    var body: some View {
        NavigationStack {
            Form {
                Section("通知与显示") {
                    Toggle("显示应用内测评与班级提醒", isOn: Binding(
                        get: { state.localFeatures.settings.notificationsEnabled },
                        set: { state.updateSettings(notificationsEnabled: $0) }
                    ))
                    Toggle("减少动态效果", isOn: Binding(
                        get: { state.localFeatures.settings.reduceMotion },
                        set: { state.updateSettings(reduceMotion: $0) }
                    ))
                    Toggle("语音动作引导", isOn: Binding(
                        get: { state.localFeatures.settings.voiceGuidanceEnabled },
                        set: { state.updateSettings(voiceGuidanceEnabled: $0) }
                    ))
                    Text("当前显示应用内消息；开启系统通知后可及时收到提醒。")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                Section("隐私与产品改进") {
                    Toggle("发送匿名使用情况", isOn: Binding(
                        get: { state.localFeatures.settings.analyticsEnabled },
                        set: { state.updateSettings(analyticsEnabled: $0) }
                    ))
                    Text("仅发送页面事件、App版本和本次启动随机会话；不发送孩子身份、学校、手机号、健康数值或摄像头内容。")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                Section("同步状态") {
                    LabeledContent("待同步记录", value: "\(state.pendingSyncCount) 条")
                    Text(state.pendingSyncCount == 0
                         ? "当前没有等待同步的本地操作。"
                         : "记录已保存，联网后会自动同步。")
                        .font(.footnote).foregroundStyle(.secondary)
                    let syncState = state.workflowState(for: "sync-pending")
                    Button { Task { await state.syncPendingRecords() } } label: {
                        HStack {
                            if syncState.isSubmitting { ProgressView() }
                            Text(syncState.isSubmitting ? "正在同步…" : "立即同步")
                        }
                    }
                    .disabled(state.pendingSyncCount == 0 || syncState.isSubmitting)
                    if case let .succeeded(message) = syncState {
                        Text(message).font(.footnote).foregroundStyle(ReferenceColor.green)
                    }
                    if case let .failed(message) = syncState {
                        Text(message).font(.footnote).foregroundStyle(.red)
                    }
                }
                Section("账号安全") {
                    Text("退出登录会清除设备上的绑定孩子、草稿和通知状态；学校测评记录不会受影响。")
                        .font(.footnote).foregroundStyle(.secondary)
                    Button("清除设备数据并退出登录", role: .destructive) {
                        showingClearDataConfirmation = true
                    }
                }
            }
            .navigationTitle("设置")
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("完成") { dismiss() } } }
            .confirmationDialog("清除设备数据？", isPresented: $showingClearDataConfirmation, titleVisibility: .visible) {
                Button("清除并退出", role: .destructive) { state.switchAccount(); dismiss() }
                Button("取消", role: .cancel) {}
            } message: {
                Text("此操作会移除本设备上的登录态、孩子绑定和本地草稿，后续可重新登录。")
            }
        }
    }
}

struct AccountInfoSheet: View {
    let title: String
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var state: AppState
    @State private var feedback = ""
    @State private var feedbackSubmitted = false
    @State private var showingDeleteConfirmation = false
    @State private var showingConsentRevokeConfirmation = false
    @State private var showingAccountDeletionConfirmation = false
    private let feedbackDraftKey = "account-feedback"
    var body: some View {
        let commandState = state.workflowState(for: "support")
        NavigationStack {
            Form {
                if title == "个人资料" || title == "个人信息" {
                    Section("账号信息") {
                        LabeledContent("姓名", value: state.activeDisplayName)
                        LabeledContent("手机号", value: maskedPhone(state.profile?.phone ?? ""))
                        LabeledContent("所属学校", value: state.profile?.schoolName ?? "学校")
                        Text("账号信息由学校或平台管理员维护。") .font(.footnote).foregroundStyle(.secondary)
                    }
                } else if title == "我的权限" {
                    Section("当前权限") { Label("查看测评、报告和成长建议", systemImage: "checkmark.circle.fill").foregroundStyle(ReferenceColor.green); Label("管理所负责班级数据", systemImage: "checkmark.circle.fill").foregroundStyle(ReferenceColor.green); Text("权限以学校后台授权为准。") .font(.footnote).foregroundStyle(.secondary) }
                } else if title == "帮助与反馈" {
                    Section("问题反馈") {
                        if feedbackSubmitted {
                            Label("反馈已保存，联网后自动同步。", systemImage: "checkmark.circle.fill").foregroundStyle(ReferenceColor.green)
                        } else {
                            TextEditor(text: $feedback).frame(minHeight: 110).onChange(of: feedback) { _, value in state.saveDraft(value, key: feedbackDraftKey) }
                            if case let .failed(message) = commandState { Text(message).font(.caption).foregroundStyle(.red) }
                            Button {
                                let message = feedback.trimmingCharacters(in: .whitespacesAndNewlines)
                                guard !message.isEmpty else { return }
                                Task { if await state.submitSupportCommand(message) { state.clearDraft(feedbackDraftKey); feedbackSubmitted = true } }
                            } label: {
                                HStack(spacing: 6) { if commandState.isSubmitting { ProgressView() }; Text(commandState.isSubmitting ? "正在提交…" : "提交反馈") }
                            }
                            .disabled(commandState.isSubmitting || feedback.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        }
                    }
                    Section("常见问题") { Text("孩子绑定码由学校或班主任提供。\n测评报告生成后会在消息中心通知。\n如遇数据异常，请联系学校管理员。") .font(.footnote).foregroundStyle(.secondary) }
                } else if title == "数据与隐私" {
                    let child = state.selectedChild
                    let exportState = child.map { state.workflowState(for: "privacy:\($0.id):export") } ?? .idle
                    let deleteState = child.map { state.workflowState(for: "privacy:\($0.id):delete") } ?? .idle
                    let revokeState = child.map { state.workflowState(for: "privacy:\($0.id):consent-revoke") } ?? .idle
                    let accountDeleteState = state.workflowState(for: "privacy:account-deletion")
                    Section("孩子数据") {
                        LabeledContent("当前孩子", value: child?.name ?? "请先绑定并选择孩子")
                        Text("仅可为已绑定孩子提交申请。导出文件生成后会通过消息中心通知；删除申请需要学校或平台审核，审核前不会删除任何记录。")
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                    Section("数据权利") {
                        Button { guard let child else { return }; Task { _ = await state.submitPrivacyRequest(studentID: child.id, type: .export) } } label: {
                            HStack { if exportState.isSubmitting { ProgressView() }; Text(exportState.isSubmitting ? "正在提交…" : "申请导出孩子数据") }
                        }.disabled(child == nil || exportState.isSubmitting)
                        if case let .succeeded(message) = exportState { Text(message).font(.footnote).foregroundStyle(ReferenceColor.green) }
                        if case let .failed(message) = exportState { Text(message).font(.footnote).foregroundStyle(.red) }
                        Button("申请删除/匿名化处理", role: .destructive) { showingDeleteConfirmation = true }.disabled(child == nil || deleteState.isSubmitting)
                        if case let .succeeded(message) = deleteState { Text(message).font(.footnote).foregroundStyle(ReferenceColor.green) }
                        if case let .failed(message) = deleteState { Text(message).font(.footnote).foregroundStyle(.red) }
                        Button("撤回身体测评数据使用同意", role: .destructive) { showingConsentRevokeConfirmation = true }
                            .disabled(child == nil || revokeState.isSubmitting)
                        if case let .succeeded(message) = revokeState { Text(message).font(.footnote).foregroundStyle(ReferenceColor.green) }
                        if case let .failed(message) = revokeState { Text(message).font(.footnote).foregroundStyle(.red) }
                        Button("申请注销当前账户", role: .destructive) { showingAccountDeletionConfirmation = true }
                            .disabled(accountDeleteState.isSubmitting)
                        if case let .succeeded(message) = accountDeleteState { Text(message).font(.footnote).foregroundStyle(ReferenceColor.green) }
                        if case let .failed(message) = accountDeleteState { Text(message).font(.footnote).foregroundStyle(.red) }
                    }
                } else {
                    Section("协议说明") { Text("向上少年仅在获得授权后处理学生健康与运动数据，用于测评、报告和课程建议。儿童账号和家庭绑定数据不会用于商业推广。") .font(.footnote).foregroundStyle(.secondary); Text("协议版本：2026.1") .font(.footnote).foregroundStyle(.secondary) }
                }
            }
            .navigationTitle(title)
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("完成") { dismiss() } } }
            .task {
                if title == "帮助与反馈" {
                    state.clearWorkflowState("support")
                    feedback = state.localFeatures.drafts[feedbackDraftKey] ?? ""
                }
            }
            .confirmationDialog("提交删除/匿名化申请？", isPresented: $showingDeleteConfirmation, titleVisibility: .visible) {
                Button("提交申请", role: .destructive) { if let child = state.selectedChild { Task { _ = await state.submitPrivacyRequest(studentID: child.id, type: .delete) } } }
                Button("取消", role: .cancel) {}
            } message: { Text("此操作不会立即删除数据。学校或平台审核通过前，测评记录仍会保留。") }
            .confirmationDialog("撤回身体测评数据使用同意？", isPresented: $showingConsentRevokeConfirmation, titleVisibility: .visible) {
                Button("确认撤回", role: .destructive) {
                    if let child = state.selectedChild { Task { _ = await state.revokeHealthConsent(studentID: child.id) } }
                }
                Button("取消", role: .cancel) {}
            } message: { Text("撤回后，新的身体测评提交前需要重新授权；已完成的学校记录不会被自动删除。") }
            .confirmationDialog("申请注销当前账户？", isPresented: $showingAccountDeletionConfirmation, titleVisibility: .visible) {
                Button("提交注销申请", role: .destructive) { Task { _ = await state.submitAccountDeletionRequest() } }
                Button("取消", role: .cancel) {}
            } message: { Text("账户会先进入审核队列。批准后将撤销登录会话并匿名化账户信息；学校侧已完成的测评记录按留存规则处理。") }
        }
    }

    private func maskedPhone(_ phone: String) -> String {
        let digits = phone.filter(\.isNumber)
        guard digits.count >= 7 else { return phone.isEmpty ? "未绑定手机号" : phone }
        let start = digits.prefix(3)
        let end = digits.suffix(4)
        return "\(start)****\(end)"
    }
}

struct CourseSheetItem: Identifiable { let name: String; var id: String { name } }
struct PublishClassPostSheet: View {
    let author: String
    var editingPost: ClassPostDraft?
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var state: AppState
    @State private var content = ""
    @State private var validationMessage: String?
    @State private var submitted = false
    @State private var selectedPhoto: PhotosPickerItem?
    @State private var attachmentName: String?
    @State private var attachmentReference: String?
    @State private var attachmentType = "image"
    @State private var attachmentError: String?
    private var workflowKey: String { "post:\(state.profile?.id ?? "session")" }
    private var draftKey: String { "class-post-\(editingPost?.id.uuidString ?? state.profile?.id ?? "session")" }
    var body: some View {
        let commandState = state.workflowState(for: workflowKey)
        return NavigationStack {
            VStack(alignment: .leading, spacing: 14) {
                if submitted {
                    VStack(spacing: 12) {
                        Image(systemName: "checkmark.circle.fill").font(.system(size: 48)).foregroundStyle(ReferenceColor.green)
                        Text(editingPost == nil ? "动态已保存" : "修改已保存").font(.title3.bold())
                        Text("内容已保存，联网后自动同步。").font(.system(size: 12)).foregroundStyle(.secondary).multilineTextAlignment(.center)
                        Spacer()
                        Button("完成") { dismiss() }.font(.system(size: 14, weight: .bold)).frame(maxWidth: .infinity).padding(.vertical, 12).foregroundStyle(.white).background(ReferenceColor.blue, in: RoundedRectangle(cornerRadius: 11))
                    }
                } else {
                    Text(editingPost == nil ? "发布班级动态" : "编辑班级动态").font(.title3.bold())
                    Text("内容会自动保存并同步，请勿发布学生隐私信息。").font(.system(size: 12)).foregroundStyle(.secondary)
                    TextEditor(text: $content).frame(minHeight: 160).padding(8).overlay(RoundedRectangle(cornerRadius: 10).stroke(validationMessage == nil ? ReferenceColor.navy.opacity(0.15) : .red, lineWidth: 1)).onChange(of: content) { _, value in state.saveDraft(value, key: draftKey) }
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Label(attachmentName ?? "可添加 1 个图片或视频附件", systemImage: attachmentName == nil ? "photo.badge.plus" : attachmentType == "video" ? "video.fill" : "photo.fill")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(attachmentName == nil ? .secondary : ReferenceColor.blue)
                            Spacer()
                            PhotosPicker(selection: $selectedPhoto, matching: .any(of: [.images, .videos])) {
                                Text(attachmentName == nil ? "选择附件" : "更换")
                                    .font(.system(size: 12, weight: .bold))
                            }
                            .frame(minWidth: 44, minHeight: 44)
                            if attachmentName != nil {
                                Button("移除") {
                                    selectedPhoto = nil
                                    attachmentName = nil
                                    attachmentReference = nil
                                    attachmentType = "image"
                                    attachmentError = nil
                                }
                                .font(.system(size: 12, weight: .bold))
                                .foregroundStyle(.red)
                                .frame(minWidth: 44, minHeight: 44)
                            }
                        }
                        Text("仅支持 JPG、PNG 或 MP4，最大 20MB。发布前会先上传到学校文件服务；页面不会保存相册原始路径。")
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                        if let attachmentError { Text(attachmentError).font(.system(size: 12)).foregroundStyle(.red) }
                    }
                    .padding(12)
                    .background(ReferenceColor.sky.opacity(0.65), in: RoundedRectangle(cornerRadius: 12))
                    .onChange(of: selectedPhoto) { _, item in
                        guard let item else { return }
                        Task { await loadSelectedPhoto(item) }
                    }
                    if let validationMessage { Text(validationMessage).font(.system(size: 12)).foregroundStyle(.red) }
                    if case let .failed(message) = commandState { Text(message).font(.system(size: 12)).foregroundStyle(.red) }
                    Spacer()
                    Button {
                        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
                        guard !trimmed.isEmpty else { validationMessage = "动态内容不能为空。"; return }
                        let attachments = attachmentReference.map { [ClassPostAttachment(id: attachmentName ?? "班级圈附件", type: attachmentType, objectID: nil, localReference: $0, thumbnailObjectID: nil)] } ?? []
                        if let editingPost { state.updateClassPost(id: editingPost.id, text: trimmed); state.clearDraft(draftKey); submitted = true }
                        else { Task { if await state.submitClassPostCommand(trimmed, author: author, attachments: attachments) { state.clearDraft(draftKey); submitted = true } } }
                    } label: {
                        HStack { if commandState.isSubmitting { ProgressView().tint(.white) }; Text(commandState.isSubmitting ? "正在提交…" : editingPost == nil ? "保存动态" : "保存修改") }
                            .font(.system(size: 14, weight: .bold)).frame(maxWidth: .infinity).padding(.vertical, 12).foregroundStyle(.white).background(ReferenceColor.blue, in: RoundedRectangle(cornerRadius: 11))
                    }
                    .disabled(commandState.isSubmitting || content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .padding(18)
            .navigationBarTitleDisplayMode(.inline)
            .task {
                if editingPost == nil { state.clearWorkflowState(workflowKey) }
                content = editingPost?.content ?? state.localFeatures.drafts[draftKey] ?? state.localFeatures.drafts["class-post-\(author)"] ?? ""
                if let attachment = editingPost?.attachments?.first {
                    attachmentName = attachment.id
                    attachmentReference = attachment.localReference
                    attachmentType = attachment.type
                }
            }
        }
    }

    @MainActor
    private func loadSelectedPhoto(_ item: PhotosPickerItem) async {
        attachmentError = nil
        do {
            guard let data = try await item.loadTransferable(type: Data.self) else { throw CourseAttachmentError.unavailable }
            let kind = try CourseAttachmentStore.mediaKind(for: item.supportedContentTypes)
            let mediaName = kind.type == "video" ? "班级圈视频" : "班级圈照片"
            let stored = try CourseAttachmentStore.persistMediaData(data, suggestedName: "\(mediaName)-\(UUID().uuidString).\(kind.extension)")
            attachmentName = stored.name
            attachmentReference = stored.reference
            attachmentType = kind.type
        } catch {
            attachmentError = error.localizedDescription
            attachmentName = nil
            attachmentReference = nil
            attachmentType = "image"
        }
    }
}
struct HealthArticleSheet: View {
    let title: String
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @State private var openFailed = false
    var body: some View {
        NavigationStack {
            VStack(spacing: 15) {
                Image(systemName: "book.closed.fill").font(.system(size: 44)).foregroundStyle(ReferenceColor.green)
                Text(title).font(.title3.bold()).multilineTextAlignment(.center)
                Text("完整健康专栏将由“向上少年健康成长”微信公众号提供。") .font(.system(size: 13)).foregroundStyle(.secondary).multilineTextAlignment(.center).padding(.horizontal, 28)
                if openFailed { Text("当前设备未安装微信，请直接搜索公众号：向上少年健康成长。").font(.system(size: 12)).foregroundStyle(.red).multilineTextAlignment(.center).padding(.horizontal, 24) }
                Button {
                    let url = URL(string: "weixin://")!
                    if UIApplication.shared.canOpenURL(url) { openURL(url); dismiss() } else { openFailed = true }
                } label: { Label(openFailed ? "重试打开微信" : "打开微信公众号", systemImage: "arrow.up.forward.app") }.buttonStyle(.borderedProminent)
                Text("若未安装微信，可搜索公众号：向上少年健康成长").font(.system(size: 12)).foregroundStyle(.secondary)
            }.frame(maxWidth: .infinity, maxHeight: .infinity).navigationTitle("健康科普").navigationBarTitleDisplayMode(.inline).toolbar { ToolbarItem(placement: .topBarTrailing) { Button("关闭") { dismiss() } } }
        }
    }
}

struct ParentHealthDimension: View {
    let category: AssessmentCategory; let detail: String; let color: Color
    @EnvironmentObject private var state: AppState
    @EnvironmentObject private var router: AppRouter
    private var hasRecord: Bool { guard let child = state.selectedChild else { return false }; return state.familyHealthRecord(for: child, category: category) != nil }
    var body: some View { Button { if state.selectedChild != nil { router.push(.assessment(category)) } else { router.push(.children(returnAfterBinding: true)) } } label: {
        HStack(spacing: 10) { Image(systemName: category.icon).font(.system(size: 16, weight: .bold)).foregroundStyle(color).frame(width: 34, height: 34).background(color.opacity(0.10), in: RoundedRectangle(cornerRadius: 9)); VStack(alignment: .leading, spacing: 3) { Text(category.rawValue).font(.system(size: 12, weight: .bold)); Text(detail).font(.system(size: 12)).foregroundStyle(.secondary) }; Spacer(); Text(hasRecord ? "已保存" : "去填写").font(.system(size: 12, weight: .bold)).foregroundStyle(color); Image(systemName: "chevron.right").font(.system(size: 12)).foregroundStyle(.secondary) }
            .foregroundStyle(ReferenceColor.navy).padding(10).background(.white, in: RoundedRectangle(cornerRadius: 10))
    }.buttonStyle(.plain).accessibilityLabel(hasRecord ? "查看\(category.rawValue)家庭健康记录" : "填写\(category.rawValue)家庭健康记录") }
}
