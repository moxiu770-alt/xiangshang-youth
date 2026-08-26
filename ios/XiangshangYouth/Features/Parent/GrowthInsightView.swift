import SwiftUI

struct GrowthInsightView: View {
    @EnvironmentObject private var state: AppState
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var period = GrowthReportPeriod.week
    @State private var animatedProgress = 0.0
    let onOpenCourses: () -> Void

    private var student: Student? { state.selectedChild }
    private var bodyRecord: BodyAssessmentRecord? { student.flatMap(state.bodyAssessment(for:)) }
    private var insight: GrowthInsight {
        let assessmentCount = state.localFeatures.completedAssessments.filter { key in student.map { key.hasPrefix($0.id) } ?? false }.count
        return GrowthInsight.make(
            period: period,
            checkInDates: state.localFeatures.checkInDates,
            planDates: bodyRecord?.completedPlanDays ?? [],
            assessmentCount: assessmentCount,
            bodyAttention: student.flatMap { student in bodyRecord?.attention(ageMonths: student.bodyAssessmentAgeMonths, gender: student.gender) },
            totalScore: student.flatMap { student in
                state.hasPublishedSchoolReport(for: student)
                    ? state.visibleReport(for: student)?.totalScore
                    : nil
            }
        )
    }
    private var reduceMotion: Bool { state.localFeatures.settings.reduceMotion || systemReduceMotion }
    private var columns: [GridItem] { Array(repeating: GridItem(.flexible(), spacing: 8), count: dynamicTypeSize.isAccessibilitySize ? 1 : 3) }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 14) {
                    Picker("报告周期", selection: $period) {
                        ForEach(GrowthReportPeriod.allCases) { Text($0.rawValue).tag($0) }
                    }
                    .pickerStyle(.segmented)

                    ReferenceCard {
                        HStack(spacing: 18) {
                            ZStack {
                                Circle().stroke(ReferenceColor.blue.opacity(0.12), lineWidth: 10)
                                Circle().trim(from: 0, to: animatedProgress)
                                    .stroke(LinearGradient(colors: [ReferenceColor.blue, ReferenceColor.green], startPoint: .topLeading, endPoint: .bottomTrailing), style: StrokeStyle(lineWidth: 10, lineCap: .round))
                                    .rotationEffect(.degrees(-90))
                                VStack(spacing: 1) {
                                    Text("\(insight.consistencyPercent)%").font(.title2.bold()).foregroundStyle(ReferenceColor.navy)
                                    Text("完成率").font(.caption).foregroundStyle(.secondary)
                                }
                            }.frame(width: 104, height: 104)
                            VStack(alignment: .leading, spacing: 6) {
                                Text("\(student?.name ?? "孩子")的\(period.rawValue)成长报告").font(.headline).foregroundStyle(ReferenceColor.navy)
                                Text("来自运动打卡、家庭计划和已完成测评，不使用虚构训练数据。")
                                    .font(.caption).foregroundStyle(.secondary)
                                Label("活跃 \(insight.activeDays) / \(insight.targetActiveDays) 天", systemImage: "calendar.badge.checkmark")
                                    .font(.caption.weight(.semibold)).foregroundStyle(ReferenceColor.blue)
                            }
                        }
                    }

                    LazyVGrid(columns: columns, spacing: 8) {
                        metric("运动活跃", "\(insight.activeDays) 天", "figure.run", ReferenceColor.blue)
                        metric("计划完成", "\(insight.planDays) 天", "checkmark.seal.fill", ReferenceColor.green)
                        metric("健康测评", "\(insight.assessmentCount) 项", "heart.text.square.fill", ReferenceColor.pink)
                    }

                    ReferenceCard {
                        VStack(alignment: .leading, spacing: 10) {
                            Label("计划已更新", systemImage: "slider.horizontal.3")
                                .font(.caption.weight(.bold)).foregroundStyle(ReferenceColor.green)
                            Text(insight.planTitle).font(.title3.bold()).foregroundStyle(ReferenceColor.navy)
                            Text(insight.planReason).font(.caption).foregroundStyle(.secondary)
                            HStack(spacing: 8) {
                                planPill("每周 \(insight.sessionsPerWeek) 次", "calendar")
                                planPill("每次 \(insight.minutesPerSession) 分钟", "clock")
                            }
                            Divider()
                            ForEach(Array(insight.actions.enumerated()), id: \.offset) { index, action in
                                HStack(alignment: .top, spacing: 9) {
                                    Text("\(index + 1)").font(.caption.bold()).foregroundStyle(.white).frame(width: 20, height: 20).background(ReferenceColor.blue, in: Circle())
                                    Text(action).font(.subheadline).foregroundStyle(ReferenceColor.navy)
                                }
                            }
                        }
                    }

                    Button {
                        FrontendTelemetry.record(.adaptivePlanOpenedCourses, value: period.rawValue)
                        dismiss()
                        onOpenCourses()
                    } label: {
                        Label("开始今日训练", systemImage: "play.fill").font(.headline).frame(maxWidth: .infinity).padding(.vertical, 13)
                    }.buttonStyle(.borderedProminent)

                    Text("计划调整属于健康管理建议，不替代医疗诊断；出现疼痛、麻木、无力或持续异常时请停止训练并咨询专业人员。")
                        .font(.caption).foregroundStyle(.secondary)
                }.padding(16).frame(maxWidth: 720)
            }
            .background(ReferenceColor.canvas)
            .navigationTitle("成长报告")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("完成") { dismiss() } } }
            .task { FrontendTelemetry.record(.growthReportOpened, value: period.rawValue); updateProgress() }
            .onChange(of: period) { _, value in FrontendTelemetry.record(.growthReportPeriodChanged, value: value.rawValue); updateProgress() }
        }
    }

    private func updateProgress() {
        let value = Double(insight.consistencyPercent) / 100
        if reduceMotion { animatedProgress = value }
        else { animatedProgress = 0; withAnimation(.easeOut(duration: 0.7)) { animatedProgress = value } }
    }
    private func metric(_ title: String, _ value: String, _ icon: String, _ color: Color) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Image(systemName: icon).foregroundStyle(color)
            Text(value).font(.title3.bold()).foregroundStyle(ReferenceColor.navy)
            Text(title).font(.caption).foregroundStyle(.secondary)
        }.frame(maxWidth: .infinity, alignment: .leading).padding(12).background(.white, in: RoundedRectangle(cornerRadius: 14))
    }
    private func planPill(_ title: String, _ icon: String) -> some View {
        Label(title, systemImage: icon).font(.caption.weight(.semibold)).foregroundStyle(ReferenceColor.blue).padding(.horizontal, 9).padding(.vertical, 6).background(ReferenceColor.sky, in: Capsule())
    }
}
