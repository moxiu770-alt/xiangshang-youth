import SwiftUI

struct ParentHomeView: View {
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
                case 0: ParentLandingView()
                case 1: ParentEvaluationDashboard()
                case 2: ParentCoursesDashboard()
                case 3: ParentClassCircleDashboard()
                default: AccountDashboard()
                }
            }
            .id(selectedTab)
            .transition(.opacity.combined(with: .move(edge: .trailing)))
            parentBottomBar
        }
        .background(ReferenceColor.canvas)
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.22), value: selectedTab)
        .frame(maxWidth: 720)
        .frame(maxWidth: .infinity)
        }
    }

    private var parentBottomBar: some View {
        HStack {
            tab(index: 0, icon: "house.fill", title: "首页")
            tab(index: 1, icon: "doc.text.fill", title: "我的测评")
            tab(index: 2, icon: "play.rectangle.fill", title: "我的课程")
            tab(index: 3, icon: "person.3.fill", title: "班级圈")
            tab(index: 4, icon: "person.fill", title: "我的")
        }
        .padding(.top, 7).padding(.bottom, 5)
        .background(.white)
        .overlay(alignment: .top) { Rectangle().fill(ReferenceColor.navy.opacity(0.06)).frame(height: 0.5) }
    }

    private func tab(index: Int, icon: String, title: String) -> some View {
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

struct ParentBindingPrompt: View {
    @EnvironmentObject private var router: AppRouter
    var body: some View {
        ZStack {
            ReferenceColor.canvas.ignoresSafeArea()
            VStack(spacing: 12) {
                Image(systemName: "person.2.badge.plus").font(.system(size: 42)).foregroundStyle(ReferenceColor.blue)
                Text("请先绑定孩子").font(.title3.bold()).foregroundStyle(ReferenceColor.navy)
                Text("绑定后才能查看孩子的测评、报告和课程。\n绑定码由学校或班主任提供。").font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.center)
                Button("去绑定孩子") { router.push(.children) }.buttonStyle(.borderedProminent)
            }.padding(24)
        }
    }
}

