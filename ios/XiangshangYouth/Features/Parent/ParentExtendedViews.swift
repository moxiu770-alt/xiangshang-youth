import SwiftUI
import UIKit
import AVKit
import PhotosUI
import UniformTypeIdentifiers

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

struct ParentCourseTeaser: View {
    let image: String; let title: String
    @State private var isPresented = false
    var body: some View { Button { isPresented = true } label: { VStack(alignment: .leading, spacing: 5) { Image(image).resizable().scaledToFill().frame(height: 52).frame(maxWidth: .infinity).clipped(); Text(title).font(.system(size: 12, weight: .bold)).foregroundStyle(ReferenceColor.navy).lineLimit(2); Text("免费学习 ›").font(.system(size: 12)).foregroundStyle(ReferenceColor.green) }.padding(6).background(.white, in: RoundedRectangle(cornerRadius: 12)) }.buttonStyle(.plain).sheet(isPresented: $isPresented) { CourseDetailSheet(title: title) } }
}

struct ParentArticleRow: View {
    let title: String; let detail: String
    @State private var isPresented = false
    var body: some View { Button { isPresented = true } label: { HStack { Image(systemName: "book.closed.fill").foregroundStyle(ReferenceColor.green).frame(width: 34, height: 34).background(ReferenceColor.green.opacity(0.10), in: RoundedRectangle(cornerRadius: 9)); VStack(alignment: .leading, spacing: 3) { Text(title).font(.system(size: 12, weight: .bold)); Text(detail).font(.system(size: 12)).foregroundStyle(.secondary) }; Spacer(); Image(systemName: "chevron.right").font(.system(size: 12)).foregroundStyle(.secondary) }.foregroundStyle(ReferenceColor.navy).padding(10).background(.white, in: RoundedRectangle(cornerRadius: 10)) }.buttonStyle(.plain).sheet(isPresented: $isPresented) { HealthArticleSheet(title: title) } }
}

/// The two missing parent tabs from the supplied information architecture.
/// All cards are actionable and can switch to the remote source without changing the route contract.
struct ParentCoursesDashboard: View {
    @EnvironmentObject private var state: AppState
    @State private var selectedKind = 0
    @State private var selectedCourse: String?
    @State private var selectedRemoteCourse: RemoteLesson?
    @State private var catalogShown = false
    @State private var loadedCourseChildID: String?
    @State private var recommendationMessage: String?
    private let publicCourses = [("figure.run", "体质成长课", ReferenceColor.blue), ("eye.fill", "视力守护课", ReferenceColor.green), ("mouth.fill", "口腔健康课", ReferenceColor.purple), ("brain.head.profile", "心理舒展课", ReferenceColor.pink)]
    private let schoolCourses = [("figure.run", "校内体能提升课", ReferenceColor.blue), ("eye.fill", "校园视力守护课", ReferenceColor.green), ("figure.strengthtraining.traditional", "课后运动巩固课", ReferenceColor.purple), ("person.3.fill", "亲子运动指导课", ReferenceColor.pink)]

    var body: some View {
        ScrollView {
            VStack(spacing: 10) {
                ParentPageNavigation(title: "我的课程", showsBell: false)
                ReferenceHeader(name: state.selectedChild?.name ?? "未选择孩子", school: "\(state.selectedChild?.className ?? "尚未绑定班级") · 成长课程", initial: String((state.selectedChild?.name ?? "孩").prefix(1)), avatarAsset: "ChildAvatar")
                Picker("课程类型", selection: $selectedKind) { Text("公益课程").tag(0); Text("学校课程").tag(1) }
                    .pickerStyle(.segmented).padding(.horizontal, 12)
                ReferenceSectionTitle(title: selectedKind == 0 ? "公益课堂" : "精选学校课程", trailing: "全部课程", action: { catalogShown = true }).padding(.horizontal, 12)
                if state.usesRemoteDataSource {
                    if state.coursesLoading { LoadingStateView() }
                    else if let error = state.coursesError { ErrorStateView(message: error) { if let child = state.selectedChild { Task { await state.loadCourses(for: child) } } } }
                    else if state.remoteCourses.isEmpty { EmptyStateView(title: "暂无已分配课程", detail: "学校或平台分配课程后会显示在这里。") }
                    else { LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) { ForEach(state.remoteCourses.filter { selectedKind == 0 ? $0.videoSource != nil : true }, id: \.lessonID) { course in
                        Button { selectedRemoteCourse = course } label: { VStack(alignment: .leading, spacing: 7) { Image(systemName: "play.circle.fill").font(.system(size: 23, weight: .semibold)).foregroundStyle(ReferenceColor.blue); Text(course.title).font(.system(size: 13, weight: .bold)).foregroundStyle(ReferenceColor.navy).lineLimit(2); Text(course.completed ? "已完成" : course.lastPositionMs > 0 ? "继续学习" : "开始学习").font(.system(size: 12)).foregroundStyle(ReferenceColor.green) }.frame(maxWidth: .infinity, alignment: .leading).padding(12).background(ReferenceColor.blue.opacity(0.08), in: RoundedRectangle(cornerRadius: 11)) }.buttonStyle(.plain) } }.padding(.horizontal, 12) }
                } else { LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                    ForEach(selectedKind == 0 ? publicCourses : schoolCourses, id: \.1) { icon, title, color in
                        Button { selectedCourse = title } label: {
                            VStack(alignment: .leading, spacing: 7) {
                                Image(systemName: icon).font(.system(size: 23, weight: .semibold)).foregroundStyle(color)
                                Text(title).font(.system(size: 13, weight: .bold)).foregroundStyle(ReferenceColor.navy).lineLimit(1)
                                Text(selectedKind == 0 ? "公益 · 立即学习" : "校内课程 · 查看课程").font(.system(size: 12)).foregroundStyle(color)
                            }.frame(maxWidth: .infinity, alignment: .leading).padding(12)
                                .background(color.opacity(0.08), in: RoundedRectangle(cornerRadius: 11))
                        }.buttonStyle(.plain)
                    }
                }.padding(.horizontal, 12) }
                Button { selectedCourse = "客服咨询" } label: {
                    HStack { Image(systemName: "message.fill"); VStack(alignment: .leading) { Text("课程咨询").font(.system(size: 12, weight: .bold)); Text("填写后自动保存并同步").font(.system(size: 12)) }; Spacer(); Image(systemName: "chevron.right") }
                        .foregroundStyle(ReferenceColor.blue).padding(12).background(.white, in: RoundedRectangle(cornerRadius: 10))
                }.buttonStyle(.plain).padding(.horizontal, 12)
            }.padding(.bottom, 10)
        }.background(ReferenceColor.canvas)
        .task {
            if state.usesRemoteDataSource { await state.loadClassPosts() }
        }
        .overlay {
            if let error = state.error, state.data == nil { ErrorStateView(message: error) { Task { await state.refreshDashboard() } }.frame(maxWidth: .infinity, maxHeight: .infinity).background(ReferenceColor.canvas) }
            else if state.loading || state.data == nil { ZStack { ReferenceColor.canvas.ignoresSafeArea(); LoadingStateView() } }
            else if state.selectedChild == nil { ParentBindingPrompt() }
        }
        .sheet(item: Binding(get: { selectedCourse.map(CourseSheetItem.init) }, set: { selectedCourse = $0?.name })) { item in
            CourseDetailSheet(title: item.name)
        }
        .sheet(item: $selectedRemoteCourse) { course in CourseDetailSheet(title: course.title, courseID: course.courseID, lessonID: course.lessonID, remoteVideoSource: course.videoSource, initialPositionMs: course.lastPositionMs, expectedProgressVersion: course.version) }
        .sheet(isPresented: $catalogShown) {
            CourseCatalogSheet(kind: selectedKind == 0 ? "公益课堂" : "精选学校课程", isSchoolCourse: selectedKind == 1)
        }
        .alert("暂无法打开课程", isPresented: Binding(get: { recommendationMessage != nil }, set: { if !$0 { recommendationMessage = nil } })) {
            Button("知道了") { recommendationMessage = nil }
        } message: { Text(recommendationMessage ?? "") }
        .task(id: state.selectedChild?.id) {
            guard let child = state.selectedChild else { return }
            loadedCourseChildID = nil
            if state.usesRemoteDataSource { await state.loadCourses(for: child) }
            loadedCourseChildID = child.id
            resolveRecommendedCourseIfReady()
        }
        .onChange(of: state.remoteCourses.map(\.lessonID)) { _, _ in resolveRecommendedCourseIfReady() }
        .onChange(of: state.courseRecommendationTarget) { _, _ in resolveRecommendedCourseIfReady() }
    }

    private func resolveRecommendedCourseIfReady() {
        guard let target = state.courseRecommendationTarget,
              let child = state.selectedChild,
              target.childID == child.id,
              loadedCourseChildID == child.id else { return }
        if !state.usesRemoteDataSource {
            selectedCourse = target.title
            state.clearRecommendedCourseTarget()
            return
        }
        guard state.remoteCoursesChildID == child.id, !state.coursesLoading else { return }
        guard let courseID = target.courseID, let lessonID = target.lessonID else {
            recommendationMessage = "该报告的课程建议尚未包含可播放课程信息，请在学校同步课程后再试。"
            state.clearRecommendedCourseTarget()
            return
        }
        if let lesson = state.remoteCourses.first(where: { $0.courseID == courseID && $0.lessonID == lessonID }) {
            selectedRemoteCourse = lesson
        } else if state.coursesError == nil {
            recommendationMessage = "学校暂未为该孩子分配这节推荐课程。"
        }
        if state.coursesError == nil { state.clearRecommendedCourseTarget() }
    }
}

