import SwiftUI

struct PrincipalHomeView: View {
    @EnvironmentObject private var state: AppState
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    @State private var selectedTab = 0

    private var reduceMotion: Bool { state.localFeatures.settings.reduceMotion || systemReduceMotion }

    var body: some View {
        ZStack {
            ReferenceColor.canvas.ignoresSafeArea()
        VStack(spacing: 0) {
            Group {
                switch selectedTab {
                case 0: PrincipalDashboard()
                case 1: GradeStatsView()
                case 2: ClassStatsView()
                default: RiskStudentsView()
                }
            }
            .id(selectedTab)
            .transition(.opacity.combined(with: .move(edge: .trailing)))
            HStack {
                tab(0, "chart.bar.fill", "总览")
                tab(1, "graduationcap.fill", "年级")
                tab(2, "person.3.fill", "班级")
                tab(3, "exclamationmark.shield.fill", "风险")
            }
            .padding(.top, 7).padding(.bottom, 5)
            .background(.white)
            .overlay(alignment: .top) { Rectangle().fill(ReferenceColor.navy.opacity(0.06)).frame(height: 0.5) }
        }
        .background(ReferenceColor.canvas)
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.22), value: selectedTab)
        .frame(maxWidth: 720)
        .frame(maxWidth: .infinity)
        }
    }

    private func tab(_ index: Int, _ icon: String, _ title: String) -> some View {
        Button {
            if reduceMotion {
                var transaction = Transaction()
                transaction.animation = nil
                withTransaction(transaction) { selectedTab = index }
            } else {
                withAnimation { selectedTab = index }
            }
        } label: {
            VStack(spacing: 3) {
                Image(systemName: icon).font(.system(size: 14, weight: .semibold))
                Text(title).font(.system(size: 8, weight: .medium))
            }
            .foregroundStyle(selectedTab == index ? ReferenceColor.blue : Color.secondary)
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
        .accessibilityHint(selectedTab == index ? "当前页面" : "打开\(title)")
    }
}
struct PrincipalDashboard: View {
    @EnvironmentObject private var state: AppState
    @EnvironmentObject private var router: AppRouter
    @State private var selectedPeriod = 0
    @State private var dashboardAppeared = false
    @State private var isRegionDetailShown = false

    private var students: [Student] { state.data?.students ?? [] }
    private var classes: [ClassInfo] { state.data?.classes ?? [] }
    private var activeTask: TestTask? { state.data?.tasks.first }
    // `TestTask` is the school-level aggregate published by the assessment service.
    // The local student list is intentionally only a representative Mock sample, so it
    // must not replace the task aggregate and turn 15/20 into the misleading 2/4.
    private var activeCompletedCount: Int { activeTask?.completedCount ?? 0 }
    private var activeTotalCount: Int { activeTask?.totalCount ?? 0 }
    private var completionRate: Double { guard activeTotalCount > 0 else { return 0 }; return Double(activeCompletedCount) / Double(activeTotalCount) }
    private func completionRate(for grade: Grade) -> Double {
        let gradeClasses = classes.filter { $0.gradeId == grade.id }
        guard !gradeClasses.isEmpty else { return 0 }
        return Double(gradeClasses.map(\.completionRate).reduce(0, +)) / Double(gradeClasses.count) / 100
    }
    private var riskStudents: [Student] { students.filter { ($0.totalScore ?? 35) < 25 || state.taskStatus(for: $0) == .review || state.taskStatus(for: $0) == .retest } }
    private var averageScore: Double { let scores = students.compactMap(\.totalScore); return scores.isEmpty ? 0 : scores.reduce(0, +) / Double(scores.count) }

    var body: some View {
        Group {
            if let error = state.error, state.data == nil {
                ErrorStateView(message: error) { Task { await state.refreshDashboard() } }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(ReferenceColor.canvas)
            } else if state.loading || state.data == nil {
                LoadingStateView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(ReferenceColor.canvas)
            } else if students.isEmpty {
                EmptyStateView(title: "暂无学校数据", detail: "请刷新后重试，或联系学校管理员。")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(ReferenceColor.canvas)
            } else {
                dashboardContent
            }
        }
    }