struct ParentLandingView: View {
    @EnvironmentObject private var state: AppState; @EnvironmentObject private var router: AppRouter
    @State private var activityDetail: String?
    @State private var expertDetail: String?
    @State private var healthChannelDetail: String?
    var body: some View { ScrollView { VStack(spacing: 9) {
        ReferenceHeader(name: state.selectedChild?.name ?? "王小明", school: "\(state.selectedChild?.className ?? "三年级2班") · 点击切换孩子", initial: String((state.selectedChild?.name ?? "王").prefix(1)), avatarAsset: "ChildAvatar", identityAction: { router.push(.children) })
        Button { activityDetail = "向上少年健康成长季" } label: { ParentCampaignCard() }.buttonStyle(.plain).padding(.horizontal, 9)
        ReferenceCard { VStack(spacing: 8) { HStack { VStack(alignment: .leading) { Text("综合测评").font(.system(size: 17, weight: .bold)).foregroundStyle(ReferenceColor.blue); Text("运动表现、心理健康、口腔健康状况").font(.system(size: 9)).foregroundStyle(.secondary) }; Spacer(); Image(systemName: "sun.max.fill").foregroundStyle(ReferenceColor.yellow) }; LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 7) { assessmentMetric(.fitness); assessmentMetric(.mental); assessmentMetric(.vision); assessmentMetric(.oral) }; Button("继续测评") { router.push(.assessment(.fitness)) }.font(.system(size: 12, weight: .bold)).frame(maxWidth: 150).padding(.vertical, 6).background(ReferenceColor.blue, in: Capsule()).foregroundStyle(.white) }.padding(2) }.padding(.horizontal, 9)
        HStack {
            Button { if let child = state.selectedChild { router.push(.report(child)) } else { router.push(.children) } } label: { ReferenceAction(icon: "calendar", title: "测评报告", color: ReferenceColor.blue) }.buttonStyle(.plain)
            Button { router.push(.parentMessages) } label: { ReferenceAction(icon: "exclamationmark.circle.fill", title: "健康提醒", color: .red) }.buttonStyle(.plain)
            Button { state.checkInToday(); router.push(.healthProfile) } label: { ReferenceAction(icon: "checkmark.seal.fill", title: "打卡记录", color: ReferenceColor.green) }.buttonStyle(.plain)
            Button { router.push(.parentCourses) } label: { ReferenceAction(icon: "play.rectangle.fill", title: "推荐课程", color: .orange) }.buttonStyle(.plain)
        }.padding(.horizontal, 10)
        HStack { Text("专家团队").font(.system(size: 14, weight: .bold)); Spacer(); Button("查看全部 ›") { router.push(.expertList) }.font(.system(size: 10, weight: .semibold)).foregroundStyle(ReferenceColor.blue) }.padding(.horizontal, 12)
        HStack {
            ForEach(Array(zip(["ExpertProfessor", "ExpertDoctor", "ExpertCoach", "ExpertCounselor"], ["张教授", "李医生", "王教练", "刘主任"])), id: \.0) { pair in
                Button { expertDetail = pair.1 } label: { VStack(spacing: 4) {
                    Image(pair.0).resizable().scaledToFit().frame(width: 37, height: 37).background(ReferenceColor.sky, in: Circle()).clipShape(Circle())
                    Text(pair.1).font(.system(size: 9, weight: .medium))
                }
                .frame(maxWidth: .infinity) }.buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 12)
        ReferenceSectionTitle(title: "公益课堂", trailing: "全部课程", action: { router.push(.parentCourses) }).padding(.horizontal, 12)
        HStack(spacing: 8) {
            ParentCourseTeaser(image: "ActivityClassroom", title: "体质成长课")
            ParentCourseTeaser(image: "ActivityFootball", title: "运动表现课")
            ParentCourseTeaser(image: "ActivityBalance", title: "心理舒展课")
        }.padding(.horizontal, 12)
        ReferenceSectionTitle(title: "健康科普", trailing: "关注公众号", action: { healthChannelDetail = "向上少年健康成长公众号" }).padding(.horizontal, 12)
        VStack(spacing: 7) {
            ParentArticleRow(title: "儿童科学长高的 5 个关键习惯", detail: "成长专栏 · 3分钟前")
            ParentArticleRow(title: "居家体态训练 10 分钟", detail: "健康专栏 · 今日推荐")
        }.padding(.horizontal, 12)
    }.padding(.bottom, 8) }.background(ReferenceColor.canvas)
        .refreshable { await state.refreshDashboard() }
        .overlay {
            if let error = state.error, state.data == nil {
                ErrorStateView(message: error) { Task { await state.refreshDashboard() } }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(ReferenceColor.canvas)
            } else if state.loading || state.data == nil {
                ZStack { ReferenceColor.canvas.ignoresSafeArea(); LoadingStateView() }
            } else if state.selectedChild == nil {
                ParentBindingPrompt()
            }
        }
        .sheet(item: Binding(get: { activityDetail.map(CourseSheetItem.init) }, set: { activityDetail = $0?.name })) { item in ActivityDetailSheet(title: item.name) }
        .sheet(item: Binding(get: { expertDetail.map(CourseSheetItem.init) }, set: { expertDetail = $0?.name })) { item in ExpertDetailSheet(name: item.name) }
        .sheet(item: Binding(get: { healthChannelDetail.map(CourseSheetItem.init) }, set: { healthChannelDetail = $0?.name })) { item in HealthArticleSheet(title: item.name) }
    }
    private func metric(_ icon: String, _ title: String, _ subtitle: String, _ color: Color) -> some View {
        Button { if let child = state.selectedChild { router.push(.report(child)) } else { router.push(.children) } } label: {
            ReferenceMetric(icon: icon, title: title, value: subtitle, color: color)
        }.buttonStyle(.plain).accessibilityLabel("查看\(title)报告")
    }
    private func assessmentMetric(_ category: AssessmentCategory) -> some View { Button { router.push(.assessment(category)) } label: { ReferenceMetric(icon: category.icon, title: category.rawValue, value: category == .fitness ? "继续测评" : "开始测评", color: category.color) }.buttonStyle(.plain) }
}

