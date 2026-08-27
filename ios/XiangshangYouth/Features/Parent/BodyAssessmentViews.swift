import SwiftUI

/// The family-side assessment intentionally stores only the parent's confirmed
/// observations and completed tasks. Real-time capture is processed in the
/// App and does not retain photos or videos at this stage.
struct BodyAssessmentView: View {
    enum Step: Int, CaseIterable { case overview, consent, profile, bmi, environment, capture, confirm, result, plan }
    private let assessmentSteps = ["使用说明", "监护人授权", "孩子身体信息", "身高体重和BMI", "拍摄环境检查", "摄像头测评", "质量确认", "结果报告", "训练计划"]

    @EnvironmentObject var state: AppState
    @EnvironmentObject var router: AppRouter
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State var step: Step = .overview
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
    @State var showFollowAlong = false
    @State var followAlongDayIndex = 0
    @State var followAlongDate = Date()
    @State private var parentsExpanded = false
    @State var showsAllPlanDays = false
    /// Viewing a saved family observation is read-only navigation context. Its
    /// back action must leave the feature, not expose the old confirmation
    /// form where a finished record could be accidentally re-submitted.
    @State private var viewingSavedRecord = false

    private var student: Student? { state.selectedChild }
    private var visualSummary: String? {
        let summary = visualHints.keys.sorted { $0.rawValue < $1.rawValue }.compactMap { visualHints[$0] }.joined(separator: "\n")
        return summary.isEmpty ? nil : summary
    }
    var provisionalRecord: BodyAssessmentRecord {
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
    var record: BodyAssessmentRecord? { student.flatMap(state.bodyAssessment(for:)) }

    var body: some View {
        Group {
            if let student {
                AppScaffold(title: stepTitle, onBack: goBack, scrollResetID: step.rawValue) {
                    VStack(spacing: AppTheme.sectionSpacing) {
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
                    .padding(.top, AppTheme.cardSpacing)
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
        AssessmentProgressHeader(titles: assessmentSteps, currentIndex: displayStepIndex)
    }

    private func overview(_ student: Student) -> some View {
        VStack(spacing: AppTheme.cardSpacing) {
            AssessmentHeroCard(
                icon: "figure.walk.motion",
                eyebrow: "为 \(student.name) 准备",
                title: "约 5 分钟完成身体测评",
                detail: "记录身高、体重与四项姿态动作，形成家庭健康观察和训练建议。"
            ) {
                HStack(spacing: 8) {
                    AssessmentFactChip(icon: "clock.fill", title: "约 5 分钟")
                    AssessmentFactChip(icon: "camera.fill", title: "端内识别")
                    AssessmentFactChip(icon: "lock.shield.fill", title: "不存原片")
                }
            }

            if let record {
                ReferenceCard {
                    VStack(alignment: .leading, spacing: 12) {
                        ReferenceSectionTitle(title: "最近一次记录", trailing: dateText(record.measuredAt))
                        HStack(alignment: .center) {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(String(format: "%.1f", record.bmi))
                                    .font(.system(size: 30, weight: .bold))
                                    .foregroundStyle(ReferenceColor.blue)
                                Text("BMI")
                                    .font(.system(size: AppTheme.captionSize, weight: .semibold))
                                    .foregroundStyle(AppTheme.muted)
                            }
                            Spacer()
                            VStack(alignment: .trailing, spacing: 7) {
                                attentionBadge(record.attention(ageMonths: student.bodyAssessmentAgeMonths, gender: student.gender))
                                Text("已完成 \(record.completedCaptures.count) / \(BodyAssessmentRecord.CaptureTask.allCases.count) 项采集")
                                    .font(.system(size: AppTheme.captionSize))
                                    .foregroundStyle(AppTheme.muted)
                            }
                        }
                        Text("测评于 \(dateText(record.measuredAt)) · 已完成 \(record.completedCaptures.count) 项拍摄任务")
                            .font(.system(size: AppTheme.captionSize)).foregroundStyle(AppTheme.muted)
                        Button { viewingSavedRecord = true; move(to: .result) } label: {
                            Label("查看结果与计划", systemImage: "chevron.right")
                                .font(.system(size: AppTheme.secondarySize, weight: .semibold))
                                .frame(maxWidth: .infinity, minHeight: AppTheme.minimumTapSize)
                        }
                        .buttonStyle(.bordered)
                        .tint(ReferenceColor.blue)
                    }
                }
            }

            ReferenceCard {
                VStack(alignment: .leading, spacing: 14) {
                    ReferenceSectionTitle(title: "测评流程", trailing: "共 9 步")
                    AssessmentPhaseRow(number: 1, title: "准备资料", detail: "阅读说明、完成监护授权并确认孩子信息", icon: "checklist")
                    Divider()
                    AssessmentPhaseRow(number: 2, title: "填写与采集", detail: "录入身高体重，检查环境并完成四项动作", icon: "camera.viewfinder")
                    Divider()
                    AssessmentPhaseRow(number: 3, title: "查看建议", detail: "确认质量，查看结果并开始训练计划", icon: "chart.bar.doc.horizontal")
                }
            }
            AssessmentInfoBanner(
                icon: "cross.case.fill",
                title: "家庭运动健康观察",
                detail: "结果用于运动建议，不替代医疗诊断。如孩子有疼痛、麻木或活动受限，请先咨询专业人员。",
                tint: ReferenceColor.green
            )
            AssessmentPrimaryAction(title: record == nil ? "开始身体测评" : "开始新的测评", icon: "arrow.right") {
                viewingSavedRecord = false
                move(to: .consent)
            }
        }
    }

    private var consentStep: some View {
        VStack(alignment: .leading, spacing: AppTheme.cardSpacing) {
            AssessmentHeroCard(
                icon: "lock.shield.fill",
                eyebrow: "隐私与安全",
                title: "由监护人陪同完成",
                detail: "相机画面只在手机内实时处理，不保存照片、视频或原始帧。"
            ) {
                AssessmentFactChip(icon: "checkmark.shield.fill", title: "仅保存结构化测量结果")
            }

            ReferenceCard {
                VStack(alignment: .leading, spacing: 14) {
                    ReferenceSectionTitle(title: "需要你的确认", trailing: adultReady && consentAcknowledged ? "已完成" : "2 项")
                    readinessToggle(
                        title: "监护关系确认",
                        detail: "我是孩子的监护人，并将在测评过程中全程陪同。",
                        icon: "person.badge.shield.checkmark",
                        isOn: $adultReady
                    )
                    Divider()
                    readinessToggle(
                        title: "摄像头与算法说明",
                        detail: "我已了解数据用途、保留范围和撤回授权方式。",
                        icon: "camera.metering.center.weighted",
                        isOn: $consentAcknowledged
                    )
                }
            }

            AssessmentInfoBanner(
                icon: "heart.text.square.fill",
                title: "用途说明",
                detail: "身体测评仅用于家庭运动健康筛查和训练建议，不构成疾病诊断。",
                tint: ReferenceColor.green
            )
            AssessmentPrimaryAction(
                title: adultReady && consentAcknowledged ? "继续确认孩子资料" : "请完成两项确认",
                icon: "arrow.right",
                enabled: adultReady && consentAcknowledged
            ) { move(to: .profile) }
        }
    }

    private func profileStep(_ student: Student) -> some View {
        VStack(alignment: .leading, spacing: AppTheme.cardSpacing) {
            AssessmentInfoBanner(
                icon: "person.text.rectangle.fill",
                title: "确认测评对象",
                detail: "BMI 年龄参考会使用孩子档案中的出生日期、性别和本次测量日期。"
            )
            ReferenceCard {
                VStack(alignment: .leading, spacing: 14) {
                    HStack(spacing: 13) {
                        Text(String(student.name.prefix(1)))
                            .font(.system(size: 22, weight: .bold))
                            .foregroundStyle(.white)
                            .frame(width: 52, height: 52)
                            .background(LinearGradient(colors: [ReferenceColor.blue, Color(hex: "39B7B0")], startPoint: .topLeading, endPoint: .bottomTrailing), in: Circle())
                        VStack(alignment: .leading, spacing: 3) {
                            Text(student.name)
                                .font(.system(size: AppTheme.sectionTitleSize, weight: .bold))
                                .foregroundStyle(ReferenceColor.navy)
                            Text("\(student.grade) · \(student.className)")
                                .font(.system(size: AppTheme.secondarySize))
                                .foregroundStyle(AppTheme.muted)
                        }
                        Spacer()
                        Image(systemName: "checkmark.seal.fill")
                            .foregroundStyle(ReferenceColor.green)
                            .accessibilityLabel("孩子档案已载入")
                    }
                    Divider()
                    profileDataRow(icon: "person.fill", title: "性别", value: student.gender)
                    profileDataRow(icon: "birthday.cake.fill", title: "年龄参考", value: student.bodyAssessmentAgeLabel)
                    profileDataRow(icon: "building.2.fill", title: "学校档案", value: "\(student.grade) \(student.className)")
                    Text("如资料有误，请先在家庭账户中联系学校更正。年龄别 BMI 只使用孩子资料中的出生日期和本次测量日期计算。")
                        .font(.system(size: AppTheme.captionSize)).foregroundStyle(AppTheme.muted)
                        .padding(.top, 2)
                }
            }
            AssessmentPrimaryAction(title: "确认无误，填写身高体重", icon: "arrow.right") { move(to: .bmi) }
        }
    }

    private var environmentStep: some View {
        VStack(alignment: .leading, spacing: AppTheme.cardSpacing) {
            environmentPreview
            ReferenceCard {
                VStack(alignment: .leading, spacing: 14) {
                    ReferenceSectionTitle(title: "开始前检查", trailing: spaceReady ? "环境已确认" : "3 项")
                    checklist("镜头距离约 2–3 米，手机竖直并保持稳定", icon: "iphone.gen3")
                    Divider()
                    checklist("画面中只出现一名孩子，头部到双脚完整入镜", icon: "person.crop.rectangle")
                    Divider()
                    checklist("光线均匀、地面平整，周围没有易碰撞物品", icon: "sun.max.fill")
                }
            }
            readinessToggle(
                title: "环境已经准备好",
                detail: "我已确认以上条件，孩子可以安全完成动作。",
                icon: "checkmark.shield.fill",
                isOn: $spaceReady
            )
            AssessmentInfoBanner(
                icon: "camera.aperture",
                title: "相机还会自动检查",
                detail: "打开相机后将继续识别光线、距离、遮挡、多人入镜和身体离开画面。"
            )
            AssessmentPrimaryAction(
                title: spaceReady ? "进入动作采集" : "请先确认拍摄环境",
                icon: "camera.fill",
                enabled: spaceReady
            ) { move(to: .capture) }
        }
    }

    private func bmiEntry(_ student: Student) -> some View {
        VStack(alignment: .leading, spacing: AppTheme.cardSpacing) {
            AssessmentHeroCard(
                icon: "scalemass.fill",
                eyebrow: "本次实际测量",
                title: "填写身高和体重",
                detail: "请使用身高仪和体重秤的实际读数，相机不会估算身高或体重。"
            ) {
                HStack(spacing: 8) {
                    AssessmentFactChip(icon: "function", title: "自动计算 BMI")
                    AssessmentFactChip(icon: "calendar", title: student.bodyAssessmentAgeLabel)
                }
            }
            ruler(title: "身高", value: $height, range: 90...190, unit: "cm", step: 0.5)
            ruler(title: "体重", value: $weight, range: 15...90, unit: "kg", step: 0.1)

            ReferenceCard {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(alignment: .center) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("当前 BMI")
                                .font(.system(size: AppTheme.captionSize, weight: .semibold))
                                .foregroundStyle(AppTheme.muted)
                            Text(height > 0 && weight > 0 ? String(format: "%.1f", provisionalRecord.bmi) : "--")
                                .font(.system(size: 38, weight: .bold, design: .rounded))
                                .foregroundStyle(ReferenceColor.blue)
                        }
                        Spacer()
                        VStack(alignment: .trailing, spacing: 6) {
                            attentionBadge(provisionalBMILevel, label: provisionalRecord.bmiScreeningLabel(ageMonths: student.bodyAssessmentAgeMonths, gender: student.gender))
                            Text("儿童年龄别 BMI 参考")
                                .font(.system(size: AppTheme.captionSize))
                                .foregroundStyle(AppTheme.muted)
                        }
                    }
                    Divider()
                    Text("BMI = 体重(kg) ÷ 身高²(m²)。结果会结合出生日期、性别和测量日期给出年龄别参考。")
                        .font(.system(size: AppTheme.captionSize))
                        .foregroundStyle(AppTheme.muted)
                    if let heightAssessment = provisionalRecord.heightDevelopmentAssessment(ageMonths: student.bodyAssessmentAgeMonths, gender: student.gender) {
                        Text("当前身高发育：\(heightAssessment.level.label) · \(heightAssessment.ageYears)岁参考中位 \(String(format: "%.1f", heightAssessment.median)) cm · 儿童身高参考标准")
                            .font(.system(size: AppTheme.captionSize)).foregroundStyle(ReferenceColor.navy)
                    }
                }
            }

            DisclosureGroup(isExpanded: $parentsExpanded) {
                VStack(alignment: .leading, spacing: AppTheme.cardSpacing) {
                    Text("仅用于计算遗传靶身高参考区间，不代表成年身高预测。")
                        .font(.system(size: AppTheme.captionSize))
                        .foregroundStyle(AppTheme.muted)
                    ruler(title: "父亲身高", value: $fatherHeight, range: 120...230, unit: "cm", step: 0.5)
                    ruler(title: "母亲身高", value: $motherHeight, range: 120...230, unit: "cm", step: 0.5)
                    if let geneticHeight = provisionalRecord.geneticHeightReference(gender: student.gender) {
                        let range = provisionalRecord.geneticHeightRange(gender: student.gender)
                        let rangeText = range.map { String(format: "%.1f–%.1f cm", $0.lowerBound, $0.upperBound) } ?? "待完整填写"
                        AssessmentInfoBanner(
                            icon: "ruler.fill",
                            title: String(format: "遗传靶身高中位 %.1f cm", geneticHeight),
                            detail: "参考区间 \(rangeText) · 仅作家庭健康管理参考",
                            tint: ReferenceColor.green
                        )
                    }
                }
                .padding(.top, AppTheme.cardSpacing)
            } label: {
                Label("补充父母身高（选填）", systemImage: "person.2.fill")
                    .font(.system(size: AppTheme.bodySize, weight: .semibold))
                    .foregroundStyle(ReferenceColor.navy)
            }
            .padding(AppTheme.cardPadding)
            .background(.white, in: RoundedRectangle(cornerRadius: AppTheme.cardRadius, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: AppTheme.cardRadius, style: .continuous).stroke(AppTheme.divider.opacity(0.8), lineWidth: 0.75))

            AssessmentPrimaryAction(
                title: hasValidCoreMeasurements ? "继续检查拍摄环境" : "请填写有效身高和体重",
                icon: "arrow.right",
                enabled: hasValidCoreMeasurements
            ) { move(to: .environment) }
        }
    }

    private var captureGuide: some View {
        VStack(alignment: .leading, spacing: AppTheme.cardSpacing) {
            AssessmentHeroCard(
                icon: "camera.viewfinder",
                eyebrow: "端内视觉识别",
                title: "完成 4 项动作采集",
                detail: "每项约 10–20 秒。按语音提示调整站位，达到质量要求后自动完成。"
            ) {
                HStack(spacing: 8) {
                    AssessmentFactChip(icon: "checkmark.circle.fill", title: "已完成 \(completedCaptures.count) / \(BodyAssessmentRecord.CaptureTask.allCases.count)")
                    AssessmentFactChip(icon: "speaker.wave.2.fill", title: "语音指导")
                }
            }
            ForEach(Array(BodyAssessmentRecord.CaptureTask.allCases.enumerated()), id: \.element.id) { index, task in
                Button { activeCameraTask = task } label: {
                    HStack(spacing: 13) {
                        ZStack {
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .fill((completedCaptures.contains(task) ? ReferenceColor.green : ReferenceColor.blue).opacity(0.10))
                            if completedCaptures.contains(task) {
                                Image(systemName: "checkmark")
                                    .font(.system(size: 19, weight: .bold))
                            } else {
                                Text("\(index + 1)")
                                    .font(.system(size: 19, weight: .bold, design: .rounded))
                            }
                        }
                        .foregroundStyle(completedCaptures.contains(task) ? ReferenceColor.green : ReferenceColor.blue)
                        .frame(width: 48, height: 48)
                        VStack(alignment: .leading, spacing: 4) {
                            HStack(spacing: 6) {
                                Text(task.title)
                                    .font(.system(size: AppTheme.bodySize, weight: .semibold))
                                    .foregroundStyle(ReferenceColor.navy)
                                if completedCaptures.contains(task) {
                                    Text("已完成")
                                        .font(.system(size: AppTheme.captionSize, weight: .semibold))
                                        .foregroundStyle(ReferenceColor.green)
                                }
                            }
                            Text(task.instruction)
                                .font(.system(size: AppTheme.captionSize))
                                .foregroundStyle(AppTheme.muted)
                                .multilineTextAlignment(.leading)
                                .lineLimit(2)
                            if let feedback = captureFeedback[task] {
                                Text(feedback)
                                    .font(.system(size: AppTheme.captionSize, weight: .medium))
                                    .foregroundStyle(completedCaptures.contains(task) ? ReferenceColor.green : AppTheme.warning)
                                    .lineLimit(2)
                            }
                        }
                        Spacer()
                        Image(systemName: completedCaptures.contains(task) ? "arrow.clockwise.camera" : "camera.fill")
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundStyle(completedCaptures.contains(task) ? ReferenceColor.green : ReferenceColor.blue)
                    }
                    .padding(14)
                    .background(.white, in: RoundedRectangle(cornerRadius: AppTheme.cardRadius, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: AppTheme.cardRadius, style: .continuous).stroke(completedCaptures.contains(task) ? ReferenceColor.green.opacity(0.28) : AppTheme.divider.opacity(0.8), lineWidth: 0.85))
                }.buttonStyle(.plain).accessibilityLabel("\(task.title)，\(completedCaptures.contains(task) ? "已完成" : "打开相机")")
            }
            AssessmentInfoBanner(
                icon: "eye.trianglebadge.exclamationmark",
                title: "质量不足会提示重拍",
                detail: "系统会检查清晰度、全身入镜、多人、遮挡、距离和中途离开，不会用低质量画面生成结果。"
            )
            let allCaptured = completedCaptures.count == BodyAssessmentRecord.CaptureTask.allCases.count
            AssessmentPrimaryAction(
                title: allCaptured ? "继续质量确认" : "还需完成 \(BodyAssessmentRecord.CaptureTask.allCases.count - completedCaptures.count) 项",
                icon: "arrow.right",
                enabled: allCaptured
            ) { move(to: .confirm) }
        }
    }

    private var observationConfirm: some View {
        VStack(alignment: .leading, spacing: AppTheme.cardSpacing) {
            AssessmentHeroCard(
                icon: "checkmark.shield.fill",
                eyebrow: "采集完成",
                title: "确认质量与安全信息",
                detail: "四项动作均已达到基础取景要求。提交前请补充孩子近期的身体感受。"
            ) {
                HStack(spacing: 8) {
                    AssessmentFactChip(icon: "camera.fill", title: "4 项已采集")
                    AssessmentFactChip(icon: "person.fill.checkmark", title: "单人完整入镜")
                }
            }
            if !visualHints.isEmpty {
                ReferenceCard {
                    VStack(alignment: .leading, spacing: 10) {
                        ReferenceSectionTitle(title: "本次画面提示", trailing: "请家长确认")
                        ForEach(visualHints.keys.sorted { $0.rawValue < $1.rawValue }, id: \.self) { task in
                            if let hint = visualHints[task] {
                                Label("\(task.title)：\(hint)", systemImage: "viewfinder.circle.fill")
                                    .font(.system(size: AppTheme.secondarySize))
                                    .foregroundStyle(AppTheme.warning)
                            }
                        }
                    }
                }
            }
            confirmationToggle(title: "孩子近期有肩背、腰背或坐姿疼痛/不适", detail: "作为安全提示展示给家长，不会替代测评结论。", value: $asymmetric)
            confirmationToggle(title: "孩子近期有行走困难、跛行或活动受限", detail: "如持续存在，请优先咨询专业人员。", value: $gaitConcern)
            AssessmentInfoBanner(
                icon: "cross.case.fill",
                title: "不是医学诊断",
                detail: "出现疼痛、麻木、无力或进行性变化时，请暂停运动并及时就医。",
                tint: AppTheme.warning
            )
            AssessmentPrimaryAction(title: "生成家庭观察结果", icon: "checkmark.circle.fill") {
                guard let student else { return }
                state.saveBodyAssessment(provisionalRecord, for: student)
                move(to: .result)
            }
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
            let currentConsent = student.flatMap { state.localFeatures.healthConsents[$0.id] }
            let consentIsCurrent = currentConsent?.revokedAt == nil
                && currentConsent?.privacyPolicyVersion == LegalPolicy.privacyPolicyVersion
                && currentConsent?.cameraConsentVersion == LegalPolicy.cameraConsentVersion
                && currentConsent?.algorithmNoticeVersion == LegalPolicy.algorithmNoticeVersion
            if restoredStep >= Step.profile.rawValue, !consentIsCurrent {
                // A draft created under an older policy must not resume beyond
                // the consent gate after the bundled policy versions change.
                step = .consent
                adultReady = false
                consentAcknowledged = false
            }
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
    func move(to next: Step) {
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
                        Image(systemName: "minus").font(.caption.bold()).frame(width: 32, height: 32)
                    }.buttonStyle(.bordered).tint(bodyCoral).accessibilityLabel("\(title)减少")
                    TextField("输入", text: textValue)
                        .keyboardType(.decimalPad).multilineTextAlignment(.trailing)
                        .font(.title3.bold()).foregroundStyle(bodyCoral)
                        .frame(width: 72).accessibilityLabel("\(title)数值")
                    Text(unit).font(.subheadline.weight(.semibold)).foregroundStyle(bodyCoral)
                    Button { value.wrappedValue = BodyMeasurementInput.normalized((value.wrappedValue > 0 ? value.wrappedValue : range.lowerBound) + step, range: range, step: step) } label: {
                        Image(systemName: "plus").font(.caption.bold()).frame(width: 32, height: 32)
                    }.buttonStyle(.bordered).tint(bodyCoral).accessibilityLabel("\(title)增加")
                }
            }
            Slider(value: Binding(get: { value.wrappedValue > 0 ? value.wrappedValue : range.lowerBound }, set: { value.wrappedValue = BodyMeasurementInput.normalized($0, range: range, step: step) }), in: range, step: step).tint(bodyCoral)
            HStack(spacing: 0) {
                ForEach(0..<17, id: \.self) { _ in Rectangle().fill(bodyCoral.opacity(0.22)).frame(width: 1, height: 7); Spacer(minLength: 0) }
            }.padding(.horizontal, 4)
            HStack { Text(String(format: "%.0f", range.lowerBound)); Spacer(); Text("滑动 / 输入 / 微调"); Spacer(); Text(String(format: "%.0f", range.upperBound)) }.font(.caption).foregroundStyle(.secondary)
        }
        .padding(AppTheme.cardPadding)
        .background(.white, in: RoundedRectangle(cornerRadius: AppTheme.cardRadius, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: AppTheme.cardRadius, style: .continuous).stroke(AppTheme.divider.opacity(0.8), lineWidth: 0.75))
    }
    private func profileDataRow(icon: String, title: String, value: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .foregroundStyle(ReferenceColor.blue)
                .frame(width: 24)
            Text(title)
                .font(.system(size: AppTheme.secondarySize))
                .foregroundStyle(AppTheme.muted)
            Spacer()
            Text(value)
                .font(.system(size: AppTheme.secondarySize, weight: .semibold))
                .foregroundStyle(ReferenceColor.navy)
                .multilineTextAlignment(.trailing)
        }
        .accessibilityElement(children: .combine)
    }
    private var environmentPreview: some View {
        ZStack {
            LinearGradient(colors: [Color(hex: "172B4D"), Color(hex: "245A87")], startPoint: .topLeading, endPoint: .bottomTrailing)
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(.white.opacity(0.76), style: StrokeStyle(lineWidth: 2, dash: [8, 6]))
                .padding(.horizontal, 62)
                .padding(.vertical, 24)
            VStack(spacing: 8) {
                Image(systemName: "figure.stand")
                    .font(.system(size: 58, weight: .light))
                Text("头部到双脚完整入镜")
                    .font(.system(size: AppTheme.bodySize, weight: .semibold))
                Text("手机与孩子保持约 2–3 米")
                    .font(.system(size: AppTheme.captionSize))
                    .foregroundStyle(.white.opacity(0.76))
            }
            .foregroundStyle(.white)
        }
        .frame(height: 210)
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("拍摄取景示意，孩子头部到双脚完整入镜，手机距离约二到三米")
    }
    private func checklist(_ text: String, icon: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(ReferenceColor.blue)
                .frame(width: 24)
            Text(text)
                .font(.system(size: AppTheme.secondarySize))
                .foregroundStyle(ReferenceColor.navy)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
    }
    private func readinessToggle(title: String, detail: String, icon: String, isOn: Binding<Bool>) -> some View {
        HStack(alignment: .center, spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(isOn.wrappedValue ? ReferenceColor.green : ReferenceColor.blue)
                .frame(width: 40, height: 40)
                .background((isOn.wrappedValue ? ReferenceColor.green : ReferenceColor.blue).opacity(0.10), in: RoundedRectangle(cornerRadius: 11, style: .continuous))
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: AppTheme.bodySize, weight: .semibold))
                    .foregroundStyle(ReferenceColor.navy)
                Text(detail)
                    .font(.system(size: AppTheme.captionSize))
                    .foregroundStyle(AppTheme.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 4)
            Toggle("", isOn: isOn)
                .labelsHidden()
                .tint(ReferenceColor.green)
                .accessibilityLabel(title)
        }
        .padding(12)
        .background(AppTheme.surface, in: RoundedRectangle(cornerRadius: AppTheme.controlRadius, style: .continuous))
    }
    private func confirmationToggle(title: String, detail: String, value: Binding<Bool>) -> some View {
        Toggle(isOn: value) {
            VStack(alignment: .leading, spacing: 5) {
                Text(title).font(.system(size: AppTheme.bodySize, weight: .semibold)).foregroundStyle(ReferenceColor.navy)
                Text(detail).font(.system(size: AppTheme.captionSize)).foregroundStyle(AppTheme.muted)
            }
        }
        .tint(ReferenceColor.blue)
        .padding(AppTheme.cardPadding)
        .background(.white, in: RoundedRectangle(cornerRadius: AppTheme.cardRadius, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: AppTheme.cardRadius, style: .continuous).stroke(AppTheme.divider.opacity(0.75), lineWidth: 0.75))
    }
    let bodyCoral = ReferenceColor.blue
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
