import SwiftUI

struct TeacherClassBoardView: View {
    @EnvironmentObject private var state: AppState
    @EnvironmentObject private var router: AppRouter
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    @State private var dashboardAppeared = false
    @State private var selectedPeriod = 0
    @SceneStorage("teacher.selectedClassID") private var selectedClassID: String?
    @SceneStorage("teacher.selectedTaskID") private var selectedTaskID: String?
    @State private var historicalDetailShown = false
    private var classInfo: ClassInfo? { state.managedTeacherClasses.first(where: { $0.id == selectedClassID }) ?? state.managedTeacherClasses.first }
    private var className: String { classInfo?.name ?? "我的班级" }
    private var currentTask: TestTask? { state.data?.tasks.first(where: { $0.id == selectedTaskID }) ?? state.data?.tasks.first }
    private var classStudents: [Student] { state.data?.students.filter { $0.classID == classInfo?.id } ?? [] }
    private var isHistorical: Bool { selectedPeriod == 1 }
    /// In a remote session, class analytics must come from the selected
    /// task's server-side aggregation. Falling back to the bounded dashboard
    /// directory produces a plausible but incomplete school statistic.
    private var totalCount: Int { isHistorical ? 0 : remoteOverview?.totalCount ?? (state.usesRemoteDataSource ? 0 : classStudents.count) }
    private var measuredCount: Int { isHistorical ? 0 : remoteOverview?.completedCount ?? (state.usesRemoteDataSource ? 0 : classStudents.filter { state.taskStatus(for: $0, taskID: currentTask?.id) == .completed }.count) }
    private var remoteOverview: TeacherAnalyticsOverview? {
        guard !isHistorical else { return nil }
        // `dataAvailable == false` is an explicit absence of analytics, not a
        // zero-result class. Keep it out of every metric calculation.
        let context = TeacherOverviewContext(schoolID: state.profile?.schoolID ?? "", classID: classInfo?.id ?? "", taskID: currentTask?.id ?? "", standardVersion: currentTask?.ruleVersion ?? "")
        guard state.teacherOverviewContext == context else { return nil }
        return state.teacherOverview?.dataAvailable == true ? state.teacherOverview : nil
    }
    private func officialReport(for student: Student) -> DiagnosisReport? {
        guard state.hasPublishedSchoolReport(for: student) else { return nil }
        return state.visibleReport(for: student)
    }
    private var lowScoreStudentIDs: Set<String> {
        Set(classStudents.compactMap(officialReport(for:)).filter { $0.requiresFollowUp }.map(\.student.id))
    }
    private var riskCount: Int { isHistorical ? 0 : remoteOverview?.riskCount ?? (state.usesRemoteDataSource ? 0 : classStudents.filter { lowScoreStudentIDs.contains($0.id) || state.taskStatus(for: $0, taskID: currentTask?.id) == .review || state.taskStatus(for: $0, taskID: currentTask?.id) == .retest }.count) }
    private var lowScoreCount: Int { isHistorical ? 0 : remoteOverview?.lowScoreCount ?? (state.usesRemoteDataSource ? 0 : lowScoreStudentIDs.count) }
    private var reviewCount: Int { isHistorical ? 0 : remoteOverview?.reviewCount ?? (state.usesRemoteDataSource ? 0 : classStudents.filter { state.taskStatus(for: $0, taskID: currentTask?.id) == .review }.count) }
    private var retestCount: Int { isHistorical ? 0 : remoteOverview?.retestCount ?? (state.usesRemoteDataSource ? 0 : classStudents.filter { state.taskStatus(for: $0, taskID: currentTask?.id) == .retest }.count) }
    private var processingCount: Int { isHistorical || state.usesRemoteDataSource ? 0 : classStudents.filter { [.checkedIn, .waiting, .testing].contains(state.taskStatus(for: $0, taskID: currentTask?.id)) }.count }
    private var completedCount: Int { measuredCount }
    private var riskStudents: [Student] { isHistorical || (state.usesRemoteDataSource && remoteOverview == nil) ? [] : classStudents.filter { lowScoreStudentIDs.contains($0.id) || [.review, .retest].contains(state.taskStatus(for: $0, taskID: currentTask?.id)) } }
    private var completion: Double { totalCount == 0 ? 0 : Double(measuredCount) / Double(totalCount) }
    private var reduceMotion: Bool { state.localFeatures.settings.reduceMotion || systemReduceMotion }

