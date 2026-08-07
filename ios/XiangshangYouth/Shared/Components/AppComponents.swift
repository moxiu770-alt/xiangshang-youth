import SwiftUI

struct AppScaffold<Content: View>: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var router: AppRouter
    @EnvironmentObject private var state: AppState
    let title: String; @ViewBuilder var content: Content
    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                Button(action: { if router.path.isEmpty { dismiss() } else { router.pop() } }) { Image(systemName: "chevron.left").font(.system(size: 15, weight: .bold)).foregroundStyle(AppTheme.ink).frame(width: 34, height: 34).background(.ultraThinMaterial, in: Circle()).frame(width: 44, height: 44) }.accessibilityLabel("返回").frame(maxWidth: .infinity, alignment: .leading)
                Text(title).font(.system(size: 16, weight: .bold)).foregroundStyle(AppTheme.ink)
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
                .font(.system(size: 10, weight: .semibold))
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
        VStack(alignment: .leading, spacing: 4) { Text(student.name).font(.headline).foregroundStyle(AppTheme.ink); Text("\(student.grade) · \(student.className) · \(student.gender)").font(.caption).foregroundStyle(AppTheme.muted); Label(student.isPovertyArea ? "贫困地区学生" : student.region, systemImage: student.isPovertyArea ? "heart.text.square" : "mappin.and.ellipse").font(.caption2).foregroundStyle(student.isPovertyArea ? AppTheme.danger : AppTheme.muted) }
        Spacer(); if let score = student.totalScore { VStack { Text("\(score, specifier: "%.1f")").font(.headline).foregroundStyle(AppTheme.primary); Text("/ 35分").font(.caption2).foregroundStyle(AppTheme.muted) } }; Image(systemName: "chevron.right").foregroundStyle(.tertiary)
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
        Label(task.date, systemImage: "calendar").font(.subheadline).foregroundStyle(AppTheme.muted); Label(task.location, systemImage: "mappin.and.ellipse").font(.subheadline).foregroundStyle(AppTheme.muted); ProgressView(value: Double(task.completedCount), total: Double(task.totalCount)).tint(AppTheme.teal); Text("已完成 \(task.completedCount) / \(task.totalCount) 人 · \(task.ruleVersion)").font(.caption).foregroundStyle(AppTheme.muted)
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
struct ScoreSummaryCard: View { let title: String; let value: String; let caption: String; var body: some View { VStack(alignment: .leading, spacing: 8) { Text(title).font(.caption).foregroundStyle(AppTheme.muted); Text(value).font(.title2.bold()).foregroundStyle(AppTheme.ink); Text(caption).font(.caption2).foregroundStyle(AppTheme.teal) }.frame(maxWidth: .infinity, alignment: .leading).padding(14).background(.white, in: RoundedRectangle(cornerRadius: 16)).accessibilityElement(children: .ignore).accessibilityLabel("\(title)，\(value)，\(caption)") } }
struct ReportMetricCard: View { let result: ScoreResult; var body: some View { VStack(alignment: .leading, spacing: 8) { Label(result.item.shortName, systemImage: result.item.icon).font(.caption.weight(.medium)).foregroundStyle(AppTheme.muted); Text("\(result.score, specifier: "%.1f")").font(.title3.bold()).foregroundStyle(AppTheme.primary); Text("满分 5 分").font(.caption2).foregroundStyle(AppTheme.muted); HStack(spacing: 5) { Text("置信度 \(result.confidence * 100, specifier: "%.0f")%").font(.caption2); Text(result.reviewStatus.label).font(.caption2.weight(.semibold)) }.foregroundStyle(result.reviewStatus == .passed ? AppTheme.teal : AppTheme.danger) }.frame(maxWidth: .infinity, alignment: .leading).padding(12).background(AppTheme.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 12)).accessibilityElement(children: .ignore).accessibilityLabel("\(result.item.shortName)，\(result.score, specifier: "%.1f")分，满分5分，置信度\(result.confidence * 100, specifier: "%.0f")%，\(result.reviewStatus.label)") } }
struct FilterBar: View { let options: [String]; @Binding var selection: String; var body: some View { ScrollView(.horizontal, showsIndicators: false) { HStack { ForEach(options, id: \.self) { item in Button(item) { selection = item }.buttonStyle(.bordered).tint(selection == item ? AppTheme.primary : AppTheme.muted) } } } } }
struct GradeClassSelector: View { let grades: [Grade]; let classes: [ClassInfo]; @Binding var grade: String; @Binding var className: String; var body: some View { HStack { Menu { ForEach(grades) { item in Button(item.name) { grade = item.name } } } label: { Label(grade, systemImage: "graduationcap") }; Divider(); Menu { ForEach(classes) { item in Button(item.name) { className = item.name } } } label: { Label(className, systemImage: "person.3") } }.font(.subheadline.weight(.medium)).padding(12).background(.white, in: RoundedRectangle(cornerRadius: 12)) } }
