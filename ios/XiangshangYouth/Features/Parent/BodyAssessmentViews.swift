import SwiftUI

/// The family-side assessment intentionally stores only the parent's confirmed
/// observations and completed tasks. Real-time capture is processed in the
/// App and does not retain photos or videos at this stage.
struct BodyAssessmentView: View {
    enum Step: Int, CaseIterable { case overview, consent, profile, bmi, environment, capture, confirm, result, plan }
    let assessmentSteps = ["使用说明", "监护人授权", "孩子身体信息", "身高体重和BMI", "拍摄环境检查", "摄像头测评", "质量确认", "结果报告", "训练计划"]

    @EnvironmentObject var state: AppState
    @EnvironmentObject var router: AppRouter
    @Environment(\.accessibilityReduceMotion) var reduceMotion
    @State var step: Step = .overview
    // Values deliberately start empty (zero) rather than with a child's
    // fabricated measurement. The ruler becomes active only after a parent
    // enters a real value.
    @State var height = 0.0
    @State var weight = 0.0
    @State var fatherHeight = 0.0
    @State var motherHeight = 0.0
    @State var completedCaptures = Set<BodyAssessmentRecord.CaptureTask>()
    @State var asymmetric = false
    @State var gaitConcern = false
    @State var activeCameraTask: BodyAssessmentRecord.CaptureTask?
    @State var captureFeedback: [BodyAssessmentRecord.CaptureTask: String] = [:]
    @State var visualHints: [BodyAssessmentRecord.CaptureTask: String] = [:]
    @State var postureSnapshots: [BodyAssessmentRecord.CaptureTask: PostureMetricSnapshot] = [:]
    @State var standingShoulderText = ""
    @State var standingPelvisText = ""
    @State var standingHeadTiltText = ""
    @State var adamsObservedResult = "unrecorded"
    @State var adamsProminenceSide = "无"
    @State var gaitObservedResult = "unrecorded"
    @State var gaitObservationNote = ""
    @State var seatedMidlineText = ""
    @State var seatedShoulderText = ""
    @State var seatedKyphosisResult = "unrecorded"
    @State var thoracicAtrText = ""
    @State var lumbarAtrText = ""
    @State var thoracicAtrSide = "无"
    @State var lumbarAtrSide = "无"
    @State var atrRetestEnabled = false
    @State var thoracicAtrRepeatText = ""
    @State var lumbarAtrRepeatText = ""
    @State var seatedForwardBendAtrText = ""
    @State var occiputWallDistanceText = ""
    @State var occiputWallDistanceRepeatText = ""
    @State var adultReady = false
    @State var spaceReady = false
    @State var consentAcknowledged = false
    @State var didLoad = false
    @State var showFollowAlong = false
    @State var followAlongDayIndex = 0
    @State var followAlongDate = Date()
    @State var parentsExpanded = false
    @State var showsAllPlanDays = false
    /// Viewing a saved family observation is read-only navigation context. Its
    /// back action must leave the feature, not expose the old confirmation
    /// form where a finished record could be accidentally re-submitted.
    @State var viewingSavedRecord = false

