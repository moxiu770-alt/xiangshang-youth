import SwiftUI

/// Shared notification center used by parent and teacher workbenches. Historical
/// school-management links may still resolve here, but the principal workbench
/// itself is no longer rendered in the mobile app.
/// Keeping one route makes every bell behave consistently and leaves the message
/// source replaceable by MessageApi/RemoteRepository later.
struct NotificationsView: View {
    @EnvironmentObject private var state: AppState
    @EnvironmentObject private var router: AppRouter
    @State private var selectedMessage: MessageItem?

    private var messages: [MessageItem] { state.data?.messages ?? [] }

    var body: some View {
        AppScaffold(title: "消息通知") {
            VStack(spacing: 9) {
                if let error = state.error, state.data == nil {
                    ErrorStateView(message: error) { Task { await state.refreshDashboard() } }
                } else if state.loading || state.data == nil {
                    LoadingStateView()
                } else if messages.isEmpty {
                    EmptyStateView(title: "暂无消息通知", detail: "新的测评、补测和班级通知会显示在这里。")
                } else {
                    HStack {
                        Text("全部通知").font(.system(size: 15, weight: .bold)).foregroundStyle(ReferenceColor.navy)
                        Spacer()
                        if state.unreadMessageCount > 0 {
                            Button("全部已读") { state.markAllMessagesRead() }
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundStyle(ReferenceColor.blue)
                                .buttonStyle(.plain)
                                .accessibilityLabel("将全部通知标记为已读")
                        }
                        Text("未读 \(state.unreadMessageCount)")
                            .font(.system(size: 16, weight: .semibold)).foregroundStyle(ReferenceColor.blue)
                    }
                    .padding(.horizontal, AppTheme.pagePadding)

                    ForEach(messages) { message in
                        Button {
                            state.markMessageRead(message.id)
                            if !openBusinessRoute(message) {
                                let expired = message.expiresAt.flatMap { ISO8601DateFormatter().date(from: $0) }.map { $0 < Date() } ?? false
                                selectedMessage = expired ? MessageItem(id: message.id, title: message.title, content: "该通知已过期，不能继续打开。", time: message.time, isRead: true, category: message.category) : routeFailureDetail(for: message)
                            }
                        } label: {
                            HStack(spacing: 10) {
                                Image(systemName: message.category == "报告" ? "doc.text.fill" : "bell.fill")
                                    .foregroundStyle(message.category == "报告" ? ReferenceColor.blue : .orange)
                                    .frame(width: 34, height: 34)
                                    .background((message.category == "报告" ? ReferenceColor.blue : Color.orange).opacity(0.12), in: RoundedRectangle(cornerRadius: 10))
                                VStack(alignment: .leading, spacing: 3) {
                                    HStack(spacing: 5) {
                                        Text(message.title).font(.system(size: 16, weight: .bold)).foregroundStyle(ReferenceColor.navy)
                                        if !message.isRead && !state.localFeatures.readMessageIDs.contains(message.id) { Circle().fill(.red).frame(width: 5, height: 5) }
                                    }
                                    Text(message.content).font(.system(size: 16)).foregroundStyle(.secondary).lineLimit(2)
                                    Text("\(message.category) · \(message.time)").font(.system(size: 16)).foregroundStyle(.secondary)
                                }
                                Spacer()
                                Image(systemName: "chevron.right").font(.system(size: 16, weight: .semibold)).foregroundStyle(.secondary)
                            }
                            .padding(11)
                            .background(.white, in: RoundedRectangle(cornerRadius: 11))
                        }
                        .buttonStyle(.plain)
                        .padding(.horizontal, AppTheme.pagePadding)
                    }
                }
            }
        }
        .sheet(item: $selectedMessage) { message in
            if normalizedRoute(message.businessRoute) == "classnotice", let notificationID = message.businessID {
                ClassNoticeDetailSheet(message: message, notificationID: notificationID)
            } else {
                NavigationStack {
                    VStack(alignment: .leading, spacing: 13) {
                        Text(message.title).font(.title3.bold()).foregroundStyle(ReferenceColor.navy)
                        Text("\(message.category) · \(message.time)").font(.subheadline).foregroundStyle(.secondary)
                        Divider()
                        Text(message.content).font(.body).foregroundStyle(ReferenceColor.navy)
                        Spacer()
                    }
                    .padding()
                    .navigationTitle("通知详情")
                    .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("完成") { selectedMessage = nil } } }
                }
            }
        }
    }

    private func routeFailureDetail(for message: MessageItem) -> MessageItem {
        guard let route = normalizedRoute(message.businessRoute) else { return message }
        switch route {
        case "course", "lesson":
            return MessageItem(id: message.id, title: message.title, content: "该课程通知缺少孩子、课程或课节编号，暂时不能打开指定课程。", time: message.time, isRead: true, category: message.category)
        case "report", "task", "retest", "bodyassessment":
            return MessageItem(id: message.id, title: message.title, content: "当前账号无权打开这条通知关联的数据，或关联对象已不存在。", time: message.time, isRead: true, category: message.category)
        case "activity", "expertappointment":
            return MessageItem(id: message.id, title: message.title, content: "该通知缺少可打开的业务编号，暂时只能查看通知内容。", time: message.time, isRead: true, category: message.category)
        case "classnotice":
            return message.businessID == nil
                ? MessageItem(id: message.id, title: message.title, content: "该班级通知缺少通知编号，暂时只能查看文字内容。", time: message.time, isRead: true, category: message.category)
                : message
        default:
            return message
        }
    }

    private func openBusinessRoute(_ message: MessageItem) -> Bool {
        let expired = message.expiresAt.flatMap { ISO8601DateFormatter().date(from: $0) }.map { $0 < Date() } ?? false
        guard !expired, let route = normalizedRoute(message.businessRoute) else { return false }
        switch (state.selectedRole, route) {
        case (.parent, "report"):
            guard let id = message.childID, let child = state.boundChildren.first(where: { $0.id == id }) else { return false }
            router.push(.report(child)); return true
        case (.parent, "course"), (.parent, "lesson"):
            guard let id = message.childID,
                  state.boundChildren.contains(where: { $0.id == id }),
                  message.courseID != nil || message.lessonID != nil || message.businessID != nil else { return false }
            state.openCourseTarget(
                for: id,
                courseID: message.courseID ?? (route == "course" ? message.businessID : nil),
                lessonID: message.lessonID ?? (route == "lesson" ? message.businessID : nil),
                title: message.actionLabel ?? message.title
            )
            router.push(.parentCourses); return true
        case (.parent, "activity"):
            guard let businessID = message.businessID else { return false }
            state.openActivityTarget(businessID); router.push(.activityList); return true
        case (.parent, "expertappointment"):
            guard let businessID = message.businessID else { return false }
            state.openExpertAppointmentTarget(businessID); router.push(.expertList); return true
        case (.parent, "childbinding"):
            router.push(.children(returnAfterBinding: false)); return true
        case (.parent, "bodyassessment"):
            guard let id = message.childID, state.boundChildren.contains(where: { $0.id == id }) else { return false }
            if state.selectedChild?.id != id, let child = state.boundChildren.first(where: { $0.id == id }) {
                state.selectChild(child)
            }
            router.push(.bodyAssessment); return true
        case (.parent, "classnotice"), (.teacher, "classnotice"):
            guard message.businessID?.isEmpty == false else { return false }
            selectedMessage = message
            return true
        case (.parent, "task"), (.parent, "retest"):
            guard let id = message.childID, state.boundChildren.contains(where: { $0.id == id }), let taskID = message.taskID ?? message.businessID, state.data?.tasks.contains(where: { $0.id == taskID }) == true else { return false }
            router.push(.parentEvaluations); return true
        case (.teacher, "task"), (.teacher, "retest"):
            guard let taskID = message.taskID ?? message.businessID, let task = state.data?.tasks.first(where: { $0.id == taskID }), state.managedTeacherClasses.contains(where: { task.classIDs.contains($0.id) }) else { return false }
            router.push(.teacherTaskDetail(task)); return true
        case (.teacher, "report"):
            guard let studentID = message.childID, let student = state.data?.students.first(where: { $0.id == studentID }), state.managedTeacherClasses.contains(where: { $0.id == student.classID }) else { return false }
            router.push(.report(student)); return true
        default:
            return false
        }
    }

    private func normalizedRoute(_ value: String?) -> String? {
        value?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .replacingOccurrences(of: "-", with: "")
            .replacingOccurrences(of: "_", with: "")
    }
}

