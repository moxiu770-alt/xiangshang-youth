import SwiftUI

/// Expert catalogue and appointment lifecycle UI. Appointments are always routed by stable IDs.
struct ExpertDetailSheet: View {
    let name: String
    var expert: RemoteExpert? = nil
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var state: AppState
    @State private var date = ""
    @State private var selectedDate = Date()
    @State private var selectedSlot = ""
    @State private var selectedRemoteSlot: ExpertAvailableSlot?
    @State private var note = ""
    @State private var submitted = false
    @State private var isEditingBooking = false
    private var draftKey: String { "expert-\(expertID)-\(currentChildID ?? "none")" }
    private var legacyDraftKey: String { "expert-\(name)" }
    private var expertID: String { expert?.expertID ?? "" }
    private var commandKey: String { "expert:\(expertID)\(currentChildID.map { ":\($0)" } ?? "")" }
    private var cancelCommandKey: String { "expert-cancel:\(expertID)\(currentChildID.map { ":\($0)" } ?? "")" }
    var body: some View { NavigationStack { VStack(spacing: 14) {
        Image(systemName: "person.crop.circle.badge.checkmark").font(.system(size: 48)).foregroundStyle(ReferenceColor.blue)
        Text("\(name) · 健康成长专家").font(.title3.bold())
        Text(expert?.bio ?? "擅长儿童运动发展与健康评估，可为孩子提供体质、运动及成长建议。提交预约后会安排跟进。")
            .font(.system(size: 15)).foregroundStyle(.secondary).multilineTextAlignment(.center).padding(.horizontal, 28)
        let commandState = state.workflowState(for: commandKey)
        let failed: Bool = { if case .failed = commandState { return true }; return false }()
        if case let .failed(message) = state.workflowState(for: cancelCommandKey) {
            Text(message).font(.system(size: 16)).foregroundStyle(.red).padding(.horizontal, 20)
        }
        if submitted && !failed && !isEditingBooking { VStack(spacing: 9) { Label(state.repository.supportsRemoteAcknowledgement ? "预约已确认。" : "预约已保存，联网后自动同步。", systemImage: "checkmark.circle.fill").font(.system(size: 16)).foregroundStyle(ReferenceColor.green); Text(date).font(.system(size: 16, weight: .semibold)).foregroundStyle(.secondary); Button("修改预约信息") { isEditingBooking = true; state.clearWorkflowState(commandKey) }.buttonStyle(.bordered); Button("取消预约") { Task { if await state.cancelExpertCommand(expertID: expertID, expertName: name) { submitted = false; dismiss() } } }.buttonStyle(.bordered).tint(.red) } } else { VStack(alignment: .leading, spacing: 10) { DatePicker("选择日期", selection: $selectedDate, in: Date()..., displayedComponents: .date).datePickerStyle(.compact).onChange(of: selectedDate) { _, _ in updatePreferredDateDraft() }; Text("可预约时段").font(.system(size: 15, weight: .bold)); if state.usesRemoteDataSource && availableRemoteSlots.isEmpty { Text(state.expertSlotErrors[expertID] ?? "当前暂无可预约时段").font(.system(size: 16)).foregroundStyle(.secondary) }; LazyVGrid(columns: [GridItem(.adaptive(minimum: 120), spacing: 8)], spacing: 8) { ForEach(slotLabels, id: \.id) { slot in Button { selectedSlot = slot.label; selectedRemoteSlot = slot.remote; updatePreferredDateDraft() } label: { Text(slot.label).font(.system(size: 16, weight: .bold)).frame(maxWidth: .infinity).padding(.vertical, 10).foregroundStyle(selectedSlot == slot.label ? .white : ReferenceColor.navy).background(selectedSlot == slot.label ? ReferenceColor.blue : ReferenceColor.sky, in: RoundedRectangle(cornerRadius: 10)) }.buttonStyle(.plain) } }; if !date.isEmpty { Label("已选：\(date)", systemImage: "calendar.badge.clock").font(.system(size: 16)).foregroundStyle(ReferenceColor.blue) }; TextField("咨询说明", text: $note, axis: .vertical).lineLimit(3...5).textFieldStyle(.roundedBorder) }.padding(.horizontal, 20).onChange(of: note) { _, _ in state.saveDraft("\(date)|\(note)", key: draftKey) }; if case let .failed(message) = commandState { Text(message).font(.subheadline).foregroundStyle(.red) }; Button { Task { let success = isEditingBooking ? await state.rescheduleExpertCommand(name: name, preferredDate: date, note: note, expertID: expertID, serviceID: selectedRemoteSlot?.serviceID, slotID: selectedRemoteSlot?.slotID, scheduledStartAt: selectedRemoteSlot?.scheduledStartAt, scheduledEndAt: selectedRemoteSlot?.scheduledEndAt) : await state.submitExpertCommand(name: name, preferredDate: date, note: note, expertID: expertID, serviceID: selectedRemoteSlot?.serviceID, slotID: selectedRemoteSlot?.slotID, scheduledStartAt: selectedRemoteSlot?.scheduledStartAt, scheduledEndAt: selectedRemoteSlot?.scheduledEndAt); if success { state.clearDraft(draftKey); submitted = true; isEditingBooking = false } } } label: { HStack { if commandState.isSubmitting { ProgressView() }; Text(commandState.isSubmitting ? "正在提交…" : isEditingBooking ? "更新预约" : failed ? "重新提交" : "提交预约") } }.buttonStyle(.borderedProminent).disabled(commandState.isSubmitting || date.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty) }
    }.frame(maxWidth: .infinity, maxHeight: .infinity).navigationTitle("专家详情").navigationBarTitleDisplayMode(.inline).toolbar { ToolbarItem(placement: .topBarTrailing) { Button("关闭") { dismiss() } } }.task { guard !expertID.isEmpty else { return }; await state.loadExpertSlots(expertID: expertID); let persistedDraft = state.localFeatures.drafts[draftKey] ?? state.localFeatures.drafts[legacyDraftKey]; if let saved = persistedDraft?.split(separator: "|", maxSplits: 1).map(String.init), saved.count == 2 { date = saved[0]; note = saved[1] } else if let saved = state.localFeatures.expertAppointments.first(where: { $0.expertID == expertID && ($0.childID == currentChildID || $0.childID == nil) }) { date = saved.preferredDate; note = saved.note }; submitted = state.localFeatures.expertAppointments.contains { $0.expertID == expertID && ($0.childID == currentChildID || $0.childID == nil) && ($0.status == .pendingSync || $0.status == .submitted) } } } }