    private var dashboardContent: some View {
        ScrollView {
            VStack(spacing: 10) {
                ReferenceHeader(name: "周校长", school: "向上实验小学 · 南湖校区", initial: "周")
                HStack {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("学校运动健康总览").font(.system(size: 19, weight: .bold)).foregroundStyle(ReferenceColor.navy)
                        Text("覆盖3个年级 · 6个班级 · \(students.count)名学生").font(.system(size: 10)).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("退出校长端") {
                        state.chooseAnotherRole()
                        router.reset()
                    }
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(ReferenceColor.blue)
                    Picker("统计周期", selection: $selectedPeriod) {
                        Text("本轮测评").tag(0); Text("2026秋季").tag(1)
                    }.pickerStyle(.menu).tint(ReferenceColor.blue).font(.system(size: 11, weight: .semibold))
                }.padding(.horizontal, 14).padding(.top, 3)

                Button { router.push(.gradeStats) } label: { schoolHero }
                    .buttonStyle(.plain)
                    .scaleEffect(dashboardAppeared ? 1 : 0.96)
                    .opacity(dashboardAppeared ? 1 : 0)
                scoreGrid
                    .offset(y: dashboardAppeared ? 0 : 12)
                    .opacity(dashboardAppeared ? 1 : 0)
                gradeComparison
                    .offset(y: dashboardAppeared ? 0 : 18)
                    .opacity(dashboardAppeared ? 1 : 0)
                HStack(spacing: 9) {
                    overviewButton(title: "班级完成率", subtitle: "6个班级实时进度", icon: "rectangle.3.group.fill", color: ReferenceColor.purple, route: .classStats)
                    overviewButton(title: "重点风险学生", subtitle: "\(riskStudents.count)人需要跟进", icon: "person.crop.circle.badge.exclamationmark", color: .red, route: .riskStudents)
                }.padding(.horizontal, 12)
                Button { isRegionDetailShown = true } label: {
                    ReferenceCard {
                        VStack(alignment: .leading, spacing: 8) {
                            ReferenceSectionTitle(title: "区域关怀统计", trailing: "查看地区明细", showsLink: true)
                            HStack(spacing: 12) {
                                Image(systemName: "map.fill").font(.system(size: 26)).foregroundStyle(.orange).frame(width: 42, height: 42).background(.orange.opacity(0.12), in: Circle())
                                VStack(alignment: .leading, spacing: 3) {
                                    Text("粤北山区 · 贫困地区关怀").font(.system(size: 12, weight: .bold))
                                    Text("\(students.filter(\.isPovertyArea).count)名学生已纳入公益运动课程支持").font(.system(size: 10)).foregroundStyle(.secondary)
                                }
                                Spacer()
                                Image(systemName: "chevron.right").font(.system(size: 10, weight: .bold)).foregroundStyle(.secondary)
                            }
                        }
                    }
                }.buttonStyle(.plain).padding(.horizontal, 12)
            }.padding(.bottom, 14)
        }
        .background(ReferenceColor.canvas)
        .refreshable { await state.refreshDashboard() }
        .task { withAnimation(.spring(response: 0.65, dampingFraction: 0.78)) { dashboardAppeared = true } }
        .sheet(isPresented: $isRegionDetailShown) {
            NavigationStack {
                List {
                    Section("地区测评覆盖") {
                        regionRow("南湖校区", count: students.count, detail: "覆盖3个年级 · 6个班级")
                        regionRow("粤北山区", count: students.filter(\.isPovertyArea).count, detail: "贫困地区学生 · 已纳入公益支持")
                    }
                    Section("公益关怀进度") {
                        LabeledContent("已完成测评", value: "\(students.filter { ($0.totalScore ?? 0) > 0 }.count) 人")
                        LabeledContent("待重点跟进", value: "\(riskStudents.count) 人")
                        Text("地区标签和公益支持资格由学校管理端维护，场地端上传成绩后会自动刷新。")
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                }
                .navigationTitle("地区关怀明细")
                .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("关闭") { isRegionDetailShown = false } } }
            }
        }
    }

    private var schoolHero: some View {
        ReferenceCard {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Label("2026年秋季综合运动能力测评", systemImage: "chart.line.uptrend.xyaxis").font(.system(size: 13, weight: .bold))
                    Spacer()
                    Text("进行中").font(.system(size: 10, weight: .bold)).foregroundStyle(ReferenceColor.blue).padding(.horizontal, 9).padding(.vertical, 4).background(ReferenceColor.sky, in: Capsule())
                }
                HStack(alignment: .bottom) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("\(Int(completionRate * 100))%").font(.system(size: 31, weight: .bold)).foregroundStyle(ReferenceColor.blue)
                        Text("全校测评完成率").font(.system(size: 10)).foregroundStyle(.secondary)
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 3) {
                        Text("\(activeCompletedCount) / \(activeTotalCount) 人").font(.system(size: 14, weight: .bold)).foregroundStyle(ReferenceColor.navy)
                        Text("已完成 · 规则 v1.0").font(.system(size: 9)).foregroundStyle(.secondary)
                    }
                }
                AnimatedProgressLine(value: completionRate, colors: [ReferenceColor.blue, ReferenceColor.green], height: 8)
            }
        }.padding(.horizontal, 12)
    }

    private var scoreGrid: some View {
        HStack(spacing: 7) {
            dashboardMetric("平均总分", String(format: "%.1f", averageScore), "35分制", "sportscourt.fill", ReferenceColor.blue) { router.push(.gradeStats) }
            dashboardMetric("风险学生", "\(riskStudents.count)", "待及时跟进", "exclamationmark.shield.fill", .red) { router.push(.riskStudents) }
            dashboardMetric("公益支持", "\(students.filter(\.isPovertyArea).count)", "贫困地区学生", "heart.fill", ReferenceColor.pink) { isRegionDetailShown = true }
        }.padding(.horizontal, 12)
    }

    private var gradeComparison: some View {
        ReferenceCard {
            VStack(alignment: .leading, spacing: 9) {
                ReferenceSectionTitle(title: "年级完成率对比", trailing: "全部年级", action: { router.push(.gradeStats) })
                ForEach(Array((state.data?.grades ?? []).enumerated()), id: \.element.id) { index, grade in
                    let progress = completionRate(for: grade)
                    Button { router.pendingGradeFilter = grade.name; router.push(.classStats) } label: {
                        HStack(spacing: 8) {
                            Text(grade.name).font(.system(size: 11, weight: .semibold)).frame(width: 42, alignment: .leading)
                            AnimatedProgressLine(value: progress, colors: [index == 0 ? .orange : ReferenceColor.green, index == 0 ? ReferenceColor.yellow : ReferenceColor.blue])
                            Text("\(Int(progress * 100))%").font(.system(size: 10, weight: .bold)).foregroundStyle(index == 0 ? .orange : ReferenceColor.green).frame(width: 32, alignment: .trailing)
                        }
                    }.buttonStyle(.plain)
                }
                Text("7项平均分：跳跃 3.9 · 滑步 3.8 · 平衡 3.6 · 掷准 3.9").font(.system(size: 9)).foregroundStyle(.secondary).padding(.top, 2)
            }
        }.padding(.horizontal, 12)
    }

    private func dashboardMetric(_ title: String, _ value: String, _ note: String, _ icon: String, _ color: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 5) {
                Image(systemName: icon).font(.system(size: 17, weight: .semibold)).foregroundStyle(color)
                Text(value).font(.system(size: 20, weight: .bold)).foregroundStyle(ReferenceColor.navy)
                Text(title).font(.system(size: 10, weight: .bold))
                Text(note).font(.system(size: 8)).foregroundStyle(.secondary)
            }.frame(maxWidth: .infinity, alignment: .leading).padding(9).background(.white, in: RoundedRectangle(cornerRadius: 10))
        }.buttonStyle(.plain)
    }

    private func regionRow(_ name: String, count: Int, detail: String) -> some View {
        HStack { Image(systemName: "mappin.and.ellipse").foregroundStyle(.orange); VStack(alignment: .leading) { Text(name); Text(detail).font(.caption).foregroundStyle(.secondary) }; Spacer(); Text("\(count)人").fontWeight(.semibold).foregroundStyle(ReferenceColor.blue) }
    }

    private func overviewButton(title: String, subtitle: String, icon: String, color: Color, route: AppRoute) -> some View {
        Button { router.push(route) } label: {
            HStack(spacing: 8) {
                Image(systemName: icon).font(.system(size: 19)).foregroundStyle(.white).frame(width: 37, height: 37).background(color, in: RoundedRectangle(cornerRadius: 10))
                VStack(alignment: .leading, spacing: 2) { Text(title).font(.system(size: 11, weight: .bold)); Text(subtitle).font(.system(size: 8)).foregroundStyle(.secondary) }
                Spacer()
            }.padding(9).background(.white, in: RoundedRectangle(cornerRadius: 10))
        }.buttonStyle(.plain)
    }
}
struct GradeStatsView: View {
    @EnvironmentObject private var state: AppState
    @EnvironmentObject private var router: AppRouter
    let showsBack: Bool
    @State private var selectedMetric = "完成率"
    init(showsBack: Bool = false) { self.showsBack = showsBack }
    private func completionRate(for grade: Grade) -> Int {
        let gradeClasses = (state.data?.classes ?? []).filter { $0.gradeId == grade.id }
        guard !gradeClasses.isEmpty else { return 0 }
        return Int((Double(gradeClasses.map(\.completionRate).reduce(0, +)) / Double(gradeClasses.count)).rounded())
    }
    private var completionRates: [Int] {
        (state.data?.grades ?? []).map { completionRate(for: $0) }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 10) {
                if showsBack { ParentPageNavigation(title: "年级对比", showsBack: true) }
                ReferenceHeader(name: "周校长", school: "向上实验小学", initial: "周")
                VStack(alignment: .leading, spacing: 8) {
                    ReferenceSectionTitle(title: "不同年级对比", trailing: "规则版本 v1.0")
                    Picker("对比维度", selection: $selectedMetric) {
                        Text("完成率").tag("完成率")
                        Text("平均总分").tag("平均总分")
                        Text("风险人数").tag("风险人数")
                    }.pickerStyle(.segmented)
                    Text("按小学综合运动能力标准 v1.0 汇总，点击年级可查看班级进度。")
                        .font(.system(size: 9)).foregroundStyle(.secondary)
                }.padding(.horizontal, 12)
                ForEach(Array((state.data?.grades ?? []).enumerated()), id: \.element.id) { index, grade in
                    let rate = completionRates[index]
                    let gradeClasses = (state.data?.classes ?? []).filter { $0.gradeId == grade.id }
                    let gradeStudents = (state.data?.students ?? []).filter { $0.grade == grade.name }
                    // Class completion rates are the authoritative aggregate. The local
                    // students are a UI sample rather than the full school roster.
                    let totalStudents = gradeStudents.isEmpty ? gradeClasses.reduce(0) { $0 + $1.studentCount } : gradeStudents.count
                    let completedStudents = Int((Double(totalStudents) * Double(rate) / 100).rounded())
                    let gradeRisk = gradeStudents.filter { ($0.totalScore ?? 35) < 25 || [.review, .retest].contains(state.taskStatus(for: $0)) }.count
                    let gradeScores = gradeStudents.compactMap(\.totalScore)
                    let averageScore = gradeScores.isEmpty ? 0 : gradeScores.reduce(0, +) / Double(gradeScores.count)
                    let metric = selectedMetric == "完成率" ? "\(rate)%" : selectedMetric == "平均总分" ? String(format: "%.1f", averageScore) : "\(gradeRisk)人"
                    let metricProgress: Double = switch selectedMetric {
                    case "平均总分": min(1, averageScore / 35)
                    case "风险人数": totalStudents > 0 ? min(1, Double(gradeRisk) / Double(totalStudents)) : 0
                    default: Double(rate) / 100
                    }
                    let metricCaption = selectedMetric == "平均总分" ? "满分 35 分" : selectedMetric == "风险人数" ? "风险占比" : "完成率"
                    Button { router.pendingGradeFilter = grade.name; router.push(.classStats) } label: {
                        ReferenceCard {
                            VStack(spacing: 8) {
                                HStack {
                                    VStack(alignment: .leading, spacing: 3) {
                                        Text(grade.name).font(.system(size: 14, weight: .bold))
                                        Text("\(grade.standardVersion) · 2个班级").font(.system(size: 9)).foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    VStack(alignment: .trailing, spacing: 2) {
                                    Text(metric).font(.system(size: 18, weight: .bold)).foregroundStyle(selectedMetric == "风险人数" ? .red : ReferenceColor.green)
                                    Text(selectedMetric).font(.system(size: 9)).foregroundStyle(.secondary)
                                    }
                                    Image(systemName: "chevron.right").font(.system(size: 10, weight: .bold)).foregroundStyle(.secondary)
                                }
                                AnimatedProgressLine(value: metricProgress, colors: [selectedMetric == "风险人数" ? .red : (index == 0 ? .orange : ReferenceColor.green), ReferenceColor.blue], height: 6)
                                HStack { Text("已完成 \(completedStudents) 人"); Spacer(); Text("\(metricCaption) · \(selectedMetric == "风险人数" ? "\(gradeRisk) 人" : selectedMetric == "平均总分" ? String(format: "%.1f 分", averageScore) : "\(rate)%")") }
                                    .font(.system(size: 8)).foregroundStyle(.secondary)
                            }
                        }
                    }.buttonStyle(.plain)
                    .padding(.horizontal, 12)
                }
            }
        }
        .background(ReferenceColor.canvas)
        .overlay {
            if let error = state.error, state.data == nil {
                ErrorStateView(message: error) { Task { await state.refreshDashboard() } }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(ReferenceColor.canvas)
            } else if state.loading || state.data == nil {
                ZStack {
                    ReferenceColor.canvas.ignoresSafeArea()
                    LoadingStateView()
                }
            } else if (state.data?.grades ?? []).isEmpty {
                ZStack {
                    ReferenceColor.canvas.ignoresSafeArea()
                    EmptyStateView(title: "暂无年级数据", detail: "请刷新后重试，或联系学校管理员。")
                }
            }
        }
    }
}