struct ParentCampaignCard: View {
    @State private var drifts = false
    var body: some View {
        ZStack(alignment: .leading) {
            Image("ParentCampaign")
                .resizable()
                .scaledToFill()
                .frame(height: 108)
                .clipped()
                .scaleEffect(drifts ? 1.035 : 1)
                .offset(x: drifts ? -4 : 4)
            LinearGradient(colors: [.white.opacity(0.96), .white.opacity(0.62), .clear], startPoint: .leading, endPoint: .trailing)
            VStack(alignment: .leading, spacing: 4) {
                Text("向上少年健康成长季").font(.system(size: 15, weight: .bold)).foregroundStyle(ReferenceColor.navy)
                Text("综合测评 · 运动表现更出彩").font(.system(size: 10)).foregroundStyle(.secondary)
                AnimatedProgressLine(value: 0.75).frame(width: 145)
                Text("测评于：7月16日 - 8月15日").font(.system(size: 8)).foregroundStyle(.secondary)
            }
            .padding(12)
        }
        .frame(height: 108)
        .clipShape(RoundedRectangle(cornerRadius: 11))
        .overlay(RoundedRectangle(cornerRadius: 11).stroke(ReferenceColor.blue.opacity(0.08), lineWidth: 1))
        .task { withAnimation(.easeInOut(duration: 5).repeatForever(autoreverses: true)) { drifts = true } }
    }
}

struct ChildrenView: View {
    @EnvironmentObject private var state: AppState
    @EnvironmentObject private var router: AppRouter
    @State private var bindingPresented = false
    @State private var childName = ""
    @State private var bindingCode = ""
    @State private var bindingError: String?
    @State private var bindingHelpPresented = false
    var body: some View {
        AppScaffold(title: "孩子管理") {
            VStack(spacing: 8) {
                if let error = state.error, state.data == nil {
                    ErrorStateView(message: error) { Task { await state.refreshDashboard() } }
                } else if state.loading || state.data == nil {
                    LoadingStateView()
                } else {
                    HStack {
                        Text("已绑定孩子 \(state.boundChildren.count) 人").font(.headline).foregroundStyle(AppTheme.ink)
                        Spacer()
                        Button("绑定孩子") { bindingPresented = true }.buttonStyle(.borderedProminent)
                    }
                    if state.boundChildren.isEmpty {
                        EmptyStateView(title: "暂无绑定孩子", detail: "请使用学校提供的绑定码添加孩子档案。")
                    } else {
                        ForEach(state.boundChildren) { child in
                            StudentCard(student: child) {
                                state.selectChild(child)
                                router.pop()
                            }
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity)
        }
        .sheet(isPresented: $bindingPresented) {
            NavigationStack {
                Form {
                    Section("孩子信息") {
                        TextField("孩子姓名", text: $childName)
                            .accessibilityIdentifier("child-name-field")
                        TextField("学校绑定码", text: $bindingCode)
                            .accessibilityIdentifier("child-binding-code-field")
                        HStack(alignment: .top, spacing: 8) {
                            Image(systemName: "info.circle.fill").foregroundStyle(ReferenceColor.blue)
                            VStack(alignment: .leading, spacing: 4) {
                                Text("绑定码由学校或班主任提供，用于确认家庭与孩子关系。")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                Button("绑定码在哪找？") { bindingHelpPresented = true }
                                    .font(.caption.weight(.semibold))
                                    .buttonStyle(.plain)
                                    .foregroundStyle(ReferenceColor.blue)
                                    .accessibilityLabel("查看绑定码获取说明")
                            }
                        }
                        if let bindingError { Text(bindingError).font(.caption).foregroundStyle(.red) }
                    }
                    Section { Button("确认绑定") {
                        guard state.bindChild(name: childName, code: bindingCode) else { bindingError = "姓名或绑定码不匹配，请核对后重试。"; return }
                        bindingError = nil; childName = ""; bindingCode = ""
                        state.clearDraft("child-binding-name")
                        state.clearDraft("child-binding-code")
                        bindingPresented = false
                        // Return to the page that requested binding so the newly
                        // selected child immediately unlocks the report/task
                        // entry point instead of leaving the family in a dead-end
                        // management screen.
                        router.pop()
                    }.frame(maxWidth: .infinity) }
                }
                .navigationTitle("绑定孩子")
                .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("取消") { bindingPresented = false } } }
            }
        }
        .onChange(of: bindingPresented) { _, isPresented in
            guard isPresented else { return }
            childName = state.localFeatures.drafts["child-binding-name"] ?? ""
            bindingCode = state.localFeatures.drafts["child-binding-code"] ?? ""
            bindingError = nil
        }
        .onChange(of: childName) { _, value in
            guard bindingPresented else { return }
            state.saveDraft(value, key: "child-binding-name")
        }
        .onChange(of: bindingCode) { _, value in
            guard bindingPresented else { return }
            state.saveDraft(value, key: "child-binding-code")
        }
        .alert("绑定码获取说明", isPresented: $bindingHelpPresented) {
            Button("知道了", role: .cancel) { }
        } message: {
            Text("绑定码由学校后台生成。请联系班主任或学校管理员，在“家长绑定管理/学生档案”中获取孩子专属绑定码。若学校尚未发放，请先向班主任申请；平台不会自动猜测或生成绑定码。")
        }
    }
}

struct ParentEvaluationsView: View { var body: some View { ParentEvaluationDashboard() } }

struct ParentPageNavigation: View {
    @EnvironmentObject private var router: AppRouter
    @EnvironmentObject private var state: AppState
    let title: String
    var showsBack = false
    var body: some View {
        ZStack {
            if showsBack && !router.path.isEmpty {
                Button { router.pop() } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 14, weight: .bold))
                        .frame(width: 32, height: 32)
                        .background(.ultraThinMaterial, in: Circle())
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("返回")
                .accessibilityHint("返回上一页")
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            Text(title).font(.system(size: 15, weight: .bold))
            HStack {
                Spacer()
                Button { router.push(state.selectedRole == .teacher ? .teacherMessages : .notifications) } label: {
                    Image(systemName: "bell").font(.system(size: 14, weight: .medium))
                        .overlay(alignment: .topTrailing) {
                            if state.unreadMessageCount > 0 {
                                Circle().fill(.red).frame(width: 4, height: 4).offset(x: 2, y: -2)
                            }
                        }
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }.buttonStyle(.plain).accessibilityLabel("消息通知").accessibilityHint("打开消息中心")
            }
        }
        .foregroundStyle(ReferenceColor.navy)
        .padding(.horizontal, 15).padding(.vertical, 8)
        .background { Rectangle().fill(.ultraThinMaterial).ignoresSafeArea(edges: .top) }
        .overlay(alignment: .bottom) { Rectangle().fill(ReferenceColor.navy.opacity(0.08)).frame(height: 0.5) }
        .toolbar(.hidden, for: .navigationBar)
    }
}

