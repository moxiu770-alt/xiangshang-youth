import SwiftUI

/// Assessment flow preserves the production route boundary and keeps unfinished entries
/// recoverable before the external systems are connected.
struct AssessmentFlowView: View {
    let category: AssessmentCategory
    @EnvironmentObject private var router: AppRouter
    @EnvironmentObject private var state: AppState
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    @State private var step = 0
    @State private var completed = false
    @State private var answer = ""
    @State private var validationMessage: String?
    private var steps: [String] { switch category { case .fitness: ["基础信息", "遗传身高", "脊柱姿态", "运动表现"]; case .vision: ["基础信息", "用眼习惯", "视力筛查"]; case .oral: ["基础信息", "口腔习惯", "口腔筛查"]; case .mental: ["开始说明", "家庭感受记录", "家庭观察结果"] } }
    var body: some View { ScrollView { VStack(spacing: 14) {
        ParentPageNavigation(title: "\(category.rawValue)测评", showsBack: true)
        VStack(spacing: 8) { Image(systemName: category.icon).font(.system(size: 42, weight: .semibold)).foregroundStyle(category.color).frame(width: 78, height: 78).background(category.color.opacity(0.12), in: Circle()); Text("\(state.selectedChild?.name ?? "未选择孩子")的\(category.rawValue)测评").font(.system(size: 18, weight: .bold)); Text(category == .fitness ? "完成身高、体态与学校运动表现记录" : "请根据孩子最近情况完成本次测评") .font(.system(size: 12)).foregroundStyle(.secondary).multilineTextAlignment(.center) }.padding(.top, 14)
        HStack(spacing: 0) { ForEach(steps.indices, id: \.self) { index in VStack(spacing: 5) { Circle().fill(index <= step ? category.color : Color.gray.opacity(0.2)).frame(width: 24, height: 24).overlay { Text("\(index + 1)").font(.system(size: 12, weight: .bold)).foregroundStyle(index <= step ? .white : .secondary) }; Text(steps[index]).font(.system(size: 12)).foregroundStyle(index <= step ? category.color : .secondary).lineLimit(1) }.frame(maxWidth: .infinity); if index < steps.count - 1 { Rectangle().fill(index < step ? category.color : Color.gray.opacity(0.2)).frame(height: 2) } } }.padding(.horizontal, 14)
        ReferenceCard { VStack(alignment: .leading, spacing: 10) { Text(completed ? (category == .fitness ? "学校运动表现记录" : "家庭健康记录已保存") : steps[step]).font(.system(size: 15, weight: .bold)); Text(description).font(.system(size: 12)).foregroundStyle(.secondary); if let savedAtText { Label("最后保存：\(savedAtText)", systemImage: "clock").font(.system(size: 12)).foregroundStyle(.secondary) }; if completed { ForEach(steps.indices, id: \.self) { index in VStack(alignment: .leading, spacing: 3) { Text(steps[index]).font(.system(size: 12, weight: .semibold)).foregroundStyle(category.color); Text(archivedEntry(for: index)).font(.system(size: 12)).foregroundStyle(ReferenceColor.navy) }.frame(maxWidth: .infinity, alignment: .leading).padding(9).background(category.color.opacity(0.06), in: RoundedRectangle(cornerRadius: 8)) } } else { if category == .fitness { TextField(inputPlaceholder, text: $answer).textFieldStyle(.roundedBorder).onChange(of: answer) { _, value in state.saveDraft(value, key: draftKey) } } else { StructuredObservationStep(title: questionLabel, options: currentOptions, tint: category.color, allowsMultiple: category == .mental && step == 1, answer: $answer) { value in state.saveDraft(value, key: draftKey) } }; Label("已保存，可稍后继续。", systemImage: "internaldrive").font(.system(size: 12)).foregroundStyle(.secondary) }; if let validationMessage { Text(validationMessage).font(.system(size: 12)).foregroundStyle(.red) }; if category == .fitness && step == 3 { Label("运动发展测试由学校场地端完成，正式 7 项成绩会在上传后同步。", systemImage: "building.2.crop.circle").font(.system(size: 12)).foregroundStyle(ReferenceColor.blue).padding(9).background(ReferenceColor.sky, in: RoundedRectangle(cornerRadius: 8)) }; if completed { Label(category == .fitness ? "学校正式体测报告由场地端生成；本页不生成或替代正式 7 项成绩。" : "这是家长填写并保存在设备的家庭健康记录，不会作为学校正式测评结果同步。", systemImage: category == .fitness ? "building.2.crop.circle" : "lock.shield.fill").font(.system(size: 12)).foregroundStyle(ReferenceColor.blue).padding(9).background(ReferenceColor.sky, in: RoundedRectangle(cornerRadius: 8)) }; if category == .mental && step == 0 { Label("这是家庭感受记录，不会发起第三方授权，也不会生成心理诊断。", systemImage: "heart.text.square.fill").font(.system(size: 12)).foregroundStyle(ReferenceColor.purple).padding(9).background(ReferenceColor.purple.opacity(0.08), in: RoundedRectangle(cornerRadius: 8)) } }.padding(12) }.padding(.horizontal, 12)
        if completed, category != .fitness {
            Button { beginEditing() } label: { Label("重新填写家庭记录", systemImage: "pencil") .font(.system(size: 13, weight: .bold)).frame(maxWidth: .infinity).padding(.vertical, 11).foregroundStyle(category.color).background(category.color.opacity(0.10), in: RoundedRectangle(cornerRadius: 12)) }.buttonStyle(.plain).padding(.horizontal, 16)
        }
        if !completed, category != .fitness, hasArchivedRecord {
            Label("正在编辑新版本；完成保存前，原健康记录仍会保留。", systemImage: "checkmark.shield")
                .font(.system(size: 12)).foregroundStyle(.secondary).padding(.horizontal, 18)
            Button("取消本次编辑，保留原记录") { cancelEditing() }
                .font(.system(size: 12, weight: .semibold)).foregroundStyle(.secondary)
                .buttonStyle(.plain).padding(.horizontal, 16)
        }
        Button { submitCurrentStep() } label: { Text(completed ? "查看健康档案" : step == steps.count - 1 ? "保存健康记录" : "保存并下一步").font(.system(size: 14, weight: .bold)).frame(maxWidth: .infinity).padding(.vertical, 12).foregroundStyle(.white).background(category.color, in: RoundedRectangle(cornerRadius: 12)) }.buttonStyle(.plain).padding(.horizontal, 16)
    }.padding(.bottom, 14) }.background(ReferenceColor.canvas).task(id: "\(state.selectedChild?.id ?? "anonymous")-\(category.rawValue)") {
        // Older app versions kept only a completion marker. Without archived
        // answers it must remain an editable form, not a false saved record.
        completed = category == .fitness
            ? state.localFeatures.completedAssessments.contains(completionKey)
            : hasArchivedRecord
        if let savedStep = Int(state.localFeatures.drafts[progressKey] ?? "") {
            step = min(max(savedStep, 0), steps.count - 1)
        }
        answer = state.localFeatures.drafts[draftKey] ?? ""
        // Remote mode must refresh the selected child's structured record when
        // this page is opened directly, not only when the child picker changes.
        // Never fall back to another child's cached record while the request is
        // in flight; the selected child ID remains part of every lookup key.
        if category != .fitness, state.usesRemoteDataSource, let child = state.selectedChild {
            await state.loadFamilyHealthObservations(for: child)
            completed = state.familyHealthRecord(for: child, category: category) != nil
            answer = state.localFeatures.drafts[draftKey] ?? ""
        }
    } .onChange(of: step) { _, value in
        state.saveDraft(String(value), key: progressKey)
        answer = state.localFeatures.drafts[draftKey] ?? ""
        validationMessage = nil
    } .overlay {
        if let error = state.error, state.data == nil { ErrorStateView(message: error) { Task { await state.refreshDashboard() } }.frame(maxWidth: .infinity, maxHeight: .infinity).background(ReferenceColor.canvas) }
        else if state.loading || state.data == nil { ZStack { ReferenceColor.canvas.ignoresSafeArea(); LoadingStateView() } }
        else if state.selectedChild == nil { ParentBindingPrompt() }
    } }
    private var description: String { if completed { return category == .fitness ? "本页只记录学校运动表现信息；正式 7 项体测成绩仍以场地端报告为准。" : "本次家庭健康记录已保存到健康档案，不会作为学校正式测评结果同步。" }; switch category { case .fitness: return ["确认孩子的出生日期、当前身高和体重。", "填写父母身高，系统会计算遗传身高区间。", "按引导上传或记录站立姿态筛查结果。", "选择学校测试完成情况，或暂时跳过等待场地端回传。"][step]; case .vision: return "填写用眼习惯并进行视力筛查结果确认。"; case .oral: return "填写刷牙习惯并确认近期口腔筛查结果。"; case .mental: return ["请由家长陪同完成。这是家庭观察记录，不会发起第三方授权，也不会生成心理诊断。", "记录孩子最近一周的情绪、睡眠或同伴互动感受；请避免填写不必要的敏感隐私。", "保存后可在健康档案查看。若持续担忧，请联系学校心理老师或医疗专业人员。"][step] } }
    private var draftKey: String { "assessment-\(state.selectedChild?.id ?? "anonymous")-\(category.rawValue)-\(step)" }
    private func archiveKey(for step: Int) -> String { "assessment-\(state.selectedChild?.id ?? "anonymous")-\(category.rawValue)-\(step)" }
    private func archivedEntry(for index: Int) -> String {
        if let child = state.selectedChild,
           let saved = state.familyHealthRecord(for: child, category: category)?.entries[steps[index]]?.trimmingCharacters(in: .whitespacesAndNewlines),
           !saved.isEmpty { return saved }
        return state.localFeatures.drafts[archiveKey(for: index)]?.trimmingCharacters(in: .whitespacesAndNewlines).nonEmpty ?? "未填写"
    }
    private var progressKey: String { "assessment-progress-\(state.selectedChild?.id ?? "anonymous")-\(category.rawValue)" }
    private var completionKey: String { "\(state.selectedChild?.id ?? "anonymous")-\(category.rawValue)" }
    private var hasArchivedRecord: Bool {
        guard let child = state.selectedChild else { return false }
        return state.familyHealthRecord(for: child, category: category) != nil
    }
    private var savedAtText: String? {
        guard let child = state.selectedChild, let date = state.familyHealthRecord(for: child, category: category)?.completedAt else { return nil }
        return Self.savedAtFormatter.string(from: date)
    }
    private static let savedAtFormatter: DateFormatter = { let formatter = DateFormatter(); formatter.locale = Locale(identifier: "zh_CN"); formatter.dateFormat = "yyyy年M月d日 HH:mm"; return formatter }()
    private var reduceMotion: Bool { state.localFeatures.settings.reduceMotion || systemReduceMotion }
    private var inputPlaceholder: String { switch category { case .fitness: return ["例如：身高132cm，体重30kg", "例如：父亲175cm，母亲162cm", "例如：站姿筛查正常", "例如：学校场地端待回传"][step]; case .vision: return "例如：每日屏幕使用不超过1小时"; case .oral: return "例如：每日早晚刷牙，近期无牙痛"; case .mental: return ["例如：已阅读家庭观察说明", "例如：近一周睡眠规律，愿意参加课间活动", "例如：暂未发现持续困扰；如有需要会联系老师"][step] } }
    private var questionLabel: String { switch category { case .vision: return step == 1 ? "用眼频率（可补充说明）" : "视力观察情况"; case .oral: return step == 1 ? "口腔习惯频率（可补充说明）" : "口腔观察情况"; case .mental: return step == 1 ? "近一周家庭感受（可多选）" : "需要关注的程度"; default: return inputPlaceholder } }
    private var currentOptions: [String] {
        switch category {
        case .fitness: return []
        case .vision:
            return step == 0 ? ["孩子资料已确认", "需要补充观察"] : step == 1 ? ["很少超过30分钟", "每天1小时左右", "每天2小时以上", "经常近距离用眼"] : ["未发现明显异常", "偶尔眯眼/揉眼", "经常看不清", "已建议线下检查"]
        case .oral:
            return step == 0 ? ["孩子资料已确认", "需要补充观察"] : step == 1 ? ["早晚刷牙", "每天一次", "偶尔漏刷", "需家长提醒"] : ["未发现明显不适", "偶尔牙龈出血", "近期牙痛/龋齿", "已建议线下检查"]
        case .mental:
            return step == 0 ? ["已阅读说明", "稍后再填写"] : step == 1 ? ["睡眠和情绪稳定", "偶尔低落/烦躁", "近期压力较明显", "需与老师沟通"] : ["未发现持续困扰", "需要继续观察", "希望老师关注", "建议寻求专业支持"]
        }
    }
    private func beginEditing() {
        guard let child = state.selectedChild else { return }
        let saved = state.familyHealthRecord(for: child, category: category)?.entries ?? [:]
        for index in steps.indices { state.saveDraft(saved[steps[index]] ?? archivedEntry(for: index), key: archiveKey(for: index)) }
        step = 0
        completed = false
        answer = state.localFeatures.drafts[archiveKey(for: 0)] ?? ""
        validationMessage = nil
    }
    private func cancelEditing() {
        for index in steps.indices { state.clearDraft(archiveKey(for: index)) }
        state.clearDraft(progressKey)
        step = 0
        answer = ""
        validationMessage = nil
        completed = true
    }
    private func submitCurrentStep() { guard completed || !answer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { validationMessage = "请选择或填写本步骤信息后再继续。"; return }; if completed { router.push(.healthProfile); return }; if step < steps.count - 1 { if reduceMotion { var transaction = Transaction(); transaction.animation = nil; withTransaction(transaction) { step += 1 } } else { withAnimation { step += 1 } } } else { var entries = Dictionary(uniqueKeysWithValues: steps.indices.map { (steps[$0], state.localFeatures.drafts[archiveKey(for: $0)]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "") }); if category != .fitness { entries["频率"] = entries[steps[min(1, steps.count - 1)]]; entries["严重程度"] = entries[steps[min(2, steps.count - 1)]] }; state.clearDraft(progressKey); completed = true; state.completeAssessment(category, entries: entries) } }
}