struct ClassStatsView: View {
    @EnvironmentObject private var state: AppState
    @EnvironmentObject private var router: AppRouter
    let showsBack: Bool
    @State private var selectedGrade = "全部年级"

    init(initialGrade: String? = nil, showsBack: Bool = false) {
        _selectedGrade = State(initialValue: initialGrade ?? "全部年级")
        self.showsBack = showsBack
    }

    private var classes: [ClassInfo] {
        let source = state.data?.classes ?? []
        guard selectedGrade != "全部年级" else { return source }
        return source.filter { item in
            state.data?.grades.first { grade in grade.id == item.gradeId }?.name == selectedGrade
        }
    }
    private func completionRate(for item: ClassInfo) -> Int {
        // This is the class aggregate from the dashboard payload. A representative
        // local roster must not silently change a published completion percentage.
        item.completionRate
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 9) {
                if showsBack { ParentPageNavigation(title: "班级完成率", showsBack: true) }
                ReferenceHeader(name: "周校长", school: "向上实验小学", initial: "周")
                FilterBar(options: ["全部年级"] + (state.data?.grades.map(\.name) ?? []), selection: $selectedGrade).padding(.horizontal, 12)
                Text("\(classes.count)个班级 · 点击班级查看需重点跟进的学生")
                    .font(.system(size: 10)).foregroundStyle(.secondary).frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 14)
                ForEach(classes) { item in
                    let rate = completionRate(for: item)
                    Button { router.pendingClassFilter = item.name; router.push(.riskStudents) } label: {
                        ReferenceCard {
                            VStack(spacing: 8) {
                                HStack {
                                    VStack(alignment: .leading, spacing: 3) {
                                        Text(item.name).font(.system(size: 13, weight: .bold))
                                        Text("\(item.teacherName) · \(item.studentCount)人").font(.system(size: 9)).foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    Text("\(rate)%").font(.system(size: 18, weight: .bold)).foregroundStyle(rate < 80 ? .red : ReferenceColor.green)
                                    Image(systemName: "chevron.right").font(.system(size: 10, weight: .bold)).foregroundStyle(.secondary)
                                }
                                AnimatedProgressLine(value: Double(rate) / 100, colors: [rate < 80 ? .orange : ReferenceColor.green, ReferenceColor.blue], height: 6)
                                HStack { Text("待完成 \(max(0, item.studentCount - Int((Double(item.studentCount) * Double(rate) / 100).rounded()))) 人"); Spacer(); Text(rate < 80 ? "建议班主任跟进" : "进度正常") }
                                    .font(.system(size: 8)).foregroundStyle(rate < 80 ? .orange : .secondary)
                            }
                        }
                    }.buttonStyle(.plain)
                    .padding(.horizontal, 12)
                }
                if classes.isEmpty { EmptyStateView(title: "暂无班级数据", detail: "请调整年级筛选后重试。") }
            }
        }
        .background(ReferenceColor.canvas)
        .overlay {
            if let error = state.error, state.data == nil {
                ErrorStateView(message: error) { Task { await state.refreshDashboard() } }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(ReferenceColor.canvas)
            } else if state.loading || state.data == nil {
                ZStack {
                    ReferenceColor.canvas.ignoresSafeArea()
                    LoadingStateView()
                }
            }
        }
    }
}