    var body: some View {
        ScrollView {
            VStack(spacing: 7) {
                HStack {
                    Button { router.pop() } label: {
                        Image(systemName: "chevron.left")
                            .frame(width: 44, height: 44)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("返回")
                    .accessibilityHint("返回上一页")
                    Spacer()
                    VStack(spacing: 1) {
                        Text("\(className) · 班级数据看板").font(.system(size: 16, weight: .bold))
                        Text("\(state.profile?.schoolName ?? "学校") · \(className) · 共\(totalCount)人").font(.system(size: 16)).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button { router.push(.teacherMessages) } label: {
                        Image(systemName: "bell").overlay(alignment: .topTrailing) {
                            if state.unreadMessageCount > 0 { Circle().fill(.red).frame(width: 5, height: 5) }
                        }
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                    }.buttonStyle(.plain).accessibilityLabel("消息通知").accessibilityHint("打开消息中心")
                }
                .font(.system(size: 16, weight: .semibold))
                .padding(.horizontal, AppTheme.pagePadding)
                .padding(.top, 8)

                HStack {
                    Menu {
                        ForEach(state.managedTeacherClasses) { item in
                            Button(item.name) { selectedClassID = item.id }
                        }
                    } label: {
                        Label(className, systemImage: "person.3.fill")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(ReferenceColor.blue)
                    }
                    Menu {
                        ForEach(state.data?.tasks ?? []) { item in Button(item.title) { selectedTaskID = item.id } }
                    } label: {
                        Label(currentTask?.title ?? "选择测评任务", systemImage: "list.clipboard")
                            .font(.system(size: 16, weight: .semibold)).foregroundStyle(ReferenceColor.blue)
                    }
                    chip("本轮综合测评", selected: selectedPeriod == 0) { selectedPeriod = 0 }
                    chip("2026春季", selected: selectedPeriod == 1) { selectedPeriod = 1 }
                    Spacer()
                    Text("更新于 \(BusinessClock.string(format: "MM-dd HH:mm"))").font(.system(size: 16)).foregroundStyle(.secondary)
                }
                .padding(.horizontal, AppTheme.pagePadding)

                if isHistorical {
                    Button { historicalDetailShown = true } label: {
                        Label("2026春季为已归档汇总；学生明细请切换回本轮综合测评查看", systemImage: "archivebox.fill")
                            .font(.system(size: 16)).foregroundStyle(ReferenceColor.purple)
                            .frame(maxWidth: .infinity, alignment: .leading).padding(9)
                            .background(ReferenceColor.purple.opacity(0.08), in: RoundedRectangle(cornerRadius: 9))
                    }
                    .buttonStyle(.plain).padding(.horizontal, AppTheme.pagePadding)
                }

                boardCard(title: "班级健康概览", trailing: isHistorical ? "归档说明" : "查看明细", action: drillDown { router.push(.studentList(classInfo)) }) {
                    HStack {
                        boardStat("班级人数", "\(remoteOverview?.totalCount ?? totalCount)", "person.3.fill", ReferenceColor.blue, action: drillDown { router.push(.studentList(classInfo)) })
                        boardStat("已测评", "\(remoteOverview?.completedCount ?? measuredCount)", "checkmark.circle.fill", ReferenceColor.green, action: drillDown { router.push(.teacherTasks) })
                        boardStat("测评率", "\(remoteOverview.map { $0.totalCount == 0 ? 0 : $0.completedCount * 100 / $0.totalCount } ?? Int(completion * 100))%", "circle", ReferenceColor.green, action: drillDown { router.push(.teacherTasks) })
                        boardStat("待处理预警", "\(riskCount)", "exclamationmark.shield.fill", .red, action: drillDown { router.push(.reviewList) })
                    }
                }

                boardCard(title: "7 项运动项目进度", trailing: isHistorical ? "归档说明" : "查看任务", action: drillDown { router.push(.teacherTasks) }) {
                    Text("仅统计学校场地端的综合运动能力测评任务。")
                        .font(.system(size: 16)).foregroundStyle(.secondary)
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 2), spacing: 8) {
                        ForEach(TestItem.allCases) { item in
                            Button(action: drillDown { router.push(.teacherTasks) }) {
                                HStack(spacing: 8) {
                                    Image(systemName: item.icon).font(.system(size: 20, weight: .semibold)).foregroundStyle(ReferenceColor.blue)
                                    VStack(alignment: .leading, spacing: 3) {
                                        Text(item.rawValue).font(.system(size: 16, weight: .semibold)).foregroundStyle(ReferenceColor.navy).lineLimit(2)
                                        if let metric = remoteOverview?.itemStats.first(where: { $0.itemCode == item.rawValue }) {
                                            Text("\(metric.measuredCount)/\(metric.totalCount)人 · \(metric.averageScore, specifier: "%.1f")分").font(.system(size: 16)).foregroundStyle(.secondary)
                                        } else { Text(state.usesRemoteDataSource ? "暂无该项目数据" : "单项数据待同步").font(.system(size: 16)).foregroundStyle(.secondary) }
                                    }
                                    Spacer(minLength: 0)
                                }.frame(maxWidth: .infinity, minHeight: 52, alignment: .leading).padding(10).background(ReferenceColor.sky.opacity(0.62), in: RoundedRectangle(cornerRadius: 12))
                            }.buttonStyle(.plain).accessibilityLabel("查看\(item.rawValue)任务进度")
                        }
                    }
                }

                HStack(spacing: 7) {
                    // This is a teacher-scoped drill-down.  Routing to the
                    // principal risk workbench leaked the wrong role header
                    // and school-wide context into a class teacher's board.
                    compactBoardCard(title: "问题分布", trailing: "", action: drillDown { router.push(.reviewList) }) {
                        VStack(spacing: 5) {
                            smallBar("低分", min(1, Double(lowScoreCount) / Double(max(1, classStudents.count))), ReferenceColor.blue, "\(lowScoreCount)人")
                            smallBar("待复核", min(1, Double(reviewCount) / Double(max(1, classStudents.count))), .orange, "\(reviewCount)人")
                            smallBar("待补测", min(1, Double(retestCount) / Double(max(1, classStudents.count))), ReferenceColor.purple, "\(retestCount)人")
                        }
                    }
                    compactBoardCard(title: "班级总评", trailing: "", action: drillDown { router.push(.reviewList) }) {
                        HStack(spacing: 10) {
                            ZStack {
                                Circle().trim(from: 0.15, to: 0.92).stroke(AngularGradient(colors: [ReferenceColor.green, ReferenceColor.yellow, .red], center: .center), style: StrokeStyle(lineWidth: 8, lineCap: .round)).rotationEffect(.degrees(-90))
                                Text("\(riskCount)").font(.system(size: 17, weight: .bold))
                            }
                            .frame(width: 54, height: 54)
                            VStack(alignment: .leading, spacing: 4) {
                                Label("待处理 \(riskCount)", systemImage: "exclamationmark.circle.fill").foregroundStyle(.red)
                                Label("处理中 \(processingCount)", systemImage: "circle.fill").foregroundStyle(ReferenceColor.yellow)
                                Label("已完成 \(completedCount)", systemImage: "checkmark.circle.fill").foregroundStyle(ReferenceColor.green)
                            }
                            .font(.system(size: 16, weight: .medium))
                        }
                    }
                }
                .padding(.horizontal, AppTheme.pagePadding)

                boardCard(title: "测评平均完成趋势", trailing: isHistorical ? "归档说明" : "查看详情", action: drillDown { router.push(.teacherTasks) }) {
                    EmptyStateView(title: isHistorical ? "暂无历史趋势数据" : "暂无趋势数据", detail: "趋势数据同步后显示，不展示演示统计。")
                }

                boardCard(title: "重点关注学生", trailing: isHistorical ? "归档说明" : "查看全部", action: drillDown { router.push(.reviewList) }) {
                    if isHistorical {
                        Text("历史周期数据尚未同步；不展示演示统计或学生明细。")
                            .font(.system(size: 16)).foregroundStyle(.secondary).frame(maxWidth: .infinity, alignment: .leading)
                    } else if riskStudents.isEmpty {
                        Text("当前没有重点风险学生").font(.system(size: 16)).foregroundStyle(.secondary).frame(maxWidth: .infinity, alignment: .leading)
                    } else {
                        VStack(spacing: 6) {
                            ForEach(Array(riskStudents.prefix(3))) { student in
                                Button {
                                    router.push(.report(student))
                                } label: {
                                    studentAlert(student.name, riskDetail(for: student), state.taskStatus(for: student).rawValue, riskColor(for: student))
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel("查看\(student.name)的风险报告")
                            }
                        }
                    }
                }

                HStack(spacing: 7) {
                    actionButton("推送班级通知", "bell.fill", ReferenceColor.blue) { router.push(.teacherNoticeComposer) }
                    ShareLink(item: classBoardExport, subject: Text("\(className)测评数据报告")) {
                        Label("导出班级数据报告", systemImage: "square.and.arrow.up")
                            .font(.system(size: 16, weight: .bold))
                            .frame(maxWidth: .infinity)
                            .frame(minHeight: 48)
                            .foregroundStyle(.white)
                            .background(ReferenceColor.purple, in: RoundedRectangle(cornerRadius: 12))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("导出班级数据报告")
                    actionButton("处理重点预警", "exclamationmark.shield.fill", .red) { router.push(.reviewList) }
                }
                .padding(.horizontal, AppTheme.pagePadding)
            }
            .padding(.bottom, 10)
        }
        .task(id: "\(selectedClassID ?? "")|\(currentTask?.id ?? "")") {
            guard let classID = classInfo?.id, let task = currentTask else { return }
            await state.loadTeacherOverview(classID: classID, task: task)
        }
        .background(ReferenceColor.canvas)
        .overlay {
            if let error = state.error, state.data == nil {
                ZStack {
                    ReferenceColor.canvas.ignoresSafeArea()
                    ErrorStateView(message: error) { Task { await state.refreshDashboard() } }
                }
            } else if state.loading || state.data == nil {
                ZStack {
                    ReferenceColor.canvas.ignoresSafeArea()
                    LoadingStateView()
                }
            } else if state.usesRemoteDataSource && !isHistorical && remoteOverview == nil {
                ZStack {
                    ReferenceColor.canvas.ignoresSafeArea()
                    EmptyStateView(title: "当前班级统计正在同步", detail: "服务端返回本任务统计后，将显示完成率、风险分布和单项成绩。")
                }
            } else if classStudents.isEmpty {
                ZStack {
                    ReferenceColor.canvas.ignoresSafeArea()
                    EmptyStateView(title: "暂无班级数据", detail: "学生名单同步后，这里会显示班级看板。")
                }
            }
        }
        .navigationBarBackButtonHidden()
        .task(id: reduceMotion) {
            guard !reduceMotion else { dashboardAppeared = true; return }
            withAnimation(.spring(response: 0.8, dampingFraction: 0.75).delay(0.18)) { dashboardAppeared = true }
        }
        .sheet(isPresented: $historicalDetailShown) {
            NavigationStack {
                List {
                    Section("2026春季归档") { Text("历史汇总尚未同步，当前不展示演示人数、完成率或风险数。") }
                    Section("查看范围") {
                        Text("该周期仅保留班级汇总。出于学生健康数据保护，历史学生明细需由学校管理端授权后查看；本应用当前只开放本轮测评的学生报告。")
                    }
                }
                .navigationTitle("历史测评归档")
                .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("关闭") { historicalDetailShown = false } } }
            }
        }
    }

