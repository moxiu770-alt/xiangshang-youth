import SwiftUI

private struct ReportInsight: Identifiable {
    let id = UUID()
    let icon: String
    let title: String
    let eyebrow: String
    let detail: String
    let color: Color
}

struct ReportDetailView: View {
    @EnvironmentObject private var state: AppState
    @EnvironmentObject private var router: AppRouter
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    let student: Student
    @State private var selectedInsight: ReportInsight?
    @State private var rulesExpanded = false
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
                                    .font(.subheadline)
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
            VStack(spacing: AppTheme.sectionSpacing) {
                reportHero(currentStudent, report: report)
                if let reportError = state.reportError {
                    ErrorStateView(message: reportError, retry: { Task { await state.refreshReport(for: currentStudent) } }, dismiss: state.clearReportError)
                        .frame(minHeight: 150)
                        .background(.white, in: RoundedRectangle(cornerRadius: 16))
                }
                section("七项能力表现", subtitle: "单项满分 5 分，点击查看学校核验说明", icon: "chart.bar.fill") {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: dynamicTypeSize.isAccessibilitySize ? 1 : 2), spacing: 10) {
                        ForEach(report.normalizedScores) { score in
                            Button {
                                selectedInsight = ReportInsight(
                                    icon: score.item.icon,
                                    title: score.item.shortName,
                                    eyebrow: "\(String(format: "%.1f", score.normalizedScore)) / 5 分 · \(score.normalizedReviewStatus.label)",
                                    detail: score.note,
                                    color: score.normalizedReviewStatus == .passed ? ReferenceColor.green : AppTheme.warning
                                )
                            } label: { ReportMetricCard(result: score) }
                            .buttonStyle(.plain)
                        }
                    }
                }
                section("能力标签", subtitle: "基于本次已核验成绩归纳", icon: "tag.fill") {
                    FlowTags(tags: report.abilityTags, color: ReferenceColor.blue)
                }
                section("风险与行动", subtitle: "用具体行动代替笼统结论", icon: "exclamationmark.shield.fill") {
                    VStack(spacing: 9) {
                        ForEach(report.riskAlerts, id: \.self) { alert in
                            insightRow(
                                icon: alert == "暂无高风险提示" ? "checkmark.shield.fill" : "exclamationmark.triangle.fill",
                                title: alert,
                                detail: alert == "暂无高风险提示" ? "保持当前运动习惯，按学校周期复测" : "查看原因、家庭观察要点与建议行动",
                                color: alert == "暂无高风险提示" ? ReferenceColor.green : AppTheme.danger
                            ) {
                                selectedInsight = ReportInsight(icon: "exclamationmark.shield.fill", title: "风险说明", eyebrow: report.riskLevel.label, detail: alert, color: alert == "暂无高风险提示" ? ReferenceColor.green : AppTheme.danger)
                            }
                        }
                    }
                }
                section("训练建议", subtitle: "从当前能力短板开始，每次优先完成 1–2 项", icon: "figure.strengthtraining.traditional") {
                    VStack(spacing: 9) {
                        ForEach(Array(report.trainingAdvice.enumerated()), id: \.offset) { index, advice in
                            insightRow(icon: "\(index + 1).circle.fill", title: advice, detail: "查看练习要点和安全提示", color: ReferenceColor.green) {
                                selectedInsight = ReportInsight(icon: "figure.strengthtraining.traditional", title: "训练建议", eyebrow: "第 \(index + 1) 项", detail: advice, color: ReferenceColor.green)
                            }
                        }
                    }
                }
                section("课程建议", subtitle: "已按孩子当前能力表现匹配", icon: "play.rectangle.fill") { VStack(spacing: 10) { ForEach(report.courseSuggestions) { course in Button {
                    if state.selectedRole == .parent {
                        // The course tab resolves this destination after the
                        // child's scoped catalogue arrives. Do not use the
                        // display title as a remote lookup key.
                        state.openRecommendedCourse(for: currentStudent.id, suggestion: course)
                        router.push(.parentCourses)
                    } else {
                        selectedInsight = ReportInsight(icon: "play.rectangle.fill", title: course.title, eyebrow: course.isPublicBenefit ? "公益课程" : "推荐课程", detail: "\(course.focus) · \(course.duration)", color: ReferenceColor.blue)
                    }
                } label: { courseRow(course) }.buttonStyle(.plain) } } }
                if let bodyRecord {
                    section("家庭身体观察", subtitle: "家长记录，不计入学校七项体测得分", icon: "figure.stand") {
                        Button { router.push(.bodyAssessment) } label: {
                            VStack(alignment: .leading, spacing: 9) {
                            HStack {
                                Text(String(format: "BMI %.1f", bodyRecord.bmi)).font(.headline).foregroundStyle(AppTheme.ink)
                                Spacer()
                                Text(bodyRecord.attention(ageMonths: currentStudent.bodyAssessmentAgeMonths, gender: currentStudent.gender).label)
                                    .font(.system(size: AppTheme.captionSize, weight: .semibold)).foregroundStyle(ReferenceColor.green)
                                Image(systemName: "chevron.right").foregroundStyle(AppTheme.muted)
                            }
                            Text("记录日期：\(bodyRecord.measuredAt.formatted(date: .abbreviated, time: .omitted)) · 已完成 \(bodyRecord.completedCaptures.count) 项拍摄任务")
                                .font(.system(size: AppTheme.captionSize)).foregroundStyle(AppTheme.muted)
                            if let geneticHeight = bodyRecord.geneticHeightReference(gender: currentStudent.gender) {
                                Text("遗传靶身高参考：\(String(format: "%.1f", geneticHeight)) cm（\(bodyRecord.geneticHeightFormula(gender: currentStudent.gender))，仅供健康管理参考）")
                                    .font(.subheadline).foregroundStyle(AppTheme.muted)
                            }
                            if let heightAssessment = bodyRecord.heightDevelopmentAssessment(ageMonths: currentStudent.bodyAssessmentAgeMonths, gender: currentStudent.gender) {
                                Text("当前身高发育：\(heightAssessment.level.label) · \(heightAssessment.ageYears)岁参考中位 \(String(format: "%.1f", heightAssessment.median)) cm")
                                    .font(.subheadline).foregroundStyle(AppTheme.muted)
                            }
                            if let hint = bodyRecord.visualObservationSummary {
                                Label(hint, systemImage: "viewfinder.circle.fill").font(.subheadline).foregroundStyle(.orange)
                            }
                            Text("该记录为家长居家观察与年龄别 BMI 筛查，不属于学校体测的 7 项能力得分，也不构成医学诊断。")
                                .font(.system(size: AppTheme.captionSize)).foregroundStyle(AppTheme.muted)
                            }
                            .padding(16)
                            .background(AppTheme.surface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                        }
                        .buttonStyle(.plain)
                    }
                }
                section("评分依据", subtitle: "保留本次报告采用的规则快照", icon: "checkmark.seal.fill") {
                    DisclosureGroup(isExpanded: $rulesExpanded) {
                        VStack(alignment: .leading, spacing: 9) {
                        LabeledContent("年级标准", value: report.ruleVersion)
                        LabeledContent("适用地区", value: report.regionPolicy.region)
                        LabeledContent("地区政策", value: report.regionPolicy.povertyAreaLabel ?? "通用学生政策")
                        LabeledContent("规则生效日期", value: report.regionPolicy.effectiveDate)
                        Text("报告会保留本次测评采用的评测标准；场地端成绩或地区政策更新后，可查看最新依据。")
                            .font(.system(size: AppTheme.captionSize))
                            .foregroundStyle(AppTheme.muted)
                        }
                        .padding(.top, 10)
                    } label: {
                        Text(rulesExpanded ? "收起规则详情" : "查看规则版本与适用范围")
                            .font(.system(size: AppTheme.secondarySize, weight: .semibold))
                            .foregroundStyle(ReferenceColor.blue)
                    }
                    .font(.subheadline)
                }
            }
        }
        .task(id: currentStudent.id) { await state.refreshReport(for: currentStudent) }
        .sheet(item: $selectedInsight) { insight in reportInsightSheet(insight) }
    }

    private func reportHero(_ currentStudent: Student, report: DiagnosisReport) -> some View {
        let level = report.riskLevel
        let levelColor: Color = switch level {
        case .low: ReferenceColor.green
        case .attention: AppTheme.warning
        case .high: AppTheme.danger
        case .unavailable: .white.opacity(0.78)
        }
        let statusLabel = report.isComplete
            ? (report.reviewItems.isEmpty ? level.label : "\(report.reviewItems.count) 项待复核")
            : "还差 \(AssessmentScoreRules.itemCount - report.scoredItemCount) 项"
        return VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .center, spacing: 16) {
                ZStack {
                    Circle().stroke(.white.opacity(0.20), lineWidth: 9)
                    Circle()
                        .trim(from: 0, to: report.scoreCompletionRatio)
                        .stroke(.white, style: StrokeStyle(lineWidth: 9, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                    VStack(spacing: 0) {
                        Text(report.isComplete ? String(format: "%.1f", report.totalScore) : "\(report.scoredItemCount)")
                            .font(.system(size: 24, weight: .bold, design: .rounded))
                        Text(report.isComplete ? "/ 35" : "/ 7 项")
                            .font(.system(size: 16, weight: .semibold))
                            .opacity(0.78)
                    }
                    .foregroundStyle(.white)
                }
                .frame(width: 102, height: 102)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(report.isComplete ? "体测总分 \(report.totalScore, specifier: "%.1f") 分，满分 35 分" : "已完成 \(report.scoredItemCount) 项，共 7 项")

                VStack(alignment: .leading, spacing: 6) {
                    Text(currentStudent.name)
                        .font(.system(size: AppTheme.pageTitleSize, weight: .bold))
                    Text("\(currentStudent.grade) · \(currentStudent.className)")
                        .font(.system(size: AppTheme.secondarySize, weight: .medium))
                        .foregroundStyle(.white.opacity(0.82))
                    Text(statusLabel)
                        .font(.system(size: AppTheme.captionSize, weight: .semibold))
                        .foregroundStyle(levelColor)
                        .padding(.horizontal, 9)
                        .padding(.vertical, 5)
                        .background(.white.opacity(0.14), in: Capsule())
                }
                .foregroundStyle(.white)
                Spacer(minLength: 0)
            }

            Divider().overlay(.white.opacity(0.20))
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 14) {
                    Label(report.assessmentDate, systemImage: "calendar")
                    Label(currentStudent.region, systemImage: "mappin.and.ellipse")
                    Spacer(minLength: 0)
                    syncReportButton(currentStudent)
                }
                VStack(alignment: .leading, spacing: 10) {
                    Label(report.assessmentDate, systemImage: "calendar")
                    Label(currentStudent.region, systemImage: "mappin.and.ellipse")
                    syncReportButton(currentStudent)
                }
            }
            .font(.system(size: AppTheme.captionSize, weight: .medium))
            .foregroundStyle(.white.opacity(0.86))
        }
        .padding(20)
        .background(
            LinearGradient(colors: [ReferenceColor.blue, Color(hex: "17A7B7")], startPoint: .topLeading, endPoint: .bottomTrailing),
            in: RoundedRectangle(cornerRadius: 22, style: .continuous)
        )
        .shadow(color: ReferenceColor.blue.opacity(0.18), radius: 18, y: 10)
    }

    private func syncReportButton(_ currentStudent: Student) -> some View {
        Button { Task { await state.refreshReport(for: currentStudent) } } label: {
            HStack(spacing: 6) {
                if state.reportLoading { ProgressView().tint(.white) }
                Image(systemName: state.reportLoading ? "arrow.triangle.2.circlepath" : "arrow.clockwise")
                Text(state.reportLoading ? "同步中" : "更新报告")
            }
            .font(.system(size: AppTheme.captionSize, weight: .semibold))
            .padding(.horizontal, 11)
            .frame(minHeight: 36)
            .background(.white.opacity(0.16), in: Capsule())
        }
        .buttonStyle(.plain)
        .disabled(state.reportLoading)
        .accessibilityLabel(state.reportLoading ? "正在同步报告" : "同步最新体测报告")
    }

    private func section<Content: View>(
        _ title: String,
        subtitle: String? = nil,
        icon: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 13) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: icon)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(ReferenceColor.blue)
                    .frame(width: 36, height: 36)
                    .background(ReferenceColor.blue.opacity(0.10), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.system(size: AppTheme.sectionTitleSize, weight: .bold))
                        .foregroundStyle(ReferenceColor.navy)
                        .accessibilityAddTraits(.isHeader)
                    if let subtitle {
                        Text(subtitle)
                            .font(.system(size: AppTheme.captionSize))
                            .foregroundStyle(AppTheme.muted)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(AppTheme.cardPadding)
        .background(.white, in: RoundedRectangle(cornerRadius: AppTheme.cardRadius, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: AppTheme.cardRadius, style: .continuous).stroke(AppTheme.divider.opacity(0.72), lineWidth: 0.8))
    }

    private func insightRow(icon: String, title: String, detail: String, color: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(alignment: .center, spacing: 11) {
                Image(systemName: icon)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(color)
                    .frame(width: 38, height: 38)
                    .background(color.opacity(0.10), in: RoundedRectangle(cornerRadius: 11, style: .continuous))
                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.system(size: AppTheme.secondarySize, weight: .semibold))
                        .foregroundStyle(ReferenceColor.navy)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(detail)
                        .font(.system(size: AppTheme.captionSize))
                        .foregroundStyle(AppTheme.muted)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right").foregroundStyle(AppTheme.muted)
            }
            .padding(16)
            .background(AppTheme.surface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private func courseRow(_ course: CourseSuggestion) -> some View {
        HStack(spacing: 12) {
            ZStack {
                LinearGradient(colors: [ReferenceColor.blue, ReferenceColor.green], startPoint: .topLeading, endPoint: .bottomTrailing)
                Image(systemName: "play.fill").font(.system(size: 17, weight: .bold)).foregroundStyle(.white)
            }
            .frame(width: 52, height: 52)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            VStack(alignment: .leading, spacing: 4) {
                Text(course.title)
                    .font(.system(size: AppTheme.secondarySize, weight: .semibold))
                    .foregroundStyle(ReferenceColor.navy)
                    .fixedSize(horizontal: false, vertical: true)
                Text("\(course.focus) · \(course.duration)")
                    .font(.system(size: AppTheme.captionSize))
                    .foregroundStyle(AppTheme.muted)
                Text(course.isPublicBenefit ? "公益课程" : "为孩子推荐")
                    .font(.system(size: AppTheme.captionSize, weight: .semibold))
                    .foregroundStyle(course.isPublicBenefit ? ReferenceColor.green : ReferenceColor.blue)
            }
            Spacer(minLength: 0)
            Image(systemName: "chevron.right").foregroundStyle(AppTheme.muted)
        }
        .padding(16)
        .background(AppTheme.surface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("课程建议：\(course.title)，\(course.focus)，\(course.duration)")
    }

    private func reportInsightSheet(_ insight: ReportInsight) -> some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 18) {
                    Image(systemName: insight.icon)
                        .font(.system(size: 30, weight: .semibold))
                        .foregroundStyle(insight.color)
                        .frame(width: 68, height: 68)
                        .background(insight.color.opacity(0.12), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                    VStack(spacing: 6) {
                        Text(insight.eyebrow)
                            .font(.system(size: AppTheme.captionSize, weight: .semibold))
                            .foregroundStyle(insight.color)
                        Text(insight.title)
                            .font(.system(size: AppTheme.pageTitleSize, weight: .bold))
                            .foregroundStyle(ReferenceColor.navy)
                            .multilineTextAlignment(.center)
                    }
                    Text(insight.detail)
                        .font(.system(size: AppTheme.bodySize))
                        .foregroundStyle(AppTheme.ink)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(AppTheme.cardPadding)
                        .background(AppTheme.surface, in: RoundedRectangle(cornerRadius: AppTheme.cardRadius, style: .continuous))
                    AssessmentInfoBanner(icon: "checkmark.shield.fill", title: "建议如何使用", detail: "结合孩子日常状态循序练习；如有疼痛、不适或活动受限，请停止训练并咨询专业人员。")
                }
                .padding(20)
            }
            .background(AppTheme.surface.ignoresSafeArea())
            .navigationTitle("报告说明")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("完成") { selectedInsight = nil } } }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }
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
struct FlowTags: View {
    let tags: [String]
    let color: Color
    var body: some View {
        AdaptiveFlowLayout(spacing: 8) {
            ForEach(tags, id: \.self) { tag in
                Text(tag)
                    .font(.system(size: AppTheme.captionSize, weight: .semibold))
                    .foregroundStyle(color)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 7)
                    .background(color.opacity(0.10), in: Capsule())
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
