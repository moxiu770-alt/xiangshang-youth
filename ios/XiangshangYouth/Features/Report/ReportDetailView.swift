import SwiftUI

struct ReportDetailView: View {
    @EnvironmentObject private var state: AppState
    @EnvironmentObject private var router: AppRouter
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    let student: Student
    @State private var selectedDetail: String?
    var body: some View {
        if let error = state.error, state.data == nil {
            AppScaffold(title: "体测报告") {
                ErrorStateView(message: error) { Task { await state.refreshDashboard() } }
            }
        } else if state.loading || state.data == nil {
            AppScaffold(title: "体测报告") {
                LoadingStateView()
            }
        } else if let currentStudent = state.data?.students.first(where: { $0.id == student.id }) {
            if state.hasPublishedSchoolReport(for: currentStudent) {
                if let report = state.visibleReport(for: currentStudent) {
                    reportContent(for: currentStudent, report: report)
                } else {
                    AppScaffold(title: "体测报告") {
                        VStack(spacing: 14) {
                            if let reportError = state.reportError {
                                ErrorStateView(message: reportError) { Task { await state.refreshReport(for: currentStudent) } }
                            } else {
                                LoadingStateView()
                                Text("正在获取学校已发布的体测报告")
                                    .font(.footnote)
                                    .foregroundStyle(AppTheme.muted)
                            }
                        }
                        .frame(maxWidth: .infinity, minHeight: 260)
                        .task(id: currentStudent.id) { await state.refreshReport(for: currentStudent) }
                    }
                }
            } else {
                SchoolReportPendingView(student: currentStudent)
            }
        } else {
            // A stale push or a server-side roster change must not retain the
            // health data carried in a route payload.  The user can safely go
            // back and refresh the current class/family list instead.
            AppScaffold(title: "体测报告") {
                EmptyStateView(title: "未找到学生档案", detail: "该学生可能已调班或档案尚未同步，请返回后刷新列表。")
            }
        }
    }