    private var classBoardExport: String {
        """
        向上少年 · \(className)测评数据报告
        测评完成率：\(Int(completion * 100))%
        已完成：\(measuredCount) / \(totalCount) 人
        待处理预警：\(riskCount) 人
        待复核：\(reviewCount) 人；待补测：\(retestCount) 人
        评测标准：小学综合运动能力标准 v1.0
        """
    }

    private func chip(_ text: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(text + "⌄")
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(selected ? ReferenceColor.blue : ReferenceColor.navy)
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(selected ? ReferenceColor.sky : .white, in: Capsule())
                .overlay(Capsule().stroke(ReferenceColor.blue.opacity(selected ? 0.35 : 0.08), lineWidth: 1))
        }.buttonStyle(.plain)
    }

    private func drillDown(_ action: @escaping () -> Void) -> () -> Void {
        { if isHistorical { historicalDetailShown = true } else { action() } }
    }

    private func boardCard<Content: View>(title: String, trailing: String, action: @escaping () -> Void, @ViewBuilder content: () -> Content) -> some View {
        ReferenceCard {
            VStack(alignment: .leading, spacing: 7) {
                ReferenceSectionTitle(title: title, trailing: trailing, action: action)
                content()
            }
        }
        .padding(.horizontal, AppTheme.pagePadding)
    }

    private func compactBoardCard<Content: View>(title: String, trailing: String, action: @escaping () -> Void, @ViewBuilder content: () -> Content) -> some View {
        Button(action: action) {
            ReferenceCard {
                VStack(alignment: .leading, spacing: 7) {
                    ReferenceSectionTitle(title: title, trailing: trailing)
                    content()
                }
            }
        }
        .buttonStyle(.plain)
    }

    private func boardStat(_ title: String, _ value: String, _ icon: String, _ color: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 3) {
                Text(title).font(.system(size: 16)).foregroundStyle(.secondary)
                HStack(spacing: 2) {
                    Text(value).font(.system(size: 18, weight: .bold)).foregroundStyle(color)
                    Image(systemName: icon).font(.system(size: 16)).foregroundStyle(color)
                }
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("查看\(title)：\(value)")
    }

    private func healthGauge(_ title: String, _ color: Color, completion: Double, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 2) {
                Text(title).font(.system(size: 16, weight: .bold))
                ZStack {
                    Circle().stroke(color.opacity(0.18), lineWidth: 5)
                    Circle().trim(from: 0, to: dashboardAppeared ? completion : 0)
                        .stroke(color, style: StrokeStyle(lineWidth: 5, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                    Text("\(Int(completion * 100))%").font(.system(size: 16, weight: .bold)).foregroundStyle(color)
                }
                .frame(width: 40, height: 40)
                Text("\(Int((1 - completion) * 100))% 未完成").font(.system(size: 16)).foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 3)
            .background(color.opacity(0.04), in: RoundedRectangle(cornerRadius: 7))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("查看\(title)测评健康度")
    }

    private func smallBar(_ label: String, _ value: Double, _ color: Color, _ count: String) -> some View {
        HStack(spacing: 5) {
            Text(label).font(.system(size: 16)).frame(width: 34, alignment: .leading)
            GeometryReader { proxy in
                RoundedRectangle(cornerRadius: 3).fill(color).frame(width: proxy.size.width * value, height: 5)
            }
            .frame(height: 5)
            Text(count).font(.system(size: 16)).foregroundStyle(.secondary)
        }
    }

    private func studentAlert(_ name: String, _ detail: String, _ state: String, _ color: Color) -> some View {
        HStack(spacing: 8) {
            Circle().fill(color.opacity(0.15)).frame(width: 28, height: 28).overlay(Text(String(name.prefix(1))).font(.system(size: 16, weight: .bold)).foregroundStyle(color))
            Text(name).font(.system(size: 16, weight: .bold)).frame(width: 48, alignment: .leading)
            Text(detail).font(.system(size: 16)).foregroundStyle(.secondary)
            Spacer()
            Text(state).font(.system(size: 16, weight: .bold)).foregroundStyle(color)
        }
        .frame(minHeight: 48)
    }

    private func riskDetail(for student: Student) -> String {
        switch state.taskStatus(for: student) {
        case .review: return "测评结果待复核"
        case .retest: return "需要安排补测"
        default: return "综合得分偏低"
        }
    }

    private func riskColor(for student: Student) -> Color {
        switch state.taskStatus(for: student) {
        case .retest: return ReferenceColor.purple
        case .review: return .orange
        default: return .red
        }
    }

    private func actionButton(_ title: String, _ icon: String, _ color: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: icon)
                .font(.system(size: 16, weight: .bold))
                .frame(maxWidth: .infinity)
                .frame(minHeight: 48)
                .foregroundStyle(.white)
                .background(color, in: RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
    }
}