struct ParentEvaluationDashboard: View {
    @EnvironmentObject private var state: AppState; @EnvironmentObject private var router: AppRouter
    @State private var ringProgress = 0.0
    private var report: DiagnosisReport? { state.selectedChild.map { state.report(for: $0) } }
    private var reportProgress: Double { Double(report?.scores.count ?? 0) / Double(TestItem.allCases.count) }
    var body: some View { ScrollView { VStack(spacing: 9) { ParentPageNavigation(title: "我的测评"); ReferenceHeader(name: state.selectedChild?.name ?? "王小明", school: "\(state.selectedChild?.className ?? "三年级2班") · 成长小档案", initial: String((state.selectedChild?.name ?? "王").prefix(1)), showsBell: false, avatarAsset: "ChildAvatar")
        HStack { ZStack { Circle().stroke(ReferenceColor.blue.opacity(0.15), lineWidth: 8).frame(width: 72, height: 72); Circle().trim(from: 0, to: ringProgress).stroke(LinearGradient(colors: [ReferenceColor.blue, ReferenceColor.green], startPoint: .top, endPoint: .bottom), style: StrokeStyle(lineWidth: 8, lineCap: .round)).rotationEffect(.degrees(-90)).frame(width: 72, height: 72); VStack { Text((report?.student.totalScore ?? 0) >= 25 ? "良好" : "需关注").font(.system(size: 14, weight: .bold)).foregroundStyle(ReferenceColor.blue); Text("综合能力").font(.system(size: 8)).foregroundStyle(.secondary) } }; VStack(alignment: .leading, spacing: 4) { Text("健康综合测评").font(.system(size: 14, weight: .bold)); Text("覆盖孩子的运动与健康成长情况").font(.system(size: 9)).foregroundStyle(.secondary); AnimatedProgressLine(value: reportProgress).frame(height: 6); Text("已完成 \(report?.scores.count ?? 0) 项 · 进度 \(Int(reportProgress * 100))% · 总分 \(String(format: "%.1f", report?.totalScore ?? 0))") .font(.system(size: 9)).foregroundStyle(ReferenceColor.blue) }; Spacer(); Image("ChildAvatar").resizable().scaledToFit().frame(width: 57, height: 57) }
        .padding(12)
        .background(LinearGradient(colors: [ReferenceColor.sky, Color.white], startPoint: .leading, endPoint: .trailing), in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(ReferenceColor.blue.opacity(0.12), lineWidth: 1))
        .padding(.horizontal, 12)
        ReferenceSectionTitle(title: "健康测评结果", trailing: "查看详细报告", action: { if let child = state.selectedChild { router.push(.report(child)) } }).padding(.horizontal, 12); LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) { metric("figure.run", "体质", healthSummary, ReferenceColor.blue); metric("eye.fill", "视力", healthSummary, ReferenceColor.green); metric("mouth.fill", "口腔", healthSummary, ReferenceColor.purple); metric("brain.head.profile", "心理", healthSummary, ReferenceColor.pink) }.padding(.horizontal, 12)
        ReferenceSectionTitle(title: "体质成长档案", trailing: "最新身高 132 cm").padding(.horizontal, 12)
        ReferenceCard { VStack(alignment: .leading, spacing: 8) { Text("身高成长趋势").font(.system(size: 11, weight: .bold)); HStack(alignment: .bottom, spacing: 13) { ForEach([108, 114, 120, 126, 132], id: \.self) { value in VStack(spacing: 3) { RoundedRectangle(cornerRadius: 4).fill(ReferenceColor.blue.opacity(value == 132 ? 1 : 0.35)).frame(width: 22, height: CGFloat(value - 96)); Text("\(value)").font(.system(size: 7)).foregroundStyle(.secondary) } }; Spacer() }; Text("遗传身高区间：165–173 cm · 运动表现持续向好").font(.system(size: 8)).foregroundStyle(.secondary) } }.padding(.horizontal, 12)
        ReferenceSectionTitle(title: "详细报告", trailing: "四维健康评估").padding(.horizontal, 12)
        VStack(spacing: 7) { ParentHealthDimension(title: "体质", detail: "脊柱姿态 · 遗传身高 · 运动表现", color: ReferenceColor.blue); ParentHealthDimension(title: "视力", detail: "屈光筛查 · 用眼习惯", color: ReferenceColor.green); ParentHealthDimension(title: "口腔", detail: "龋齿风险 · 牙列发育", color: ReferenceColor.purple); ParentHealthDimension(title: "心理", detail: "情绪状态 · 同伴适应", color: ReferenceColor.pink) }.padding(.horizontal, 12)
    } }.background(ReferenceColor.canvas)
        .refreshable { await state.refreshDashboard() }
        .task { withAnimation(.easeOut(duration: 1.0)) { ringProgress = reportProgress } }
        .overlay {
            if let error = state.error, state.data == nil {
                ErrorStateView(message: error) { Task { await state.refreshDashboard() } }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(ReferenceColor.canvas)
            } else if state.loading || state.data == nil {
                ZStack { ReferenceColor.canvas.ignoresSafeArea(); LoadingStateView() }
            } else if state.selectedChild == nil {
                ParentBindingPrompt()
            }
        } }
    private func metric(_ icon: String, _ title: String, _ subtitle: String, _ color: Color) -> some View {
        Button { if let child = state.selectedChild { router.push(.report(child)) } else { router.push(.children) } } label: {
            ReferenceMetric(icon: icon, title: title, value: subtitle, color: color)
        }.buttonStyle(.plain).accessibilityLabel("查看\(title)报告")
    }
    private var healthSummary: String { "\(report?.assessmentDate ?? "待测评") · \(((report?.student.totalScore ?? 0) >= 25) ? "良好" : "需关注")" }
}

