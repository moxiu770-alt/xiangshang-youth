import SwiftUI
import UIKit
import UniformTypeIdentifiers

/// The family-side assessment intentionally stores only the parent's confirmed
/// observations and completed tasks.  Captured photos/videos stay in the
/// system picker and are never uploaded or retained by this app at this stage.
struct BodyAssessmentView: View {
    private enum Step: Int, CaseIterable { case overview, bmi, capture, confirm, result, plan }

    @EnvironmentObject private var state: AppState
    @EnvironmentObject private var router: AppRouter
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var step: Step = .overview
    @State private var height = 132.0
    @State private var weight = 30.0
    @State private var completedCaptures = Set<BodyAssessmentRecord.CaptureTask>()
    @State private var asymmetric = false
    @State private var gaitConcern = false
    @State private var activeCameraTask: BodyAssessmentRecord.CaptureTask?
    @State private var didLoad = false

    private var student: Student? { state.selectedChild }
    private var provisionalRecord: BodyAssessmentRecord {
        BodyAssessmentRecord(
            heightCentimeters: height,
            weightKilograms: weight,
            measuredAt: .now,
            ruleVersion: BodyAssessmentRecord.ruleVersion,
            completedCaptures: completedCaptures,
            parentMarkedAsymmetric: asymmetric,
            parentMarkedGaitConcern: gaitConcern,
            savedAt: .now,
            nextFollowUpDate: followUpDate,
            completedPlanDays: state.bodyAssessment(for: student ?? fallbackStudent)?.completedPlanDays ?? []
        )
    }
    private var fallbackStudent: Student { Student(id: "body-assessment-preview", name: "孩子", gender: "男", grade: "三年级", className: "三年级1班", region: "", isPovertyArea: false, taskStatus: .completed, totalScore: nil) }
    private var followUpDate: Date {
        let level = provisionalBMILevel
        let days = level == .red ? 7 : level == .yellow || asymmetric || gaitConcern ? 30 : 90
        return Calendar.current.date(byAdding: .day, value: days, to: .now) ?? .now
    }
    private var provisionalBMILevel: BodyAssessmentRecord.AttentionLevel {
        let bmi = weight / pow(height / 100, 2)
        return BodyAssessmentRecord(heightCentimeters: height, weightKilograms: weight, measuredAt: .now, ruleVersion: BodyAssessmentRecord.ruleVersion, completedCaptures: [], parentMarkedAsymmetric: false, parentMarkedGaitConcern: false, savedAt: .now, nextFollowUpDate: .now, completedPlanDays: []).bmiAttention(age: student?.bodyAssessmentAge ?? 9, gender: student?.gender ?? "男")
    }
    private var record: BodyAssessmentRecord? { student.flatMap(state.bodyAssessment(for:)) }

    var body: some View {
        Group {
            if let student {
                AppScaffold(title: stepTitle) {
                    VStack(spacing: 16) {
                        progress
                        switch step {
                        case .overview: overview(student)
                        case .bmi: bmiEntry(student)
                        case .capture: captureGuide
                        case .confirm: observationConfirm
                        case .result: result(student)
                        case .plan: plan(student)
                        }
                    }
                    .padding(.top, 12)
                }
                .task { load(record: state.bodyAssessment(for: student)) }
            } else {
                ParentBindingPrompt()
            }
        }
        .sheet(item: $activeCameraTask) { task in
            VisionCapturePicker(task: task) {
                completedCaptures.insert(task)
                activeCameraTask = nil
            }
            .ignoresSafeArea()
        }
    }

    private var stepTitle: String {
        switch step {
        case .overview: "身体测评"
        case .bmi: "身高体重录入"
        case .capture: "视觉引导采集"
        case .confirm: "家长确认"
        case .result: "身体测评结果"
        case .plan: "28 天健康计划"
        }
    }