struct RiskStudentsView: View {
    @EnvironmentObject private var state: AppState
    @EnvironmentObject private var router: AppRouter
    let showsBack: Bool
    @State private var selectedRisk = "全部"
    let initialClass: String?

    init(initialClass: String? = nil, showsBack: Bool = false) {
        self.initialClass = initialClass
        self.showsBack = showsBack
    }

    private var students: [Student] {
        let all = (state.data?.students ?? []).filter { initialClass == nil || $0.className == initialClass }
        switch selectedRisk {
        case "待复核": return all.filter { state.taskStatus(for: $0) == .review }
        case "待补测": return all.filter { state.taskStatus(for: $0) == .retest }
        case "低分": return all.filter { ($0.totalScore ?? 35) < 25 }
        default: return all.filter { ($0.totalScore ?? 35) < 25 || state.taskStatus(for: $0) == .review || state.taskStatus(for: $0) == .retest }
        }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 8) {
                if showsBack { ParentPageNavigation(title: "重点风险学生", showsBack: true) }
                ReferenceHeader(name: "周校长", school: "向上实验小学", initial: "周")
                HStack { Text("重点关注学生").font(.system(size: 14, weight: .bold)); Spacer(); Text("共\(students.count)人").font(.system(size: 10, weight: .semibold)).foregroundStyle(.red) }.padding(.horizontal, 14)
                FilterBar(options: ["全部", "待复核", "待补测", "低分"], selection: $selectedRisk).padding(.horizontal, 12)
                Text("点击学生查看7项测评、风险提示和训练建议。")
                    .font(.system(size: 9)).foregroundStyle(.secondary).frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 14)
                ForEach(students) { student in
                    StudentCard(student: student) { router.push(.report(student)) }
                        .padding(.horizontal, 12)
                }
                if students.isEmpty { EmptyStateView(title: "当前筛选暂无学生", detail: "该类预警已处理完成。") }
            }
        }
        .background(ReferenceColor.canvas)
        .overlay {
            if let error = state.error, state.data == nil {
                ErrorStateView(message: error) { Task { await state.refreshDashboard() } }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(ReferenceColor.canvas)
            } else if state.loading || state.data == nil {
                ZStack {
                    ReferenceColor.canvas.ignoresSafeArea()
                    LoadingStateView()
                }
            }
        }
    }
}