struct TeacherClassesView: View {
    @EnvironmentObject private var state: AppState
    @EnvironmentObject private var router: AppRouter
    var body: some View {
        ScrollView {
            VStack(spacing: 10) {
                ParentPageNavigation(title: "我管理的班级", showsBack: true)
                ReferenceHeader(name: state.activeDisplayName, school: "\(state.profile?.schoolName ?? "学校") · \(state.managedTeacherClasses.map(\.name).joined(separator: "、").isEmpty ? "暂无班级" : state.managedTeacherClasses.map(\.name).joined(separator: "、"))", initial: String(state.activeDisplayName.prefix(1)), avatarAsset: "TeacherAvatar")
                ReferenceSectionTitle(title: "我管理的班级", trailing: "负责 \(state.managedTeacherClasses.count) 个班级").padding(.horizontal, AppTheme.pagePadding)
                if let error = state.error, state.data == nil {
                    ErrorStateView(message: error) { Task { await state.refreshDashboard() } }
                } else if state.loading || state.data == nil {
                    LoadingStateView()
                } else if let data = state.data, data.classes.isEmpty {
                    EmptyStateView(title: "暂无管理班级", detail: "学校完成分班后，这里会显示管理班级。")
                } else if let data = state.data {
                    ForEach(state.managedTeacherClasses) { item in
                        let classStudents = data.students.filter { $0.classID == item.id }
                        let completedCount = classStudents.filter { student in
                            state.taskStatus(for: student) == .completed
                        }.count
                        let completionRate: Int = {
                            // Dashboard student rows are paged in Remote mode;
                            // use the class aggregate returned by the school
                            // service instead of a partial local numerator.
                            if state.usesRemoteDataSource { return item.completionRate }
                            guard !classStudents.isEmpty else { return item.completionRate }
                            return Int((Double(completedCount) / Double(classStudents.count) * 100).rounded())
                        }()
                        Button { router.push(.studentList(item)) } label: {
                            HStack {
                                VStack(alignment: .leading) {
                                    Text(item.name).font(.system(size: 16, weight: .bold))
                                    Text("\(item.studentCount)人 · \(item.teacherName)").font(.system(size: 16)).foregroundStyle(.secondary)
                                }
                                Spacer()
                                VStack(alignment: .trailing) {
                                    Text("\(completionRate)%").font(.system(size: 17, weight: .bold)).foregroundStyle(ReferenceColor.green)
                                    Text("完成率").font(.system(size: 16)).foregroundStyle(.secondary)
                                }
                            }
                            .padding(16)
                            .background(.white, in: RoundedRectangle(cornerRadius: 10))
                        }
                        .buttonStyle(.plain)
                        .padding(.horizontal, AppTheme.pagePadding)
                    }
                }
            }
        }
        .background(ReferenceColor.canvas)
    }
}