    @ViewBuilder private func reportContent(for currentStudent: Student, report: DiagnosisReport) -> some View {
        let bodyRecord = state.bodyAssessment(for: currentStudent)
        AppScaffold(title: "体测报告") {
            VStack(spacing: 16) {
                VStack(alignment: .leading, spacing: 9) {
                    HStack(alignment: .top) {
                        VStack(alignment: .leading) { Text(report.student.name).font(.title2.bold()).foregroundStyle(.white); Text("\(report.student.grade) · \(report.student.className)").foregroundStyle(.white.opacity(0.85)) }
                        Spacer()
                        VStack(alignment: .trailing, spacing: 4) {
                            Text(report.isComplete ? "\(report.totalScore, specifier: "%.1f") / 35" : "待完成 \(report.scoredItemCount)/7 项").font(.title2.bold()).foregroundStyle(.white)
                            Button {
                                Task { await state.refreshReport(for: currentStudent) }
                            } label: {
                                Label(state.reportLoading ? "同步中" : "同步报告", systemImage: "arrow.clockwise")
                                    .font(.caption2.weight(.semibold))
                            }
                            .buttonStyle(.bordered)
                            .tint(.white)
                            .disabled(state.reportLoading)
                            .accessibilityLabel(state.reportLoading ? "正在同步报告" : "同步最新体测报告")
                        }
                    }
                    Divider().overlay(.white.opacity(0.25)); Label(report.student.region, systemImage: "mappin.and.ellipse").font(.caption).foregroundStyle(.white.opacity(0.9)); Text("测评日期：\(report.assessmentDate) · 评测标准已应用").font(.caption2).foregroundStyle(.white.opacity(0.8))
                }.padding(18).background(LinearGradient(colors: [AppTheme.primary, AppTheme.teal], startPoint: .topLeading, endPoint: .bottomTrailing), in: RoundedRectangle(cornerRadius: 20))
                if let reportError = state.reportError {
                    ErrorStateView(message: reportError, retry: { Task { await state.refreshReport(for: currentStudent) } }, dismiss: state.clearReportError)
                        .frame(minHeight: 150)
                        .background(.white, in: RoundedRectangle(cornerRadius: 16))
                }
                Text("7项能力得分").font(.headline).frame(maxWidth: .infinity, alignment: .leading)
                // Preserve the two-column phone layout at normal text sizes,
                // while giving each metric a full row at accessibility sizes.
                LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: dynamicTypeSize.isAccessibilitySize ? 1 : 2), spacing: 10) {
                    ForEach(report.scores) { score in
                        Button { selectedDetail = "\(score.item.shortName)：\(String(format: "%.1f", score.score))分\n\(score.note)\n状态：\(score.reviewStatus.label)" } label: {
                            ReportMetricCard(result: score)
                        }.buttonStyle(.plain)
                    }
                }
                section("能力标签", icon: "tag.fill") { FlowTags(tags: report.abilityTags, color: AppTheme.teal) }
                section("风险提示", icon: "exclamationmark.shield.fill") { VStack(alignment: .leading, spacing: 7) { ForEach(report.riskAlerts, id: \.self) { alert in Button { selectedDetail = "风险提示\n\(alert)" } label: { Label(alert, systemImage: "circle.fill").font(.subheadline).foregroundStyle(alert == "暂无高风险提示" ? AppTheme.teal : AppTheme.danger).frame(maxWidth: .infinity, alignment: .leading) }.buttonStyle(.plain) } } }
                section("训练建议", icon: "figure.strengthtraining.traditional") { VStack(alignment: .leading, spacing: 8) { ForEach(report.trainingAdvice, id: \.self) { advice in Button { selectedDetail = "训练建议\n\(advice)" } label: { Text("• \(advice)").font(.subheadline).foregroundStyle(AppTheme.ink).frame(maxWidth: .infinity, alignment: .leading) }.buttonStyle(.plain) } } }
                section("课程建议", icon: "play.rectangle.fill") { VStack(spacing: 10) { ForEach(report.courseSuggestions) { course in Button {
                    if state.selectedRole == .parent {
                        // The course tab resolves this destination after the
                        // child's scoped catalogue arrives. Do not use the
                        // display title as a remote lookup key.
                        state.openRecommendedCourse(for: currentStudent.id, suggestion: course)
                        router.push(.parentCourses)
                    } else {
                        selectedDetail = "课程建议\n\(course.title)\n\(course.focus) · \(course.duration)\n\(course.isPublicBenefit ? "公益课程" : "推荐课程")"
                    }
                } label: { HStack { Image(systemName: "play.circle.fill").font(.title2).foregroundStyle(AppTheme.teal); VStack(alignment: .leading) { Text(course.title).font(.subheadline.weight(.semibold)); Text("\(course.focus) · \(course.duration)").font(.caption).foregroundStyle(AppTheme.muted) }; Spacer(); Text(course.isPublicBenefit ? "公益" : "推荐").font(.caption2.weight(.semibold)).foregroundStyle(AppTheme.primary) }.padding(10).background(AppTheme.surface, in: RoundedRectangle(cornerRadius: 10)).accessibilityElement(children: .combine).accessibilityLabel("课程建议：\(course.title)，\(course.focus)，\(course.duration)") }.buttonStyle(.plain) } } }
                if let bodyRecord {
                    section("家庭身体观察（家长记录）", icon: "figure.stand") {
                        VStack(alignment: .leading, spacing: 7) {
                            HStack {
                                Text(String(format: "BMI %.1f", bodyRecord.bmi)).font(.headline).foregroundStyle(AppTheme.ink)
                                Spacer()
                                Text(bodyRecord.attention(ageMonths: currentStudent.bodyAssessmentAgeMonths, gender: currentStudent.gender).label)
                                    .font(.caption.weight(.semibold)).foregroundStyle(AppTheme.teal)
                            }
                            Text("记录日期：\(bodyRecord.measuredAt.formatted(date: .abbreviated, time: .omitted)) · 已完成 \(bodyRecord.completedCaptures.count) 项拍摄任务")
                                .font(.caption).foregroundStyle(AppTheme.muted)
                            if let geneticHeight = bodyRecord.geneticHeightReference(gender: currentStudent.gender) {
                                Text("遗传靶身高参考：\(String(format: "%.1f", geneticHeight)) cm（\(bodyRecord.geneticHeightFormula(gender: currentStudent.gender))，仅供健康管理参考）")
                                    .font(.caption2).foregroundStyle(AppTheme.muted)
                            }
                            if let heightAssessment = bodyRecord.heightDevelopmentAssessment(ageMonths: currentStudent.bodyAssessmentAgeMonths, gender: currentStudent.gender) {
                                Text("当前身高发育：\(heightAssessment.level.label) · \(heightAssessment.ageYears)岁参考中位 \(String(format: "%.1f", heightAssessment.median)) cm")
                                    .font(.caption2).foregroundStyle(AppTheme.muted)
                            }
                            if let hint = bodyRecord.visualObservationSummary {
                                Label(hint, systemImage: "viewfinder.circle.fill").font(.caption).foregroundStyle(.orange)
                            }
                            Text("该记录为家长居家观察与年龄别 BMI 筛查，不属于学校体测的 7 项能力得分，也不构成医学诊断。")
                                .font(.caption2).foregroundStyle(AppTheme.muted)
                        }
                    }
                }
                section("规则依据与适用范围", icon: "checkmark.seal.fill") {
                    VStack(alignment: .leading, spacing: 7) {
                        LabeledContent("年级标准", value: report.ruleVersion)
                        LabeledContent("适用地区", value: report.regionPolicy.region)
                        LabeledContent("地区政策", value: report.regionPolicy.povertyAreaLabel ?? "通用学生政策")
                        LabeledContent("规则生效日期", value: report.regionPolicy.effectiveDate)
                        Text("报告会保留本次测评采用的评测标准；场地端成绩或地区政策更新后，可查看最新依据。")
                            .font(.caption)
                            .foregroundStyle(AppTheme.muted)
                    }
                    .font(.subheadline)
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel("评测标准：\(report.ruleVersion)，适用地区\(report.regionPolicy.region)，政策\(report.regionPolicy.povertyAreaLabel ?? "通用学生政策")，生效日期\(report.regionPolicy.effectiveDate)")
                }
            }
        }
        .task(id: currentStudent.id) { await state.refreshReport(for: currentStudent) }
        .alert("报告详情", isPresented: Binding(get: { selectedDetail != nil }, set: { if !$0 { selectedDetail = nil } })) {
            Button("知道了") { selectedDetail = nil }
        } message: {
            Text(selectedDetail ?? "")
        }
    }
    private func section<Content: View>(_ title: String, icon: String, @ViewBuilder content: () -> Content) -> some View { VStack(alignment: .leading, spacing: 10) { Label(title, systemImage: icon).font(.headline).foregroundStyle(AppTheme.ink); content() }.frame(maxWidth: .infinity, alignment: .leading).padding(15).background(.white, in: RoundedRectangle(cornerRadius: 16)) }
}

