import SwiftUI

struct ReportDetailView: View {
    @EnvironmentObject private var state: AppState
    let student: Student
    @State private var selectedDetail: String?
    var body: some View {
        let report = state.report(for: student)
        return AppScaffold(title: "体测报告") {
            VStack(spacing: 16) {
                VStack(alignment: .leading, spacing: 9) {
                    HStack(alignment: .top) {
                        VStack(alignment: .leading) { Text(report.student.name).font(.title2.bold()).foregroundStyle(.white); Text("\(report.student.grade) · \(report.student.className)").foregroundStyle(.white.opacity(0.85)) }
                        Spacer()
                        VStack(alignment: .trailing, spacing: 4) {
                            Text("\(report.totalScore, specifier: "%.1f") / 35").font(.title2.bold()).foregroundStyle(.white)
                            Button {
                                Task { await state.refreshDashboard() }
                            } label: {
                                Label(state.loading ? "同步中" : "同步报告", systemImage: "arrow.clockwise")
                                    .font(.caption2.weight(.semibold))
                            }
                            .buttonStyle(.bordered)
                            .tint(.white)
                            .disabled(state.loading)
                            .accessibilityLabel(state.loading ? "正在同步报告" : "同步最新体测报告")
                        }
                    }
                    Divider().overlay(.white.opacity(0.25)); Label(report.student.region, systemImage: "mappin.and.ellipse").font(.caption).foregroundStyle(.white.opacity(0.9)); if report.student.isPovertyArea { Label("贫困地区专项帮扶标签", systemImage: "heart.text.square").font(.caption.weight(.semibold)).foregroundStyle(.white) }; Text("测评日期：\(report.assessmentDate) · 规则：\(report.ruleVersion)").font(.caption2).foregroundStyle(.white.opacity(0.8))
                }.padding(18).background(LinearGradient(colors: [AppTheme.primary, AppTheme.teal], startPoint: .topLeading, endPoint: .bottomTrailing), in: RoundedRectangle(cornerRadius: 20))
                Text("7项能力得分").font(.headline).frame(maxWidth: .infinity, alignment: .leading)
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                    ForEach(report.scores) { score in
                        Button { selectedDetail = "\(score.item.shortName)：\(String(format: "%.1f", score.score))分\n\(score.note)\n置信度 \(Int(score.confidence * 100))%" } label: {
                            ReportMetricCard(result: score)
                        }.buttonStyle(.plain)
                    }
                }
                section("能力标签", icon: "tag.fill") { FlowTags(tags: report.abilityTags, color: AppTheme.teal) }
                section("风险提示", icon: "exclamationmark.shield.fill") { VStack(alignment: .leading, spacing: 7) { ForEach(report.riskAlerts, id: \.self) { alert in Button { selectedDetail = "风险提示\n\(alert)" } label: { Label(alert, systemImage: "circle.fill").font(.subheadline).foregroundStyle(alert == "暂无高风险提示" ? AppTheme.teal : AppTheme.danger).frame(maxWidth: .infinity, alignment: .leading) }.buttonStyle(.plain) } } }
                section("训练建议", icon: "figure.strengthtraining.traditional") { VStack(alignment: .leading, spacing: 8) { ForEach(report.trainingAdvice, id: \.self) { advice in Button { selectedDetail = "训练建议\n\(advice)" } label: { Text("• \(advice)").font(.subheadline).foregroundStyle(AppTheme.ink).frame(maxWidth: .infinity, alignment: .leading) }.buttonStyle(.plain) } } }
                section("课程建议", icon: "play.rectangle.fill") { VStack(spacing: 10) { ForEach(report.courseSuggestions) { course in Button { selectedDetail = "课程建议\n\(course.title)\n\(course.focus) · \(course.duration)\n\(course.isPublicBenefit ? "公益课程" : "推荐课程")" } label: { HStack { Image(systemName: "play.circle.fill").font(.title2).foregroundStyle(AppTheme.teal); VStack(alignment: .leading) { Text(course.title).font(.subheadline.weight(.semibold)); Text("\(course.focus) · \(course.duration)").font(.caption).foregroundStyle(AppTheme.muted) }; Spacer(); Text(course.isPublicBenefit ? "公益" : "推荐").font(.caption2.weight(.semibold)).foregroundStyle(AppTheme.primary) }.padding(10).background(AppTheme.surface, in: RoundedRectangle(cornerRadius: 10)).accessibilityElement(children: .combine).accessibilityLabel("课程建议：\(course.title)，\(course.focus)，\(course.duration)") }.buttonStyle(.plain) } } }
            }
        }
        .alert("报告详情", isPresented: Binding(get: { selectedDetail != nil }, set: { if !$0 { selectedDetail = nil } })) {
            Button("知道了") { selectedDetail = nil }
        } message: {
            Text(selectedDetail ?? "")
        }
    }
    private func section<Content: View>(_ title: String, icon: String, @ViewBuilder content: () -> Content) -> some View { VStack(alignment: .leading, spacing: 10) { Label(title, systemImage: icon).font(.headline).foregroundStyle(AppTheme.ink); content() }.frame(maxWidth: .infinity, alignment: .leading).padding(15).background(.white, in: RoundedRectangle(cornerRadius: 16)) }
}
struct FlowTags: View { let tags: [String]; let color: Color; var body: some View { HStack { ForEach(tags, id: \.self) { Text($0).font(.caption.weight(.medium)).foregroundStyle(color).padding(.horizontal, 9).padding(.vertical, 6).background(color.opacity(0.12), in: Capsule()) }; Spacer(minLength: 0) } } }