enum StudentListMode: Equatable {
    case all, outstanding, unassigned
    var title: String {
        switch self {
        case .all: "学生列表"
        case .outstanding: "优秀学生评选"
        case .unassigned: "待分班学生"
        }
    }
    var emptyDetail: String {
        switch self {
        case .all: "当前班级暂未同步学生名单。"
        case .outstanding: "完成测评后，总分达到 30 分的学生会显示在这里。"
        case .unassigned: "当前所有学生均已完成班级归属，学校同步新的待分班名单后会显示在这里。"
        }
    }
}

struct StudentListView: View {
    @EnvironmentObject private var state: AppState
    @EnvironmentObject private var router: AppRouter
    let classInfo: ClassInfo?
    var mode: StudentListMode = .all
    var body: some View {
        AppScaffold(title: classInfo?.name ?? mode.title) {
            VStack(spacing: 8) {
                if let error = state.error, state.data == nil {
                    ErrorStateView(message: error) { Task { await state.refreshDashboard() } }
                } else if state.loading || state.data == nil {
                    LoadingStateView()
                } else {
                    let students = (state.data?.students ?? []).filter {
                        (classInfo == nil || $0.classID == classInfo?.id)
                        && (mode != .outstanding || ((state.hasPublishedSchoolReport(for: $0) && (state.visibleReport(for: $0)?.totalScore ?? 0) >= 30)))
                        && (mode != .unassigned || $0.className.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                    if students.isEmpty {
                        EmptyStateView(title: mode == .outstanding ? "暂无符合条件的学生" : mode == .unassigned ? "暂无待分班学生" : "暂无学生数据", detail: mode.emptyDetail)
                    } else {
                        ForEach(students.sorted { (state.visibleReport(for: $0)?.totalScore ?? -1) > (state.visibleReport(for: $1)?.totalScore ?? -1) }) { student in
                            StudentCard(student: student) { router.push(.report(student)) }
                        }
                        if let total = state.data?.studentTotal, let loaded = state.data?.students.count, loaded < total {
                            VStack(spacing: 6) {
                                if let loadError = state.studentsLoadError {
                                    Text(loadError).font(.subheadline).foregroundStyle(.red).multilineTextAlignment(.center)
                                }
                                Button {
                                    Task { await state.loadMoreStudents() }
                                } label: {
                                    HStack(spacing: 6) {
                                        if state.studentsLoadingMore { ProgressView().controlSize(.small) }
                                        Text(state.studentsLoadingMore ? "正在加载" : "加载更多学生（已显示 \(loaded)/\(total)）")
                                    }
                                    .frame(maxWidth: .infinity).padding(.vertical, 10)
                                }
                                .buttonStyle(.borderedProminent)
                                .disabled(state.studentsLoadingMore || state.isOffline)
                                .accessibilityLabel("加载更多学生，已显示 \(loaded) 人，共 \(total) 人")
                            }.padding(.vertical, 8)
                        }
                    }
                }
            }
        }
    }
}

struct TeacherTasksView: View {
    @EnvironmentObject private var state: AppState
    @EnvironmentObject private var router: AppRouter
    var body: some View {
        ScrollView {
            VStack(spacing: 10) {
                ParentPageNavigation(title: "延时课程上传", showsBack: true)
                ReferenceHeader(name: state.activeDisplayName, school: "\(state.profile?.schoolName ?? "学校") · 体育组", initial: String(state.activeDisplayName.prefix(1)), avatarAsset: "TeacherAvatar")
                ReferenceSectionTitle(title: "近日测评任务", trailing: "共 \(state.data?.tasks.count ?? 0) 项任务").padding(.horizontal, AppTheme.pagePadding)
                if let error = state.error, state.data == nil {
                    ErrorStateView(message: error) { Task { await state.refreshDashboard() } }
                } else if state.loading || state.data == nil {
                    LoadingStateView()
                } else {
                    let tasks = state.data?.tasks ?? []
                    if tasks.isEmpty {
                        EmptyStateView(title: "暂无测评任务", detail: "新的任务发布后会在这里显示。")
                    } else {
                        ForEach(tasks) { task in
                            TestTaskCard(task: task) { router.push(.teacherTaskDetail(task)) }
                                .padding(.horizontal, AppTheme.pagePadding)
                        }
                    }
                }
            }
        }
        .background(ReferenceColor.canvas)
    }
}

struct TeacherTaskDetailView: View {
    @EnvironmentObject private var state: AppState
    @EnvironmentObject private var router: AppRouter
    let task: TestTask
    @State private var selectedStudent: Student?
    @State private var rosterSearch = ""
    @State private var rosterStatus: TaskStatus?
    var body: some View {
        let currentTask = state.data?.tasks.first(where: { $0.id == task.id }) ?? task
        AppScaffold(title: "任务详情") {
            VStack(spacing: 10) {
                TestTaskCard(task: currentTask, action: nil)
                HStack(spacing: 8) {
                    TextField("搜索学生或班级", text: $rosterSearch)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(size: 15))
                    Menu {
                        Button("全部状态") { rosterStatus = nil }
                        ForEach(TaskStatus.allCases, id: \.self) { status in Button(status.rawValue) { rosterStatus = status } }
                    } label: {
                        Label(rosterStatus?.rawValue ?? "状态", systemImage: "line.3.horizontal.decrease.circle")
                            .font(.system(size: 16, weight: .semibold))
                    }
                }
                Text("点击学生按现场队列更新签到、候测、测试、复核或补测状态；不支持跨步骤直接完成。")
                    .font(.system(size: 16)).foregroundStyle(.secondary).frame(maxWidth: .infinity, alignment: .leading)
                if let error = state.error, state.data == nil {
                    ErrorStateView(message: error) { Task { await state.refreshDashboard() } }
                } else if state.loading || state.data == nil {
                    LoadingStateView()
                } else if state.usesRemoteDataSource && state.taskRosterRecords[currentTask.id] == nil {
                    LoadingStateView()
                } else {
                    let query = rosterSearch.trimmingCharacters(in: .whitespacesAndNewlines)
                    let taskStudents = state.taskRosterStudents(taskID: currentTask.id, fallbackTask: currentTask).filter { student in
                        state.canManageTaskStudent(student)
                        && (query.isEmpty || student.name.localizedCaseInsensitiveContains(query) || student.className.localizedCaseInsensitiveContains(query))
                        && (rosterStatus == nil || state.taskStatus(for: student, taskID: currentTask.id) == rosterStatus)
                    }
                    if taskStudents.isEmpty {
                        EmptyStateView(title: "暂无任务学生", detail: "该任务目前没有可操作的授权名单。")
                    }
                    ForEach(taskStudents) { student in
                        TeacherStudentStatusRow(student: student, status: state.taskStatus(for: student, taskID: currentTask.id), syncState: state.taskStatusSyncState(for: student, taskID: currentTask.id)) { selectedStudent = student }
                    }
                }
            }
        }
        .sheet(item: $selectedStudent) { student in TaskStatusSheet(student: student, status: state.taskStatus(for: student, taskID: currentTask.id), taskID: currentTask.id) }
        .task(id: currentTask.id) { await state.loadTaskStudents(taskID: currentTask.id) }
    }
}

struct ReviewListView: View {
    @EnvironmentObject private var state: AppState
    @EnvironmentObject private var router: AppRouter
    @State private var selectedStudent: Student?
    @State private var selectedBodyReview: BodyScreeningReviewItem?
    @State private var reviewMode = 0
    var body: some View {
        ScrollView {
            VStack(spacing: 10) {
                ParentPageNavigation(title: "预警中心", showsBack: true)
                ReferenceHeader(name: state.activeDisplayName, school: "\(state.profile?.schoolName ?? "学校") · \(state.managedTeacherClasses.map(\.name).joined(separator: "、").isEmpty ? "暂无班级" : state.managedTeacherClasses.map(\.name).joined(separator: "、"))", initial: String(state.activeDisplayName.prefix(1)), avatarAsset: "TeacherAvatar")
                ReferenceSectionTitle(title: "预警中心", trailing: "待处理列表").padding(.horizontal, AppTheme.pagePadding)
                Picker("复核类型", selection: $reviewMode) {
                    Text("学校体测").tag(0)
                    Text("家庭身体观察").tag(1)
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, AppTheme.pagePadding)
                if reviewMode == 0 {
                if let error = state.error, state.data == nil {
                    ErrorStateView(message: error) { Task { await state.refreshDashboard() } }
                } else if state.loading || state.data == nil {
                    LoadingStateView()
                } else {
                    let managedClassIDs = Set(state.managedTeacherClasses.map(\.id))
                    let students = state.data?.students.filter { student in
                        guard let classID = student.classID, managedClassIDs.contains(classID) else { return false }
                        return [.review, .retest, .absent].contains(state.taskStatus(for: student))
                    } ?? []
                    Text("待处理 \(students.count) 人 · 点击可更新处理状态")
                        .font(.system(size: 16, weight: .semibold)).foregroundStyle(.red).frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, AppTheme.pagePadding)
                    ForEach(students) { student in
                        TeacherStudentStatusRow(student: student, status: state.taskStatus(for: student), syncState: state.localFeatures.taskStatusSyncStates[student.id]) { selectedStudent = student }
                            .padding(.horizontal, AppTheme.pagePadding)
                        if let note = state.localFeatures.reviewNotes[student.id] {
                            Text("复核意见：\(note)")
                                .font(.system(size: 16)).foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 18)
                        }
                    }
                    if students.isEmpty { EmptyStateView(title: "暂无待处理预警", detail: "待复核、待补测和缺席学生将在此显示。") }
                }
                } else {
                    bodyScreeningReviewQueue
                }
            }
        }
        .background(ReferenceColor.canvas)
        .sheet(item: $selectedStudent) { student in TaskStatusSheet(student: student, status: state.taskStatus(for: student), requiresReviewNote: true) }
        .sheet(item: $selectedBodyReview) { item in BodyScreeningReviewSheet(item: item) }
        .task(id: reviewMode) { if reviewMode == 1 { await state.loadBodyScreeningReviews() } }
    }

    @ViewBuilder private var bodyScreeningReviewQueue: some View {
        if !state.teacherHasCapability("REVIEW_RESULT") {
            ErrorStateView(message: "当前账号没有身体观察复核权限。") { router.pop() }
        } else if state.bodyScreeningReviewsLoading && state.bodyScreeningReviews.isEmpty {
            LoadingStateView()
        } else if let error = state.bodyScreeningReviewsError, state.bodyScreeningReviews.isEmpty {
            ErrorStateView(message: error) { Task { await state.loadBodyScreeningReviews() } }
        } else if state.bodyScreeningReviews.isEmpty {
            EmptyStateView(title: "暂无身体观察待复核记录", detail: "算法不确定、质量边界或风险候选记录将在这里显示。")
        } else {
            Text("待处理 \(state.bodyScreeningReviews.count) 条 · 仅展示结构化证据，不包含原始照片或视频")
                .font(.system(size: 15, weight: .semibold)).foregroundStyle(AppTheme.muted)
                .frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, AppTheme.pagePadding)
            ForEach(state.bodyScreeningReviews) { item in
                Button { selectedBodyReview = item } label: {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            Text(item.studentDisplayName).font(.system(size: 16, weight: .bold)).foregroundStyle(ReferenceColor.navy)
                            Spacer()
                            Text("质量 \(item.qualityScore.map(String.init) ?? "--")")
                                .font(.system(size: 15, weight: .semibold)).foregroundStyle(item.qualityScore.map { $0 >= 70 ? ReferenceColor.green : AppTheme.warning } ?? AppTheme.muted)
                            Image(systemName: "chevron.right").foregroundStyle(AppTheme.muted)
                        }
                        Text("\(item.attempts.count) 项结构化证据 · \(item.reasonCodes.map(bodyReviewReason).joined(separator: "、"))")
                            .font(.system(size: 15)).foregroundStyle(AppTheme.muted).fixedSize(horizontal: false, vertical: true)
                        HStack {
                            Text(item.protocolVersion ?? "协议版本待同步")
                            Spacer()
                            Text("v\(item.version)")
                        }.font(.system(size: 16)).foregroundStyle(.secondary)
                    }
                    .padding(15).background(.white, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                }.buttonStyle(.plain).padding(.horizontal, AppTheme.pagePadding)
                    .accessibilityLabel("\(item.studentDisplayName)身体观察待复核，质量分\(item.qualityScore.map(String.init) ?? "未知")")
            }
        }
    }

    private func bodyReviewReason(_ code: String) -> String {
        switch code {
        case "MODEL_PENDING_HUMAN_VALIDATION": "模型待人工验证"
        case "RISK_CANDIDATE": "存在关注指标"
        case "HIGH_UNCERTAINTY": "算法不确定性较高"
        case "LOW_CONFIDENCE": "关键点置信度不足"
        case "REPEATABILITY_FAILED": "两次采集一致性不足"
        default: code.replacingOccurrences(of: "_", with: " ")
        }
    }
}