struct HealthProfileView: View { var body: some View { HealthDashboard() } }
struct HealthDashboard: View {
    @EnvironmentObject private var state: AppState
    @EnvironmentObject private var router: AppRouter
    @State private var checkInDetailShown = false
    private var report: DiagnosisReport? { state.selectedChild.map { state.report(for: $0) } }
    var body: some View { ScrollView { VStack(spacing: 10) { ParentPageNavigation(title: "健康档案", showsBack: true); ReferenceHeader(name: state.selectedChild?.name ?? "王小明", school: state.selectedChild?.className ?? "三年级2班", initial: String((state.selectedChild?.name ?? "王").prefix(1)), avatarAsset: "ChildAvatar"); ReferenceSectionTitle(title: "健康报告", trailing: "查看全部报告", action: { if let child = state.selectedChild { router.push(.report(child)) } }).padding(.horizontal, 12); HStack(spacing: 7) { healthMetric("figure.run", "体质", reportSummary, ReferenceColor.blue); healthMetric("eye.fill", "视力", reportSummary, ReferenceColor.green); healthMetric("mouth.fill", "口腔", reportSummary, ReferenceColor.purple); healthMetric("brain.head.profile", "心理", reportSummary, ReferenceColor.pink) }.padding(.horizontal, 12)
        ReferenceCard { VStack(alignment: .leading, spacing: 8) { ReferenceSectionTitle(title: "本月打卡", trailing: "查看记录", action: { checkInDetailShown = true }); let days = ["日", "一", "二", "三", "四", "五", "六"]; HStack { ForEach(days, id: \.self) { Text($0).font(.system(size: 9)).frame(maxWidth: .infinity).foregroundStyle(.secondary) } }; LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 7), spacing: 8) { ForEach(1...28, id: \.self) { day in Text("\(day)").font(.system(size: 9, weight: day % 3 == 0 ? .bold : .regular)).foregroundStyle(day % 3 == 0 ? ReferenceColor.green : ReferenceColor.navy).frame(width: 17, height: 17).background(day % 3 == 0 ? ReferenceColor.green.opacity(0.12) : .clear, in: Circle()) } } } }.padding(.horizontal, 12)
        RecentFamilyActivities().padding(.horizontal, 12)
        CourseSuggestionBanner().padding(.horizontal, 12)
        UpcomingTrainingCard().padding(.horizontal, 12)
        }.padding(.bottom, 8) }.background(ReferenceColor.canvas)
            .overlay {
                if let error = state.error, state.data == nil {
                    ErrorStateView(message: error) { Task { await state.refreshDashboard() } }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(ReferenceColor.canvas)
                } else if state.loading || state.data == nil {
                    ZStack { ReferenceColor.canvas.ignoresSafeArea(); LoadingStateView() }
                } else if state.selectedChild == nil {
                    ParentBindingPrompt()
                }
            }
        .sheet(isPresented: $checkInDetailShown) {
            NavigationStack {
                VStack(spacing: 12) {
                    Image(systemName: "checkmark.seal.fill").font(.system(size: 44)).foregroundStyle(ReferenceColor.green)
                    Text("本月已保存 \(state.localFeatures.checkInDates.count) 次运动打卡").font(.headline)
                    Text("打卡记录会自动保存并同步到成长档案。")
                        .font(.footnote).foregroundStyle(.secondary).multilineTextAlignment(.center)
                    Spacer()
                }.padding(24)
                .navigationTitle("本月运动打卡")
                .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("完成") { checkInDetailShown = false } } }
            }
        }
    }
    private var reportSummary: String { "\(report?.assessmentDate ?? "待测评") · \(((report?.student.totalScore ?? 0) >= 25) ? "良好" : "需关注")" }
    private func healthMetric(_ icon: String, _ title: String, _ subtitle: String, _ color: Color) -> some View {
        Button { if let child = state.selectedChild { router.push(.report(child)) } else { router.push(.children) } } label: {
            ReferenceMetric(icon: icon, title: title, value: subtitle, color: color)
        }.buttonStyle(.plain).accessibilityLabel("查看\(title)报告")
    }
}

