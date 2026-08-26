import SwiftUI

/// The family-side assessment intentionally stores only the parent's confirmed
/// observations and completed tasks. Real-time capture is processed in the
/// App and does not retain photos or videos at this stage.
struct BodyAssessmentView: View {
    private enum Step: Int, CaseIterable { case overview, consent, profile, bmi, environment, capture, confirm, result, plan }
    private let assessmentSteps = ["使用说明", "监护人授权", "孩子身体信息", "身高体重和BMI", "拍摄环境检查", "摄像头测评", "质量确认", "结果报告", "训练计划"]

    @EnvironmentObject private var state: AppState
    @EnvironmentObject private var router: AppRouter
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var step: Step = .overview
    // Values deliberately start empty (zero) rather than with a child's
    // fabricated measurement. The ruler becomes active only after a parent
    // enters a real value.
    @State private var height = 0.0
    @State private var weight = 0.0
    @State private var fatherHeight = 0.0
    @State private var motherHeight = 0.0
    @State private var completedCaptures = Set<BodyAssessmentRecord.CaptureTask>()
    @State private var asymmetric = false
    @State private var gaitConcern = false
    @State private var activeCameraTask: BodyAssessmentRecord.CaptureTask?
    @State private var captureFeedback: [BodyAssessmentRecord.CaptureTask: String] = [:]
    @State private var visualHints: [BodyAssessmentRecord.CaptureTask: String] = [:]
    @State private var postureSnapshots: [BodyAssessmentRecord.CaptureTask: PostureMetricSnapshot] = [:]
    @State private var adultReady = false
    @State private var spaceReady = false
    @State private var consentAcknowledged = false
    @State private var didLoad = false
    @State private var showFollowAlong = false
    @State private var followAlongDayIndex = 0
    @State private var followAlongDate = Date()
    /// Viewing a saved family observation is read-only navigation context. Its
    /// back action must leave the feature, not expose the old confirmation
    /// form where a finished record could be accidentally re-submitted.
    @State private var viewingSavedRecord = false

    private var student: Student? { state.selectedChild }
    private var visualSummary: String? {
        let summary = visualHints.keys.sorted { $0.rawValue < $1.rawValue }.compactMap { visualHints[$0] }.joined(separator: "\n")
        return summary.isEmpty ? nil : summary
    }
    private var provisionalRecord: BodyAssessmentRecord {
        BodyAssessmentRecord(
            heightCentimeters: height,
            weightKilograms: weight,
            measuredAt: .now,
            ruleVersion: BodyAssessmentRecord.ruleVersion,
            completedCaptures: completedCaptures,
            parentMarkedAsymmetric: asymmetric,
            parentMarkedGaitConcern: gaitConcern,
            visualObservationHint: visualSummary,
            captureObservationHints: visualHints,
            fatherHeightCentimeters: fatherHeight,
            motherHeightCentimeters: motherHeight,
            savedAt: .now,
            nextFollowUpDate: followUpDate,
            completedPlanDays: state.bodyAssessment(for: student ?? fallbackStudent)?.completedPlanDays ?? [],
            postureReport: postureSnapshots.isEmpty ? nil : PostureAssessmentReport.make(snapshots: postureSnapshots, ageMonths: student?.bodyAssessmentAgeMonths),
            ageMonthsAtMeasurement: student?.bodyAssessmentAgeMonths
        )
    }
    private var fallbackStudent: Student { Student(id: "body-assessment-preview", name: "孩子", gender: "男", grade: "三年级", className: "三年级1班", region: "", isPovertyArea: false, taskStatus: .completed, totalScore: nil) }
    private var hasValidCoreMeasurements: Bool {
        (90.0...190.0).contains(height) && (15.0...90.0).contains(weight)
    }
    private var followUpDate: Date {
        let level = provisionalBMILevel
        let days = level == .red ? 7 : level == .yellow || asymmetric || gaitConcern ? 30 : 90
        return BusinessClock.addingDays(days)
    }
    private var provisionalBMILevel: BodyAssessmentRecord.AttentionLevel {
        return BodyAssessmentRecord(heightCentimeters: height, weightKilograms: weight, measuredAt: .now, ruleVersion: BodyAssessmentRecord.ruleVersion, completedCaptures: [], parentMarkedAsymmetric: false, parentMarkedGaitConcern: false, savedAt: .now, nextFollowUpDate: .now, completedPlanDays: []).bmiAttention(ageMonths: student?.bodyAssessmentAgeMonths, gender: student?.gender ?? "男")
    }
    private var record: BodyAssessmentRecord? { student.flatMap(state.bodyAssessment(for:)) }

