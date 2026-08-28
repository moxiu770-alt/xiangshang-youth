import SwiftUI

/// Activity discovery, registration, amendment, cancellation, and history.
/// Business identifiers remain activityId / registrationId; visible titles are display-only.
struct ActivityListView: View {
    @EnvironmentObject private var state: AppState
    @State private var selected: RemoteActivity?
    @State private var showingHistory = false
    private var visibleRegistrationHistory: [ActivityRegistrationAck] {
        state.activityRegistrationHistory.filter { $0.childID == state.selectedChild?.id || $0.childID == nil }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 9) {
                ParentPageNavigation(title: "成长活动", showsBack: true)
                if state.activitiesLoading {
                    LoadingStateView().padding(.top, 24)
                } else if state.usesRemoteDataSource, let error = state.activitiesError {
                    ErrorStateView(message: error) { Task { await state.loadActivities() } }
                        .padding(.horizontal, AppTheme.pagePadding)
                } else if displayActivities.isEmpty {
                    EmptyStateView(title: "暂无可报名活动", detail: "学校发布活动后会显示在这里。")
                        .padding(.horizontal, AppTheme.pagePadding)
                } else {
                    ForEach(displayActivities) { activity in
                        Button { selected = activity } label: {
                            HStack(spacing: 12) {
                                Image("ParentCampaign").resizable().scaledToFill().frame(width: 64, height: 54).clipShape(RoundedRectangle(cornerRadius: 12))
                                VStack(alignment: .leading, spacing: 5) {
                                    Text(activity.title).font(.system(size: 16, weight: .bold)).foregroundStyle(ReferenceColor.navy)
                                    Text(activity.description ?? "活动说明以学校通知为准").font(.system(size: 16)).foregroundStyle(.secondary).lineLimit(2)
                                    Text(activity.registrationEndAt.map { "报名截止 · \($0.prefix(10))" } ?? "报名时间待通知").font(.system(size: 16, weight: .semibold)).foregroundStyle(ReferenceColor.blue)
                                }
                                Spacer()
                                Image(systemName: "chevron.right").font(.system(size: 16)).foregroundStyle(.secondary)
                            }
                            .padding(16)
                            .background(.white, in: RoundedRectangle(cornerRadius: 12))
                        }
                        .buttonStyle(.plain)
                        .padding(.horizontal, AppTheme.pagePadding)
                    }
                }
                if !visibleRegistrationHistory.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("报名历史").font(.system(size: 15, weight: .bold)).foregroundStyle(ReferenceColor.navy)
                            Spacer()
                            Button("查看全部") { showingHistory = true }
                                .font(.system(size: 16, weight: .semibold))
                                .frame(minHeight: 44)
                        }
                        .padding(.horizontal, AppTheme.pagePadding)
                        ForEach(visibleRegistrationHistory.prefix(5)) { item in
                            HStack {
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(item.activityTitle ?? item.activityID).font(.system(size: 15, weight: .bold)).foregroundStyle(ReferenceColor.navy)
                                    Text(item.updatedAt.map { "更新时间 · \(String($0.prefix(16)))" } ?? "报名记录").font(.system(size: 16)).foregroundStyle(.secondary)
                                }
                                Spacer()
                                Text(activityHistoryStatus(item.status)).font(.system(size: 16, weight: .bold)).foregroundStyle(item.status == "cancelled" ? .red : ReferenceColor.blue)
                            }
                            .padding(16)
                            .background(.white, in: RoundedRectangle(cornerRadius: 12))
                            .padding(.horizontal, AppTheme.pagePadding)
                        }
                    }
                    .padding(.top, 6)
                }
            }
            .padding(.bottom, 10)
        }
        .background(ReferenceColor.canvas)
        .task { await state.loadActivities() }
        .onChange(of: displayActivities.map(\.activityID)) { _, _ in consumePendingActivity() }
        .sheet(item: $selected) { item in ActivityDetailSheet(title: item.title, activity: item) }
        .sheet(isPresented: $showingHistory) { ActivityRegistrationHistorySheet(history: visibleRegistrationHistory) }
    }

    private var displayActivities: [RemoteActivity] {
        if state.usesRemoteDataSource { return state.remoteActivities }
        return [RemoteActivity(activityID: "health-growth-season-2026", schoolID: nil, title: "向上少年健康成长季", description: "综合测评 · 运动表现更出彩", startsAt: nil, endsAt: nil, capacity: 60, registrationStartAt: nil, registrationEndAt: "2026-09-10", status: "open", version: 1, registeredCount: 42, remainingCapacity: 18, registrationID: nil, registrationStatus: nil, childID: nil)]
    }
    private func consumePendingActivity() {
        guard let target = state.pendingActivityID,
              let activity = displayActivities.first(where: { $0.activityID == target }) else { return }
        selected = activity
        state.clearActivityTarget()
    }
    private func activityHistoryStatus(_ value: String) -> String {
        switch value { case "confirmed": return "已确认"; case "pending": return "待确认"; case "cancelled": return "已取消"; case "rejected": return "未通过"; default: return value }
    }
}
private struct ActivityRegistrationHistorySheet: View {
    let history: [ActivityRegistrationAck]
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 10) {
                    if history.isEmpty {
                        EmptyStateView(title: "暂无报名历史", detail: "完成报名、修改或取消后会显示记录。")
                    } else {
                        ForEach(history) { item in
                            VStack(alignment: .leading, spacing: 8) {
                                HStack(alignment: .top) {
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(item.activityTitle ?? item.activityID)
                                            .font(.system(size: 15, weight: .bold))
                                            .foregroundStyle(ReferenceColor.navy)
                                        Text("报名编号 \(item.registrationID)")
                                            .font(.system(size: 16))
                                            .foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    Text(activityStatus(item.status))
                                        .font(.system(size: 16, weight: .bold))
                                        .foregroundStyle(item.status == "cancelled" ? .red : ReferenceColor.blue)
                                }
                                HStack {
                                    Text(item.updatedAt.map { "更新 \(String($0.prefix(16)))" } ?? "待学校同步时间")
                                    Spacer()
                                    Text(item.version.map { "版本 \($0)" } ?? "版本待同步")
                                }
                                .font(.system(size: 16))
                                .foregroundStyle(.secondary)
                            }
                            .padding(18)
                            .background(.white, in: RoundedRectangle(cornerRadius: 14))
                        }
                    }
                }
                .padding(16)
            }
            .background(ReferenceColor.canvas)
            .navigationTitle("报名历史")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("关闭") { dismiss() } } }
        }
    }

    private func activityStatus(_ value: String) -> String {
        switch value {
        case "confirmed": return "已确认"
        case "pending": return "待确认"
        case "cancelled": return "已取消"
        case "rejected": return "未通过"
        default: return value
        }
    }
}