struct RecentFamilyActivities: View {
    @EnvironmentObject private var router: AppRouter
    @State private var slides = false
    @State private var selectedActivity: String?
    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            ReferenceSectionTitle(title: "最近家庭运动", trailing: "查看全部", action: { router.push(.parentCourses) })
            HStack(spacing: 7) {
                activityTile("ActivityClassroom", "课间活力操", "本周完成 2 次", ReferenceColor.green, offset: -3)
                activityTile("ActivityFootball", "足球启蒙", "亲子运动日", ReferenceColor.blue, offset: 0)
                activityTile("ActivityBalance", "平衡挑战", "推荐给小明", ReferenceColor.yellow, offset: 3)
            }
        }
        .task { withAnimation(.easeInOut(duration: 4).repeatForever(autoreverses: true)) { slides = true } }
        .sheet(item: Binding(get: { selectedActivity.map(CourseSheetItem.init) }, set: { selectedActivity = $0?.name })) { item in
            CourseDetailSheet(title: item.name)
        }
    }

    private func activityTile(_ image: String, _ title: String, _ note: String, _ color: Color, offset: CGFloat) -> some View {
        Button { selectedActivity = title } label: { VStack(alignment: .leading, spacing: 4) {
            Image(image).resizable().scaledToFill().frame(height: 44).frame(maxWidth: .infinity).clipped()
                .scaleEffect(slides ? 1.07 : 1)
                .offset(x: slides ? offset : -offset)
            Text(title).font(.system(size: 9, weight: .bold)).lineLimit(1)
            Text(note).font(.system(size: 7)).foregroundStyle(color).lineLimit(1)
        }
        .padding(4)
        .background(.white, in: RoundedRectangle(cornerRadius: 8))
        .frame(maxWidth: .infinity)
        }
        .buttonStyle(.plain)
    }
}