private struct BodyScreeningReviewSheet: View {
    let item: BodyScreeningReviewItem
    @EnvironmentObject private var state: AppState
    @Environment(\.dismiss) private var dismiss
    @State private var decision: BodyScreeningReviewDecision = .continueObservation
    @State private var comment = ""
    @State private var recaptureTasks: Set<BodyAssessmentRecord.CaptureTask> = []
    private var workflowKey: String { "body-screening-review:\(item.reviewId)" }

    var body: some View {
        NavigationStack {
            List {
                Section("结构化采集证据") {
                    LabeledContent("学生", value: item.studentDisplayName)
                    LabeledContent("总质量分", value: item.qualityScore.map(String.init) ?? "未提供")
                    ForEach(item.attempts) { attempt in
                        VStack(alignment: .leading, spacing: 6) {
                            Text(taskTitle(attempt.captureTask)).font(.headline)
                            Text("置信度 \(Int(attempt.confidence * 100))% · \(attempt.sampleCount) 个有效样本 · \(attempt.attemptCount) 次采集")
                                .font(.subheadline).foregroundStyle(.secondary)
                            if let quality = attempt.qualityScore { ProgressView(value: Double(quality), total: 100).tint(quality >= 70 ? ReferenceColor.green : AppTheme.warning) }
                            ForEach(attempt.evidenceMetrics ?? []) { metric in
                                VStack(alignment: .leading, spacing: 2) {
                                    HStack(alignment: .firstTextBaseline) {
                                        Text(metric.label).foregroundStyle(ReferenceColor.navy)
                                        Spacer(minLength: 12)
                                        Text(metric.displayedValue).fontWeight(.semibold).multilineTextAlignment(.trailing)
                                    }
                                    Text(metric.sourceTitle).font(.subheadline).foregroundStyle(.secondary)
                                }
                                .font(.subheadline)
                                .accessibilityElement(children: .combine)
                                .accessibilityLabel("\(metric.label)，\(metric.displayedValue)，来源\(metric.sourceTitle)")
                            }
                            if (attempt.evidenceMetrics ?? []).isEmpty {
                                Text("本动作暂无可展示的白名单指标，仅可依据采集质量决定是否重采。")
                                    .font(.subheadline).foregroundStyle(.secondary)
                            }
                        }.accessibilityElement(children: .combine)
                    }
                    Text("“相对投影值”和“摄像头估计”不是物理厘米、ATR 或 Cobb 角。不提供原始照片或视频；复核结论仅用于健康管理与后续行动，不构成医疗诊断。")
                        .font(.subheadline).foregroundStyle(.secondary)
                }
                Section("复核结论") {
                    Picker("处理方式", selection: $decision) { ForEach(BodyScreeningReviewDecision.allCases) { Text($0.title).tag($0) } }
                    TextEditor(text: $comment).frame(minHeight: 96).accessibilityLabel("复核依据和后续处理说明")
                    if decision == .recapture {
                        ForEach(BodyAssessmentRecord.CaptureTask.allCases, id: \.self) { task in
                            Toggle(task.title, isOn: Binding(get: { recaptureTasks.contains(task) }, set: { selected in if selected { recaptureTasks.insert(task) } else { recaptureTasks.remove(task) } }))
                        }
                    }
                    if case let .failed(message) = state.workflowState(for: workflowKey) { Text(message).foregroundStyle(.red).font(.subheadline) }
                }
                Section {
                    Button {
                        Task { if await state.submitBodyScreeningReview(item, decision: decision, comment: comment, recaptureTasks: recaptureTasks) { dismiss() } }
                    } label: {
                        HStack { Spacer(); if state.workflowState(for: workflowKey).isSubmitting { ProgressView() } else { Text("确认提交").fontWeight(.semibold) }; Spacer() }
                    }.disabled(state.workflowState(for: workflowKey).isSubmitting)
                }
            }
            .navigationTitle("身体观察复核")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("关闭") { dismiss() } } }
        }
    }

    private func taskTitle(_ value: String) -> String { BodyAssessmentRecord.CaptureTask(rawValue: value)?.title ?? value }
}