private struct ClassNoticeDetailSheet: View {
    @EnvironmentObject private var state: AppState
    @Environment(\.dismiss) private var dismiss
    let message: MessageItem
    let notificationID: String
    @State private var detail: NotificationCampaignDetail?
    @State private var loading = true
    @State private var error: String?

    var body: some View {
        NavigationStack {
            Group {
                if loading {
                    LoadingStateView()
                } else if let error {
                    ErrorStateView(message: error) {
                        Task { await reload() }
                    }
                } else if let detail {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 14) {
                            Text(detail.title).font(.title3.bold()).foregroundStyle(ReferenceColor.navy)
                            Text(detail.sentAt.map { "发送时间 \($0)" } ?? "\(message.category) · \(message.time)")
                                .font(.system(size: 15))
                                .foregroundStyle(.secondary)
                            Text(detail.content)
                                .font(.system(size: 15))
                                .foregroundStyle(ReferenceColor.navy)
                                .fixedSize(horizontal: false, vertical: true)
                            if detail.parentReceiptEnabled {
                                receiptCard(detail)
                            }
                            if let stats = detail.receiptStats {
                                Text("回执统计：已确认 \(stats.acknowledged) / \(stats.total)，待确认 \(stats.pending)")
                                    .font(.system(size: 15, weight: .semibold))
                                    .foregroundStyle(ReferenceColor.blue)
                                    .padding(16)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .background(ReferenceColor.blue.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
                            }
                        }
                        .padding()
                    }
                } else {
                    EmptyStateView(title: "通知暂不可用", detail: "学校同步通知详情后会显示在这里。")
                }
            }
            .navigationTitle("班级通知")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("完成") { dismiss() } } }
            .task { await reload() }
        }
    }

    private func receiptCard(_ detail: NotificationCampaignDetail) -> some View {
        let acknowledged = detail.userReceiptStatus == "acknowledged"
        return VStack(alignment: .leading, spacing: 10) {
            Text(acknowledged ? "已确认收到" : "需要家长确认")
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(acknowledged ? ReferenceColor.green : ReferenceColor.navy)
            Text(acknowledged ? "学校已收到您的确认回执。" : "请确认已阅读本通知，学校会用于统计家长回执。")
                .font(.system(size: 15))
                .foregroundStyle(.secondary)
            if !acknowledged && state.selectedRole == .parent {
                let command = state.workflowState(for: "notice:receipt:\(notificationID)")
                Button {
                    Task {
                        if await state.acknowledgeClassNotice(notificationID: notificationID) {
                            await reload()
                        }
                    }
                } label: {
                    HStack {
                        if command.isSubmitting { ProgressView() }
                        Text(command.isSubmitting ? "提交中" : "确认收到")
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(command.isSubmitting)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.white, in: RoundedRectangle(cornerRadius: 12))
    }

    private func reload() async {
        loading = true
        error = nil
        if let loaded = await state.loadClassNoticeDetail(notificationID: notificationID) {
            detail = loaded
        } else if case let .failed(message) = state.workflowState(for: "notice:detail:\(notificationID)") {
            error = message
        }
        loading = false
    }
}
