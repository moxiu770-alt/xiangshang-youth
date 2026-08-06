import SwiftUI

/// Shared notification center used by parent, teacher and principal workbenches.
/// Keeping one route makes every bell behave consistently and leaves the message
/// source replaceable by MessageApi/RemoteRepository later.
struct NotificationsView: View {
    @EnvironmentObject private var state: AppState
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
                        Text("未读 \(state.unreadMessageCount)")
                            .font(.system(size: 10, weight: .semibold)).foregroundStyle(ReferenceColor.blue)
                    }
                    .padding(.horizontal, 12)

                    ForEach(messages) { message in
                        Button {
                            state.markMessageRead(message.id)
                            selectedMessage = message
                        } label: {
                            HStack(spacing: 10) {
                                Image(systemName: message.category == "报告" ? "doc.text.fill" : "bell.fill")
                                    .foregroundStyle(message.category == "报告" ? ReferenceColor.blue : .orange)
                                    .frame(width: 34, height: 34)
                                    .background((message.category == "报告" ? ReferenceColor.blue : Color.orange).opacity(0.12), in: RoundedRectangle(cornerRadius: 10))
                                VStack(alignment: .leading, spacing: 3) {
                                    HStack(spacing: 5) {
                                        Text(message.title).font(.system(size: 12, weight: .bold)).foregroundStyle(ReferenceColor.navy)
                                        if !message.isRead && !state.localFeatures.readMessageIDs.contains(message.id) { Circle().fill(.red).frame(width: 5, height: 5) }
                                    }
                                    Text(message.content).font(.system(size: 9)).foregroundStyle(.secondary).lineLimit(2)
                                    Text("\(message.category) · \(message.time)").font(.system(size: 8)).foregroundStyle(.secondary)
                                }
                                Spacer()
                                Image(systemName: "chevron.right").font(.system(size: 9, weight: .semibold)).foregroundStyle(.secondary)
                            }
                            .padding(11)
                            .background(.white, in: RoundedRectangle(cornerRadius: 11))
                        }
                        .buttonStyle(.plain)
                        .padding(.horizontal, 12)
                    }
                }
            }
        }
        .sheet(item: $selectedMessage) { message in
            NavigationStack {
                VStack(alignment: .leading, spacing: 13) {
                    Text(message.title).font(.title3.bold()).foregroundStyle(ReferenceColor.navy)
                    Text("\(message.category) · \(message.time)").font(.caption).foregroundStyle(.secondary)
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