private struct TeacherStudentStatusRow: View {
    let student: Student
    let status: TaskStatus
    let syncState: LocalSubmissionStatus?
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Text(String(student.name.prefix(1))).font(.system(size: 15, weight: .bold)).foregroundStyle(.white).frame(width: 32, height: 32).background(ReferenceColor.blue, in: Circle())
                VStack(alignment: .leading, spacing: 3) { Text(student.name).font(.system(size: 16, weight: .bold)); Text("\(student.grade) · \(student.className)").font(.system(size: 16)).foregroundStyle(.secondary) }
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text(status.rawValue).font(.system(size: 16, weight: .bold)).foregroundStyle(status.color).padding(.horizontal, 8).padding(.vertical, 4).background(status.color.opacity(0.12), in: Capsule())
                    if let syncState {
                        Text(syncState.taskStatusLabel)
                            .font(.system(size: 16, weight: .medium))
                            .foregroundStyle(syncState == .failed ? Color.red : .secondary)
                    }
                }
                Image(systemName: "chevron.right").font(.system(size: 16, weight: .bold)).foregroundStyle(.secondary)
            }.padding(11).background(.white, in: RoundedRectangle(cornerRadius: 10))
        }.buttonStyle(.plain)
    }
}

private struct TaskStatusSheet: View {
    let student: Student
    let status: TaskStatus
    let taskID: String?
    var requiresReviewNote: Bool
    @EnvironmentObject private var state: AppState
    @Environment(\.dismiss) private var dismiss
    @State private var reviewNote = ""
    @State private var validationMessage: String?
    private var draftKey: String { "review-note-\(student.id)" }