struct ActivityDetailSheet: View {
    let title: String
    var activity: RemoteActivity? = nil
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var state: AppState
    @State private var contactName = ""
    // Keep production forms free of mock contact data.  A verified account
    // phone is seeded when the sheet opens; otherwise the field is blank.
    @State private var phone = ""
    @State private var consented = false
    @State private var validationMessage: String?
    @State private var isEditingRegistration = false
    private var activityID: String { activity?.activityID ?? "health-growth-season-2026" }
    private var draftKey: String { "activity-registration-\(activityID)-\(selectedChildID ?? "none")" }
    private var legacyDraftKey: String { "activity-registration-\(activityID)" }
    private var commandKey: String { "activity:\(activityID)\(selectedChildID.map { ":\($0)" } ?? "")" }
    private var cancelCommandKey: String { "activity-cancel:\(activityID)\(selectedChildID.map { ":\($0)" } ?? "")" }
    private var selectedChildID: String? { state.selectedChild?.id }

    var body: some View {
        let registered = state.localFeatures.activityRegistrations.contains {
            $0.activityID == activityID &&
            ($0.childID == selectedChildID || $0.childID == nil) &&
            $0.registrationStatus != "cancelled" &&
            $0.status != .failed
        }
        let commandState = state.workflowState(for: commandKey)
        let cancelCommandState = state.workflowState(for: cancelCommandKey)
        let hasFailure: Bool = { if case .failed = commandState { return true }; return false }()
        NavigationStack { GeometryReader { geometry in ScrollView { VStack(alignment: .leading, spacing: 16) {
            Image("ParentCampaign")
                .resizable()
                .scaledToFill()
                .frame(width: max(0, geometry.size.width - 32), height: 180)
                .clipped()
                .clipShape(RoundedRectangle(cornerRadius: 16))
            Text(title).font(.title3.bold()).fixedSize(horizontal: false, vertical: true)
            Label(activity?.startsAt.map { "\($0.prefix(10)) · 以学校通知为准" } ?? (state.repository.supportsRemoteAcknowledgement ? "活动时间以学校通知为准" : "2026 秋季测评 · 以学校通知为准"), systemImage: "calendar").font(.system(size: 16)).foregroundStyle(.secondary)
            Text(activity?.description ?? (state.repository.supportsRemoteAcknowledgement
                 ? "完成综合健康测评，了解孩子的运动发展与健康成长情况。提交后将同步至孩子成长档案。"
                 : "完成综合健康测评，了解孩子的运动发展与健康成长情况。报名信息会自动保存并同步。"))
                .font(.system(size: 16)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            VStack(alignment: .leading, spacing: 8) { Text("活动说明").font(.system(size: 16, weight: .bold)); Text("• 完成四项健康测评\n• 查看个性化成长报告\n• 可预约学校体测场地") .font(.system(size: 16)).foregroundStyle(ReferenceColor.navy).fixedSize(horizontal: false, vertical: true) }.frame(maxWidth: .infinity, alignment: .leading).padding(18).background(ReferenceColor.sky, in: RoundedRectangle(cornerRadius: 12))
            HStack(spacing: 10) {
                activityMetric("剩余名额", capacityText, ReferenceColor.green)
                activityMetric("报名截止", deadlineText, ReferenceColor.blue)
                activityMetric("学校确认", registrationStatusText(registered: registered), ReferenceColor.yellow)
            }
            if case let .failed(message) = cancelCommandState {
                Text(message).font(.system(size: 16)).foregroundStyle(.red)
            }
            if registered && !hasFailure && !isEditingRegistration {
                VStack(alignment: .leading, spacing: 8) {
                    Label(state.repository.supportsRemoteAcknowledgement
                          ? "报名已确认，活动开始前将通过消息中心通知您。"
                          : "报名信息已保存，联网后自动同步。", systemImage: "checkmark.circle.fill")
                        .font(.system(size: 16, weight: .medium)).foregroundStyle(ReferenceColor.green)
                    Button("修改报名信息") {
                        if let record = state.localFeatures.activityRegistrations.first(where: { $0.activityID == activityID && ($0.childID == selectedChildID || $0.childID == nil) }) { contactName = record.contactName; phone = record.phone }
                        isEditingRegistration = true
                        state.clearWorkflowState(commandKey)
                    }.font(.system(size: 16, weight: .semibold))
                    Button("取消报名") {
                        Task {
                            if await state.cancelActivityRegistrationCommand(activityID) {
                                isEditingRegistration = false
                            }
                        }
                    }
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.red)
                }
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    Text("报名信息").font(.system(size: 15, weight: .bold))
                    TextField("联系人姓名", text: $contactName).textFieldStyle(.roundedBorder)
                    TextField("手机号", text: $phone).keyboardType(.phonePad).textFieldStyle(.roundedBorder)
                    Toggle("已阅读活动说明并同意接收报名通知", isOn: $consented).font(.system(size: 15)).fixedSize(horizontal: false, vertical: true)
                }
                .onChange(of: contactName) { _, _ in saveDraft() }
                .onChange(of: phone) { _, _ in saveDraft() }
                .onChange(of: consented) { _, _ in saveDraft() }
                if let validationMessage { Text(validationMessage).font(.system(size: 16)).foregroundStyle(.red) }
                if case let .failed(message) = commandState { Text(message).font(.system(size: 16)).foregroundStyle(.red) }
            }
            Button {
                guard !contactName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { validationMessage = "请填写联系人姓名。"; return }
                guard phone.filter(\.isNumber).count == 11 else { validationMessage = "请填写 11 位手机号。"; return }
                guard consented else { validationMessage = "请先确认活动说明和通知授权。"; return }
                validationMessage = nil
                Task {
                    let success = await state.submitActivityCommand(activityID, contactName: contactName, phone: phone)
                    if success { state.clearDraft(draftKey); isEditingRegistration = false }
                }
            } label: {
                HStack(spacing: 7) {
                    if commandState.isSubmitting { ProgressView().tint(.white) }
                    Text(commandState.isSubmitting ? "正在提交…" : isEditingRegistration ? "更新报名信息" : registered ? "已保存待同步" : "确认报名")
                }
                .font(.system(size: 16, weight: .bold)).frame(maxWidth: .infinity).padding(.vertical, 12).foregroundStyle(.white).background(hasFailure ? .orange : registered ? ReferenceColor.green : ReferenceColor.blue, in: RoundedRectangle(cornerRadius: 12))
            }
            .buttonStyle(.plain).disabled(commandState.isSubmitting || (registered && !hasFailure && !isEditingRegistration))
        }
        .frame(width: max(0, geometry.size.width - 32), alignment: .leading)
        .padding(.horizontal, 16).padding(.vertical, 16)
        } }
        .scrollDismissesKeyboard(.interactively)
        .navigationTitle("活动详情").navigationBarTitleDisplayMode(.inline).toolbar { ToolbarItem(placement: .topBarTrailing) { Button("关闭") { dismiss() }.frame(minWidth: 44, minHeight: 44) } }
        .task {
            let persistedDraft = state.localFeatures.drafts[draftKey] ?? state.localFeatures.drafts[legacyDraftKey]
            if let values = persistedDraft?.split(separator: "|", maxSplits: 2).map(String.init), values.count >= 2 {
                contactName = values[0]
                phone = values[1]
                consented = values.count == 3 && values[2] == "1"
            } else {
                // A registration establishes a real family identity. Seed a
                // fresh activity form from it rather than reverting to the
                // mock default name, while always preserving an existing draft.
                contactName = state.activeDisplayName
                if let profilePhone = state.profile?.phone,
                   profilePhone.filter(\.isNumber).count == 11 {
                    phone = profilePhone
                } else {
                    phone = ""
                }
            }
        }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
    }

    private func saveDraft() { state.saveDraft("\(contactName)|\(phone)|\(consented ? "1" : "0")", key: draftKey) }
    private var capacityText: String {
        if let remaining = activity?.remainingCapacity, let capacity = activity?.capacity { return "\(remaining)/\(capacity)" }
        if let remaining = activity?.remainingCapacity { return "\(remaining)" }
        return "待学校发布"
    }
    private var deadlineText: String {
        guard let value = activity?.registrationEndAt else { return "待通知" }
        return String(value.prefix(10))
    }
    private func registrationStatusText(registered: Bool) -> String {
        switch activity?.registrationStatus {
        case "confirmed": return "已确认"
        case "pending": return "待确认"
        case "cancelled": return "已取消"
        default: return registered ? "待通知" : "未报名"
        }
    }
    private func activityMetric(_ label: String, _ value: String, _ color: Color) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(value).font(.system(size: 16, weight: .bold)).foregroundStyle(color)
            Text(label).font(.system(size: 16)).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(.white, in: RoundedRectangle(cornerRadius: 10))
    }
}