/// A school report is an issued result, not a placeholder for a task that is
/// still running.  This route is shared by family, teacher and principal
/// flows, so the waiting state also gives every entry point a safe way back.
struct SchoolReportPendingView: View {
    @EnvironmentObject private var router: AppRouter
    let student: Student

    var body: some View {
        AppScaffold(title: "体测报告") {
            VStack(spacing: 16) {
                Image(systemName: "doc.badge.clock")
                    .font(.system(size: 44))
                    .foregroundStyle(ReferenceColor.blue)
                Text("报告暂未发布")
                    .font(.title3.bold())
                    .foregroundStyle(ReferenceColor.navy)
                Text("\(student.name)的学校运动体测报告将在场地端完成成绩核验并发布后显示。家庭身体测评记录不影响学校 7 项体测报告。")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                Button("返回上一页") { router.pop() }
                    .buttonStyle(.borderedProminent)
                    .tint(ReferenceColor.blue)
            }
            .frame(maxWidth: .infinity, minHeight: 320)
            .padding(24)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(student.name)的学校体测报告暂未发布")
    }
}
struct FlowTags: View { let tags: [String]; let color: Color; var body: some View { HStack { ForEach(tags, id: \.self) { Text($0).font(.caption.weight(.medium)).foregroundStyle(color).padding(.horizontal, 9).padding(.vertical, 6).background(color.opacity(0.12), in: Capsule()) }; Spacer(minLength: 0) } } }