    private var availableRemoteSlots: [ExpertAvailableSlot] { state.expertSlots[expertID] ?? [] }
    private var currentChildID: String? { state.selectedChild?.id }
    private var slotLabels: [(id: String, label: String, remote: ExpertAvailableSlot?)] {
        let remote = availableRemoteSlots.map { slot in (id: slot.slotID, label: slotLabel(slot), remote: Optional(slot)) }
        if !remote.isEmpty { return remote }
        if state.usesRemoteDataSource { return [] }
        return ["09:00-09:30", "10:00-10:30", "14:00-14:30", "16:00-16:30"].map { (id: $0, label: $0, remote: nil) }
    }
    private static let slotFormatter: DateFormatter = { let formatter = DateFormatter(); formatter.locale = Locale(identifier: "zh_CN"); formatter.dateFormat = "yyyy年M月d日"; return formatter }()
    private func updatePreferredDateDraft() {
        guard !selectedSlot.isEmpty else { return }
        date = "\(Self.slotFormatter.string(from: selectedDate)) \(selectedSlot)"
        state.saveDraft("\(date)|\(note)", key: draftKey)
    }
    private func slotLabel(_ slot: ExpertAvailableSlot) -> String {
        let start = String(slot.scheduledStartAt.suffix(8).prefix(5))
        let end = String(slot.scheduledEndAt.suffix(8).prefix(5))
        return "\(start)-\(end)"
    }
}
struct ExpertListView: View {
    @EnvironmentObject private var state: AppState
    @State private var selected: RemoteExpert?
    @State private var showingHistory = false
    private var visibleAppointmentHistory: [ExpertAppointmentAck] {
        state.expertAppointmentHistory.filter { $0.childID == state.selectedChild?.id || $0.childID == nil }
    }
    var body: some View {
        ScrollView {
            VStack(spacing: 9) {
                ParentPageNavigation(title: "专家团队", showsBack: true)
                if state.expertsLoading {
                    LoadingStateView().padding(.top, 24)
                } else if state.usesRemoteDataSource, let error = state.expertsError {
                    ErrorStateView(message: error) { Task { await state.loadExperts() } }
                        .padding(.horizontal, AppTheme.pagePadding)
                } else if displayExperts.isEmpty {
                    EmptyStateView(title: "暂无可预约专家", detail: "学校开通专家服务后会显示可预约人员。").padding(.horizontal, AppTheme.pagePadding)
                } else {
                    ForEach(displayExperts) { item in
                        Button { selected = item } label: {
                            HStack(spacing: 12) {
                                Image(expertAvatarAsset(item.expertID)).resizable().scaledToFit().frame(width: 56, height: 56).background(ReferenceColor.sky, in: Circle()).clipShape(Circle())
                                VStack(alignment: .leading, spacing: 5) {
                                    Text(item.name).font(.system(size: 16, weight: .bold))
                                    Text(item.title ?? "健康成长专家").font(.system(size: 16)).foregroundStyle(ReferenceColor.blue)
                                    Text(item.bio ?? "简介、专业领域与服务内容").font(.system(size: 16)).foregroundStyle(.secondary)
                                }
                                Spacer()
                                Image(systemName: "chevron.right").font(.system(size: 16)).foregroundStyle(.secondary)
                            }
                            .foregroundStyle(ReferenceColor.navy).padding(16).background(.white, in: RoundedRectangle(cornerRadius: 12))
                        }
                        .buttonStyle(.plain)
                        .padding(.horizontal, AppTheme.pagePadding)
                    }
                }
                if !visibleAppointmentHistory.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("预约历史").font(.system(size: 15, weight: .bold)).foregroundStyle(ReferenceColor.navy)
                            Spacer()
                            Button("查看全部") { showingHistory = true }
                                .font(.system(size: 16, weight: .semibold))
                                .frame(minHeight: 44)
                        }
                        .padding(.horizontal, AppTheme.pagePadding)
                        ForEach(visibleAppointmentHistory.prefix(5)) { item in
                            HStack {
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(item.expertName ?? item.expertID ?? "专家预约").font(.system(size: 15, weight: .bold)).foregroundStyle(ReferenceColor.navy)
                                    Text(item.preferredDate ?? item.scheduledStartAt.map { String($0.prefix(16)) } ?? "预约时间待确认").font(.system(size: 16)).foregroundStyle(.secondary)
                                }
                                Spacer()
                                Text(appointmentStatus(item.status)).font(.system(size: 16, weight: .bold)).foregroundStyle(item.status == "cancelled" ? .red : ReferenceColor.blue)
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
        .task { await state.loadExperts() }
        .onChange(of: displayExperts.map(\.expertID)) { _, _ in consumePendingExpert() }
        .onChange(of: state.expertAppointmentHistory.map(\.appointmentID)) { _, _ in consumePendingExpert() }
        .sheet(item: $selected) { item in ExpertDetailSheet(name: item.name, expert: item) }
        .sheet(isPresented: $showingHistory) { ExpertAppointmentHistorySheet(history: visibleAppointmentHistory) }
    }
    private var displayExperts: [RemoteExpert] {
        state.remoteExperts.isEmpty && !state.usesRemoteDataSource ? [
            RemoteExpert(expertID: "expert-zhang-child-sports", schoolID: nil, name: "张教授", title: "儿童运动发展", bio: "儿童运动发展与家庭训练建议", status: "active"),
            RemoteExpert(expertID: "expert-li-growth-screening", schoolID: nil, name: "李医生", title: "儿童健康评估", bio: "成长筛查与家庭观察建议", status: "active"),
            RemoteExpert(expertID: "expert-wang-youth-training", schoolID: nil, name: "王教练", title: "青少年运动训练", bio: "动作训练和运动习惯建立", status: "active"),
            RemoteExpert(expertID: "expert-liu-family-support", schoolID: nil, name: "刘主任", title: "儿童心理成长", bio: "家庭支持与心理观察", status: "active")
        ] : state.remoteExperts
    }
    private func consumePendingExpert() {
        guard let target = state.pendingExpertAppointmentID,
              let expertID = state.expertAppointmentHistory.first(where: { $0.appointmentID == target })?.expertID,
              let expert = displayExperts.first(where: { $0.expertID == expertID }) else { return }
        selected = expert
        state.clearExpertAppointmentTarget()
    }
    private func expertAvatarAsset(_ expertID: String) -> String {
        if expertID.contains("li-growth") { return "ExpertDoctor" }
        if expertID.contains("wang") { return "ExpertCoach" }
        if expertID.contains("liu") { return "ExpertCounselor" }
        return "ExpertProfessor"
    }
    private func appointmentStatus(_ value: String) -> String {
        switch value { case "confirmed": return "已确认"; case "pending": return "待确认"; case "reschedule_requested": return "改期待确认"; case "cancelled": return "已取消"; case "completed": return "已完成"; default: return value }
    }
}

private struct ExpertAppointmentHistorySheet: View {
    let history: [ExpertAppointmentAck]
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 10) {
                    if history.isEmpty {
                        EmptyStateView(title: "暂无预约历史", detail: "预约、改期或取消后会显示记录。")
                    } else {
                        ForEach(history) { item in
                            VStack(alignment: .leading, spacing: 8) {
                                HStack(alignment: .top) {
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(item.expertName ?? item.expertID ?? "专家预约")
                                            .font(.system(size: 15, weight: .bold))
                                            .foregroundStyle(ReferenceColor.navy)
                                        Text("预约编号 \(item.appointmentID)")
                                            .font(.system(size: 16))
                                            .foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    Text(appointmentStatus(item.status))
                                        .font(.system(size: 16, weight: .bold))
                                        .foregroundStyle(item.status == "cancelled" ? .red : ReferenceColor.blue)
                                }
                                Text(item.preferredDate ?? item.scheduledStartAt.map { String($0.prefix(16)) } ?? "预约时间待确认")
                                    .font(.system(size: 15, weight: .semibold))
                                    .foregroundStyle(ReferenceColor.navy)
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
            .navigationTitle("预约历史")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("关闭") { dismiss() } } }
        }
    }

    private func appointmentStatus(_ value: String) -> String {
        switch value {
        case "confirmed": return "已确认"
        case "pending": return "待确认"
        case "reschedule_requested": return "改期待确认"
        case "cancelled": return "已取消"
        case "completed": return "已完成"
        default: return value
        }
    }
}