private extension String {
    var nonEmpty: String? { isEmpty ? nil : self }
}

private struct StructuredObservationStep: View {
    let title: String
    let options: [String]
    let tint: Color
    let allowsMultiple: Bool
    @Binding var answer: String
    let onChange: (String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.system(size: 12, weight: .semibold)).foregroundStyle(.secondary)
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 128), spacing: 8)], alignment: .leading, spacing: 8) {
                ForEach(options, id: \.self) { option in
                    Button {
                        let note = answer.split(separator: "｜", maxSplits: 1).dropFirst().first.map(String.init)
                        let current = answer.split(separator: "｜", maxSplits: 1).first.map(String.init) ?? ""
                        let values = current.split(whereSeparator: { $0 == "、" || $0 == "," || $0 == "，" }).map(String.init)
                        let next = allowsMultiple
                            ? (values.contains(option) ? values.filter { $0 != option } : values + [option])
                            : [option]
                        let selection = next.joined(separator: "、")
                        answer = note?.isEmpty == false ? "\(selection)｜\(note!)" : selection
                        onChange(answer)
                    } label: {
                        Text(option)
                            .font(.system(size: 13, weight: .semibold))
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.vertical, 10)
                            .padding(.horizontal, 11)
                            .foregroundStyle(answer.split(separator: "｜", maxSplits: 1).first?.split(whereSeparator: { $0 == "、" || $0 == "," || $0 == "，" }).contains(Substring(option)) == true ? .white : ReferenceColor.navy)
                            .background(answer.split(separator: "｜", maxSplits: 1).first?.split(whereSeparator: { $0 == "、" || $0 == "," || $0 == "，" }).contains(Substring(option)) == true ? tint : ReferenceColor.canvas, in: RoundedRectangle(cornerRadius: 11))
                    }
                    .buttonStyle(.plain)
                    .frame(minHeight: 44)
                    .accessibilityLabel("选择\(option)")
                }
            }
            TextField("补充说明（选填）", text: Binding(
                get: { answer.contains("｜") ? String(answer.split(separator: "｜", maxSplits: 1).last ?? "") : "" },
                set: { note in
                    let selected = answer.split(separator: "｜", maxSplits: 1).first.map(String.init) ?? answer
                    let value = note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? selected : "\(selected)｜\(note)"
                    answer = value
                    onChange(value)
                }
            ))
            .textFieldStyle(.roundedBorder)
        }
    }
}