    var body: some View {
        Group {
            if let student {
                AppScaffold(title: stepTitle, onBack: goBack) {
                    VStack(spacing: 16) {
                        progress
                        switch step {
                        case .overview: overview(student)
                        case .consent: consentStep
                        case .profile: profileStep(student)
                        case .bmi: bmiEntry(student)
                        case .environment: environmentStep
                        case .capture: captureGuide
                        case .confirm: observationConfirm
                        case .result: result(student)
                        case .plan: plan(student)
                        }
                    }
                    .padding(.top, 12)
                }
                .task { load(record: state.bodyAssessment(for: student), draft: state.bodyAssessmentDraft(for: student)) }
                .onChange(of: height) { _, _ in persistDraft() }
                .onChange(of: weight) { _, _ in persistDraft() }
                .onChange(of: fatherHeight) { _, _ in persistDraft() }
                .onChange(of: motherHeight) { _, _ in persistDraft() }
                .onChange(of: adultReady) { _, _ in persistDraft() }
                .onChange(of: consentAcknowledged) { _, _ in persistDraft() }
                .onChange(of: spaceReady) { _, _ in persistDraft() }
                .onChange(of: completedCaptures) { _, _ in persistDraft() }
                .onChange(of: asymmetric) { _, _ in persistDraft() }
                .onChange(of: gaitConcern) { _, _ in persistDraft() }
                .onChange(of: visualHints) { _, _ in persistDraft() }
                .onChange(of: postureSnapshots) { _, _ in persistDraft() }
            } else {
                ParentBindingPrompt()
            }
        }
        .sheet(item: $activeCameraTask) { task in
            LiveVisionCaptureSheet(task: task, measuredHeightCm: height, ageMonths: student?.bodyAssessmentAgeMonths) { review in
                captureFeedback[task] = review.message
                if let hint = review.observationHint { visualHints[task] = hint }
                else { visualHints.removeValue(forKey: task) }
                if let snapshot = review.postureSnapshot { postureSnapshots[task] = snapshot }
                if review.accepted { completedCaptures.insert(task) }
                activeCameraTask = nil
            } cancelled: {
                captureFeedback[task] = "已取消记录，可随时重新开始。"
                activeCameraTask = nil
            }
            .ignoresSafeArea()
            .interactiveDismissDisabled()
        }
        .sheet(isPresented: $showFollowAlong) {
            if let student {
                FollowAlongTrainingView(studentID: student.id, studentName: student.name, dayIndex: followAlongDayIndex, ageMonths: student.bodyAssessmentAgeMonths) {
                    // The training receipt owns plan completion. AppState only
                    // marks the day after a camera-verified session; ending a
                    // manual fallback must not create a false streak.
                }
            } else {
                ParentBindingPrompt()
            }
        }
    }

    private var stepTitle: String {
        assessmentSteps[displayStepIndex]
    }

    private var displayStepIndex: Int {
        step.rawValue
    }