    var student: Student? { state.selectedChild }
    var visualSummary: String? {
        let summary = visualHints.keys.sorted { $0.rawValue < $1.rawValue }.compactMap { visualHints[$0] }.joined(separator: "\n")
        return summary.isEmpty ? nil : summary
    }
    var thoracicAtrFirst: Double? { standardizedMeasurement(thoracicAtrText, range: 0...30) }
    var lumbarAtrFirst: Double? { standardizedMeasurement(lumbarAtrText, range: 0...30) }
    var thoracicAtrRepeat: Double? { standardizedMeasurement(thoracicAtrRepeatText, range: 0...30) }
    var lumbarAtrRepeat: Double? { standardizedMeasurement(lumbarAtrRepeatText, range: 0...30) }
    var seatedForwardBendAtr: Double? { standardizedMeasurement(seatedForwardBendAtrText, range: 0...30) }
    var thoracicAtr: Double? { averagedATR(first: thoracicAtrFirst, repeatValue: thoracicAtrRepeat) }
    var lumbarAtr: Double? { averagedATR(first: lumbarAtrFirst, repeatValue: lumbarAtrRepeat) }
    var occiputWallDistanceFirst: Double? { standardizedMeasurement(occiputWallDistanceText, range: 0...15) }
    var occiputWallDistanceSecond: Double? { standardizedMeasurement(occiputWallDistanceRepeatText, range: 0...15) }
    var occiputWallDistance: Double? {
        SpineScreeningStandard.maximumOcciputWallDistance(first: occiputWallDistanceFirst, second: occiputWallDistanceSecond)
    }
    var atrRecorded: Bool {
        guard let thoracicAtr, let lumbarAtr else { return false }
        return (thoracicAtr == 0 || thoracicAtrSide != "无") && (lumbarAtr == 0 || lumbarAtrSide != "无")
    }
    var otwdRecorded: Bool { occiputWallDistance != nil }
    var standingShoulder: Double? { standardizedMeasurement(standingShoulderText, range: 0...10) }
    var standingPelvis: Double? { standardizedMeasurement(standingPelvisText, range: 0...10) }
    var standingHeadTilt: Double? { standardizedMeasurement(standingHeadTiltText, range: 0...30) }
    var seatedMidline: Double? { standardizedMeasurement(seatedMidlineText, range: 0...10) }
    var seatedShoulder: Double? { standardizedMeasurement(seatedShoulderText, range: 0...10) }
    var standingMeasured: Bool { standingShoulder != nil && standingPelvis != nil && standingHeadTilt != nil }
    var adamsObserved: Bool { adamsObservedResult != "unrecorded" && (adamsObservedResult == "negative" || adamsProminenceSide != "无") }
    var gaitObserved: Bool { gaitObservedResult != "unrecorded" }
    var seatedMeasured: Bool { seatedMidline != nil && seatedShoulder != nil && seatedKyphosisResult != "unrecorded" }
    var completedStandardItems: Int {
        SpineScreeningStandard.homeCameraItems.reduce(into: 0) { count, item in
            if case .camera(let task) = item.method, completedCaptures.contains(task) { count += 1 }
        }
    }
    var standardSnapshots: [BodyAssessmentRecord.CaptureTask: PostureMetricSnapshot] {
        var value = postureSnapshots
        if var standing = value[.standingBack], let standingShoulder, let standingPelvis, let standingHeadTilt {
            standing.shoulderHeightDifferenceCm = standingShoulder
            standing.pelvicHeightDifferenceCm = standingPelvis
            standing.headTiltDegrees = standingHeadTilt
            value[.standingBack] = standing
        }
        if var forward = value[.forwardBend], let thoracicAtr, let lumbarAtr {
            forward.thoracicAtrDegrees = thoracicAtr
            forward.lumbarAtrDegrees = lumbarAtr
            forward.instrumentAtrDegrees = max(thoracicAtr, lumbarAtr)
            forward.thoracicAtrSide = thoracicAtr == 0 ? nil : thoracicAtrSide
            forward.lumbarAtrSide = lumbarAtr == 0 ? nil : lumbarAtrSide
            forward.thoracicAtrFirstDegrees = thoracicAtrFirst
            forward.thoracicAtrSecondDegrees = atrRetestEnabled ? thoracicAtrRepeat : nil
            forward.lumbarAtrFirstDegrees = lumbarAtrFirst
            forward.lumbarAtrSecondDegrees = atrRetestEnabled ? lumbarAtrRepeat : nil
            forward.seatedForwardBendAtrDegrees = seatedForwardBendAtr
            forward.adamsObservedResult = adamsObservedResult == "unrecorded" ? nil : adamsObservedResult
            forward.adamsProminenceSide = adamsObservedResult == "negative" ? nil : (adamsProminenceSide == "无" ? nil : adamsProminenceSide)
            value[.forwardBend] = forward
        }
        if var gait = value[.gaitVideo], gaitObserved {
            gait.gaitObservedAbnormal = gaitObservedResult == "abnormal"
            let note = gaitObservationNote.trimmingCharacters(in: .whitespacesAndNewlines)
            gait.gaitObservationNote = note.isEmpty ? nil : note
            value[.gaitVideo] = gait
        }
        if var seated = value[.seatedPosture], let occiputWallDistance {
            seated.occiputWallDistanceCm = occiputWallDistance
            seated.spinalMidlineDeviationCm = seatedMidline
            seated.shoulderHeightDifferenceCm = seatedShoulder
            seated.seatedThoracicKyphosisObserved = seatedKyphosisResult == "abnormal"
            value[.seatedPosture] = seated
        }
        return value
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
            postureReport: standardSnapshots.isEmpty ? nil : PostureAssessmentReport.make(snapshots: standardSnapshots, ageMonths: student?.bodyAssessmentAgeMonths),
            ageMonthsAtMeasurement: student?.bodyAssessmentAgeMonths
        )
    }
    var fallbackStudent: Student { Student(id: "body-assessment-preview", name: "孩子", gender: "男", grade: "三年级", className: "三年级1班", region: "", isPovertyArea: false, taskStatus: .completed, totalScore: nil) }
    var hasValidCoreMeasurements: Bool {
        (90.0...190.0).contains(height) && (15.0...90.0).contains(weight)
    }
    var followUpDate: Date {
        let level = provisionalBMILevel
        let days = level == .red ? 7 : level == .yellow || asymmetric || gaitConcern ? 30 : 90
        return BusinessClock.addingDays(days)
    }
    var provisionalBMILevel: BodyAssessmentRecord.AttentionLevel {
        return BodyAssessmentRecord(heightCentimeters: height, weightKilograms: weight, measuredAt: .now, ruleVersion: BodyAssessmentRecord.ruleVersion, completedCaptures: [], parentMarkedAsymmetric: false, parentMarkedGaitConcern: false, savedAt: .now, nextFollowUpDate: .now, completedPlanDays: []).bmiAttention(ageMonths: student?.bodyAssessmentAgeMonths, gender: student?.gender ?? "男")
    }
    var record: BodyAssessmentRecord? { student.flatMap(state.bodyAssessment(for:)) }

    var body: some View {
        Group {
            if let student {
                persistedAssessmentContent(student)
            } else {
                ParentBindingPrompt()
            }
        }
        .sheet(item: $activeCameraTask) { task in
            LiveVisionCaptureSheet(task: task, measuredHeightCm: height, ageMonths: student?.bodyAssessmentAgeMonths) { review in
                if let hint = review.observationHint { visualHints[task] = hint }
                else { visualHints.removeValue(forKey: task) }
                if var snapshot = review.postureSnapshot, review.accepted {
                    if let first = postureSnapshots[task], first.repeatabilityStatus == "awaiting-second-take" {
                        let repeatability = PostureCaptureRepeatability.verify(first: first, second: snapshot)
                        if repeatability.passed {
                            postureSnapshots[task] = PostureCaptureRepeatability.merged(first: first, second: snapshot, result: repeatability)
                            completedCaptures.insert(task)
                            captureFeedback[task] = "两次独立采集一致性通过，已完成该项记录。"
                        } else {
                            snapshot.captureAttemptCount = 1
                            snapshot.repeatabilityStatus = "awaiting-second-take"
                            snapshot.repeatabilityMaximumDifference = repeatability.maximumDifference.isFinite ? repeatability.maximumDifference : nil
                            postureSnapshots[task] = snapshot
                            completedCaptures.remove(task)
                            captureFeedback[task] = "两次记录差异较大，请离开人型框后重新入镜，再完成第 2 次采集。"
                        }
                    } else {
                        snapshot.captureAttemptCount = 1
                        snapshot.repeatabilityStatus = "awaiting-second-take"
                        snapshot.repeatabilityMaximumDifference = nil
                        postureSnapshots[task] = snapshot
                        completedCaptures.remove(task)
                        captureFeedback[task] = "第 1 次采集已保存。请离开人型框后重新入镜，完成第 2 次独立采集。"
                    }
                } else {
                    captureFeedback[task] = review.message
                }
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

    func assessmentContent(_ student: Student) -> some View {
        AppScaffold(title: stepTitle, onBack: goBack, scrollResetID: step.rawValue) {
            VStack(spacing: AppTheme.sectionSpacing) {
                progress
                assessmentStepContent(student)
            }
            .padding(.top, AppTheme.cardSpacing)
        }
    }

    @ViewBuilder
    func assessmentStepContent(_ student: Student) -> some View {
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

    func persistedAssessmentContent(_ student: Student) -> some View {
        assessmentContent(student)
            .onChange(of: draftPersistenceKey) { _, _ in persistDraft() }
            .task {
                load(record: state.bodyAssessment(for: student), draft: state.bodyAssessmentDraft(for: student))
                guard state.bodyAssessmentDraft(for: student) == nil, state.bodyAssessment(for: student) != nil else { return }
                await state.refreshLatestBodyAssessment(for: student)
                load(record: state.bodyAssessment(for: student), draft: nil)
            }
    }

    /// One compact observation key replaces a deep chain of generic
    /// `onChange` modifiers. It keeps every draft field durable while making
    /// this already substantial assessment screen practical to type-check.
    var draftPersistenceKey: [String] {
        let measurements = [height, weight, fatherHeight, motherHeight].map { String($0) }
        let workflow = [
            String(adultReady), String(consentAcknowledged), String(spaceReady),
            String(asymmetric), String(gaitConcern), String(atrRetestEnabled),
            String(describing: completedCaptures), String(describing: visualHints),
            String(describing: postureSnapshots)
        ]
        let supervised = [
            standingShoulderText, standingPelvisText, standingHeadTiltText,
            adamsObservedResult, adamsProminenceSide,
            gaitObservedResult, gaitObservationNote,
            seatedMidlineText, seatedShoulderText, seatedKyphosisResult,
            thoracicAtrText, lumbarAtrText, thoracicAtrSide, lumbarAtrSide,
            thoracicAtrRepeatText, lumbarAtrRepeatText, seatedForwardBendAtrText,
            occiputWallDistanceText, occiputWallDistanceRepeatText
        ]
        return measurements + workflow + supervised
    }

    var stepTitle: String {
        assessmentSteps[displayStepIndex]
    }

    var displayStepIndex: Int {
        step.rawValue
    }

    var progress: some View {
        AssessmentProgressHeader(titles: assessmentSteps, currentIndex: displayStepIndex)
    }

    var captureGuide: some View {
        VStack(alignment: .leading, spacing: AppTheme.cardSpacing) {
            AssessmentHeroCard(
                icon: "checklist.checked",
                eyebrow: "UY-IMCA V1 · 2026-07-20",
                title: "完成 8 段家庭相机观察",
                detail: "依次完成正面、背面、双侧、Adams 前屈、下肢力线、3 米步态、坐姿和足弓；每段需两次稳定采集。"
            ) {
                HStack(spacing: 8) {
                    AssessmentFactChip(icon: "checkmark.circle.fill", title: "已完成 \(completedStandardItems) / \(SpineScreeningStandard.homeCameraItems.count)")
                    AssessmentFactChip(icon: "speaker.wave.2.fill", title: "语音指导")
                }
            }
            AssessmentInfoBanner(
                icon: "camera.metering.center.weighted",
                title: "统一主机位",
                detail: SpineScreeningStandard.mainCameraPlacement + "；步态需准备 3 米直线通道。"
            )
            ForEach(SpineScreeningStandard.homeCameraItems) { item in
                switch item.method {
                case .camera(let task):
                    standardCameraItem(item, task: task)
                case .instrumentATR:
                    EmptyView()
                }
            }
            AssessmentInfoBanner(
                icon: "cross.case.fill",
                title: "专业增强项不在家庭端采集",
                detail: "ATR、枕墙距和软尺厘米值需要受训人员及专用器械。家庭相机不会生成 ATR、Cobb 角或医疗诊断。",
                tint: ReferenceColor.green
            )
            AssessmentInfoBanner(
                icon: "eye.trianglebadge.exclamationmark",
                title: "质量不足会提示重拍",
                detail: "系统会检查清晰度、全身入镜、多人、遮挡、距离和中途离开，不会用低质量画面生成结果。"
            )
            let allCaptured = completedStandardItems == SpineScreeningStandard.homeCameraItems.count
            AssessmentPrimaryAction(
                title: allCaptured ? "继续质量确认" : "还需完成 \(SpineScreeningStandard.homeCameraItems.count - completedStandardItems) 项",
                icon: "arrow.right",
                enabled: allCaptured
            ) { move(to: .confirm) }
        }
    }

    func standardCameraItem(_ item: SpineScreeningStandard.Item, task: BodyAssessmentRecord.CaptureTask) -> some View {
        let captured = completedCaptures.contains(task)
        let awaitingSecondTake = postureSnapshots[task]?.repeatabilityStatus == "awaiting-second-take"
        return Button { activeCameraTask = task } label: {
            HStack(alignment: .top, spacing: 13) {
                ZStack {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill((captured ? ReferenceColor.green : ReferenceColor.blue).opacity(0.10))
                    if captured { Image(systemName: "checkmark").font(.system(size: 19, weight: .bold)) }
                    else { Text("\(item.number)").font(.system(size: 19, weight: .bold, design: .rounded)) }
                }
                .foregroundStyle(captured ? ReferenceColor.green : ReferenceColor.blue)
                .frame(width: 48, height: 48)
                VStack(alignment: .leading, spacing: 5) {
                    HStack(spacing: 6) {
                        Text(item.title).font(.system(size: AppTheme.bodySize, weight: .semibold)).foregroundStyle(ReferenceColor.navy)
                        if captured { Text("两次采集已通过").font(.system(size: AppTheme.captionSize, weight: .semibold)).foregroundStyle(ReferenceColor.green) }
                        else if awaitingSecondTake { Text("还需第 2 次").font(.system(size: AppTheme.captionSize, weight: .semibold)).foregroundStyle(AppTheme.warning) }
                    }
                    Text(item.purpose).font(.system(size: AppTheme.captionSize, weight: .semibold)).foregroundStyle(ReferenceColor.blue)
                    Text(item.instruction).font(.system(size: AppTheme.captionSize)).foregroundStyle(AppTheme.muted).fixedSize(horizontal: false, vertical: true)
                    if task == .forwardBend {
                        Text(SpineScreeningStandard.forwardBendAuxiliaryPlacement)
                            .font(.system(size: AppTheme.captionSize, weight: .medium)).foregroundStyle(AppTheme.warning)
                    }
                    if let feedback = captureFeedback[task] {
                        Text(feedback).font(.system(size: AppTheme.captionSize, weight: .medium)).foregroundStyle(captured ? ReferenceColor.green : AppTheme.warning).lineLimit(2)
                    }
                }
                Spacer(minLength: 0)
                Image(systemName: captured ? "arrow.clockwise.camera" : (task == .gaitVideo ? "video.fill" : "camera.fill"))
                    .font(.system(size: 17, weight: .semibold)).foregroundStyle(captured ? ReferenceColor.green : (awaitingSecondTake ? AppTheme.warning : ReferenceColor.blue))
            }
            .padding(18)
            .background(.white, in: RoundedRectangle(cornerRadius: AppTheme.cardRadius, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: AppTheme.cardRadius, style: .continuous).stroke(captured ? ReferenceColor.green.opacity(0.28) : AppTheme.divider.opacity(0.8), lineWidth: 0.85))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("第 \(item.number) 项，\(item.title)，\(captured ? "两次采集已通过，可重新采集" : (awaitingSecondTake ? "第 1 次已完成，还需第 2 次" : "打开相机"))")
        .accessibilityIdentifier("body-capture-\(task.rawValue)")
    }

    func atrMeasurementCard(_ item: SpineScreeningStandard.Item) -> some View {
        ReferenceCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .top, spacing: 12) {
                    Text("\(item.number)").font(.system(size: 19, weight: .bold, design: .rounded)).foregroundStyle(atrRecorded ? ReferenceColor.green : ReferenceColor.blue)
                        .frame(width: 48, height: 48).background((atrRecorded ? ReferenceColor.green : ReferenceColor.blue).opacity(0.10), in: RoundedRectangle(cornerRadius: 14))
                    VStack(alignment: .leading, spacing: 4) {
                        Text(item.title).font(.system(size: AppTheme.bodySize, weight: .semibold)).foregroundStyle(ReferenceColor.navy)
                        Text(item.purpose).font(.system(size: AppTheme.captionSize, weight: .semibold)).foregroundStyle(ReferenceColor.blue)
                        Text(item.instruction).font(.system(size: AppTheme.captionSize)).foregroundStyle(AppTheme.muted).fixedSize(horizontal: false, vertical: true)
                    }
                }
                standardInstrumentRow(title: "胸段 T4-T8", value: $thoracicAtrText, side: $thoracicAtrSide)
                standardInstrumentRow(title: "腰段 T12-L3", value: $lumbarAtrText, side: $lumbarAtrSide)
                Toggle("两次读数波动较大，启用复测并取算术平均值", isOn: $atrRetestEnabled)
                    .font(.system(size: AppTheme.captionSize, weight: .semibold))
                if atrRetestEnabled {
                    standardInstrumentRow(title: "胸段复测", value: $thoracicAtrRepeatText, side: $thoracicAtrSide)
                    standardInstrumentRow(title: "腰段复测", value: $lumbarAtrRepeatText, side: $lumbarAtrSide)
                    Text("原始读数与复测读数均保留，最终胸段/腰段分别取两次算术平均值。")
                        .font(.system(size: AppTheme.captionSize)).foregroundStyle(AppTheme.muted)
                }
                Label(atrRecorded ? "ATR 读数完整，最大值 \(String(format: "%.1f", max(thoracicAtr ?? 0, lumbarAtr ?? 0)))°" : "请录入两段最大读数；非 0° 时必须选择左/右偏向", systemImage: atrRecorded ? "checkmark.circle.fill" : "exclamationmark.circle")
                    .font(.system(size: AppTheme.captionSize, weight: .semibold)).foregroundStyle(atrRecorded ? ReferenceColor.green : AppTheme.warning)
                if let maximum = [thoracicAtr, lumbarAtr].compactMap({ $0 }).max(), maximum >= SpineScreeningStandard.atrAttentionDegrees {
                    Divider()
                    Text("坐位前屈 ATR 复核（手册建议）").font(.system(size: AppTheme.secondarySize, weight: .semibold)).foregroundStyle(ReferenceColor.navy)
                    Text("让孩子坐于凳上再次前屈，录入最大 ATR。较站位下降 ≥3° 记录为“功能性偏斜可能”；变化不足 3° 进入结构异常复核提示。")
                        .font(.system(size: AppTheme.captionSize)).foregroundStyle(AppTheme.muted).fixedSize(horizontal: false, vertical: true)
                    HStack {
                        TextField("0.0", text: $seatedForwardBendAtrText).keyboardType(.decimalPad).textFieldStyle(.roundedBorder)
                            .accessibilityLabel("坐位前屈 ATR 角度")
                        Text("°").foregroundStyle(AppTheme.muted)
                    }
                }
            }
        }
    }

    func standardInstrumentRow(title: String, value: Binding<String>, side: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(title).font(.system(size: AppTheme.secondarySize, weight: .semibold)).foregroundStyle(ReferenceColor.navy)
            HStack(spacing: 10) {
                TextField("0.0", text: value)
                    .keyboardType(.decimalPad)
                    .textFieldStyle(.roundedBorder)
                    .frame(minWidth: 90)
                    .accessibilityLabel("\(title) ATR 角度")
                Text("°").foregroundStyle(AppTheme.muted)
                Picker("旋转偏向", selection: side) {
                    Text("无").tag("无"); Text("左").tag("左"); Text("右").tag("右")
                }
                .pickerStyle(.segmented)
                .frame(maxWidth: 170)
            }
        }
    }

    var occiputWallDistanceCard: some View {
        ReferenceCard {
            VStack(alignment: .leading, spacing: 9) {
                Text("项目 5 辅助定量 · 枕墙距 OTWD")
                    .font(.system(size: AppTheme.secondarySize, weight: .semibold)).foregroundStyle(ReferenceColor.navy)
                Text("坐姿观察后，脱鞋背靠平整墙面，双脚并拢，臀部及肩胛骨贴墙，双眼平视、下颌微收。水平测量后脑勺最突出点到墙面的距离，两次取最大值。")
                    .font(.system(size: AppTheme.captionSize)).foregroundStyle(AppTheme.muted).fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 10) {
                    TextField("第一次", text: $occiputWallDistanceText).keyboardType(.decimalPad).textFieldStyle(.roundedBorder)
                        .accessibilityLabel("第一次枕墙距，厘米")
                    TextField("第二次", text: $occiputWallDistanceRepeatText).keyboardType(.decimalPad).textFieldStyle(.roundedBorder)
                        .accessibilityLabel("第二次枕墙距，厘米")
                    Text("cm").foregroundStyle(AppTheme.muted)
                }
                Label(otwdRecorded ? "已自动取最大值 \(String(format: "%.1f", occiputWallDistance ?? 0)) cm" : "请分别录入两次读数，精确至 0.1 cm", systemImage: otwdRecorded ? "checkmark.circle.fill" : "ruler")
                    .font(.system(size: AppTheme.captionSize, weight: .semibold)).foregroundStyle(otwdRecorded ? ReferenceColor.green : AppTheme.warning)
            }
        }
    }

    var observationConfirm: some View {
        VStack(alignment: .leading, spacing: AppTheme.cardSpacing) {
            AssessmentHeroCard(
                icon: "checkmark.shield.fill",
                eyebrow: "采集完成",
                title: "确认质量与安全信息",
                detail: "八段相机采集已完成。提交前请核对双次采集质量和孩子近期身体感受。"
            ) {
                HStack(spacing: 8) {
                    AssessmentFactChip(icon: "checklist.checked", title: "8 段已记录")
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

    func load(record: BodyAssessmentRecord?, draft: BodyAssessmentDraft?) {
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
            standingShoulderText = draft.standingShoulderDifferenceCentimeters.map { String(format: "%.1f", $0) } ?? ""
            standingPelvisText = draft.standingPelvisDifferenceCentimeters.map { String(format: "%.1f", $0) } ?? ""
            standingHeadTiltText = draft.standingHeadTiltDegrees.map { String(format: "%.1f", $0) } ?? ""
            adamsObservedResult = draft.adamsObservedResult ?? "unrecorded"
            adamsProminenceSide = draft.adamsProminenceSide ?? "无"
            gaitObservedResult = draft.gaitObservedAbnormal.map { $0 ? "abnormal" : "normal" } ?? "unrecorded"
            gaitObservationNote = draft.gaitObservationNote ?? ""
            seatedMidlineText = draft.seatedMidlineDifferenceCentimeters.map { String(format: "%.1f", $0) } ?? ""
            seatedShoulderText = draft.seatedShoulderDifferenceCentimeters.map { String(format: "%.1f", $0) } ?? ""
            seatedKyphosisResult = draft.seatedThoracicKyphosisObserved.map { $0 ? "abnormal" : "normal" } ?? "unrecorded"
            thoracicAtrText = draft.thoracicAtrDegrees.map { String(format: "%.1f", $0) } ?? ""
            lumbarAtrText = draft.lumbarAtrDegrees.map { String(format: "%.1f", $0) } ?? ""
            thoracicAtrSide = draft.thoracicAtrSide ?? "无"
            lumbarAtrSide = draft.lumbarAtrSide ?? "无"
            atrRetestEnabled = draft.atrRetestEnabled
            thoracicAtrRepeatText = draft.thoracicAtrRepeatDegrees.map { String(format: "%.1f", $0) } ?? ""
            lumbarAtrRepeatText = draft.lumbarAtrRepeatDegrees.map { String(format: "%.1f", $0) } ?? ""
            seatedForwardBendAtrText = draft.seatedForwardBendAtrDegrees.map { String(format: "%.1f", $0) } ?? ""
            occiputWallDistanceText = draft.occiputWallDistanceCentimeters.map { String(format: "%.1f", $0) } ?? ""
            occiputWallDistanceText = draft.occiputWallDistanceFirstCentimeters.map { String(format: "%.1f", $0) } ?? occiputWallDistanceText
            occiputWallDistanceRepeatText = draft.occiputWallDistanceSecondCentimeters.map { String(format: "%.1f", $0) } ?? draft.occiputWallDistanceCentimeters.map { String(format: "%.1f", $0) } ?? ""
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
        let standing = record.postureReport?.snapshots[.standingBack]
        standingShoulderText = standing?.shoulderHeightDifferenceCm.map { String(format: "%.1f", $0) } ?? ""
        standingPelvisText = standing?.pelvicHeightDifferenceCm.map { String(format: "%.1f", $0) } ?? ""
        standingHeadTiltText = standing?.headTiltDegrees.map { String(format: "%.1f", $0) } ?? ""
        let forward = record.postureReport?.snapshots[.forwardBend]
        adamsObservedResult = forward?.adamsObservedResult ?? "unrecorded"
        adamsProminenceSide = forward?.adamsProminenceSide ?? "无"
        thoracicAtrText = (forward?.thoracicAtrFirstDegrees ?? forward?.thoracicAtrDegrees).map { String(format: "%.1f", $0) } ?? ""
        lumbarAtrText = (forward?.lumbarAtrFirstDegrees ?? forward?.lumbarAtrDegrees).map { String(format: "%.1f", $0) } ?? ""
        thoracicAtrSide = forward?.thoracicAtrSide ?? "无"
        lumbarAtrSide = forward?.lumbarAtrSide ?? "无"
        atrRetestEnabled = forward?.thoracicAtrSecondDegrees != nil || forward?.lumbarAtrSecondDegrees != nil
        thoracicAtrRepeatText = forward?.thoracicAtrSecondDegrees.map { String(format: "%.1f", $0) } ?? ""
        lumbarAtrRepeatText = forward?.lumbarAtrSecondDegrees.map { String(format: "%.1f", $0) } ?? ""
        seatedForwardBendAtrText = forward?.seatedForwardBendAtrDegrees.map { String(format: "%.1f", $0) } ?? ""
        let gaitSnapshot = record.postureReport?.snapshots[.gaitVideo]
        gaitObservedResult = gaitSnapshot?.gaitObservedAbnormal.map { $0 ? "abnormal" : "normal" } ?? "unrecorded"
        gaitObservationNote = gaitSnapshot?.gaitObservationNote ?? ""
        let seatedSnapshot = record.postureReport?.snapshots[.seatedPosture]
        seatedMidlineText = seatedSnapshot?.spinalMidlineDeviationCm.map { String(format: "%.1f", $0) } ?? ""
        seatedShoulderText = seatedSnapshot?.shoulderHeightDifferenceCm.map { String(format: "%.1f", $0) } ?? ""
        seatedKyphosisResult = seatedSnapshot?.seatedThoracicKyphosisObserved.map { $0 ? "abnormal" : "normal" } ?? "unrecorded"
        occiputWallDistanceText = seatedSnapshot?.occiputWallDistanceCm.map { String(format: "%.1f", $0) } ?? ""
        occiputWallDistanceRepeatText = occiputWallDistanceText
        if visualHints.isEmpty, let hint = record.visualObservationHint, let task = record.completedCaptures.first { visualHints[task] = hint }
    }
    func persistDraft() {
        guard let student, step.rawValue <= Step.confirm.rawValue else { return }
        state.saveBodyAssessmentDraft(BodyAssessmentDraft(step: step.rawValue, guardianReady: adultReady, consentAcknowledged: consentAcknowledged, environmentReady: spaceReady, heightCentimeters: height, weightKilograms: weight, completedCaptures: completedCaptures, parentMarkedAsymmetric: asymmetric, parentMarkedGaitConcern: gaitConcern, visualObservationHint: visualSummary, captureObservationHints: visualHints, fatherHeightCentimeters: fatherHeight, motherHeightCentimeters: motherHeight, postureSnapshots: postureSnapshots, standingShoulderDifferenceCentimeters: standingShoulder, standingPelvisDifferenceCentimeters: standingPelvis, standingHeadTiltDegrees: standingHeadTilt, adamsObservedResult: adamsObservedResult == "unrecorded" ? nil : adamsObservedResult, adamsProminenceSide: adamsProminenceSide == "无" ? nil : adamsProminenceSide, gaitObservedAbnormal: gaitObserved ? gaitObservedResult == "abnormal" : nil, gaitObservationNote: gaitObservationNote.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : gaitObservationNote.trimmingCharacters(in: .whitespacesAndNewlines), seatedMidlineDifferenceCentimeters: seatedMidline, seatedShoulderDifferenceCentimeters: seatedShoulder, seatedThoracicKyphosisObserved: seatedMeasured ? seatedKyphosisResult == "abnormal" : nil, thoracicAtrDegrees: thoracicAtrFirst, lumbarAtrDegrees: lumbarAtrFirst, thoracicAtrSide: thoracicAtrSide == "无" ? nil : thoracicAtrSide, lumbarAtrSide: lumbarAtrSide == "无" ? nil : lumbarAtrSide, atrRetestEnabled: atrRetestEnabled, thoracicAtrRepeatDegrees: thoracicAtrRepeat, lumbarAtrRepeatDegrees: lumbarAtrRepeat, seatedForwardBendAtrDegrees: seatedForwardBendAtr, occiputWallDistanceFirstCentimeters: occiputWallDistanceFirst, occiputWallDistanceSecondCentimeters: occiputWallDistanceSecond, occiputWallDistanceCentimeters: occiputWallDistance), for: student)
    }
    func standardizedMeasurement(_ raw: String, range: ClosedRange<Double>) -> Double? {
        let normalized = raw.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: ",", with: ".")
        guard !normalized.isEmpty, let value = Double(normalized), value.isFinite, range.contains(value) else { return nil }
        return (value * 10).rounded() / 10
    }

    func averagedATR(first: Double?, repeatValue: Double?) -> Double? {
        guard let first else { return nil }
        guard atrRetestEnabled else { return first }
        guard let repeatValue else { return nil }
        return ((first + repeatValue) / 2 * 10).rounded() / 10
    }
    func goBack() {
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
    func ruler(title: String, value: Binding<Double>, range: ClosedRange<Double>, unit: String, step: Double) -> some View {
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
                        Image(systemName: "minus").font(.subheadline.bold()).frame(width: 32, height: 32)
                    }.buttonStyle(.bordered).tint(bodyCoral).accessibilityLabel("\(title)减少")
                    TextField("输入", text: textValue)
                        .keyboardType(.decimalPad).multilineTextAlignment(.trailing)
                        .font(.title3.bold()).foregroundStyle(bodyCoral)
                        .frame(width: 72).accessibilityLabel("\(title)数值")
                    Text(unit).font(.subheadline.weight(.semibold)).foregroundStyle(bodyCoral)
                    Button { value.wrappedValue = BodyMeasurementInput.normalized((value.wrappedValue > 0 ? value.wrappedValue : range.lowerBound) + step, range: range, step: step) } label: {
                        Image(systemName: "plus").font(.subheadline.bold()).frame(width: 32, height: 32)
                    }.buttonStyle(.bordered).tint(bodyCoral).accessibilityLabel("\(title)增加")
                }
            }
            Slider(value: Binding(get: { value.wrappedValue > 0 ? value.wrappedValue : range.lowerBound }, set: { value.wrappedValue = BodyMeasurementInput.normalized($0, range: range, step: step) }), in: range, step: step).tint(bodyCoral)
            HStack(spacing: 0) {
                ForEach(0..<17, id: \.self) { _ in Rectangle().fill(bodyCoral.opacity(0.22)).frame(width: 1, height: 7); Spacer(minLength: 0) }
            }.padding(.horizontal, 4)
            HStack { Text(String(format: "%.0f", range.lowerBound)); Spacer(); Text("滑动 / 输入 / 微调"); Spacer(); Text(String(format: "%.0f", range.upperBound)) }.font(.subheadline).foregroundStyle(.secondary)
        }
        .padding(AppTheme.cardPadding)
        .background(.white, in: RoundedRectangle(cornerRadius: AppTheme.cardRadius, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: AppTheme.cardRadius, style: .continuous).stroke(AppTheme.divider.opacity(0.8), lineWidth: 0.75))
    }
    func profileDataRow(icon: String, title: String, value: String) -> some View {
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
    var environmentPreview: some View {
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
                Text("正后方约 2.5 米 · 镜头与胸椎同高")
                    .font(.system(size: AppTheme.captionSize))
                    .foregroundStyle(.white.opacity(0.76))
            }
            .foregroundStyle(.white)
        }
        .frame(height: 210)
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("标准主机位示意，正后方约二点五米，镜头与胸椎同高，孩子全身完整入镜")
    }
    func checklist(_ text: String, icon: String) -> some View {
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
    func readinessToggle(title: String, detail: String, icon: String, isOn: Binding<Bool>) -> some View {
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
        .padding(16)
        .background(AppTheme.surface, in: RoundedRectangle(cornerRadius: AppTheme.controlRadius, style: .continuous))
    }
    func confirmationToggle(title: String, detail: String, value: Binding<Bool>) -> some View {
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