struct CourseSuggestionBanner: View {
    @State private var lifts = false
    @State private var isPresented = false
    var body: some View {
        Button { isPresented = true } label: {
            HStack(spacing: 10) {
                Image("ActivityBalance")
                    .resizable().scaledToFill().frame(width: 58, height: 58)
                    .clipShape(RoundedRectangle(cornerRadius: 11))
                    .scaleEffect(lifts ? 1.06 : 1)
                VStack(alignment: .leading, spacing: 3) {
                    Text("为孩子推荐").font(.system(size: 10)).foregroundStyle(.secondary)
                    Text("青少年体姿改善课程").font(.system(size: 14, weight: .bold))
                    Text("每周 2 次 · 适合 7-10 岁").font(.system(size: 8)).foregroundStyle(ReferenceColor.green)
                }
                Spacer()
                Text("查看课程").font(.system(size: 10, weight: .bold))
                    .padding(.horizontal, 10).padding(.vertical, 6)
                    .background(ReferenceColor.yellow, in: Capsule()).foregroundStyle(.white)
            }
            .padding(10)
            .background(.white, in: RoundedRectangle(cornerRadius: 11))
            .overlay(RoundedRectangle(cornerRadius: 11).stroke(ReferenceColor.yellow.opacity(0.16), lineWidth: 1))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("推荐课程：青少年体姿改善课程，查看课程")
        .task { withAnimation(.easeInOut(duration: 2.3).repeatForever(autoreverses: true)) { lifts = true } }
        .sheet(isPresented: $isPresented) { CourseDetailSheet(title: "青少年体姿改善课程") }
    }
}

struct UpcomingTrainingCard: View {
    var body: some View {
        HStack(spacing: 9) {
            Image(systemName: "calendar.badge.clock").font(.system(size: 18, weight: .semibold)).foregroundStyle(ReferenceColor.green)
                .frame(width: 37, height: 37).background(ReferenceColor.green.opacity(0.12), in: RoundedRectangle(cornerRadius: 10))
            VStack(alignment: .leading, spacing: 3) {
                Text("我的运动安排").font(.system(size: 11, weight: .bold))
                Text("周三 15:30 - 16:30  足球基础训练").font(.system(size: 9)).foregroundStyle(.secondary)
            }
            Spacer()
            Text("已预约").font(.system(size: 9, weight: .bold)).foregroundStyle(ReferenceColor.green)
        }
        .padding(10)
        .background(.white, in: RoundedRectangle(cornerRadius: 11))
        .overlay(RoundedRectangle(cornerRadius: 11).stroke(ReferenceColor.green.opacity(0.13), lineWidth: 1))
    }
}

struct ParentMessagesView: View { var body: some View { ParentMessagesDashboard() } }
struct ParentMessageDetail: Identifiable {
    let id = UUID()
    let title: String
    let detail: String
    let tag: String
    let time: String
}
struct ParentMessagesDashboard: View {
    @EnvironmentObject private var state: AppState
    @State private var selectedTab = 0
    @State private var selectedMessage: ParentMessageDetail?
    private let messages: [(String, String, String, String, String, String, Color)] = [
        ("m1", "exclamationmark.circle.fill", "体质提醒", "体质指标偏低，建议关注饮食与运动习惯", "健康提醒", "08:30", .red),
        ("m2", "eye.fill", "视力提醒", "用眼时长超过建议时长，建议合理用眼", "健康提醒", "昨天 21:00", ReferenceColor.green),
        ("health-oral", "mouth.fill", "口腔提醒", "建议定期进行口腔健康检查", "成长关注", "昨天 20:00", ReferenceColor.purple),
        ("health-mental", "brain.head.profile", "心理提醒", "情绪状态良好，继续保持", "成长关注", "昨天 18:30", ReferenceColor.pink),
        ("health-growth", "bell.fill", "成长提醒", "本月完成2次运动打卡", "成长提醒", "07-15 16:20", ReferenceColor.blue),
        ("health-checkin", "star.fill", "打卡提醒", "今日运动打卡未完成，快去打卡吧！", "待完成", "07-15 08:00", .orange)
    ]