    private var progress: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack { Text("家庭身体测评 · \(assessmentSteps[displayStepIndex])").font(.headline).foregroundStyle(ReferenceColor.navy); Spacer(); Text("\(displayStepIndex + 1) / \(assessmentSteps.count)").font(.caption.weight(.bold)).foregroundStyle(ReferenceColor.blue) }
            ProgressView(value: Double(displayStepIndex + 1), total: Double(assessmentSteps.count)).tint(bodyCoral)
        }
    }

    private func overview(_ student: Student) -> some View {
        VStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 5) {
                        Text("给 \(student.name) 一次居家身体观察").font(.title3.bold()).foregroundStyle(ReferenceColor.navy)
                        Text("包含 BMI、三种姿态和一段自然步态。全程由家长操作，约 5 分钟完成。")
                            .font(.subheadline).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Image(systemName: "figure.walk.motion").font(.system(size: 36)).foregroundStyle(bodyCoral)
                }
                HStack(spacing: 8) { overviewPill("App 内相机", "camera.fill"); overviewPill("实时记录", "lock.fill"); overviewPill("健康观察", "heart.text.square") }
            }
            .padding(16).background(bodyCream, in: RoundedRectangle(cornerRadius: 20))

            if let record {
                ReferenceCard {
                    VStack(alignment: .leading, spacing: 9) {
                        Text("最近一次记录").font(.headline).foregroundStyle(ReferenceColor.navy)
                        HStack { Label(String(format: "BMI %.1f", record.bmi), systemImage: "scalemass.fill"); Spacer(); attentionBadge(record.attention(ageMonths: student.bodyAssessmentAgeMonths, gender: student.gender)) }
                        Text("测评于 \(dateText(record.measuredAt)) · 已完成 \(record.completedCaptures.count) 项拍摄任务")
                            .font(.caption).foregroundStyle(.secondary)
                        Button("查看结果与计划") { viewingSavedRecord = true; move(to: .result) }.buttonStyle(.bordered).tint(ReferenceColor.blue)
                    }
                }
            }

            ReferenceCard { VStack(alignment: .leading, spacing: 8) {
                Label("九步流程", systemImage: "list.number").font(.headline).foregroundStyle(ReferenceColor.navy)
                Text("先完成授权和孩子资料确认，再填写本次身高体重，最后进行 App 内姿态与步态观察。每一步都会按当前孩子单独保存。")
                    .font(.subheadline).foregroundStyle(.secondary)
            } }
            primaryButton("开始授权", icon: "arrow.right") { move(to: .consent) }
        }
    }

    private var consentStep: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("监护人授权").font(.title3.bold()).foregroundStyle(ReferenceColor.navy)
            Text("身体测评仅用于家庭运动健康筛查和训练建议，不替代医疗诊断。App 不保存原始照片或视频，只保存测量值、动作结果和质量摘要。")
                .font(.subheadline).foregroundStyle(.secondary)
            readinessToggle("我确认自己是孩子的监护人，并会全程陪同。", isOn: $adultReady)
            readinessToggle("我已阅读摄像头、算法和数据保留说明。", isOn: $consentAcknowledged)
            primaryButton(adultReady && consentAcknowledged ? "继续确认孩子资料" : "请完成授权确认", icon: "arrow.right") { move(to: .profile) }
                .opacity(adultReady && consentAcknowledged ? 1 : 0.55)
                .disabled(!adultReady || !consentAcknowledged)
        }
    }

    private func profileStep(_ student: Student) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("孩子身体信息").font(.title3.bold()).foregroundStyle(ReferenceColor.navy)
            ReferenceCard {
                VStack(alignment: .leading, spacing: 9) {
                    Label(student.name, systemImage: "person.fill").font(.headline).foregroundStyle(ReferenceColor.navy)
                    Text("(student.grade) · (student.className)").font(.subheadline).foregroundStyle(.secondary)
                    Text("性别：(student.gender) · 年龄参考：(student.bodyAssessmentAgeLabel)").font(.subheadline).foregroundStyle(.secondary)
                    Text("如资料有误，请先在家庭账户中联系学校更正。年龄别 BMI 只使用孩子资料中的出生日期和本次测量日期计算。")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            primaryButton("填写身高体重", icon: "arrow.right") { move(to: .bmi) }
        }
    }

    private var environmentStep: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("拍摄环境检查").font(.title3.bold()).foregroundStyle(ReferenceColor.navy)
            Text("拍摄前请确认环境安全，系统会在相机打开后继续检查光线、距离、遮挡和多人入镜。")
                .font(.subheadline).foregroundStyle(.secondary)
            readinessToggle("光线充足，地面平整，孩子可以完整入镜。", isOn: $spaceReady)
            ReferenceCard { VStack(alignment: .leading, spacing: 7) {
                checklist("镜头距离约 2–3 米，手机保持稳定")
                checklist("画面中只出现一名孩子")
                checklist("穿着便于观察肩、髋和膝部位的衣物")
            } }
            primaryButton(spaceReady ? "打开摄像头测评" : "请完成环境确认", icon: "camera.fill") { move(to: .capture) }
                .opacity(spaceReady ? 1 : 0.55)
                .disabled(!spaceReady)
        }
    }

    private func bmiEntry(_ student: Student) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("身高体重").font(.title3.bold()).foregroundStyle(ReferenceColor.navy)
            Text("请填写本次实际测量值。BMI 公式为体重(kg) ÷ 身高²(m²)，不以固定年龄作为录入条件；孩子资料已有出生日期时，报告会额外给出 \(student.bodyAssessmentAgeLabel)的年龄别筛查参考。")
                .font(.subheadline).foregroundStyle(.secondary)
            Label("为避免相机成像缩放差异，身高和体重请按身高仪、体重秤的实际读数填写；相机仅用于姿态与步态观察。", systemImage: "ruler.fill")
                .font(.caption).foregroundStyle(ReferenceColor.navy)
                .padding(12).background(ReferenceColor.blue.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
            ruler(title: "身高", value: $height, range: 90...190, unit: "cm", step: 0.5)
            ruler(title: "体重", value: $weight, range: 15...90, unit: "kg", step: 0.1)
            VStack(alignment: .leading, spacing: 5) {
                Text("遗传靶身高参考（选填）").font(.headline).foregroundStyle(ReferenceColor.navy)
                Text("男孩＝（父亲身高＋母亲身高＋13 cm）÷ 2；女孩＝（父亲身高＋母亲身高−13 cm）÷ 2。区间按中位值 ±5 cm 展示，仅作健康管理参考，不代表成年身高预测。")
                    .font(.caption).foregroundStyle(.secondary)
            }
            ruler(title: "父亲身高", value: $fatherHeight, range: 120...230, unit: "cm", step: 0.5)
            ruler(title: "母亲身高", value: $motherHeight, range: 120...230, unit: "cm", step: 0.5)
            ReferenceCard {
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        VStack(alignment: .leading, spacing: 4) { Text("当前 BMI").font(.caption).foregroundStyle(.secondary); Text(height > 0 && weight > 0 ? String(format: "%.1f", provisionalRecord.bmi) : "待填写").font(.system(size: 32, weight: .bold)).foregroundStyle(bodyCoral) }
                        Spacer()
                        VStack(alignment: .trailing, spacing: 5) { attentionBadge(provisionalBMILevel, label: provisionalRecord.bmiScreeningLabel(ageMonths: student.bodyAssessmentAgeMonths, gender: student.gender)); Text("儿童年龄别 BMI 标准").font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.trailing) }
                    }
                    if let geneticHeight = provisionalRecord.geneticHeightReference(gender: student.gender) {
                        Divider()
                        let range = provisionalRecord.geneticHeightRange(gender: student.gender)
                        let rangeText = range.map { String(format: " · 区间 %.1f–%.1f cm", $0.lowerBound, $0.upperBound) } ?? ""
                        let predictedText = "遗传靶身高中位 " + String(format: "%.1f", geneticHeight) + " cm" + rangeText
                        Text(predictedText + " · " + provisionalRecord.geneticHeightFormula(gender: student.gender))
                            .font(.caption).foregroundStyle(ReferenceColor.navy)
                    }
                    if let heightAssessment = provisionalRecord.heightDevelopmentAssessment(ageMonths: student.bodyAssessmentAgeMonths, gender: student.gender) {
                        Text("当前身高发育：\(heightAssessment.level.label) · \(heightAssessment.ageYears)岁参考中位 \(String(format: "%.1f", heightAssessment.median)) cm · 儿童身高参考标准")
                            .font(.caption).foregroundStyle(ReferenceColor.navy)
                    }
                }
            }
            primaryButton(hasValidCoreMeasurements ? "继续拍摄记录" : "请填写有效身高和体重", icon: "camera.fill") { move(to: .capture) }
                .opacity(hasValidCoreMeasurements ? 1 : 0.55)
                .disabled(!hasValidCoreMeasurements)
        }
    }

    private var captureGuide: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("拍摄引导").font(.title3.bold()).foregroundStyle(ReferenceColor.navy)
            Text("逐项打开 App 内相机，支持前后摄像头切换和语音引导。画面仅用于本次观察，不会保存为照片或视频。")
                .font(.subheadline).foregroundStyle(.secondary)
            ForEach(BodyAssessmentRecord.CaptureTask.allCases) { task in
                Button { activeCameraTask = task } label: {
                    HStack(spacing: 13) {
                        Image(systemName: task == .gaitVideo ? "video.fill" : "viewfinder").font(.title3).foregroundStyle(completedCaptures.contains(task) ? ReferenceColor.green : bodyCoral).frame(width: 42, height: 42).background((completedCaptures.contains(task) ? ReferenceColor.green : bodyCoral).opacity(0.12), in: RoundedRectangle(cornerRadius: 12))
                        VStack(alignment: .leading, spacing: 4) { Text(task.title).font(.headline).foregroundStyle(ReferenceColor.navy); Text(task.instruction).font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.leading); if let feedback = captureFeedback[task] { Text(feedback).font(.caption).foregroundStyle(completedCaptures.contains(task) ? ReferenceColor.green : .orange) } }
                        Spacer()
                        Image(systemName: completedCaptures.contains(task) ? "checkmark.seal.fill" : "camera.fill").foregroundStyle(completedCaptures.contains(task) ? ReferenceColor.green : ReferenceColor.blue)
                    }
                    .padding(13).background(.white, in: RoundedRectangle(cornerRadius: 16)).overlay(RoundedRectangle(cornerRadius: 16).stroke(completedCaptures.contains(task) ? ReferenceColor.green.opacity(0.35) : ReferenceColor.blue.opacity(0.12), lineWidth: 1))
                }.buttonStyle(.plain).accessibilityLabel("\(task.title)，\(completedCaptures.contains(task) ? "已完成" : "打开相机")")
            }
            Text("App 会实时校验画面清晰度与身体入镜完整性；如有提示不通过，请按语音提示调整距离、光线和站位后重试。")
                .font(.caption).foregroundStyle(.secondary)
            primaryButton(completedCaptures.count == BodyAssessmentRecord.CaptureTask.allCases.count ? "继续补充安全信息" : "请完成全部拍摄", icon: "arrow.right") { move(to: .confirm) }
                .opacity(completedCaptures.count == BodyAssessmentRecord.CaptureTask.allCases.count ? 1 : 0.55)
                .disabled(completedCaptures.count != BodyAssessmentRecord.CaptureTask.allCases.count)
        }
    }

    private var observationConfirm: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("质量确认与安全信息").font(.title3.bold()).foregroundStyle(ReferenceColor.navy)
            Text("请确认每项拍摄均清晰、身体完整入镜且没有多人或遮挡；家长再补充疼痛、不适或活动受限等安全信息。")
                .font(.subheadline).foregroundStyle(.secondary)
            if !visualHints.isEmpty {
                ReferenceCard {
                    VStack(alignment: .leading, spacing: 7) {
                        Text("本次画面提示").font(.caption.weight(.bold)).foregroundStyle(.orange)
                        ForEach(visualHints.keys.sorted { $0.rawValue < $1.rawValue }, id: \.self) { task in
                            if let hint = visualHints[task] {
                                Label("\(task.title)：\(hint)", systemImage: "viewfinder.circle.fill")
                                    .font(.caption)
                                    .foregroundStyle(.orange)
                            }
                        }
                    }
                }
            }
            confirmationToggle(title: "孩子近期有肩背、腰背或坐姿疼痛/不适", detail: "作为安全提示展示给家长，不会替代测评结论。", value: $asymmetric)
            confirmationToggle(title: "孩子近期有行走困难、跛行或活动受限", detail: "如持续存在，请优先咨询专业人员。", value: $gaitConcern)
            ReferenceCard { HStack(alignment: .top, spacing: 10) { Image(systemName: "info.circle.fill").foregroundStyle(ReferenceColor.blue); Text("本页为家庭健康观察，不构成脊柱侧弯、步态或其他医学诊断。出现疼痛、麻木、无力或进行性变化时，请及时就医。") .font(.caption).foregroundStyle(.secondary) } }
            primaryButton("生成家庭观察结果", icon: "checkmark.circle.fill") {
                guard let student else { return }
                state.saveBodyAssessment(provisionalRecord, for: student)
                move(to: .result)
            }
        }
    }

    private func result(_ student: Student) -> some View {
        let activeRecord = record ?? provisionalRecord
        let level = activeRecord.attention(ageMonths: student.bodyAssessmentAgeMonths, gender: student.gender)
        return VStack(alignment: .leading, spacing: 14) {
            HStack { VStack(alignment: .leading, spacing: 5) { Text("\(student.name) 的家庭观察").font(.title3.bold()).foregroundStyle(ReferenceColor.navy); Text("\(dateText(activeRecord.measuredAt)) · 儿童年龄别参考").font(.caption).foregroundStyle(.secondary) }; Spacer(); attentionBadge(level) }
            bodySyncStatus(for: student)
            ReferenceCard {
                VStack(alignment: .leading, spacing: 10) {
                    HStack { Text(String(format: "BMI %.1f", activeRecord.bmi)).font(.title2.bold()).foregroundStyle(bodyCoral); Spacer(); Text("\(String(format: "%.1f", activeRecord.heightCentimeters)) cm · \(String(format: "%.1f", activeRecord.weightKilograms)) kg").font(.caption).foregroundStyle(.secondary) }
                    if let geneticHeight = activeRecord.geneticHeightReference(gender: student.gender) {
                        let range = activeRecord.geneticHeightRange(gender: student.gender)
                        let rangeText = range.map { String(format: " · 区间 %.1f–%.1f cm", $0.lowerBound, $0.upperBound) } ?? ""
                        let predictedText = "遗传靶身高中位：" + String(format: "%.1f", geneticHeight) + " cm" + rangeText
                        Text(predictedText + "（" + activeRecord.geneticHeightFormula(gender: student.gender) + "）")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    if let heightAssessment = activeRecord.heightDevelopmentAssessment(ageMonths: student.bodyAssessmentAgeMonths, gender: student.gender) {
                        Text("当前身高发育：\(heightAssessment.level.label) · \(heightAssessment.ageYears)岁参考中位 \(String(format: "%.1f", heightAssessment.median)) cm")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    bmiTrend(history: state.bodyAssessmentHistory(for: student), fallback: activeRecord)
                }
            }
            if let report = activeRecord.postureReport {
                postureReportCard(report)
            }
            ForEach(activeRecord.observations(ageMonths: student.bodyAssessmentAgeMonths, gender: student.gender)) { item in
                HStack(spacing: 12) { Image(systemName: icon(for: item.level)).foregroundStyle(color(for: item.level)).frame(width: 24); VStack(alignment: .leading, spacing: 3) { Text(item.title).font(.subheadline.bold()).foregroundStyle(ReferenceColor.navy); Text(item.detail).font(.caption).foregroundStyle(.secondary) }; Spacer(); attentionBadge(item.level) }
                    .padding(12).background(.white, in: RoundedRectangle(cornerRadius: 14))
            }
            ReferenceCard { HStack { Image(systemName: "calendar.badge.clock").foregroundStyle(bodyCoral); VStack(alignment: .leading) { Text("下次建议复测").font(.subheadline.bold()); Text(dateText(activeRecord.nextFollowUpDate)).font(.caption).foregroundStyle(.secondary) }; Spacer() } }
            primaryButton("开始 28 天健康计划", icon: "figure.walk") { move(to: .plan) }
            Button("查看推荐课程") { router.push(.parentCourses) }.frame(maxWidth: .infinity).buttonStyle(.bordered).tint(ReferenceColor.blue)
        }
    }

    private func postureReportCard(_ report: PostureAssessmentReport) -> some View {
        VStack(alignment: .leading, spacing: 11) {
            HStack {
                Label("人体姿态测评报告", systemImage: "figure.stand.line.dotted.figure.stand")
                    .font(.headline).foregroundStyle(ReferenceColor.navy)
                Spacer()
                attentionBadge(report.overallLevel)
            }
            Text("本次观察 · \(report.snapshots.values.map(\.sampleCount).reduce(0, +)) 条记录")
                .font(.caption).foregroundStyle(.secondary)
            ForEach(BodyAssessmentRecord.CaptureTask.allCases) { task in
                if let snapshot = report.snapshots[task] {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text(task.title).font(.subheadline.bold()).foregroundStyle(ReferenceColor.navy)
                            Spacer()
                            Text(String(format: "记录稳定度 %.0f%% · %d 条", snapshot.confidence * 100, snapshot.sampleCount))
                                .font(.caption).foregroundStyle(snapshot.confidence >= PostureScreeningRules.minimumConfidence && snapshot.sampleCount >= PostureScreeningRules.minimumSamples ? ReferenceColor.green : bodyCoral)
                        }
                        Text(postureMetricSummary(snapshot))
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    .padding(9)
                    .background(ReferenceColor.canvas, in: RoundedRectangle(cornerRadius: 10))
                }
            }
            ForEach(report.reasons, id: \.self) { reason in
                HStack(alignment: .top, spacing: 7) {
                    Image(systemName: "waveform.path.ecg").foregroundStyle(ReferenceColor.blue)
                    Text(reason).font(.caption).foregroundStyle(ReferenceColor.navy)
                }
            }
            Text(report.disclaimer)
                .font(.caption).foregroundStyle(.secondary)
                .padding(10).background(ReferenceColor.blue.opacity(0.07), in: RoundedRectangle(cornerRadius: 10))
            if report.overallLevel == .pending {
                Button {
                    step = .capture
                } label: {
                    Label("重新记录稳定度不足的项目", systemImage: "arrow.clockwise.camera")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(ReferenceColor.blue)
            }
        }
        .padding(14)
        .background(.white, in: RoundedRectangle(cornerRadius: 16))
    }

    private func postureMetricSummary(_ snapshot: PostureMetricSnapshot) -> String {
        var values: [String] = []
        if let value = snapshot.shoulderHeightDifferenceCm { values.append(String(format: "双肩差 %.1f cm", value)) }
        if let value = snapshot.pelvicHeightDifferenceCm { values.append(String(format: "骨盆差 %.1f cm", value)) }
        if let value = snapshot.spinalMidlineDeviationCm { values.append(String(format: "中线偏移 %.1f cm", value)) }
        if let value = snapshot.cameraProxyAtrDegrees { values.append(String(format: "旋转代理 %.1f°", value)) }
        if let value = snapshot.gaitTrunkSwayCm { values.append(String(format: "步态摆动 %.1f cm", value)) }
        return values.isEmpty ? "指标尚未完整，请重新拍摄" : values.joined(separator: " · ")
    }

    @ViewBuilder private func bodySyncStatus(for student: Student) -> some View {
        if state.repository.supportsRemoteAcknowledgement,
           let status = state.localFeatures.bodyAssessmentSyncStates[student.id] {
            let presentation = bodySyncPresentation(for: status)
            Label(presentation.message, systemImage: presentation.icon)
                .font(.caption)
                .foregroundStyle(presentation.tint)
                .padding(11)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(presentation.tint.opacity(0.09), in: RoundedRectangle(cornerRadius: 12))
        }
    }

    private struct BodySyncPresentation {
        let message: String
        let tint: Color
        let icon: String
    }

    private func bodySyncPresentation(for status: LocalSubmissionStatus) -> BodySyncPresentation {
        switch status {
        case .pendingSync: return BodySyncPresentation(message: "测评结果已保存，联网后自动同步。", tint: .orange, icon: "clock.arrow.circlepath")
        case .submitting: return BodySyncPresentation(message: "正在同步到孩子健康档案…", tint: ReferenceColor.blue, icon: "arrow.triangle.2.circlepath")
        case .submitted: return BodySyncPresentation(message: "已同步到孩子健康档案。", tint: ReferenceColor.green, icon: "checkmark.shield.fill")
        case .failed: return BodySyncPresentation(message: "同步失败，结果仍已保存。请稍后重试。", tint: .red, icon: "exclamationmark.triangle.fill")
        case .draft: return BodySyncPresentation(message: "测评结果尚未完成保存。", tint: .secondary, icon: "doc.text")
        }
    }

    private func plan(_ student: Student) -> some View {
        let activeRecord = record ?? provisionalRecord
        let days = (0..<28).map { BusinessClock.addingDays($0, to: BusinessClock.startOfDay()) }
        return VStack(alignment: .leading, spacing: 14) {
            Text("28 天轻量姿态与健康习惯计划").font(.title3.bold()).foregroundStyle(ReferenceColor.navy)
            Text("每天 10 分钟：站姿觉察、肩背活动、平衡行走与规律作息。完成后可随时修改。") .font(.subheadline).foregroundStyle(.secondary)
            ReferenceCard { HStack { VStack(alignment: .leading) { Text("已完成 \(activeRecord.completedPlanDays.count) / 28 天").font(.headline); Text("计划进度已保存，联网后自动同步提醒。") .font(.caption).foregroundStyle(.secondary) }; Spacer(); Image(systemName: "chart.line.uptrend.xyaxis").font(.title2).foregroundStyle(ReferenceColor.green) } }
            Button {
                let today = BusinessClock.startOfDay()
                followAlongDate = today
                followAlongDayIndex = (BusinessClock.calendar.component(.weekday, from: today) + 5) % 7
                showFollowAlong = true
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: "play.circle.fill").font(.title2).foregroundStyle(.white)
                    VStack(alignment: .leading, spacing: 3) {
                        Text("开始今日训练跟练").font(.headline).foregroundStyle(.white)
                        Text("示范视频 + 可选我的画面 + 语音动作提示").font(.caption).foregroundStyle(.white.opacity(0.86))
                    }
                    Spacer()
                    Image(systemName: "chevron.right").foregroundStyle(.white)
                }
                .padding(15)
                .background(LinearGradient(colors: [ReferenceColor.blue, ReferenceColor.green], startPoint: .leading, endPoint: .trailing), in: RoundedRectangle(cornerRadius: 17))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("开始今日 训练跟练")
            ForEach(Array(days.enumerated()), id: \.offset) { index, day in
                let key = dayKey(day)
                let done = activeRecord.completedPlanDays.contains(key)
                Button {
                    if done {
                        state.toggleBodyPlanDay(day, for: student)
                    } else {
                        followAlongDayIndex = index % 7
                        followAlongDate = day
                        showFollowAlong = true
                    }
                } label: {
                    HStack { Image(systemName: done ? "checkmark.circle.fill" : "circle").foregroundStyle(done ? ReferenceColor.green : .secondary); VStack(alignment: .leading) { Text("第 \(index + 1) 天 · \(weekday(day))").font(.subheadline.bold()).foregroundStyle(ReferenceColor.navy); Text(planText(for: index % 7)).font(.caption).foregroundStyle(.secondary) }; Spacer(); Text(done ? "已完成" : "去完成").font(.caption.weight(.semibold)).foregroundStyle(done ? ReferenceColor.green : ReferenceColor.blue) }
                    .padding(13).background(.white, in: RoundedRectangle(cornerRadius: 14))
                }.buttonStyle(.plain)
            }
            Button("返回孩子健康档案") { router.push(.healthProfile) }.frame(maxWidth: .infinity).buttonStyle(.bordered).tint(ReferenceColor.blue)
        }
    }

    private func load(record: BodyAssessmentRecord?, draft: BodyAssessmentDraft?) {
        guard !didLoad else { return }; didLoad = true
        if let draft {
            let restoredStep: Int
            // Drafts written before the nine-step flow used 1=BMI, 2=capture,
            // 3=confirmation. Migrate only drafts that contain the old
            // measurement/capture payload; a new empty step 1/2 draft remains
            // on consent/profile.
            if !draft.guardianReady && !draft.consentAcknowledged && !draft.environmentReady {
                switch draft.step {
                case 1 where draft.heightCentimeters > 0 || draft.weightKilograms > 0: restoredStep = 3
                case 2 where !draft.completedCaptures.isEmpty: restoredStep = 5
                case 3 where !draft.completedCaptures.isEmpty: restoredStep = 6
                default: restoredStep = draft.step
                }
            } else { restoredStep = draft.step }
            step = Step(rawValue: min(max(restoredStep, 0), Step.confirm.rawValue)) ?? .overview
            adultReady = draft.guardianReady
            consentAcknowledged = draft.consentAcknowledged
            spaceReady = draft.environmentReady
            height = draft.heightCentimeters; weight = draft.weightKilograms; completedCaptures = draft.completedCaptures
            fatherHeight = draft.fatherHeightCentimeters ?? fatherHeight; motherHeight = draft.motherHeightCentimeters ?? motherHeight
            asymmetric = draft.parentMarkedAsymmetric; gaitConcern = draft.parentMarkedGaitConcern
            visualHints = draft.captureObservationHints
            postureSnapshots = draft.postureSnapshots
            if visualHints.isEmpty, let hint = draft.visualObservationHint, let task = draft.completedCaptures.first { visualHints[task] = hint }
            return
        }
        guard let record else { return }
        // Keep parity with Android and treat a completed record as a reusable
        // health archive. A fresh entry from Health Profile should open the
        // saved result; only a draft resumes the multi-step input flow.
        viewingSavedRecord = true
        step = .result
        height = record.heightCentimeters; weight = record.weightKilograms; completedCaptures = record.completedCaptures
        fatherHeight = record.fatherHeightCentimeters ?? fatherHeight; motherHeight = record.motherHeightCentimeters ?? motherHeight
        asymmetric = record.parentMarkedAsymmetric; gaitConcern = record.parentMarkedGaitConcern
        visualHints = record.captureObservationHints
        postureSnapshots = record.postureReport?.snapshots ?? [:]
        if visualHints.isEmpty, let hint = record.visualObservationHint, let task = record.completedCaptures.first { visualHints[task] = hint }
    }
    private func persistDraft() {
        guard let student, step.rawValue <= Step.confirm.rawValue else { return }
        state.saveBodyAssessmentDraft(BodyAssessmentDraft(step: step.rawValue, guardianReady: adultReady, consentAcknowledged: consentAcknowledged, environmentReady: spaceReady, heightCentimeters: height, weightKilograms: weight, completedCaptures: completedCaptures, parentMarkedAsymmetric: asymmetric, parentMarkedGaitConcern: gaitConcern, visualObservationHint: visualSummary, captureObservationHints: visualHints, fatherHeightCentimeters: fatherHeight, motherHeightCentimeters: motherHeight, postureSnapshots: postureSnapshots), for: student)
    }
    private func goBack() {
        if viewingSavedRecord, step == .result {
            router.pop()
            return
        }
        guard let previous = Step(rawValue: step.rawValue - 1) else {
            router.pop()
            return
        }
        move(to: previous)
    }
    private func move(to next: Step) {
        if next == .profile, let student { state.recordHealthConsent(studentID: student.id) }
        if reduceMotion { var transaction = Transaction(); transaction.animation = nil; withTransaction(transaction) { step = next } } else { withAnimation(.easeInOut(duration: 0.22)) { step = next } }; persistDraft()
    }
    private func ruler(title: String, value: Binding<Double>, range: ClosedRange<Double>, unit: String, step: Double) -> some View {
        let textValue = Binding<String>(
            get: { value.wrappedValue > 0 ? String(format: "%.1f", value.wrappedValue) : "" },
            set: { raw in
                let normalized = raw.replacingOccurrences(of: ",", with: ".")
                guard !normalized.isEmpty else { value.wrappedValue = 0; return }
                guard let number = Double(normalized) else { return }
                value.wrappedValue = BodyMeasurementInput.normalized(number, range: range, step: step)
            }
        )
        return VStack(alignment: .leading, spacing: 11) {
            HStack(alignment: .center) {
                Text(title).font(.headline).foregroundStyle(ReferenceColor.navy)
                Spacer()
                HStack(spacing: 4) {
                    Button { value.wrappedValue = BodyMeasurementInput.normalized((value.wrappedValue > 0 ? value.wrappedValue : range.lowerBound) - step, range: range, step: step) } label: {
                        Image(systemName: "minus").font(.caption.bold()).frame(width: 28, height: 28)
                    }.buttonStyle(.bordered).tint(bodyCoral).accessibilityLabel("\(title)减少")
                    TextField("输入", text: textValue)
                        .keyboardType(.decimalPad).multilineTextAlignment(.trailing)
                        .font(.title3.bold()).foregroundStyle(bodyCoral)
                        .frame(width: 72).accessibilityLabel("\(title)数值")
                    Text(unit).font(.subheadline.weight(.semibold)).foregroundStyle(bodyCoral)
                    Button { value.wrappedValue = BodyMeasurementInput.normalized((value.wrappedValue > 0 ? value.wrappedValue : range.lowerBound) + step, range: range, step: step) } label: {
                        Image(systemName: "plus").font(.caption.bold()).frame(width: 28, height: 28)
                    }.buttonStyle(.bordered).tint(bodyCoral).accessibilityLabel("\(title)增加")
                }
            }
            Slider(value: Binding(get: { value.wrappedValue > 0 ? value.wrappedValue : range.lowerBound }, set: { value.wrappedValue = BodyMeasurementInput.normalized($0, range: range, step: step) }), in: range, step: step).tint(bodyCoral)
            HStack(spacing: 0) {
                ForEach(0..<17, id: \.self) { _ in Rectangle().fill(bodyCoral.opacity(0.22)).frame(width: 1, height: 7); Spacer(minLength: 0) }
            }.padding(.horizontal, 4)
            HStack { Text(String(format: "%.0f", range.lowerBound)); Spacer(); Text("滑动 / 输入 / 微调"); Spacer(); Text(String(format: "%.0f", range.upperBound)) }.font(.caption).foregroundStyle(.secondary)
        }
        .padding(14).background(.white, in: RoundedRectangle(cornerRadius: 16))
    }
    private func overviewPill(_ title: String, _ icon: String) -> some View { Label(title, systemImage: icon).font(.caption.weight(.medium)).foregroundStyle(ReferenceColor.navy).padding(.horizontal, 8).padding(.vertical, 6).background(.white.opacity(0.72), in: Capsule()) }
    private func checklist(_ text: String) -> some View { Label(text, systemImage: "checkmark.circle.fill").font(.caption).foregroundStyle(.secondary).labelStyle(.titleAndIcon) }
    private func readinessToggle(_ text: String, isOn: Binding<Bool>) -> some View { Toggle(isOn: isOn) { Text(text).font(.caption).foregroundStyle(ReferenceColor.navy) }.tint(ReferenceColor.green) }
    private func confirmationToggle(title: String, detail: String, value: Binding<Bool>) -> some View { Toggle(isOn: value) { VStack(alignment: .leading, spacing: 4) { Text(title).font(.subheadline.bold()).foregroundStyle(ReferenceColor.navy); Text(detail).font(.caption).foregroundStyle(.secondary) } }.tint(bodyCoral).padding(14).background(.white, in: RoundedRectangle(cornerRadius: 16)) }
    private func attentionBadge(_ level: BodyAssessmentRecord.AttentionLevel, label: String? = nil) -> some View { Text(label ?? level.label).font(.caption.weight(.bold)).foregroundStyle(color(for: level)).padding(.horizontal, 8).padding(.vertical, 5).background(color(for: level).opacity(0.12), in: Capsule()) }
    private func color(for level: BodyAssessmentRecord.AttentionLevel) -> Color { switch level { case .pending: ReferenceColor.blue; case .green: ReferenceColor.green; case .yellow: .orange; case .red: .red; case .unavailable: .secondary } }
    private func icon(for level: BodyAssessmentRecord.AttentionLevel) -> String { switch level { case .pending: "camera.viewfinder"; case .green: "checkmark.shield.fill"; case .yellow: "exclamationmark.triangle.fill"; case .red: "exclamationmark.shield.fill"; case .unavailable: "calendar.badge.exclamationmark" } }
    private func primaryButton(_ title: String, icon: String, action: @escaping () -> Void) -> some View { Button(action: action) { Label(title, systemImage: icon).font(.headline).frame(maxWidth: .infinity).padding(.vertical, 14).background(bodyCoral, in: Capsule()).foregroundStyle(.white) }.buttonStyle(.plain) }
    private func bmiTrend(history: [BodyAssessmentRecord], fallback: BodyAssessmentRecord) -> some View { VStack(alignment: .leading, spacing: 7) { Text("BMI 趋势").font(.caption.weight(.semibold)).foregroundStyle(.secondary); if history.count < 2 { Text("完成下一次实测后，将显示真实趋势；不会虚构历史或目标数据。") .font(.caption).foregroundStyle(.secondary) } else { let values = Array(history.suffix(3)); HStack(alignment: .bottom, spacing: 10) { ForEach(Array(values.enumerated()), id: \.offset) { index, item in trendBar(index == values.count - 1 ? "本次" : dateText(item.measuredAt), item.bmi, values.map(\.bmi).max() ?? fallback.bmi) } } } } }
    private func trendBar(_ label: String, _ value: Double, _ maxValue: Double) -> some View { VStack(spacing: 4) { Text(String(format: "%.1f", value)).font(.caption.bold()).foregroundStyle(ReferenceColor.navy); Capsule().fill(bodyCoral.opacity(0.18)).frame(width: 48, height: 44).overlay(alignment: .bottom) { Capsule().fill(label == "本次" ? bodyCoral : ReferenceColor.blue).frame(width: 48, height: max(10, 44 * value / max(maxValue, 1))) }; Text(label).font(.caption).foregroundStyle(.secondary) } }
    private func dateText(_ date: Date) -> String { Self.dateFormatter.string(from: date) }
    private func dayKey(_ date: Date) -> String { Self.dayFormatter.string(from: date) }
    private func weekday(_ date: Date) -> String { Self.weekdayFormatter.string(from: date) }
    private func planText(for index: Int) -> String {
        let day = FollowAlongPlan.day(at: index)
        guard !day.exercises.isEmpty else { return "恢复日：轻松呼吸、肩背舒展与户外散步" }
        return day.exercises.map { "\($0.title) \($0.target)\($0.unit)" }.joined(separator: " + ")
    }
    private static let dateFormatter: DateFormatter = { let f = DateFormatter(); f.calendar = BusinessClock.calendar; f.locale = Locale(identifier: "zh_CN"); f.timeZone = BusinessClock.timeZone; f.dateFormat = "yyyy年M月d日"; return f }()
    private static let dayFormatter: DateFormatter = { let f = DateFormatter(); f.calendar = BusinessClock.calendar; f.locale = Locale(identifier: "zh_CN"); f.timeZone = BusinessClock.timeZone; f.dateFormat = "yyyy-MM-dd"; return f }()
    private static let weekdayFormatter: DateFormatter = { let f = DateFormatter(); f.calendar = BusinessClock.calendar; f.locale = Locale(identifier: "zh_CN"); f.timeZone = BusinessClock.timeZone; f.dateFormat = "EEEE"; return f }()
    private let bodyCoral = Color(red: 0.96, green: 0.48, blue: 0.35)
    private let bodyCream = Color(red: 1.0, green: 0.94, blue: 0.80)
}

struct CaptureReview {
    let accepted: Bool
    let message: String
    let observationHint: String?
    let postureSnapshot: PostureMetricSnapshot?

    init(accepted: Bool, message: String, observationHint: String? = nil, postureSnapshot: PostureMetricSnapshot? = nil) {
        self.accepted = accepted
        self.message = message
        self.observationHint = observationHint
        self.postureSnapshot = postureSnapshot
    }
}
