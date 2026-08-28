import SwiftUI

struct ParentMessagesView: View { var body: some View { ParentMessagesDashboard() } }
struct ParentMessageDetail: Identifiable {
    let message: MessageItem
    var id: String { message.id }
}
struct ParentMessagesDashboard: View {
    @EnvironmentObject private var state: AppState
    @EnvironmentObject private var router: AppRouter
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    @State private var selectedTab = 0
    @State private var selectedMessage: ParentMessageDetail?
    private var messages: [MessageItem] {
        let base = state.data?.messages ?? []
        guard let child = state.selectedChild, let body = state.bodyAssessment(for: child) else { return base }
        let level = body.attention(ageMonths: child.bodyAssessmentAgeMonths, gender: child.gender)
        let title: String
        switch level {
        case .red: title = "身体测评需优先关注"
        case .yellow: title = "身体测评复测提醒"
        case .pending: title = "请完成身体测评记录"
        case .unavailable: title = "请完善身体测评资料"
        case .green: title = "身体测评已完成"
        }
        let content = "BMI \(String(format: "%.1f", body.bmi)) · \(level.label)。建议复测：\(Self.reminderDateFormatter.string(from: body.nextFollowUpDate))。"
        return [MessageItem(id: "body-\(child.id)-\(Self.reminderDateFormatter.string(from: body.savedAt))", title: title, content: content, time: "刚刚", isRead: false, category: "健康提醒")] + base
    }
    private var reduceMotion: Bool { state.localFeatures.settings.reduceMotion || systemReduceMotion }
    private static let reminderDateFormatter: DateFormatter = { let f = DateFormatter(); f.locale = Locale(identifier: "en_US_POSIX"); f.dateFormat = "yyyyMMdd"; return f }()