    private var progress: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack { Text("家庭身体测评").font(.headline).foregroundStyle(ReferenceColor.navy); Spacer(); Text("\(min(step.rawValue + 1, 4)) / 4").font(.caption.weight(.bold)).foregroundStyle(ReferenceColor.blue) }
            ProgressView(value: Double(min(step.rawValue + 1, 4)), total: 4).tint(bodyCoral)
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
                HStack(spacing: 8) { overviewPill("手机摄像头", "camera.fill"); overviewPill("仅本机确认", "lock.fill"); overviewPill("非医学诊断", "heart.text.square") }
            }
            .padding(16).background(bodyCream, in: RoundedRectangle(cornerRadius: 20))

            if let record {
                ReferenceCard {
                    VStack(alignment: .leading, spacing: 9) {
                        Text("最近一次记录").font(.headline).foregroundStyle(ReferenceColor.navy)
                        HStack { Label(String(format: "BMI %.1f", record.bmi), systemImage: "scalemass.fill"); Spacer(); attentionBadge(record.attention(age: student.bodyAssessmentAge, gender: student.gender)) }
                        Text("测评于 \(dateText(record.measuredAt)) · 已完成 \(record.completedCaptures.count) 项视觉任务")
                            .font(.caption).foregroundStyle(.secondary)
                        Button("查看结果与计划") { move(to: .result) }.buttonStyle(.bordered).tint(ReferenceColor.blue)
                    }
                }
            }

            VStack(alignment: .leading, spacing: 10) {
                Label("开始前请确认", systemImage: "checkmark.shield.fill").font(.headline).foregroundStyle(ReferenceColor.navy)
                checklist("请让孩子穿着贴身、便于观察的衣物。")
                checklist("由成人在明亮、无障碍的空间协助拍摄。")
                checklist("孩子不适、疼痛或家长担忧时立即停止，必要时咨询专业人员。")
            }.padding(14).background(.white, in: RoundedRectangle(cornerRadius: 16))

            primaryButton("开始身体测评", icon: "arrow.right") { move(to: .bmi) }
        }
    }

    private func bmiEntry(_ student: Student) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("身高体重").font(.title3.bold()).foregroundStyle(ReferenceColor.navy)
            Text("按当前实测数据填写。BMI 将按 \(student.gender)、约 \(student.bodyAssessmentAge) 岁的年龄别参考进行关注分级，不采用成人 BMI 阈值。")
                .font(.subheadline).foregroundStyle(.secondary)
            ruler(title: "身高", value: $height, range: 90...190, unit: "cm", step: 0.5)
            ruler(title: "体重", value: $weight, range: 15...90, unit: "kg", step: 0.1)
            ReferenceCard {
                HStack {
                    VStack(alignment: .leading, spacing: 4) { Text("当前 BMI").font(.caption).foregroundStyle(.secondary); Text(String(format: "%.1f", provisionalRecord.bmi)).font(.system(size: 32, weight: .bold)).foregroundStyle(bodyCoral) }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 5) { attentionBadge(provisionalBMILevel); Text(BodyAssessmentRecord.ruleVersion).font(.caption2).foregroundStyle(.secondary).multilineTextAlignment(.trailing) }
                }
            }
            primaryButton("继续视觉采集", icon: "camera.fill") { move(to: .capture) }
        }
    }

    private var captureGuide: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("手机视觉引导").font(.title3.bold()).foregroundStyle(ReferenceColor.navy)
            Text("逐项打开手机相机。照片或视频不会保存到本地档案；完成情况仅用于生成本次家庭观察结果。")
                .font(.subheadline).foregroundStyle(.secondary)
            ForEach(BodyAssessmentRecord.CaptureTask.allCases) { task in
                Button { activeCameraTask = task } label: {
                    HStack(spacing: 13) {
                        Image(systemName: task == .gaitVideo ? "video.fill" : "viewfinder").font(.title3).foregroundStyle(completedCaptures.contains(task) ? ReferenceColor.green : bodyCoral).frame(width: 42, height: 42).background((completedCaptures.contains(task) ? ReferenceColor.green : bodyCoral).opacity(0.12), in: RoundedRectangle(cornerRadius: 12))
                        VStack(alignment: .leading, spacing: 4) { Text(task.title).font(.headline).foregroundStyle(ReferenceColor.navy); Text(task.instruction).font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.leading) }
                        Spacer()
                        Image(systemName: completedCaptures.contains(task) ? "checkmark.seal.fill" : "camera.fill").foregroundStyle(completedCaptures.contains(task) ? ReferenceColor.green : ReferenceColor.blue)
                    }
                    .padding(13).background(.white, in: RoundedRectangle(cornerRadius: 16)).overlay(RoundedRectangle(cornerRadius: 16).stroke(completedCaptures.contains(task) ? ReferenceColor.green.opacity(0.35) : ReferenceColor.blue.opacity(0.12), lineWidth: 1))
                }.buttonStyle(.plain).accessibilityLabel("\(task.title)，\(completedCaptures.contains(task) ? "已完成" : "打开相机")")
            }
            Text("模拟器中会自动改用相册，以便完整体验流程。真机将请求相机权限。")
                .font(.caption2).foregroundStyle(.secondary)
            primaryButton(completedCaptures.isEmpty ? "完成至少一项后继续" : "继续家长确认", icon: "arrow.right") { move(to: .confirm) }
                .opacity(completedCaptures.isEmpty ? 0.55 : 1)
                .disabled(completedCaptures.isEmpty)
        }
    }

    private var observationConfirm: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("请由家长确认观察结果").font(.title3.bold()).foregroundStyle(ReferenceColor.navy)
            Text("算法只提供拍摄与对齐提示；以下结论必须由陪同家长确认。若持续存在不对称、疼痛或活动受限，请不要自行判断。")
                .font(.subheadline).foregroundStyle(.secondary)
            confirmationToggle(title: "我观察到肩部、背部或骨盆有持续明显不对称", detail: "勾选后将提示 30 天内复测或咨询专业人员。", value: $asymmetric)
            confirmationToggle(title: "我观察到走路时持续偏移、跛行或左右明显不同", detail: "勾选后将作为步态关注信号。", value: $gaitConcern)
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
        let level = activeRecord.attention(age: student.bodyAssessmentAge, gender: student.gender)
        return VStack(alignment: .leading, spacing: 14) {
            HStack { VStack(alignment: .leading, spacing: 5) { Text("\(student.name) 的家庭观察").font(.title3.bold()).foregroundStyle(ReferenceColor.navy); Text("\(dateText(activeRecord.measuredAt)) · \(activeRecord.ruleVersion)").font(.caption).foregroundStyle(.secondary) }; Spacer(); attentionBadge(level) }
            ReferenceCard {
                VStack(alignment: .leading, spacing: 10) {
                    HStack { Text(String(format: "BMI %.1f", activeRecord.bmi)).font(.title2.bold()).foregroundStyle(bodyCoral); Spacer(); Text("\(String(format: "%.1f", activeRecord.heightCentimeters)) cm · \(String(format: "%.1f", activeRecord.weightKilograms)) kg").font(.caption).foregroundStyle(.secondary) }
                    bmiTrend(record: activeRecord)
                }
            }
            ForEach(activeRecord.observations(age: student.bodyAssessmentAge, gender: student.gender)) { item in
                HStack(spacing: 12) { Image(systemName: icon(for: item.level)).foregroundStyle(color(for: item.level)).frame(width: 24); VStack(alignment: .leading, spacing: 3) { Text(item.title).font(.subheadline.bold()).foregroundStyle(ReferenceColor.navy); Text(item.detail).font(.caption).foregroundStyle(.secondary) }; Spacer(); attentionBadge(item.level) }
                    .padding(12).background(.white, in: RoundedRectangle(cornerRadius: 14))
            }
            ReferenceCard { HStack { Image(systemName: "calendar.badge.clock").foregroundStyle(bodyCoral); VStack(alignment: .leading) { Text("下次建议复测").font(.subheadline.bold()); Text(dateText(activeRecord.nextFollowUpDate)).font(.caption).foregroundStyle(.secondary) }; Spacer() } }
            primaryButton("开始 28 天健康计划", icon: "figure.walk") { move(to: .plan) }
            Button("查看推荐课程") { router.push(.parentCourses) }.frame(maxWidth: .infinity).buttonStyle(.bordered).tint(ReferenceColor.blue)
        }
    }

    private func plan(_ student: Student) -> some View {
        let activeRecord = record ?? provisionalRecord
        let calendar = Calendar.current
        let days = (0..<7).compactMap { calendar.date(byAdding: .day, value: $0, to: calendar.startOfDay(for: .now)) }
        return VStack(alignment: .leading, spacing: 14) {
            Text("28 天轻量姿态与健康习惯计划").font(.title3.bold()).foregroundStyle(ReferenceColor.navy)
            Text("每天 10 分钟：站姿觉察、肩背活动、平衡行走与规律作息。完成后可随时修改。") .font(.subheadline).foregroundStyle(.secondary)
            ReferenceCard { HStack { VStack(alignment: .leading) { Text("已完成 \(activeRecord.completedPlanDays.count) / 28 天").font(.headline); Text("计划会同步到孩子的健康档案与提醒中心。") .font(.caption).foregroundStyle(.secondary) }; Spacer(); Image(systemName: "chart.line.uptrend.xyaxis").font(.title2).foregroundStyle(ReferenceColor.green) } }
            ForEach(Array(days.enumerated()), id: \.offset) { index, day in
                let key = dayKey(day)
                let done = activeRecord.completedPlanDays.contains(key)
                Button {
                    state.toggleBodyPlanDay(day, for: student)
                } label: {
                    HStack { Image(systemName: done ? "checkmark.circle.fill" : "circle").foregroundStyle(done ? ReferenceColor.green : .secondary); VStack(alignment: .leading) { Text("第 \(activeRecord.completedPlanDays.count + index + 1) 天 · \(weekday(day))").font(.subheadline.bold()).foregroundStyle(ReferenceColor.navy); Text(planText(for: index)).font(.caption).foregroundStyle(.secondary) }; Spacer(); Text(done ? "已完成" : "去完成").font(.caption.weight(.semibold)).foregroundStyle(done ? ReferenceColor.green : ReferenceColor.blue) }
                    .padding(13).background(.white, in: RoundedRectangle(cornerRadius: 14))
                }.buttonStyle(.plain)
            }
            Button("返回孩子健康档案") { router.push(.healthProfile) }.frame(maxWidth: .infinity).buttonStyle(.bordered).tint(ReferenceColor.blue)
        }
    }

    private func load(record: BodyAssessmentRecord?) {
        guard !didLoad else { return }; didLoad = true
        guard let record else { return }
        height = record.heightCentimeters; weight = record.weightKilograms; completedCaptures = record.completedCaptures
        asymmetric = record.parentMarkedAsymmetric; gaitConcern = record.parentMarkedGaitConcern
    }
    private func move(to next: Step) { if reduceMotion { var transaction = Transaction(); transaction.animation = nil; withTransaction(transaction) { step = next } } else { withAnimation(.easeInOut(duration: 0.22)) { step = next } } }
    private func ruler(title: String, value: Binding<Double>, range: ClosedRange<Double>, unit: String, step: Double) -> some View { VStack(alignment: .leading, spacing: 10) { HStack { Text(title).font(.headline).foregroundStyle(ReferenceColor.navy); Spacer(); Text(String(format: unit == "cm" ? "%.1f %@" : "%.1f %@", value.wrappedValue, unit)).font(.title2.bold()).foregroundStyle(bodyCoral) }; Slider(value: value, in: range, step: step).tint(bodyCoral); HStack { Text(String(format: "%.0f", range.lowerBound)); Spacer(); Text("滑动刻度调整"); Spacer(); Text(String(format: "%.0f", range.upperBound)) }.font(.caption2).foregroundStyle(.secondary) }.padding(14).background(.white, in: RoundedRectangle(cornerRadius: 16)) }
    private func overviewPill(_ title: String, _ icon: String) -> some View { Label(title, systemImage: icon).font(.caption2.weight(.medium)).foregroundStyle(ReferenceColor.navy).padding(.horizontal, 8).padding(.vertical, 6).background(.white.opacity(0.72), in: Capsule()) }
    private func checklist(_ text: String) -> some View { Label(text, systemImage: "checkmark.circle.fill").font(.caption).foregroundStyle(.secondary).labelStyle(.titleAndIcon) }
    private func confirmationToggle(title: String, detail: String, value: Binding<Bool>) -> some View { Toggle(isOn: value) { VStack(alignment: .leading, spacing: 4) { Text(title).font(.subheadline.bold()).foregroundStyle(ReferenceColor.navy); Text(detail).font(.caption).foregroundStyle(.secondary) } }.tint(bodyCoral).padding(14).background(.white, in: RoundedRectangle(cornerRadius: 16)) }
    private func attentionBadge(_ level: BodyAssessmentRecord.AttentionLevel) -> some View { Text(level.label).font(.caption.weight(.bold)).foregroundStyle(color(for: level)).padding(.horizontal, 8).padding(.vertical, 5).background(color(for: level).opacity(0.12), in: Capsule()) }
    private func color(for level: BodyAssessmentRecord.AttentionLevel) -> Color { switch level { case .green: ReferenceColor.green; case .yellow: .orange; case .red: .red } }
    private func icon(for level: BodyAssessmentRecord.AttentionLevel) -> String { switch level { case .green: "checkmark.shield.fill"; case .yellow: "exclamationmark.triangle.fill"; case .red: "exclamationmark.shield.fill" } }
    private func primaryButton(_ title: String, icon: String, action: @escaping () -> Void) -> some View { Button(action: action) { Label(title, systemImage: icon).font(.headline).frame(maxWidth: .infinity).padding(.vertical, 14).background(bodyCoral, in: Capsule()).foregroundStyle(.white) }.buttonStyle(.plain) }
    private func bmiTrend(record: BodyAssessmentRecord) -> some View { VStack(alignment: .leading, spacing: 7) { Text("BMI 趋势（本机家庭记录）").font(.caption.weight(.semibold)).foregroundStyle(.secondary); HStack(alignment: .bottom, spacing: 10) { trendBar("上次", max(record.bmi - 0.4, 1), record.bmi); trendBar("本次", record.bmi, record.bmi); trendBar("目标", max(record.bmi - 0.2, 1), record.bmi) } } }
    private func trendBar(_ label: String, _ value: Double, _ maxValue: Double) -> some View { VStack(spacing: 4) { Text(String(format: "%.1f", value)).font(.caption2.bold()).foregroundStyle(ReferenceColor.navy); Capsule().fill(bodyCoral.opacity(0.18)).frame(width: 48, height: 44).overlay(alignment: .bottom) { Capsule().fill(label == "本次" ? bodyCoral : ReferenceColor.blue).frame(width: 48, height: max(10, 44 * value / max(maxValue, 1))) }; Text(label).font(.caption2).foregroundStyle(.secondary) } }
    private func dateText(_ date: Date) -> String { Self.dateFormatter.string(from: date) }
    private func dayKey(_ date: Date) -> String { Self.dayFormatter.string(from: date) }
    private func weekday(_ date: Date) -> String { Self.weekdayFormatter.string(from: date) }
    private func planText(for index: Int) -> String { ["站姿觉察 2 分钟 + 肩背舒展", "平衡行走 3 分钟 + 规律饮水", "墙面天使 10 次 + 坐姿整理", "亲子步行 10 分钟", "轻松拉伸 + 早睡提醒", "户外自然行走 15 分钟", "本周复盘，记录身体感受"][index] }
    private static let dateFormatter: DateFormatter = { let f = DateFormatter(); f.locale = Locale(identifier: "zh_CN"); f.dateFormat = "yyyy年M月d日"; return f }()
    private static let dayFormatter: DateFormatter = { let f = DateFormatter(); f.locale = Locale(identifier: "zh_CN"); f.dateFormat = "yyyy-MM-dd"; return f }()
    private static let weekdayFormatter: DateFormatter = { let f = DateFormatter(); f.locale = Locale(identifier: "zh_CN"); f.dateFormat = "EEEE"; return f }()
    private let bodyCoral = Color(red: 0.96, green: 0.48, blue: 0.35)
    private let bodyCream = Color(red: 1.0, green: 0.94, blue: 0.80)
}

private struct VisionCapturePicker: UIViewControllerRepresentable {
    let task: BodyAssessmentRecord.CaptureTask
    let completed: () -> Void

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.delegate = context.coordinator
        picker.allowsEditing = false
        picker.sourceType = UIImagePickerController.isSourceTypeAvailable(.camera) ? .camera : .photoLibrary
        if task == .gaitVideo {
            picker.mediaTypes = [UTType.movie.identifier]
            if picker.sourceType == .camera { picker.cameraCaptureMode = .video }
        } else { picker.mediaTypes = [UTType.image.identifier] }
        return picker
    }
    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}
    func makeCoordinator() -> Coordinator { Coordinator(completed: completed) }
    final class Coordinator: NSObject, UINavigationControllerDelegate, UIImagePickerControllerDelegate {
        private let completed: () -> Void
        init(completed: @escaping () -> Void) { self.completed = completed }
        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) { picker.dismiss(animated: true) }
        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey : Any]) {
            let didCapture = info[.originalImage] != nil || info[.mediaURL] != nil
            picker.dismiss(animated: true) { if didCapture { self.completed() } }
        }
    }
}