    var body: some View {
        ScrollView {
            VStack(spacing: 8) {
                ParentPageNavigation(title: "健康提醒", showsBack: true)
                ReferenceHeader(name: state.selectedChild?.name ?? "王小明", school: "\(state.selectedChild?.className ?? "三年级2班") · 成长小档案", initial: String((state.selectedChild?.name ?? "王").prefix(1)), showsBell: false, avatarAsset: "ChildAvatar")
                HStack(spacing: 0) {
                    tab("消息提醒", index: 0)
                    tab("系统通知", index: 1)
                }
                .padding(.horizontal, 12)
                let visibleMessages = selectedTab == 0 ? Array(messages.prefix(4)) : Array(messages.suffix(2))
                ForEach(visibleMessages.indices, id: \.self) { index in
                    let item = visibleMessages[index]
                    Button {
                        state.markMessageRead(item.0)
                        selectedMessage = ParentMessageDetail(title: item.2, detail: item.3, tag: item.4, time: item.5)
                    } label: {
                        let isUnread = index < 2 && !state.localFeatures.readMessageIDs.contains(item.0)
                        messageRow(icon: item.1, title: item.2, detail: item.3, tag: item.4, time: item.5, color: item.6, unread: isUnread)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("\(item.1)，\(item.2)，\(item.4)，查看详情")
                }
            }
            .padding(.bottom, 9)
        }
        .background(ReferenceColor.canvas)
        .overlay {
            if let error = state.error, state.data == nil {
                ErrorStateView(message: error) { Task { await state.refreshDashboard() } }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(ReferenceColor.canvas)
            } else if state.loading || state.data == nil {
                ZStack { ReferenceColor.canvas.ignoresSafeArea(); LoadingStateView() }
            } else if state.selectedChild == nil {
                ParentBindingPrompt()
            }
        }
        .sheet(item: $selectedMessage) { item in
            NavigationStack {
                VStack(alignment: .leading, spacing: 14) {
                    Text(item.tag).font(.caption.weight(.semibold)).foregroundStyle(ReferenceColor.blue)
                    Text(item.detail).font(.body).foregroundStyle(ReferenceColor.navy)
                    Text(item.time).font(.caption).foregroundStyle(.secondary)
                    Spacer()
                }
                .padding()
                .navigationTitle(item.title)
                .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("关闭") { selectedMessage = nil } } }
            }
        }
    }

    private func tab(_ title: String, index: Int) -> some View {
        Button { withAnimation(.easeInOut(duration: 0.2)) { selectedTab = index } } label: {
            VStack(spacing: 6) {
                Text(title).font(.system(size: 11, weight: .semibold)).foregroundStyle(selectedTab == index ? ReferenceColor.blue : .secondary)
                Capsule().fill(selectedTab == index ? ReferenceColor.blue : .clear).frame(height: 2)
            }.frame(maxWidth: .infinity)
        }.buttonStyle(.plain)
    }

    private func messageRow(icon: String, title: String, detail: String, tag: String, time: String, color: Color, unread: Bool) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon).font(.system(size: 16, weight: .semibold)).foregroundStyle(color)
                .frame(width: 34, height: 34).background(color.opacity(0.10), in: RoundedRectangle(cornerRadius: 10))
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.system(size: 12, weight: .bold))
                Text(detail).font(.system(size: 9)).foregroundStyle(.secondary).lineLimit(1)
                Text(tag).font(.system(size: 8, weight: .bold)).foregroundStyle(color)
                    .padding(.horizontal, 5).padding(.vertical, 2).background(color.opacity(0.09), in: Capsule())
            }
            Spacer(minLength: 4)
            VStack(alignment: .trailing, spacing: 7) {
                HStack(spacing: 4) {
                    if unread { Circle().fill(.red).frame(width: 4, height: 4) }
                    Text(time).font(.system(size: 8)).foregroundStyle(.secondary)
                }
                Image(systemName: "chevron.right").font(.system(size: 9, weight: .bold)).foregroundStyle(.secondary)
            }
        }
        .padding(11)
        .background(.white, in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(ReferenceColor.blue.opacity(0.06), lineWidth: 1))
        .padding(.horizontal, 10)
    }
}
