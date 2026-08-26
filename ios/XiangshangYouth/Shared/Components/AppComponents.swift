import SwiftUI

struct AppScaffold<Content: View>: View {
    @EnvironmentObject private var router: AppRouter
    @EnvironmentObject private var state: AppState
    let title: String
    /// Most pages return through the router. Multi-step flows may supply an
    /// in-flow back action so a tap never abandons unfinished input.
    var onBack: (() -> Void)? = nil
    @ViewBuilder var content: Content
    @ScaledMetric(relativeTo: .headline) private var titleSize: CGFloat = 16
    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                // A workbench/root page has no in-app route to return to.  Do
                // not fall back to SwiftUI's dismiss there: that can expose a
                // blank host controller after state restoration.  The leading
                // slot remains reserved so every secondary-page title stays
                // visually centred whether a back action is present or not.
                Group {
                    if let onBack {
                        Button(action: onBack) { Image(systemName: "chevron.left").font(.system(size: 15, weight: .bold)).foregroundStyle(AppTheme.ink).frame(width: 34, height: 34).background(.ultraThinMaterial, in: Circle()).frame(width: 44, height: 44) }
                            .accessibilityLabel("返回")
                            .accessibilityHint("返回上一个页面")
                    } else if !router.path.isEmpty {
                        Button(action: { router.pop() }) { Image(systemName: "chevron.left").font(.system(size: 15, weight: .bold)).foregroundStyle(AppTheme.ink).frame(width: 34, height: 34).background(.ultraThinMaterial, in: Circle()).frame(width: 44, height: 44) }
                            .accessibilityLabel("返回")
                            .accessibilityHint("返回上一页")
                    } else {
                        Color.clear.frame(width: 44, height: 44).accessibilityHidden(true)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                // Keep a long school/class title out of the reserved back
                // affordance. The full title remains exposed to VoiceOver.
                Text(title)
                    .font(.system(size: titleSize, weight: .bold))
                    .foregroundStyle(AppTheme.ink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
                    .truncationMode(.tail)
                    .padding(.horizontal, 50)
                    .accessibilityLabel(title)
            }.padding(.horizontal, 14).frame(height: 52).background { Rectangle().fill(.ultraThinMaterial).ignoresSafeArea(edges: .top) }
            if let error = state.error, state.data == nil {
                ErrorStateView(message: error, retry: { Task { await state.refreshDashboard() } }, dismiss: state.clearError)
                    .padding(.horizontal, 12)
            } else if state.loading, state.data == nil {
                LoadingStateView()
            } else {
                ScrollView {
                    content
                        .padding(.horizontal, 12)
                        .padding(.bottom, 18)
                        .frame(maxWidth: 720)
                        .frame(maxWidth: .infinity)
                }
            }
        }
        .background(AppTheme.surface.ignoresSafeArea())
        .navigationBarBackButtonHidden(true)
        .toolbar(.hidden, for: .navigationBar)
    }
}
struct OfflineBanner: View {
    let message: String
    var body: some View {
        VStack {
            Text(message)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(AppTheme.ink)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .frame(maxWidth: .infinity)
                .background(Color.orange.opacity(0.16), in: RoundedRectangle(cornerRadius: 10))
                .padding(.horizontal, 12)
                .padding(.top, 4)
            Spacer()
        }
        .allowsHitTesting(false)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(message)
    }
}
struct RoleBadge: View { let role: UserRole; var body: some View { Label(role.rawValue, systemImage: role.icon).font(.caption.weight(.semibold)).foregroundStyle(AppTheme.primary).padding(.horizontal, 10).padding(.vertical, 6).background(AppTheme.primary.opacity(0.1), in: Capsule()).accessibilityLabel("当前角色：\(role.rawValue)") } }
struct StudentCard: View {
    let student: Student; let action: (() -> Void)?
    @ViewBuilder private var cardContent: some View { HStack(spacing: 12) {
        Text(String(student.name.prefix(1))).font(.title2.bold()).foregroundStyle(.white).frame(width: 46, height: 46).background(AppTheme.teal, in: Circle())
        VStack(alignment: .leading, spacing: 4) { Text(student.name).font(.headline).foregroundStyle(AppTheme.ink); Text("\(student.grade) · \(student.className) · \(student.gender)").font(.caption).foregroundStyle(AppTheme.muted); Label(student.region, systemImage: "mappin.and.ellipse").font(.caption).foregroundStyle(AppTheme.muted) }
        Spacer(); if let score = student.totalScore { VStack { Text("\(score, specifier: "%.1f")").font(.headline).foregroundStyle(AppTheme.primary); Text("/ 35分").font(.caption).foregroundStyle(AppTheme.muted) } }; Image(systemName: "chevron.right").foregroundStyle(.tertiary)
    }.padding(14).background(.white, in: RoundedRectangle(cornerRadius: 16)) }
    var body: some View {
        Group {
            if let action { Button(action: action) { cardContent }.buttonStyle(.plain) }
            else { cardContent }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("学生 \(student.name)，\(student.grade)，\(student.className)")
    }
}
struct TestTaskCard: View {
    let task: TestTask; let action: (() -> Void)?
    @ViewBuilder private var cardContent: some View { VStack(alignment: .leading, spacing: 10) {
        HStack { Text(task.title).font(.headline).foregroundStyle(AppTheme.ink); Spacer(); Text(task.status.rawValue).font(.caption.weight(.semibold)).foregroundStyle(statusColor(task.status)).padding(.horizontal, 8).padding(.vertical, 4).background(statusColor(task.status).opacity(0.12), in: Capsule()) }
        Label(task.date, systemImage: "calendar").font(.subheadline).foregroundStyle(AppTheme.muted); Label(task.location, systemImage: "mappin.and.ellipse").font(.subheadline).foregroundStyle(AppTheme.muted); ProgressView(value: Double(task.completedCount), total: Double(task.totalCount)).tint(AppTheme.teal); Text("已完成 \(task.completedCount) / \(task.totalCount) 人 · 评测标准已应用").font(.caption).foregroundStyle(AppTheme.muted)
    }.padding(14).background(.white, in: RoundedRectangle(cornerRadius: 16)) }
    var body: some View {
        Group {
            if let action { Button(action: action) { cardContent }.buttonStyle(.plain) }
            else { cardContent }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("体测任务 \(task.title)，状态 \(task.status.rawValue)，已完成 \(task.completedCount) 人")
    }
    private func statusColor(_ status: TaskStatus) -> Color { status == .completed ? AppTheme.teal : status == .review || status == .retest || status == .absent ? AppTheme.danger : AppTheme.primary }
}
struct ScoreSummaryCard: View { let title: String; let value: String; let caption: String; var body: some View { VStack(alignment: .leading, spacing: 8) { Text(title).font(.caption).foregroundStyle(AppTheme.muted); Text(value).font(.title2.bold()).foregroundStyle(AppTheme.ink); Text(caption).font(.caption).foregroundStyle(AppTheme.teal) }.frame(maxWidth: .infinity, alignment: .leading).padding(14).background(.white, in: RoundedRectangle(cornerRadius: 16)).accessibilityElement(children: .ignore).accessibilityLabel("\(title)，\(value)，\(caption)") } }
struct ReportMetricCard: View { let result: ScoreResult; var body: some View { VStack(alignment: .leading, spacing: 8) { Label(result.item.shortName, systemImage: result.item.icon).font(.caption.weight(.medium)).foregroundStyle(AppTheme.muted); Text("\(result.score, specifier: "%.1f")").font(.title3.bold()).foregroundStyle(AppTheme.primary); Text("满分 5 分").font(.caption).foregroundStyle(AppTheme.muted); Text("状态 · \(result.reviewStatus.label)").font(.caption.weight(.semibold)).foregroundStyle(result.reviewStatus == .passed ? AppTheme.teal : AppTheme.danger) }.frame(maxWidth: .infinity, alignment: .leading).padding(12).background(AppTheme.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 12)).accessibilityElement(children: .ignore).accessibilityLabel("\(result.item.shortName)，\(result.score, specifier: "%.1f")分，满分5分，状态\(result.reviewStatus.label)") } }
struct FilterBar: View { let options: [String]; @Binding var selection: String; var body: some View { ScrollView(.horizontal, showsIndicators: false) { HStack { ForEach(options, id: \.self) { item in Button(item) { selection = item }.buttonStyle(.bordered).tint(selection == item ? AppTheme.primary : AppTheme.muted).accessibilityLabel("筛选：\(item)").accessibilityValue(selection == item ? "已选中" : "未选中") } } } } }
struct GradeClassSelector: View { let grades: [Grade]; let classes: [ClassInfo]; @Binding var grade: String; @Binding var className: String; var body: some View { HStack { Menu { ForEach(grades) { item in Button(item.name) { grade = item.name } } } label: { Label(grade, systemImage: "graduationcap") }.accessibilityLabel("选择年级").accessibilityValue("当前为\(grade)"); Divider(); Menu { ForEach(classes) { item in Button(item.name) { className = item.name } } } label: { Label(className, systemImage: "person.3") }.accessibilityLabel("选择班级").accessibilityValue("当前为\(className)") }.font(.subheadline.weight(.medium)).padding(12).background(.white, in: RoundedRectangle(cornerRadius: 12)) } }