    var body: some View {
        ScrollView {
            VStack(spacing: 8) {
                // This screen is the family message center itself; do not
                // render a second bell that points back to the same route.
                ParentPageNavigation(title: "健康提醒", showsBell: false)
                ReferenceHeader(name: state.selectedChild?.name ?? "未选择孩子", school: "\(state.selectedChild?.className ?? "尚未绑定班级") · 成长小档案", initial: String((state.selectedChild?.name ?? "孩").prefix(1)), showsBell: false, avatarAsset: "ChildAvatar")
                if state.unreadMessageCount > 0 {
                    HStack {
                        Spacer()
                        Button("全部已读") { state.markAllMessagesRead() }
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(ReferenceColor.blue)
                            .buttonStyle(.plain)
                            .accessibilityLabel("将全部消息标记为已读")
                    }
                    .padding(.horizontal, AppTheme.pagePadding)
                }
                HStack(spacing: 0) {
                    tab("消息提醒", index: 0)
                    tab("系统通知", index: 1)
                }
                .padding(.horizontal, AppTheme.pagePadding)
                let visibleMessages = messages.filter { selectedTab == 0 ? $0.category != "系统" : $0.category == "系统" }
                if visibleMessages.isEmpty {
                    EmptyStateView(title: selectedTab == 0 ? "暂无消息提醒" : "暂无系统通知", detail: "新的测评、班级和系统通知会显示在这里。")
                        .padding(.top, 26)
                }
                ForEach(visibleMessages) { item in
                    Button {
                        state.markMessageRead(item.id)
                        if !openBusinessRoute(item) {
                            let expired = isExpired(item)
                            selectedMessage = ParentMessageDetail(message: expired ? MessageItem(id: item.id, title: item.title, content: "该通知已过期，不能继续打开。", time: item.time, isRead: true, category: item.category) : routeFailureDetail(for: item))
                        }
                    } label: {
                        let isUnread = !item.isRead && !state.localFeatures.readMessageIDs.contains(item.id)
                        messageRow(item: item, unread: isUnread)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("\(item.title)，\(item.category)，查看详情")
                }
            }
            .padding(.bottom, 9)
        }
        .background(ReferenceColor.canvas)
        .overlay {
            if let error = state.error, state.data == nil {
                ErrorStateView(message: error) { Task { await state.refreshDashboard() } }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(ReferenceColor.canvas)
            } else if state.loading || state.data == nil {
                ZStack { ReferenceColor.canvas.ignoresSafeArea(); LoadingStateView() }
            } else if state.selectedChild == nil {
                ParentBindingPrompt()
            }
        }
        .sheet(item: $selectedMessage) { item in
            NavigationStack {
                VStack(alignment: .leading, spacing: 14) {
                    Text(item.message.category).font(.subheadline.weight(.semibold)).foregroundStyle(ReferenceColor.blue)
                    Text(item.message.content).font(.body).foregroundStyle(ReferenceColor.navy)
                    Text(item.message.time).font(.subheadline).foregroundStyle(.secondary)
                    Spacer()
                }
                .padding()
                .navigationTitle(item.message.title)
                .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("关闭") { selectedMessage = nil } } }
            }
        }
    }

    private func tab(_ title: String, index: Int) -> some View {
        Button {
            if reduceMotion { var transaction = Transaction(); transaction.animation = nil; withTransaction(transaction) { selectedTab = index } }
            else { withAnimation(.easeInOut(duration: 0.2)) { selectedTab = index } }
        } label: {
            VStack(spacing: 6) {
                Text(title).font(.system(size: 16, weight: .semibold)).foregroundStyle(selectedTab == index ? ReferenceColor.blue : .secondary)
                Capsule().fill(selectedTab == index ? ReferenceColor.blue : .clear).frame(height: 2)
            }.frame(maxWidth: .infinity)
        }.buttonStyle(.plain)
    }

    private func isExpired(_ item: MessageItem) -> Bool {
        guard let value = item.expiresAt else { return false }
        let formatter = ISO8601DateFormatter()
        return formatter.date(from: value).map { $0 < Date() } ?? false
    }

    private func routeFailureDetail(for item: MessageItem) -> MessageItem {
        guard let route = normalizedRoute(item.businessRoute) else { return item }
        switch route {
        case "course", "lesson":
            guard item.childID != nil else {
                return MessageItem(id: item.id, title: item.title, content: "该课程通知缺少孩子档案信息，暂时不能打开指定课程。", time: item.time, isRead: true, category: item.category)
            }
            guard item.courseID != nil || item.lessonID != nil || item.businessID != nil else {
                return MessageItem(id: item.id, title: item.title, content: "该课程通知缺少课程或课节编号，请等待学校重新同步。", time: item.time, isRead: true, category: item.category)
            }
            return MessageItem(id: item.id, title: item.title, content: "当前家庭账号无权打开这节课程。", time: item.time, isRead: true, category: item.category)
        case "task", "retest", "report":
            return MessageItem(id: item.id, title: item.title, content: "当前账号无法打开这条通知关联的孩子、任务或报告。", time: item.time, isRead: true, category: item.category)
        case "activity", "expertappointment":
            return MessageItem(id: item.id, title: item.title, content: "该通知缺少可打开的业务编号，暂时只能查看通知内容。", time: item.time, isRead: true, category: item.category)
        case "classnotice":
            return item.businessID == nil
                ? MessageItem(id: item.id, title: item.title, content: "该班级通知缺少通知编号，暂时只能查看文字内容。", time: item.time, isRead: true, category: item.category)
                : item
        default:
            return item
        }
    }

    private func openBusinessRoute(_ item: MessageItem) -> Bool {
        guard !isExpired(item), let route = normalizedRoute(item.businessRoute) else { return false }
        switch route {
        case "report":
            guard let childID = item.childID, let child = state.boundChildren.first(where: { $0.id == childID }) else { return false }
            router.push(.report(child)); return true
        case "course", "lesson":
            guard let childID = item.childID,
                  state.boundChildren.contains(where: { $0.id == childID }),
                  item.courseID != nil || item.lessonID != nil || item.businessID != nil else { return false }
            state.openCourseTarget(
                for: childID,
                courseID: item.courseID ?? (route == "course" ? item.businessID : nil),
                lessonID: item.lessonID ?? (route == "lesson" ? item.businessID : nil),
                title: item.actionLabel ?? item.title
            )
            router.push(.parentCourses); return true
        case "activity":
            guard let businessID = item.businessID else { return false }
            state.openActivityTarget(businessID); router.push(.activityList); return true
        case "expertappointment":
            guard let businessID = item.businessID else { return false }
            state.openExpertAppointmentTarget(businessID); router.push(.expertList); return true
        case "childbinding":
            router.push(.children(returnAfterBinding: false)); return true
        case "classnotice":
            guard item.businessID?.isEmpty == false else { return false }
            selectedMessage = ParentMessageDetail(message: item)
            return true
        case "task", "retest":
            guard let taskID = item.taskID ?? item.businessID,
                  let childID = item.childID,
                  state.boundChildren.contains(where: { $0.id == childID }),
                  let task = state.data?.tasks.first(where: { $0.id == taskID && ($0.studentIDs.isEmpty || $0.studentIDs.contains(childID)) }) else { return false }
            router.push(.parentTask(task)); return true
        default: return false
        }
    }

    private func normalizedRoute(_ value: String?) -> String? {
        value?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .replacingOccurrences(of: "-", with: "")
            .replacingOccurrences(of: "_", with: "")
    }

    private func messageRow(item: MessageItem, unread: Bool) -> some View {
        let presentation = messagePresentation(for: item)
        return HStack(spacing: 10) {
            Image(systemName: presentation.icon).font(.system(size: 16, weight: .semibold)).foregroundStyle(presentation.color)
                .frame(width: 34, height: 34).background(presentation.color.opacity(0.10), in: RoundedRectangle(cornerRadius: 10))
            VStack(alignment: .leading, spacing: 3) {
                Text(item.title).font(.system(size: 16, weight: .bold))
                Text(item.content).font(.system(size: 16)).foregroundStyle(.secondary).lineLimit(2)
                Text(item.category).font(.system(size: 16, weight: .bold)).foregroundStyle(presentation.color)
                    .padding(.horizontal, 5).padding(.vertical, 2).background(presentation.color.opacity(0.09), in: Capsule())
            }
            Spacer(minLength: 4)
            VStack(alignment: .trailing, spacing: 7) {
                HStack(spacing: 4) {
                    if unread { Circle().fill(.red).frame(width: 4, height: 4) }
                    Text(item.time).font(.system(size: 16)).foregroundStyle(.secondary)
                }
                Image(systemName: "chevron.right").font(.system(size: 16, weight: .bold)).foregroundStyle(.secondary)
            }
        }
        .padding(11)
        .background(.white, in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(ReferenceColor.blue.opacity(0.06), lineWidth: 1))
        .padding(.horizontal, 10)
    }

    private func messagePresentation(for item: MessageItem) -> (icon: String, color: Color) {
        if item.title.contains("体质") { return ("exclamationmark.circle.fill", .red) }
        if item.title.contains("视力") { return ("eye.fill", ReferenceColor.green) }
        if item.title.contains("口腔") { return ("mouth.fill", ReferenceColor.purple) }
        if item.title.contains("心理") { return ("brain.head.profile", ReferenceColor.pink) }
        if item.title.contains("打卡") { return ("star.fill", .orange) }
        return ("bell.fill", ReferenceColor.blue)
    }
}