private struct CourseCatalogSheet: View {
    let kind: String
    let isSchoolCourse: Bool
    @Environment(\.dismiss) private var dismiss
    @State private var selectedCourse: String?
    private var courses: [String] {
        isSchoolCourse
            ? ["校内体能提升课", "校园视力守护课", "课后运动巩固课", "亲子运动指导课"]
            : ["体质成长课", "视力守护课", "口腔健康课", "心理舒展课"]
    }

    var body: some View {
        NavigationStack {
            List {
                Section(kind) {
                    ForEach(courses, id: \.self) { course in
                        Button { selectedCourse = course } label: {
                            Label(course, systemImage: "play.circle.fill")
                                .foregroundStyle(ReferenceColor.navy)
                        }
                    }
                }
            }
            .navigationTitle("课程目录")
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("完成") { dismiss() } } }
            .sheet(item: Binding(get: { selectedCourse.map(CourseSheetItem.init) }, set: { selectedCourse = $0?.name })) { item in
                CourseDetailSheet(title: item.name)
            }
        }
    }
}

struct ParentClassCircleDashboard: View {
    @EnvironmentObject private var state: AppState
    @EnvironmentObject private var router: AppRouter
    @State private var isComposerShown = false
    @State private var selectedMoment: String?
    @State private var editingPost: ClassPostDraft?
    @State private var commentPostID: UUID?
    @State private var commentDraft = ""
    @State private var commentSubmitted = false
    @State private var selectedFilter = "全部"
    private let pinnedNoticeID = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
    private var classMemberCount: Int {
        guard let classID = state.selectedChild?.classID else { return 0 }
        return state.data?.students.filter { $0.classID == classID }.count ?? 0
    }
    // A family feed needs the class size, not other children's identities.
    // Keep the roster private unless the school later provides explicit consent.
    private var visibleClassmates: [Student] { [] }
    private var currentMonthCheckInCount: Int {
        state.localFeatures.checkInDates.filter { $0.hasPrefix(Self.monthKeyFormatter.string(from: .now)) }.count
    }
    private var currentParentName: String { state.activeDisplayName }
    private var classTeacherName: String {
        guard let classID = state.selectedChild?.classID else { return "班级教师" }
        return state.data?.classes.first(where: { $0.id == classID })?.teacherName ?? "班级教师"
    }
    var body: some View {
        ScrollView {
            VStack(spacing: 10) {
                circleHeader
                postsFeed
                classInteractionSection
                checkInSection
                courseSections
            }.padding(.bottom, 10)
        }.background(ReferenceColor.canvas)
        .overlay {
            if let error = state.error, state.data == nil { ErrorStateView(message: error) { Task { await state.refreshDashboard() } }.frame(maxWidth: .infinity, maxHeight: .infinity).background(ReferenceColor.canvas) }
            else if state.loading || state.data == nil { ZStack { ReferenceColor.canvas.ignoresSafeArea(); LoadingStateView() } }
            else if state.selectedChild == nil { ParentBindingPrompt() }
        }
        .sheet(isPresented: $isComposerShown) { PublishClassPostSheet(author: currentParentName) }
        .sheet(item: $editingPost) { post in PublishClassPostSheet(author: post.author, editingPost: post) }
        .sheet(item: Binding(get: { selectedMoment.map(CourseSheetItem.init) }, set: { selectedMoment = $0?.name })) { item in
            if item.name.contains("互动") || item.name.contains("打卡记录") || item.name.contains("评论") {
                CircleInfoSheet(title: item.name)
            } else {
                CourseDetailSheet(title: item.name)
            }
        }
        .sheet(item: Binding(get: { commentPostID.map(CommentSheetItem.init) }, set: { commentPostID = $0?.id })) { item in
            NavigationStack { VStack(spacing: 14) { if commentSubmitted { Image(systemName: "checkmark.circle.fill").font(.system(size: 44)).foregroundStyle(ReferenceColor.green); Text("评论已保存").font(.headline); Text(state.usesRemoteDataSource ? "评论已提交到班级圈，审核状态以学校服务为准。" : "评论已保存，联网后自动同步到班级圈。").font(.footnote).foregroundStyle(.secondary).multilineTextAlignment(.center); Button("完成") { commentPostID = nil }.buttonStyle(.borderedProminent) } else { Text("给这条动态留言").font(.headline); TextField("说点鼓励的话…", text: $commentDraft, axis: .vertical).textFieldStyle(.roundedBorder); Button("保存评论") { if let postID = commentPostID { state.addClassPostComment(postID: postID, text: commentDraft); state.clearDraft(commentDraftKey(for: postID)) }; commentSubmitted = true }.buttonStyle(.borderedProminent).disabled(commentDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty) }; Spacer() }.padding(20).navigationTitle("评论").toolbar { ToolbarItem(placement: .topBarTrailing) { Button("取消") { commentPostID = nil } } } }
        }
        .onChange(of: commentDraft) { _, value in
            guard let postID = commentPostID, !commentSubmitted else { return }
            state.saveDraft(value, key: commentDraftKey(for: postID))
        }
    }
    private func commentDraftKey(for postID: UUID) -> String { "class-comment-\(postID.uuidString)" }
    private func openComment(for postID: UUID) {
        commentSubmitted = false
        commentDraft = state.localFeatures.drafts[commentDraftKey(for: postID)] ?? ""
        commentPostID = postID
    }
    @ViewBuilder private var circleHeader: some View {
        ParentPageNavigation(title: "班级圈", showsBell: false)
        ReferenceHeader(
            name: state.selectedChild?.name ?? "未选择孩子",
            school: "\(state.selectedChild?.className ?? "尚未绑定班级") · \(classMemberCount)人",
            initial: String((state.selectedChild?.name ?? "孩").prefix(1)),
            avatarAsset: "ChildAvatar"
        )
        ReferenceCard {
            HStack(spacing: 14) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("本班家校圈").font(.system(size: 16, weight: .bold))
                    Text("分享运动成长，和老师保持联系").font(.system(size: 12)).foregroundStyle(.secondary)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 3) {
                    Text("\(classMemberCount)").font(.system(size: 20, weight: .bold)).foregroundStyle(ReferenceColor.blue)
                    Text("班级成员").font(.system(size: 12)).foregroundStyle(.secondary)
                }
            }
        }
        .padding(.horizontal, 12)
        HStack(spacing: 8) {
            ForEach(["全部", "老师动态", "家长分享"], id: \.self) { filter in
                Button { selectedFilter = filter } label: {
                    Text(filter)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(selectedFilter == filter ? Color.white : ReferenceColor.blue)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(selectedFilter == filter ? ReferenceColor.blue : ReferenceColor.sky, in: Capsule())
                }
                .buttonStyle(.plain)
            }
            Spacer()
        }
        .padding(.horizontal, 12)
        Button { isComposerShown = true } label: {
            Label("发布班级动态", systemImage: "square.and.pencil")
                .font(.system(size: 12, weight: .bold))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .foregroundStyle(.white)
                .background(ReferenceColor.blue, in: RoundedRectangle(cornerRadius: 10))
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 12)
    }
    private var classInteractionSection: some View {
        ReferenceCard {
            VStack(alignment: .leading, spacing: 8) {
                ReferenceSectionTitle(title: "本班互动", trailing: "查看说明", action: { selectedMoment = "班级互动说明" })
                if visibleClassmates.isEmpty {
                    Text("暂无本班可见名单，学校完成分班后会显示在这里。")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                } else {
                    HStack { ForEach(visibleClassmates) { student in classmate(student) } }
                    Text("本页不展示或生成班级评优、排名；学校正式表彰以班主任通知为准。")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.horizontal, 12)
    }
    private var checkInSection: some View {
        let hasCheckIns = currentMonthCheckInCount > 0
        let title = hasCheckIns ? "本月已保存 \(currentMonthCheckInCount) 次运动打卡" : "本月尚未开始运动打卡"
        let icon = hasCheckIns ? "checkmark.seal.fill" : "calendar.badge.clock"
        let color = hasCheckIns ? ReferenceColor.green : Color.secondary
        return ReferenceCard {
            VStack(alignment: .leading, spacing: 7) {
                ReferenceSectionTitle(title: "本月打卡", trailing: "查看记录", action: { selectedMoment = "本月运动打卡记录" })
                Label(title, systemImage: icon)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(color)
                Text("打卡记录会自动保存并同步。")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 12)
    }
    @ViewBuilder private var courseSections: some View {
        if state.usesRemoteDataSource {
            ReferenceSectionTitle(title: "课程动态", trailing: "进入课程", action: { router.push(.parentCourses) })
                .padding(.horizontal, 12)
            EmptyStateView(title: "暂无课程动态", detail: "学校或平台分配课程后会显示在这里。")
                .padding(.horizontal, 12)
        } else {
            ReferenceSectionTitle(title: "延时课堂精彩瞬间", trailing: "查看全部", action: { router.push(.parentCourses) })
                .padding(.horizontal, 12)
            HStack(spacing: 8) {
                moment("ActivityFootball", "足球启蒙")
                moment("ActivityClassroom", "健康课堂")
                moment("ActivityBalance", "亲子平衡")
            }
            .padding(.horizontal, 12)
            ReferenceSectionTitle(title: "推荐课程", trailing: "查看详情", action: { router.push(.parentCourses) })
                .padding(.horizontal, 12)
            CourseSuggestionBanner().padding(.horizontal, 12)
            ReferenceSectionTitle(title: "我的课程", trailing: "全部课程", action: { router.push(.parentCourses) })
                .padding(.horizontal, 12)
            UpcomingTrainingCard(action: { router.push(.parentCourses) })
                .padding(.horizontal, 12)
        }
    }
    private var visiblePosts: [ClassPostDraft] {
        state.localFeatures.classPosts.filter { post in
            selectedFilter == "全部"
                || (selectedFilter == "老师动态" && post.authorRole == "teacher")
                || (selectedFilter == "家长分享" && post.authorRole != "teacher")
        }
    }
    @ViewBuilder private var postsFeed: some View {
        if state.usesRemoteDataSource, state.classPostsLoading {
            ProgressView("正在加载班级动态…").frame(maxWidth: .infinity).padding(.vertical, 18)
        } else if state.usesRemoteDataSource, let error = state.classPostsError {
            ErrorStateView(message: error) { Task { await state.loadClassPosts() } }
                .padding(.horizontal, 12)
        } else if state.usesRemoteDataSource, visiblePosts.isEmpty {
            EmptyStateView(title: "暂无班级动态", detail: "学校发布或家长分享后会显示在这里。")
                .padding(.horizontal, 12)
        }
        // 置顶通知属于班级的固定信息，不应在家长发布动态后消失；仅在“家长分享”筛选中隐藏。
        if !state.usesRemoteDataSource && selectedFilter != "家长分享" {
            pinnedAnnouncementPost(
                author: classTeacherName,
                content: "本周运动打卡已开启，欢迎家长分享孩子的练习瞬间。",
                isTeacher: true,
                isLiked: Binding(
                    get: { state.localFeatures.likedClassPostIDs.contains(pinnedNoticeID) },
                    set: { desired in
                        let current = state.localFeatures.likedClassPostIDs.contains(pinnedNoticeID)
                        if desired != current { state.toggleClassPostLike(pinnedNoticeID) }
                    }
                ),
                commentCount: state.localFeatures.classPostComments.filter { $0.postID == pinnedNoticeID }.count,
                comments: state.localFeatures.classPostComments.filter { $0.postID == pinnedNoticeID },
                onComment: { openComment(for: pinnedNoticeID) }
            )
        }
        ForEach(visiblePosts) { post in
            ClassPostCard(
                post: post,
                // Server ownership controls edit/delete. Display names are
                // anonymized and are never used as an ownership key.
                isOwner: post.ownedByCurrentUser || (post.postID == nil && post.status != .submitted),
                isLiked: state.localFeatures.likedClassPostIDs.contains(post.id),
                comments: state.localFeatures.classPostComments.filter { $0.postID == post.id },
                onEdit: { editingPost = post },
                onToggleLike: { state.toggleClassPostLike(post.id) },
                onComment: { openComment(for: post.id) },
                onDelete: { Task { _ = await state.deleteClassPostCommand(post) } },
                onReport: { Task { _ = await state.reportClassPostCommand(post) } }
            )
        }
    }
    private func pinnedAnnouncementPost(author: String, content: String, isTeacher: Bool, isLiked: Binding<Bool>, commentCount: Int, comments: [ClassPostComment], onComment: @escaping () -> Void) -> some View { ReferenceCard { VStack(alignment: .leading, spacing: 7) { HStack { Image(systemName: isTeacher ? "graduationcap.circle.fill" : "person.crop.circle.fill").font(.system(size: 28)).foregroundStyle(ReferenceColor.blue); VStack(alignment: .leading, spacing: 1) { Text(author).font(.system(size: 12, weight: .bold)).foregroundStyle(ReferenceColor.blue); Text("今天 08:30 · 本班可见").font(.system(size: 12)).foregroundStyle(.secondary) }; Spacer(); Text("置顶").font(.system(size: 12, weight: .bold)).foregroundStyle(ReferenceColor.yellow) }; Text(content).font(.system(size: 12)).foregroundStyle(ReferenceColor.navy); HStack { Button { isLiked.wrappedValue.toggle() } label: { Label(isLiked.wrappedValue ? "已赞" : "点赞", systemImage: isLiked.wrappedValue ? "hand.thumbsup.fill" : "hand.thumbsup") }.buttonStyle(.plain); Button(action: onComment) { Label("评论 \(3 + commentCount)", systemImage: "bubble.left") }.buttonStyle(.plain); Spacer(); ShareLink(item: content) { Label("分享", systemImage: "square.and.arrow.up") } }.font(.system(size: 12, weight: .semibold)).foregroundStyle(isLiked.wrappedValue ? ReferenceColor.blue : .secondary); commentPreview(comments) }.accessibilityElement(children: .contain) }.padding(.horizontal, 12) }
    @ViewBuilder private func commentPreview(_ comments: [ClassPostComment]) -> some View {
        if !comments.isEmpty {
            VStack(alignment: .leading, spacing: 3) {
                Divider()
                Text("最新评论").font(.system(size: 12, weight: .semibold)).foregroundStyle(.secondary)
                ForEach(Array(comments.suffix(2))) { comment in
                    Text("\(comment.author)：\(comment.text)").font(.system(size: 12)).foregroundStyle(ReferenceColor.navy).lineLimit(2)
                }
            }
            .padding(.top, 1)
            .accessibilityElement(children: .combine)
            .accessibilityLabel("最新评论，\(comments.count)条")
        }
    }
    private func classmate(_ student: Student) -> some View {
        let isBoundChild = student.id == state.selectedChild?.id
        let displayName = isBoundChild ? student.name : "\(student.name.prefix(1))同学"
        return VStack(spacing: 4) {
            Text(String(student.name.prefix(1))).font(.system(size: 14, weight: .bold)).foregroundStyle(.white).frame(width: 36, height: 36).background(ReferenceColor.blue.opacity(0.85), in: Circle())
            Text(displayName).font(.system(size: 12, weight: .semibold)).lineLimit(1)
            Text(student.className).font(.system(size: 12)).foregroundStyle(.secondary).lineLimit(1)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(isBoundChild ? "当前孩子 \(student.name)，\(student.className)" : "本班同学，\(student.className)")
    }
    private func moment(_ image: String, _ title: String) -> some View { Button { selectedMoment = title } label: { VStack(alignment: .leading, spacing: 4) { Image(image).resizable().scaledToFill().frame(height: 48).frame(maxWidth: .infinity).clipped().clipShape(RoundedRectangle(cornerRadius: 7)); Text(title).font(.system(size: 12, weight: .bold)).foregroundStyle(ReferenceColor.navy) }.frame(maxWidth: .infinity) }.buttonStyle(.plain) }
    private static let monthKeyFormatter: DateFormatter = { let formatter = DateFormatter(); formatter.locale = Locale(identifier: "en_US_POSIX"); formatter.dateFormat = "yyyy-MM"; return formatter }()
}

private struct ClassPostCard: View {
    @EnvironmentObject private var state: AppState
    let post: ClassPostDraft
    let isOwner: Bool
    let isLiked: Bool
    let comments: [ClassPostComment]
    let onEdit: () -> Void
    let onToggleLike: () -> Void
    let onComment: () -> Void
    let onDelete: () -> Void
    let onReport: () -> Void

    var body: some View {
        ReferenceCard {
            VStack(alignment: .leading, spacing: 7) {
                header
                Text(post.content)
                    .font(.system(size: 12))
                    .foregroundStyle(ReferenceColor.navy)
                if let attachments = post.attachments, !attachments.isEmpty {
                    attachmentPreview(attachments)
                }
                actions
                commentPreview
            }
        }
        .padding(.horizontal, 12)
    }

    private var header: some View {
        HStack {
            Image(systemName: "person.crop.circle.fill")
                .font(.system(size: 28))
                .foregroundStyle(ReferenceColor.sky)
            VStack(alignment: .leading, spacing: 1) {
                Text(post.author)
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(ReferenceColor.blue)
                Text("刚刚发布 · \(syncLabel)")
                    .font(.system(size: 12))
                    .foregroundStyle(post.status == .failed ? Color.red : Color.secondary)
            }
            Spacer()
            if isOwner {
                HStack(spacing: 8) {
                    Button("编辑", action: onEdit)
                        .foregroundStyle(ReferenceColor.blue)
                    Button("删除", action: onDelete)
                        .foregroundStyle(.red)
                }
                .font(.system(size: 12, weight: .semibold))
            } else {
                Button("举报", action: onReport)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var actions: some View {
        HStack {
            Button(action: onToggleLike) {
                Label(isLiked ? "已赞" : "点赞", systemImage: isLiked ? "hand.thumbsup.fill" : "hand.thumbsup")
            }
            .buttonStyle(.plain)
            Button(action: onComment) {
                Label("评论", systemImage: "bubble.left")
            }
            .buttonStyle(.plain)
            Spacer()
            ShareLink(item: post.content) {
                Label("分享", systemImage: "square.and.arrow.up")
            }
        }
        .font(.system(size: 12, weight: .semibold))
        .foregroundStyle(isLiked ? ReferenceColor.blue : Color.secondary)
    }

    @ViewBuilder private func attachmentPreview(_ attachments: [ClassPostAttachment]) -> some View {
        LazyVGrid(columns: [GridItem(.flexible(), spacing: 7), GridItem(.flexible(), spacing: 7), GridItem(.flexible(), spacing: 7)], spacing: 7) {
            ForEach(attachments) { attachment in
                Button {
                    Task { await state.loadClassPostAttachment(fileID: attachment.objectID ?? "") }
                } label: {
                    if let objectID = attachment.objectID, let data = state.classPostAttachmentData[objectID], let image = UIImage(data: data) {
                        Image(uiImage: image).resizable().scaledToFill().frame(height: 76).clipped().clipShape(RoundedRectangle(cornerRadius: 8))
                    } else {
                        VStack(spacing: 4) {
                            Image(systemName: attachment.type == "video" ? "video.fill" : "photo").font(.system(size: 18, weight: .semibold))
                            Text(state.classPostAttachmentErrors[attachment.objectID ?? ""] == nil ? "查看附件" : "加载失败，重试").font(.system(size: 12, weight: .semibold))
                        }
                        .frame(maxWidth: .infinity, minHeight: 76)
                        .foregroundStyle(state.classPostAttachmentErrors[attachment.objectID ?? ""] == nil ? ReferenceColor.blue : Color.red)
                        .background(ReferenceColor.sky, in: RoundedRectangle(cornerRadius: 8))
                    }
                }
                .buttonStyle(.plain)
                .accessibilityLabel(attachment.type == "video" ? "查看班级圈视频附件" : "查看班级圈图片附件")
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(attachments.count) 个班级圈附件，点击可查看")
    }

    @ViewBuilder private var commentPreview: some View {
        if !comments.isEmpty {
            VStack(alignment: .leading, spacing: 3) {
                Divider()
                Text("最新评论")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.secondary)
                ForEach(Array(comments.suffix(2))) { comment in
                    Text("\(comment.author)：\(comment.text)")
                        .font(.system(size: 12))
                        .foregroundStyle(ReferenceColor.navy)
                        .lineLimit(2)
                }
            }
            .padding(.top, 1)
            .accessibilityElement(children: .combine)
            .accessibilityLabel("最新评论，\(comments.count)条")
        }
    }

    private var syncLabel: String {
        switch post.status {
        case .submitted: "已同步"
        case .failed: "同步失败，可在设置中重试"
        case .submitting: "正在同步"
        case .draft: "未完成"
        case .pendingSync: "已保存，联网后自动同步"
        }
    }
}

private struct CommentSheetItem: Identifiable { let id: UUID }

private struct CircleInfoSheet: View {
    let title: String
    @EnvironmentObject private var state: AppState
    @Environment(\.dismiss) private var dismiss
    private var currentMonthCheckInCount: Int {
        state.localFeatures.checkInDates.filter { $0.hasPrefix(Self.monthKeyFormatter.string(from: .now)) }.count
    }
    var body: some View {
        NavigationStack {
            List {
                if title.contains("评论") {
                    Section("班级通知评论") {
                        Text("你可以在班级通知下留言，与老师和家长交流。")
                        Text("请注意保护孩子隐私，避免发布个人敏感信息。")
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                } else if title.contains("互动") {
                    Section("本班互动说明") {
                        Text("仅展示当前本班可见学生名单，便于家长确认交流范围。")
                        Text("班级评优、排名及表彰由学校和班主任统一发布，本页不生成。")
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                } else {
                    Section("\(state.selectedChild?.name ?? "孩子")的运动打卡") {
                        LabeledContent("本月完成", value: "\(currentMonthCheckInCount) 次")
                        Text(currentMonthCheckInCount == 0 ? "完成一次家庭运动后即可打卡。" : "打卡记录会自动保存并同步。")
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle(title)
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("完成") { dismiss() } } }
        }
    }
    private static let monthKeyFormatter: DateFormatter = { let formatter = DateFormatter(); formatter.locale = Locale(identifier: "en_US_POSIX"); formatter.dateFormat = "yyyy-MM"; return formatter }()
}

struct AccountDashboard: View {
    @EnvironmentObject private var state: AppState
    @EnvironmentObject private var router: AppRouter
    @State private var dialog: String?
    @State private var settingsShown = false
    var body: some View {
        ScrollView {
            VStack(spacing: 10) {
                ParentPageNavigation(title: "我的")
                Button { dialog = "个人资料" } label: {
                    HStack(spacing: 12) {
                        Image(state.selectedRole == .teacher ? "TeacherAvatar" : "ChildAvatar").resizable().scaledToFill().frame(width: 54, height: 54).background(ReferenceColor.sky, in: Circle()).clipShape(Circle())
                        VStack(alignment: .leading, spacing: 3) { Text(state.activeDisplayName).font(.system(size: 16, weight: .bold)); Text(state.profile?.schoolName ?? "学校").font(.system(size: 12)).foregroundStyle(.secondary); RoleBadge(role: state.selectedRole ?? .parent) }
                        Spacer()
                        Image(systemName: "chevron.right").foregroundStyle(.secondary)
                    }
                    .padding(14).background(.white, in: RoundedRectangle(cornerRadius: 12))
                    .contentShape(RoundedRectangle(cornerRadius: 12))
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 12)
                .accessibilityElement(children: .combine)
                .accessibilityLabel("查看个人资料")
                if state.selectedRole == .parent {
                    HStack(spacing: 8) {
                        accountMetric(title: "已绑定孩子", value: "\(state.boundChildren.count)", action: { router.push(.children(returnAfterBinding: false)) })
                        accountMetric(title: "成长报告", value: "\(state.boundChildren.filter { state.hasPublishedSchoolReport(for: $0) }.count)", action: { if let child = state.selectedChild { router.push(.report(child)) } else { router.push(.children(returnAfterBinding: true)) } })
                        accountMetric(title: "未读消息", value: "\(state.unreadMessageCount)", action: { router.push(.parentMessages) })
                    }.padding(.horizontal, 12)
                    if state.pendingSyncCount > 0 {
                        Button { settingsShown = true } label: {
                            HStack(spacing: 9) {
                                Image(systemName: "arrow.triangle.2.circlepath.circle.fill").foregroundStyle(.orange)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("有 \(state.pendingSyncCount) 条记录等待同步").font(.system(size: 12, weight: .bold))
                                    Text("已保存，联网后自动同步").font(.system(size: 12)).foregroundStyle(.secondary)
                                }
                                Spacer()
                                Text("查看").font(.system(size: 12, weight: .semibold)).foregroundStyle(ReferenceColor.blue)
                                Image(systemName: "chevron.right").font(.system(size: 12)).foregroundStyle(ReferenceColor.blue)
                            }
                            .padding(11).background(.orange.opacity(0.10), in: RoundedRectangle(cornerRadius: 10))
                        }
                        .buttonStyle(.plain)
                        .padding(.horizontal, 12)
                        .accessibilityLabel("有 \(state.pendingSyncCount) 条记录等待同步，查看同步状态")
                    }
                    ReferenceSectionTitle(title: "家庭服务", trailing: "孩子管理", action: { router.push(.children(returnAfterBinding: false)) }).padding(.horizontal, 12)
                } else {
                    let managedClassCount = min(state.data?.classes.count ?? 0, 2)
                    let reviewCount = state.data?.students.filter { state.taskStatus(for: $0) == .review || state.taskStatus(for: $0) == .retest }.count ?? 0
                    HStack(spacing: 8) {
                        accountMetric(title: "管理班级", value: "\(managedClassCount)", action: { router.push(.teacherClasses) })
                        accountMetric(title: "待处理", value: "\(reviewCount)", action: { router.push(.reviewList) })
                        accountMetric(title: "未读消息", value: "\(state.unreadMessageCount)", action: { router.push(.teacherMessages) })
                    }.padding(.horizontal, 12)
                    ReferenceSectionTitle(title: "教师工作台", trailing: "查看数据", action: { router.push(.teacherClassBoard) }).padding(.horizontal, 12)
                }
                if state.selectedRole == .teacher {
                    accountRow("个人信息", "person.text.rectangle.fill", ReferenceColor.blue) { dialog = "个人信息" }
                    accountRow("我的权限", "lock.shield.fill", ReferenceColor.green) { dialog = "我的权限" }
                    accountRow("工作数据", "chart.bar.fill", ReferenceColor.purple) { router.push(.teacherClassBoard) }
                    accountRow("设置", "gearshape.fill", .orange) { settingsShown = true }
                    accountRow("消息", "bell.fill", .red) { router.push(.teacherMessages) }
                } else {
                    accountRow("我的健康档案", "heart.text.square.fill", ReferenceColor.green) { router.push(.healthProfile) }
                    accountRow("我的课程", "play.rectangle.fill", ReferenceColor.blue) { router.push(.parentCourses) }
                    accountRow("客服咨询", "message.fill", ReferenceColor.purple) { dialog = "客服咨询" }
                    accountRow("消息", "bell.fill", .red) { router.push(.parentMessages) }
                }
                ReferenceSectionTitle(title: "服务与安全", trailing: "隐私安全").padding(.horizontal, 12)
                accountRow("通知与显示设置", "gearshape.fill", .orange) { settingsShown = true }
                accountRow("帮助与反馈", "questionmark.circle.fill", ReferenceColor.blue) { dialog = "帮助与反馈" }
                accountRow("数据与隐私", "hand.raised.fill", ReferenceColor.green) { dialog = "数据与隐私" }
                accountRow("用户协议与隐私政策", "doc.text.fill", .secondary) { dialog = "用户协议与隐私政策" }
                Button { state.chooseAnotherRole(); router.reset() } label: { Label("切换使用角色", systemImage: "arrow.left.arrow.right").font(.system(size: 12, weight: .bold)).frame(maxWidth: .infinity).padding(.vertical, 11).foregroundStyle(ReferenceColor.blue).background(ReferenceColor.sky, in: RoundedRectangle(cornerRadius: 10)) }.buttonStyle(.plain).padding(.horizontal, 12)
                Button { state.switchAccount(); router.reset() } label: { Text("切换账号").font(.system(size: 12, weight: .bold)).frame(maxWidth: .infinity).padding(.vertical, 11).foregroundStyle(.red).background(.red.opacity(0.08), in: RoundedRectangle(cornerRadius: 10)) }.buttonStyle(.plain).padding(.horizontal, 12)
            }.padding(.bottom, 10)
        }.background(ReferenceColor.canvas)
        .sheet(item: Binding(get: { dialog.map(CourseSheetItem.init) }, set: { dialog = $0?.name })) { item in
            if ["个人资料", "个人信息", "我的权限", "帮助与反馈", "数据与隐私", "用户协议与隐私政策"].contains(item.name) {
                AccountInfoSheet(title: item.name)
            } else {
                CourseDetailSheet(title: item.name)
            }
        }
        .sheet(isPresented: $settingsShown) { AppSettingsSheet() }
    }
    private func accountMetric(title: String, value: String, action: @escaping () -> Void) -> some View { Button(action: action) { VStack(spacing: 3) { Text(value).font(.system(size: 18, weight: .bold)).foregroundStyle(ReferenceColor.blue); Text(title).font(.system(size: 12)).foregroundStyle(.secondary) }.frame(maxWidth: .infinity).padding(.vertical, 10).background(.white, in: RoundedRectangle(cornerRadius: 10)) }.buttonStyle(.plain) }
    private func accountRow(_ title: String, _ icon: String, _ color: Color, action: @escaping () -> Void) -> some View { Button(action: action) { HStack(spacing: 10) { Image(systemName: icon).foregroundStyle(color).frame(width: 34, height: 34).background(color.opacity(0.10), in: RoundedRectangle(cornerRadius: 9)); Text(title).font(.system(size: 12, weight: .semibold)); Spacer(); Image(systemName: "chevron.right").font(.system(size: 12)).foregroundStyle(.secondary) }.foregroundStyle(ReferenceColor.navy).padding(11).background(.white, in: RoundedRectangle(cornerRadius: 10)) }.buttonStyle(.plain).padding(.horizontal, 12) }
}

struct AppSettingsSheet: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var state: AppState
    @State private var showingClearDataConfirmation = false
    var body: some View {
        NavigationStack {
            Form {
                Section("通知与显示") {
                    Toggle("显示应用内测评与班级提醒", isOn: Binding(
                        get: { state.localFeatures.settings.notificationsEnabled },
                        set: { state.updateSettings(notificationsEnabled: $0) }
                    ))
                    Toggle("减少动态效果", isOn: Binding(
                        get: { state.localFeatures.settings.reduceMotion },
                        set: { state.updateSettings(reduceMotion: $0) }
                    ))
                    Toggle("语音动作引导", isOn: Binding(
                        get: { state.localFeatures.settings.voiceGuidanceEnabled },
                        set: { state.updateSettings(voiceGuidanceEnabled: $0) }
                    ))
                    Text("当前显示应用内消息；开启系统通知后可及时收到提醒。")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                Section("同步状态") {
                    LabeledContent("待同步记录", value: "\(state.pendingSyncCount) 条")
                    Text(state.pendingSyncCount == 0
                         ? "当前没有等待同步的本地操作。"
                         : "记录已保存，联网后会自动同步。")
                        .font(.footnote).foregroundStyle(.secondary)
                    let syncState = state.workflowState(for: "sync-pending")
                    Button { Task { await state.syncPendingRecords() } } label: {
                        HStack {
                            if syncState.isSubmitting { ProgressView() }
                            Text(syncState.isSubmitting ? "正在同步…" : "立即同步")
                        }
                    }
                    .disabled(state.pendingSyncCount == 0 || syncState.isSubmitting)
                    if case let .succeeded(message) = syncState {
                        Text(message).font(.footnote).foregroundStyle(ReferenceColor.green)
                    }
                    if case let .failed(message) = syncState {
                        Text(message).font(.footnote).foregroundStyle(.red)
                    }
                }
                Section("账号安全") {
                    Text("退出登录会清除设备上的绑定孩子、草稿和通知状态；学校测评记录不会受影响。")
                        .font(.footnote).foregroundStyle(.secondary)
                    Button("清除设备数据并退出登录", role: .destructive) {
                        showingClearDataConfirmation = true
                    }
                }
            }
            .navigationTitle("设置")
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("完成") { dismiss() } } }
            .confirmationDialog("清除设备数据？", isPresented: $showingClearDataConfirmation, titleVisibility: .visible) {
                Button("清除并退出", role: .destructive) { state.switchAccount(); dismiss() }
                Button("取消", role: .cancel) {}
            } message: {
                Text("此操作会移除本设备上的登录态、孩子绑定和本地草稿，后续可重新登录。")
            }
        }
    }
}

struct AccountInfoSheet: View {
    let title: String
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var state: AppState
    @State private var feedback = ""
    @State private var feedbackSubmitted = false
    @State private var showingDeleteConfirmation = false
    @State private var showingConsentRevokeConfirmation = false
    @State private var showingAccountDeletionConfirmation = false
    private let feedbackDraftKey = "account-feedback"
    var body: some View {
        let commandState = state.workflowState(for: "support")
        NavigationStack {
            Form {
                if title == "个人资料" || title == "个人信息" {
                    Section("账号信息") {
                        LabeledContent("姓名", value: state.activeDisplayName)
                        LabeledContent("手机号", value: maskedPhone(state.profile?.phone ?? ""))
                        LabeledContent("所属学校", value: state.profile?.schoolName ?? "学校")
                        Text("账号信息由学校或平台管理员维护。") .font(.footnote).foregroundStyle(.secondary)
                    }
                } else if title == "我的权限" {
                    Section("当前权限") { Label("查看测评、报告和成长建议", systemImage: "checkmark.circle.fill").foregroundStyle(ReferenceColor.green); Label("管理所负责班级数据", systemImage: "checkmark.circle.fill").foregroundStyle(ReferenceColor.green); Text("权限以学校后台授权为准。") .font(.footnote).foregroundStyle(.secondary) }
                } else if title == "帮助与反馈" {
                    Section("问题反馈") {
                        if feedbackSubmitted {
                            Label("反馈已保存，联网后自动同步。", systemImage: "checkmark.circle.fill").foregroundStyle(ReferenceColor.green)
                        } else {
                            TextEditor(text: $feedback).frame(minHeight: 110).onChange(of: feedback) { _, value in state.saveDraft(value, key: feedbackDraftKey) }
                            if case let .failed(message) = commandState { Text(message).font(.caption).foregroundStyle(.red) }
                            Button {
                                let message = feedback.trimmingCharacters(in: .whitespacesAndNewlines)
                                guard !message.isEmpty else { return }
                                Task { if await state.submitSupportCommand(message) { state.clearDraft(feedbackDraftKey); feedbackSubmitted = true } }
                            } label: {
                                HStack(spacing: 6) { if commandState.isSubmitting { ProgressView() }; Text(commandState.isSubmitting ? "正在提交…" : "提交反馈") }
                            }
                            .disabled(commandState.isSubmitting || feedback.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        }
                    }
                    Section("常见问题") { Text("孩子绑定码由学校或班主任提供。\n测评报告生成后会在消息中心通知。\n如遇数据异常，请联系学校管理员。") .font(.footnote).foregroundStyle(.secondary) }
                } else if title == "数据与隐私" {
                    let child = state.selectedChild
                    let exportState = child.map { state.workflowState(for: "privacy:\($0.id):export") } ?? .idle
                    let deleteState = child.map { state.workflowState(for: "privacy:\($0.id):delete") } ?? .idle
                    let revokeState = child.map { state.workflowState(for: "privacy:\($0.id):consent-revoke") } ?? .idle
                    let accountDeleteState = state.workflowState(for: "privacy:account-deletion")
                    Section("孩子数据") {
                        LabeledContent("当前孩子", value: child?.name ?? "请先绑定并选择孩子")
                        Text("仅可为已绑定孩子提交申请。导出文件生成后会通过消息中心通知；删除申请需要学校或平台审核，审核前不会删除任何记录。")
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                    Section("数据权利") {
                        Button { guard let child else { return }; Task { _ = await state.submitPrivacyRequest(studentID: child.id, type: .export) } } label: {
                            HStack { if exportState.isSubmitting { ProgressView() }; Text(exportState.isSubmitting ? "正在提交…" : "申请导出孩子数据") }
                        }.disabled(child == nil || exportState.isSubmitting)
                        if case let .succeeded(message) = exportState { Text(message).font(.footnote).foregroundStyle(ReferenceColor.green) }
                        if case let .failed(message) = exportState { Text(message).font(.footnote).foregroundStyle(.red) }
                        Button("申请删除/匿名化处理", role: .destructive) { showingDeleteConfirmation = true }.disabled(child == nil || deleteState.isSubmitting)
                        if case let .succeeded(message) = deleteState { Text(message).font(.footnote).foregroundStyle(ReferenceColor.green) }
                        if case let .failed(message) = deleteState { Text(message).font(.footnote).foregroundStyle(.red) }
                        Button("撤回身体测评数据使用同意", role: .destructive) { showingConsentRevokeConfirmation = true }
                            .disabled(child == nil || revokeState.isSubmitting)
                        if case let .succeeded(message) = revokeState { Text(message).font(.footnote).foregroundStyle(ReferenceColor.green) }
                        if case let .failed(message) = revokeState { Text(message).font(.footnote).foregroundStyle(.red) }
                        Button("申请注销当前账户", role: .destructive) { showingAccountDeletionConfirmation = true }
                            .disabled(accountDeleteState.isSubmitting)
                        if case let .succeeded(message) = accountDeleteState { Text(message).font(.footnote).foregroundStyle(ReferenceColor.green) }
                        if case let .failed(message) = accountDeleteState { Text(message).font(.footnote).foregroundStyle(.red) }
                    }
                } else {
                    Section("协议说明") { Text("向上少年仅在获得授权后处理学生健康与运动数据，用于测评、报告和课程建议。儿童账号和家庭绑定数据不会用于商业推广。") .font(.footnote).foregroundStyle(.secondary); Text("协议版本：2026.1") .font(.footnote).foregroundStyle(.secondary) }
                }
            }
            .navigationTitle(title)
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("完成") { dismiss() } } }
            .task {
                if title == "帮助与反馈" {
                    state.clearWorkflowState("support")
                    feedback = state.localFeatures.drafts[feedbackDraftKey] ?? ""
                }
            }
            .confirmationDialog("提交删除/匿名化申请？", isPresented: $showingDeleteConfirmation, titleVisibility: .visible) {
                Button("提交申请", role: .destructive) { if let child = state.selectedChild { Task { _ = await state.submitPrivacyRequest(studentID: child.id, type: .delete) } } }
                Button("取消", role: .cancel) {}
            } message: { Text("此操作不会立即删除数据。学校或平台审核通过前，测评记录仍会保留。") }
            .confirmationDialog("撤回身体测评数据使用同意？", isPresented: $showingConsentRevokeConfirmation, titleVisibility: .visible) {
                Button("确认撤回", role: .destructive) {
                    if let child = state.selectedChild { Task { _ = await state.revokeHealthConsent(studentID: child.id) } }
                }
                Button("取消", role: .cancel) {}
            } message: { Text("撤回后，新的身体测评提交前需要重新授权；已完成的学校记录不会被自动删除。") }
            .confirmationDialog("申请注销当前账户？", isPresented: $showingAccountDeletionConfirmation, titleVisibility: .visible) {
                Button("提交注销申请", role: .destructive) { Task { _ = await state.submitAccountDeletionRequest() } }
                Button("取消", role: .cancel) {}
            } message: { Text("账户会先进入审核队列。批准后将撤销登录会话并匿名化账户信息；学校侧已完成的测评记录按留存规则处理。") }
        }
    }

    private func maskedPhone(_ phone: String) -> String {
        let digits = phone.filter(\.isNumber)
        guard digits.count >= 7 else { return phone.isEmpty ? "未绑定手机号" : phone }
        let start = digits.prefix(3)
        let end = digits.suffix(4)
        return "\(start)****\(end)"
    }
}

struct CourseSheetItem: Identifiable { let name: String; var id: String { name } }
struct PublishClassPostSheet: View {
    let author: String
    var editingPost: ClassPostDraft?
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var state: AppState
    @State private var content = ""
    @State private var validationMessage: String?
    @State private var submitted = false
    @State private var selectedPhoto: PhotosPickerItem?
    @State private var attachmentName: String?
    @State private var attachmentReference: String?
    @State private var attachmentType = "image"
    @State private var attachmentError: String?
    private var workflowKey: String { "post:\(state.profile?.id ?? "session")" }
    private var draftKey: String { "class-post-\(editingPost?.id.uuidString ?? state.profile?.id ?? "session")" }
    var body: some View {
        let commandState = state.workflowState(for: workflowKey)
        return NavigationStack {
            VStack(alignment: .leading, spacing: 14) {
                if submitted {
                    VStack(spacing: 12) {
                        Image(systemName: "checkmark.circle.fill").font(.system(size: 48)).foregroundStyle(ReferenceColor.green)
                        Text(editingPost == nil ? "动态已保存" : "修改已保存").font(.title3.bold())
                        Text("内容已保存，联网后自动同步。").font(.system(size: 12)).foregroundStyle(.secondary).multilineTextAlignment(.center)
                        Spacer()
                        Button("完成") { dismiss() }.font(.system(size: 14, weight: .bold)).frame(maxWidth: .infinity).padding(.vertical, 12).foregroundStyle(.white).background(ReferenceColor.blue, in: RoundedRectangle(cornerRadius: 11))
                    }
                } else {
                    Text(editingPost == nil ? "发布班级动态" : "编辑班级动态").font(.title3.bold())
                    Text("内容会自动保存并同步，请勿发布学生隐私信息。").font(.system(size: 12)).foregroundStyle(.secondary)
                    TextEditor(text: $content).frame(minHeight: 160).padding(8).overlay(RoundedRectangle(cornerRadius: 10).stroke(validationMessage == nil ? ReferenceColor.navy.opacity(0.15) : .red, lineWidth: 1)).onChange(of: content) { _, value in state.saveDraft(value, key: draftKey) }
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Label(attachmentName ?? "可添加 1 个图片或视频附件", systemImage: attachmentName == nil ? "photo.badge.plus" : attachmentType == "video" ? "video.fill" : "photo.fill")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(attachmentName == nil ? .secondary : ReferenceColor.blue)
                            Spacer()
                            PhotosPicker(selection: $selectedPhoto, matching: .any(of: [.images, .videos])) {
                                Text(attachmentName == nil ? "选择附件" : "更换")
                                    .font(.system(size: 12, weight: .bold))
                            }
                            .frame(minWidth: 44, minHeight: 44)
                            if attachmentName != nil {
                                Button("移除") {
                                    selectedPhoto = nil
                                    attachmentName = nil
                                    attachmentReference = nil
                                    attachmentType = "image"
                                    attachmentError = nil
                                }
                                .font(.system(size: 12, weight: .bold))
                                .foregroundStyle(.red)
                                .frame(minWidth: 44, minHeight: 44)
                            }
                        }
                        Text("仅支持 JPG、PNG 或 MP4，最大 20MB。发布前会先上传到学校文件服务；页面不会保存相册原始路径。")
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                        if let attachmentError { Text(attachmentError).font(.system(size: 12)).foregroundStyle(.red) }
                    }
                    .padding(12)
                    .background(ReferenceColor.sky.opacity(0.65), in: RoundedRectangle(cornerRadius: 12))
                    .onChange(of: selectedPhoto) { _, item in
                        guard let item else { return }
                        Task { await loadSelectedPhoto(item) }
                    }
                    if let validationMessage { Text(validationMessage).font(.system(size: 12)).foregroundStyle(.red) }
                    if case let .failed(message) = commandState { Text(message).font(.system(size: 12)).foregroundStyle(.red) }
                    Spacer()
                    Button {
                        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
                        guard !trimmed.isEmpty else { validationMessage = "动态内容不能为空。"; return }
                        let attachments = attachmentReference.map { [ClassPostAttachment(id: attachmentName ?? "班级圈附件", type: attachmentType, objectID: nil, localReference: $0, thumbnailObjectID: nil)] } ?? []
                        if let editingPost { state.updateClassPost(id: editingPost.id, text: trimmed); state.clearDraft(draftKey); submitted = true }
                        else { Task { if await state.submitClassPostCommand(trimmed, author: author, attachments: attachments) { state.clearDraft(draftKey); submitted = true } } }
                    } label: {
                        HStack { if commandState.isSubmitting { ProgressView().tint(.white) }; Text(commandState.isSubmitting ? "正在提交…" : editingPost == nil ? "保存动态" : "保存修改") }
                            .font(.system(size: 14, weight: .bold)).frame(maxWidth: .infinity).padding(.vertical, 12).foregroundStyle(.white).background(ReferenceColor.blue, in: RoundedRectangle(cornerRadius: 11))
                    }
                    .disabled(commandState.isSubmitting || content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .padding(18)
            .navigationBarTitleDisplayMode(.inline)
            .task {
                if editingPost == nil { state.clearWorkflowState(workflowKey) }
                content = editingPost?.content ?? state.localFeatures.drafts[draftKey] ?? state.localFeatures.drafts["class-post-\(author)"] ?? ""
                if let attachment = editingPost?.attachments?.first {
                    attachmentName = attachment.id
                    attachmentReference = attachment.localReference
                    attachmentType = attachment.type
                }
            }
        }
    }

    @MainActor
    private func loadSelectedPhoto(_ item: PhotosPickerItem) async {
        attachmentError = nil
        do {
            guard let data = try await item.loadTransferable(type: Data.self) else { throw CourseAttachmentError.unavailable }
            let kind = try CourseAttachmentStore.mediaKind(for: item.supportedContentTypes)
            let mediaName = kind.type == "video" ? "班级圈视频" : "班级圈照片"
            let stored = try CourseAttachmentStore.persistMediaData(data, suggestedName: "\(mediaName)-\(UUID().uuidString).\(kind.extension)")
            attachmentName = stored.name
            attachmentReference = stored.reference
            attachmentType = kind.type
        } catch {
            attachmentError = error.localizedDescription
            attachmentName = nil
            attachmentReference = nil
            attachmentType = "image"
        }
    }
}
struct HealthArticleSheet: View {
    let title: String
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @State private var openFailed = false
    var body: some View {
        NavigationStack {
            VStack(spacing: 15) {
                Image(systemName: "book.closed.fill").font(.system(size: 44)).foregroundStyle(ReferenceColor.green)
                Text(title).font(.title3.bold()).multilineTextAlignment(.center)
                Text("完整健康专栏将由“向上少年健康成长”微信公众号提供。") .font(.system(size: 13)).foregroundStyle(.secondary).multilineTextAlignment(.center).padding(.horizontal, 28)
                if openFailed { Text("当前设备未安装微信，请直接搜索公众号：向上少年健康成长。").font(.system(size: 12)).foregroundStyle(.red).multilineTextAlignment(.center).padding(.horizontal, 24) }
                Button {
                    let url = URL(string: "weixin://")!
                    if UIApplication.shared.canOpenURL(url) { openURL(url); dismiss() } else { openFailed = true }
                } label: { Label(openFailed ? "重试打开微信" : "打开微信公众号", systemImage: "arrow.up.forward.app") }.buttonStyle(.borderedProminent)
                Text("若未安装微信，可搜索公众号：向上少年健康成长").font(.system(size: 12)).foregroundStyle(.secondary)
            }.frame(maxWidth: .infinity, maxHeight: .infinity).navigationTitle("健康科普").navigationBarTitleDisplayMode(.inline).toolbar { ToolbarItem(placement: .topBarTrailing) { Button("关闭") { dismiss() } } }
        }
    }
}

struct ParentHealthDimension: View {
    let category: AssessmentCategory; let detail: String; let color: Color
    @EnvironmentObject private var state: AppState
    @EnvironmentObject private var router: AppRouter
    private var hasRecord: Bool { guard let child = state.selectedChild else { return false }; return state.familyHealthRecord(for: child, category: category) != nil }
    var body: some View { Button { if state.selectedChild != nil { router.push(.assessment(category)) } else { router.push(.children(returnAfterBinding: true)) } } label: {
        HStack(spacing: 10) { Image(systemName: category.icon).font(.system(size: 16, weight: .bold)).foregroundStyle(color).frame(width: 34, height: 34).background(color.opacity(0.10), in: RoundedRectangle(cornerRadius: 9)); VStack(alignment: .leading, spacing: 3) { Text(category.rawValue).font(.system(size: 12, weight: .bold)); Text(detail).font(.system(size: 12)).foregroundStyle(.secondary) }; Spacer(); Text(hasRecord ? "已保存" : "去填写").font(.system(size: 12, weight: .bold)).foregroundStyle(color); Image(systemName: "chevron.right").font(.system(size: 12)).foregroundStyle(.secondary) }
            .foregroundStyle(ReferenceColor.navy).padding(10).background(.white, in: RoundedRectangle(cornerRadius: 10))
    }.buttonStyle(.plain).accessibilityLabel(hasRecord ? "查看\(category.rawValue)家庭健康记录" : "填写\(category.rawValue)家庭健康记录") }
}
