import SwiftUI

/// Teacher messages stay as a secondary route so the teacher root tabs never
/// acquire a misleading back button or an inert notification bell.
struct TeacherMessageDetail: Identifiable {
    let message: MessageItem
    var id: String { message.id }
}

struct TeacherMessagesView: View {
    @EnvironmentObject private var state: AppState
    @EnvironmentObject private var router: AppRouter
    @State private var selectedMessage: TeacherMessageDetail?
    private var items: [MessageItem] { state.data?.messages ?? [] }

    var body: some View {
        ScrollView {
            VStack(spacing: 8) {
                ParentPageNavigation(title: "消息中心", showsBack: true, showsBell: false)
                if state.unreadMessageCount > 0 {
                    HStack {
                        Spacer()
                        Button("全部已读") { state.markAllMessagesRead() }
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(ReferenceColor.blue)
                            .buttonStyle(.plain)
                            .accessibilityLabel("将全部消息标记为已读")
                    }
                    .padding(.horizontal, 14)
                }
                if let error = state.error, state.data == nil {
                    ErrorStateView(message: error) { Task { await state.refreshDashboard() } }
                } else if state.loading || state.data == nil {
                    LoadingStateView()
                } else if items.isEmpty {
                    EmptyStateView(title: "暂无消息通知", detail: "新的测评、补测和班级通知会显示在这里。")
                } else {
                    ForEach(items) { item in
                        let presentation = messagePresentation(for: item)
                        let unread = !item.isRead && !state.localFeatures.readMessageIDs.contains(item.id)
                        Button {
                            state.markMessageRead(item.id)
                            if !openBusinessRoute(item) {
                                let expired = item.expiresAt.flatMap { ISO8601DateFormatter().date(from: $0) }.map { $0 < Date() } ?? false
                                selectedMessage = TeacherMessageDetail(message: expired ? MessageItem(id: item.id, title: item.title, content: "该通知已过期，不能继续打开。", time: item.time, isRead: true, category: item.category) : routeFailureDetail(for: item))
                            }
                        } label: {
                            HStack(spacing: 10) {
                                Image(systemName: presentation.icon).foregroundStyle(presentation.color).frame(width: 36, height: 36).background(presentation.color.opacity(0.10), in: RoundedRectangle(cornerRadius: 10))
                                VStack(alignment: .leading, spacing: 4) {
                                    HStack(spacing: 5) { Text(item.title).font(.system(size: 12, weight: .bold)); if unread { Circle().fill(.red).frame(width: 5, height: 5) } }
                                    Text(item.content).font(.system(size: 12)).foregroundStyle(.secondary)
                                }
                                Spacer()
                                Text(item.time).font(.system(size: 12)).foregroundStyle(.secondary)
                                Image(systemName: "chevron.right").font(.system(size: 12)).foregroundStyle(.secondary)
                            }
                            .foregroundStyle(ReferenceColor.navy)
                            .padding(11)
                            .background(.white, in: RoundedRectangle(cornerRadius: 10))
                        }
                        .buttonStyle(.plain)
                        .padding(.horizontal, 12)
                    }
                }
            }
            .padding(.bottom, 10)
        }
        .background(ReferenceColor.canvas)
        .refreshable { await state.refreshDashboard() }
        .sheet(item: $selectedMessage) { message in
            NavigationStack {
                VStack(alignment: .leading, spacing: 14) {
                    Text(message.message.title).font(.title3.bold())
                    Text(message.message.time).font(.caption).foregroundStyle(.secondary)
                    Divider()
                    Text(message.message.content).font(.body)
                    Spacer()
                }
                .padding()
                .navigationTitle("消息详情")
                .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("关闭") { selectedMessage = nil } } }
            }
        }
    }

    private func routeFailureDetail(for item: MessageItem) -> MessageItem {
        guard let route = normalizedRoute(item.businessRoute) else { return item }
        switch route {
        case "task", "retest", "report":
            return MessageItem(id: item.id, title: item.title, content: "当前教师账号无权打开这条通知关联的数据，或关联对象已不存在。", time: item.time, isRead: true, category: item.category)
        case "classnotice":
            return item.businessID == nil ? MessageItem(id: item.id, title: item.title, content: "该班级通知缺少通知编号，暂时只能查看文字内容。", time: item.time, isRead: true, category: item.category) : item
        default: return item
        }
    }

    private func openBusinessRoute(_ item: MessageItem) -> Bool {
        let expired = item.expiresAt.flatMap { ISO8601DateFormatter().date(from: $0) }.map { $0 < Date() } ?? false
        guard !expired, let route = normalizedRoute(item.businessRoute) else { return false }
        switch route {
        case "task", "retest":
            guard let taskID = item.taskID ?? item.businessID, let task = state.data?.tasks.first(where: { $0.id == taskID }), state.managedTeacherClasses.contains(where: { task.classIDs.contains($0.id) }) else { return false }
            router.push(.teacherTaskDetail(task)); return true
        case "report":
            guard let studentID = item.childID, let student = state.data?.students.first(where: { $0.id == studentID }), state.managedTeacherClasses.contains(where: { $0.id == student.classID }) else { return false }
            router.push(.report(student)); return true
        case "classnotice":
            guard item.businessID?.isEmpty == false else { return false }
            selectedMessage = TeacherMessageDetail(message: item); return true
        default: return false
        }
    }

    private func normalizedRoute(_ value: String?) -> String? {
        value?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased().replacingOccurrences(of: "-", with: "").replacingOccurrences(of: "_", with: "")
    }
}