    init(student: Student, status: TaskStatus, taskID: String? = nil, requiresReviewNote: Bool = false) {
        self.student = student
        self.status = status
        self.taskID = taskID
        self.requiresReviewNote = requiresReviewNote
    }
    var body: some View {
        NavigationStack {
            List {
                if requiresReviewNote {
                    Section("复核 / 补测处理意见") {
                        TextEditor(text: $reviewNote).frame(minHeight: 92)
                        Text("请说明证据核验结果、是否需要补测及后续处理。")
                            .font(.subheadline).foregroundStyle(.secondary)
                        if let validationMessage { Text(validationMessage).font(.subheadline).foregroundStyle(.red) }
                    }
                }
                    Section("可执行的下一步") {
                        ForEach(status.allowedNextStatuses, id: \.self) { item in
                        Button {
                            if requiresReviewNote && reviewNote.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                                validationMessage = "请先填写复核或补测处理意见。"
                                return
                            }
                            Task {
                                if await state.submitTaskStatusCommand(taskID: taskID, studentID: student.id, status: item, note: reviewNote) {
                                    state.clearDraft(draftKey)
                                    dismiss()
                                }
                            }
                        } label: {
                            HStack { Text(item.rawValue); Spacer(); if state.workflowState(for: "task-status:\(taskID ?? "missing-task")|\(student.id)").isSubmitting { ProgressView() } else if item == status { Image(systemName: "checkmark").foregroundStyle(ReferenceColor.blue) } }
                        }.foregroundStyle(item == status ? ReferenceColor.blue : ReferenceColor.navy)
                            .disabled(state.workflowState(for: "task-status:\(taskID ?? "missing-task")|\(student.id)").isSubmitting)
                    }
                    if case let .failed(message) = state.workflowState(for: "task-status:\(taskID ?? "missing-task")|\(student.id)") { Text(message).font(.subheadline).foregroundStyle(.red) }
                }
            }
            .navigationTitle("处理\(student.name)预警")
            .task { reviewNote = state.localFeatures.drafts[draftKey] ?? state.localFeatures.reviewNotes[student.id] ?? "" }
            .onChange(of: reviewNote) { _, value in state.saveDraft(value, key: draftKey) }
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("取消") { dismiss() } } }
        }
    }
}

private extension TaskStatus {
    var color: Color {
        switch self { case .completed: ReferenceColor.green; case .review, .absent: .red; case .retest: .orange; case .testing: ReferenceColor.blue; default: .secondary }
    }
}

extension LocalSubmissionStatus {
    var taskStatusLabel: String {
        switch self {
        case .draft: "本地草稿"
        case .pendingSync: "待同步"
        case .submitting: "同步中"
        case .submitted: "已同步"
        case .failed: "同步失败"
        }
    }
}
