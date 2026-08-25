import SwiftUI

struct ParentHomeView: View {
    @EnvironmentObject private var state: AppState
    @State private var selectedTab = 0

    var body: some View {
        TabView(selection: $selectedTab) {
            ParentLandingView().tabItem { Label("首页", systemImage: "house.fill") }.tag(0)
            ParentEvaluationDashboard().tabItem { Label("我的测评", systemImage: "doc.text.fill") }.tag(1)
            ParentCoursesDashboard().tabItem { Label("我的课程", systemImage: "play.rectangle.fill") }.tag(2)
            ParentClassCircleDashboard().tabItem { Label("班级圈", systemImage: "person.3.fill") }.tag(3)
            AccountDashboard().tabItem { Label("我的", systemImage: "person.fill") }.tag(4)
        }
        .tint(ReferenceColor.blue)
        .toolbarBackground(.ultraThinMaterial, for: .tabBar)
        .toolbarBackground(.visible, for: .tabBar)
        .frame(maxWidth: 720)
        .frame(maxWidth: .infinity)
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
                Button("去绑定孩子") { router.push(.children(returnAfterBinding: true)) }.buttonStyle(.borderedProminent)
            }.padding(24)
        }
    }
}

struct ParentLandingView: View {
    @EnvironmentObject private var state: AppState; @EnvironmentObject private var router: AppRouter
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @State private var selectedActivity: RemoteActivity?
    @State private var selectedExpert: RemoteExpert?
    @State private var healthChannelDetail: String?
    private var quickActionColumns: [GridItem] {
        Array(repeating: GridItem(.flexible(), spacing: 8), count: dynamicTypeSize.isAccessibilitySize || horizontalSizeClass == .compact ? 2 : 4)
    }
    var body: some View { ScrollView { VStack(spacing: 9) {
        ReferenceHeader(name: state.selectedChild?.name ?? "未选择孩子", school: "\(state.selectedChild?.className ?? "尚未绑定班级") · 点击切换孩子", initial: String((state.selectedChild?.name ?? "孩").prefix(1)), avatarAsset: "ChildAvatar", identityAction: { router.push(.children(returnAfterBinding: false)) })
        ReferenceCard { VStack(spacing: 12) { HStack { VStack(alignment: .leading, spacing: 3) { Text("孩子本周健康任务").font(.system(size: 17, weight: .bold)).foregroundStyle(ReferenceColor.navy); Text("优先完成身体测评，其他家庭记录可稍后填写").font(.system(size: 12)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true) }; Spacer(); Image(systemName: "figure.run.circle.fill").font(.system(size: 24)).foregroundStyle(ReferenceColor.blue) }; LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 9) { assessmentMetric(.fitness); assessmentMetric(.mental); assessmentMetric(.vision); assessmentMetric(.oral) }; Button("开始身体测评") { router.push(.bodyAssessment) }.font(.system(size: 14, weight: .bold)).frame(maxWidth: .infinity, minHeight: 46).background(ReferenceColor.blue, in: RoundedRectangle(cornerRadius: 12)).foregroundStyle(.white) }.padding(2) }.padding(.horizontal, 12)
        LazyVGrid(columns: quickActionColumns, spacing: 8) {
            Button { if let child = state.selectedChild { router.push(.report(child)) } else { router.push(.children(returnAfterBinding: true)) } } label: { ReferenceAction(icon: "calendar", title: "测评报告", color: ReferenceColor.blue) }.buttonStyle(.plain)
            Button { router.push(.parentMessages) } label: { ReferenceAction(icon: "exclamationmark.circle.fill", title: "健康提醒", color: .red) }.buttonStyle(.plain)
            Button { router.push(.bodyAssessment) } label: { ReferenceAction(icon: "figure.walk.motion", title: "身体测评", color: ReferenceColor.green) }.buttonStyle(.plain)
            Button { router.push(.parentCourses) } label: { ReferenceAction(icon: "play.rectangle.fill", title: "推荐课程", color: .orange) }.buttonStyle(.plain)
        }.padding(.horizontal, 12)
        ReferenceSectionTitle(title: "成长活动", trailing: "查看全部", action: { router.push(.activityList) }).padding(.horizontal, 12)
        if state.activitiesLoading {
            LoadingStateView().padding(.horizontal, 12)
        } else if let activity = state.remoteActivities.first {
            Button { selectedActivity = activity } label: { ParentCampaignCard(activity: activity) }.buttonStyle(.plain).padding(.horizontal, 12)
        } else if state.usesRemoteDataSource {
            EmptyStateView(title: "暂无可报名活动", detail: "学校发布活动后会显示在这里。").padding(.horizontal, 12)
        } else {
            Button { selectedActivity = RemoteActivity(activityID: "health-growth-season-2026", schoolID: nil, title: "向上少年健康成长季", description: "2026 秋季测评，活动时间以学校通知为准。", startsAt: nil, endsAt: nil, capacity: 60, registrationStartAt: nil, registrationEndAt: "2026-09-10", status: "open", version: 1, registeredCount: 42, remainingCapacity: 18, registrationID: nil, registrationStatus: nil, childID: nil) } label: { ParentCampaignCard() }.buttonStyle(.plain).padding(.horizontal, 12)
        }
        HStack { Text("专家团队").font(.system(size: 14, weight: .bold)); Spacer(); Button("查看全部 ›") { router.push(.expertList) }.font(.system(size: 12, weight: .semibold)).foregroundStyle(ReferenceColor.blue).frame(minHeight: 44) }.padding(.horizontal, 12)
        if state.expertsLoading {
            LoadingStateView().padding(.horizontal, 12)
        } else if !state.remoteExperts.isEmpty || !state.usesRemoteDataSource {
            HStack {
                ForEach(displayExperts.prefix(4)) { expert in
                    Button { selectedExpert = expert } label: { VStack(spacing: 4) {
                        Image(expertAvatarAsset(expert.expertID)).resizable().scaledToFit().frame(width: 37, height: 37).background(ReferenceColor.sky, in: Circle()).clipShape(Circle())
                        Text(expert.name).font(.system(size: 12, weight: .medium))
                    }
                    .frame(maxWidth: .infinity) }.buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 12)
        } else {
            EmptyStateView(title: "暂无可预约专家", detail: "学校开通专家服务后会显示可预约人员。").padding(.horizontal, 12)
        }
        ReferenceSectionTitle(title: "公益课堂", trailing: "全部课程", action: { router.push(.parentCourses) }).padding(.horizontal, 12)
        if state.usesRemoteDataSource {
            EmptyStateView(title: "暂无课程内容", detail: "学校或平台分配课程后会显示在这里。").padding(.horizontal, 12)
        } else {
            HStack(spacing: 8) {
                ParentCourseTeaser(image: "ActivityClassroom", title: "体质成长课")
                ParentCourseTeaser(image: "ActivityFootball", title: "运动表现课")
                ParentCourseTeaser(image: "ActivityBalance", title: "心理舒展课")
            }.padding(.horizontal, 12)
        }
        ReferenceSectionTitle(title: "健康科普", trailing: "关注公众号", action: { healthChannelDetail = "向上少年健康成长公众号" }).padding(.horizontal, 12)
        if state.usesRemoteDataSource {
            EmptyStateView(title: "暂无健康科普内容", detail: "学校或平台发布内容后会显示在这里。").padding(.horizontal, 12)
        } else {
            VStack(spacing: 7) {
                ParentArticleRow(title: "儿童科学长高的 5 个关键习惯", detail: "成长专栏 · 3分钟前")
                ParentArticleRow(title: "居家体态训练 10 分钟", detail: "健康专栏 · 今日推荐")
            }.padding(.horizontal, 12)
        }
    }.padding(.bottom, 8) }.background(ReferenceColor.canvas)
        .refreshable { await state.refreshDashboard() }
        .task {
            await state.loadActivities()
            await state.loadExperts()
        }
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
        .sheet(item: $selectedActivity) { item in ActivityDetailSheet(title: item.title, activity: item) }
        .sheet(item: $selectedExpert) { item in ExpertDetailSheet(name: item.name, expert: item) }
        .sheet(item: Binding(get: { healthChannelDetail.map(CourseSheetItem.init) }, set: { healthChannelDetail = $0?.name })) { item in HealthArticleSheet(title: item.name) }
    }
    private var displayExperts: [RemoteExpert] {
        state.remoteExperts.isEmpty ? [
            RemoteExpert(expertID: "expert-zhang-child-sports", schoolID: nil, name: "张教授", title: "儿童运动发展", bio: nil, status: "active"),
            RemoteExpert(expertID: "expert-li-growth-screening", schoolID: nil, name: "李医生", title: "儿童健康评估", bio: nil, status: "active"),
            RemoteExpert(expertID: "expert-wang-youth-training", schoolID: nil, name: "王教练", title: "青少年运动训练", bio: nil, status: "active"),
            RemoteExpert(expertID: "expert-liu-family-support", schoolID: nil, name: "刘主任", title: "儿童心理成长", bio: nil, status: "active")
        ] : state.remoteExperts
    }
    private func expertAvatarAsset(_ expertID: String) -> String {
        if expertID.contains("li-growth") { return "ExpertDoctor" }
        if expertID.contains("wang") { return "ExpertCoach" }
        if expertID.contains("liu") { return "ExpertCounselor" }
        return "ExpertProfessor"
    }
    private func metric(_ icon: String, _ title: String, _ subtitle: String, _ color: Color) -> some View {
        Button { if let child = state.selectedChild { router.push(.report(child)) } else { router.push(.children(returnAfterBinding: true)) } } label: {
            ReferenceMetric(icon: icon, title: title, value: subtitle, color: color)
        }.buttonStyle(.plain).accessibilityLabel("查看\(title)报告")
    }
    private func assessmentMetric(_ category: AssessmentCategory) -> some View { Button { category == .fitness ? router.push(.bodyAssessment) : router.push(.assessment(category)) } label: { ReferenceMetric(icon: category.icon, title: category.rawValue, value: category == .fitness ? "身体测评" : "开始测评", color: category.color) }.buttonStyle(.plain) }
}

struct ParentCampaignCard: View {
    var activity: RemoteActivity? = nil
    var body: some View {
        ZStack(alignment: .leading) {
            Image("ParentCampaign")
                .resizable()
                .scaledToFill()
                .frame(height: 108)
                .clipped()
            LinearGradient(colors: [.white.opacity(0.96), .white.opacity(0.62), .clear], startPoint: .leading, endPoint: .trailing)
            VStack(alignment: .leading, spacing: 4) {
                Text(activity?.title ?? "向上少年健康成长季").font(.system(size: 15, weight: .bold)).foregroundStyle(ReferenceColor.navy)
                Text(activity?.description ?? "综合测评 · 运动表现更出彩").font(.system(size: 12)).foregroundStyle(.secondary).lineLimit(1)
                if let capacity = activity?.capacity,
                   capacity > 0,
                   let remaining = activity?.remainingCapacity,
                   remaining >= 0,
                   remaining <= capacity {
                    let registered = capacity - remaining
                    AnimatedProgressLine(value: min(1, max(0, Double(registered) / Double(capacity))))
                        .frame(width: 145)
                    Text("已报名 \(registered)/\(capacity)")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                } else if activity == nil {
                    AnimatedProgressLine(value: 0.75).frame(width: 145)
                }
                Text(activity?.registrationEndAt.map { "报名截止 · \($0.prefix(10))" } ?? "2026 秋季测评 · 以学校通知为准").font(.system(size: 12)).foregroundStyle(.secondary)
            }
            .padding(12)
        }
        .frame(height: 108)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(ReferenceColor.blue.opacity(0.08), lineWidth: 1))
    }
}

struct ChildrenView: View {
    let returnAfterBinding: Bool
    @EnvironmentObject private var state: AppState
    @EnvironmentObject private var router: AppRouter
    @State private var bindingPresented = false
    @State private var childName = ""
    @State private var bindingCode = ""
    @State private var bindingError: String?
    @State private var bindingHelpPresented = false
    @State private var pendingReturnAfterBinding = false
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
                    Section { Button {
                        let name = childName
                        let code = bindingCode
                        Task {
                            let success = await state.bindChild(name: name, code: code)
                            if success {
                                bindingError = nil; childName = ""; bindingCode = ""
                                state.clearDraft("child-binding-name")
                                state.clearDraft("child-binding-code")
                                pendingReturnAfterBinding = returnAfterBinding
                                bindingPresented = false
                            } else if case let .failed(message) = state.workflowState(for: "child-binding") {
                                bindingError = message
                            } else {
                                bindingError = "姓名或绑定码不匹配，请核对后重试。"
                            }
                        }
                    } label: {
                        HStack {
                            if state.workflowState(for: "child-binding").isSubmitting { ProgressView() }
                            Text(state.workflowState(for: "child-binding").isSubmitting ? "正在绑定…" : "确认绑定")
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .disabled(state.workflowState(for: "child-binding").isSubmitting) }
                }
                .navigationTitle("绑定孩子")
                .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("取消") { bindingPresented = false } } }
            }
        }
        .onChange(of: bindingPresented) { _, isPresented in
            if !isPresented {
                guard pendingReturnAfterBinding else { return }
                pendingReturnAfterBinding = false
                // Let SwiftUI finish dismissing the sheet before changing the
                // NavigationStack path. Popping in the same transaction can
                // leave the user on the child-management route.
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                    router.pop()
                }
                return
            }
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
            Text("绑定码由学校后台生成。请联系班主任或学校管理员，在“家长绑定管理/学生档案”中获取孩子专属绑定码。若学校尚未发放，请先向班主任申请；平台不会代填或生成绑定码。")
        }
    }
}

struct ParentEvaluationsView: View { var body: some View { ParentEvaluationDashboard() } }

struct ParentPageNavigation: View {
    @EnvironmentObject private var router: AppRouter
    @EnvironmentObject private var state: AppState
    let title: String
    var showsBack = false
    /// A page that already renders a profile header keeps notification access in
    /// that header.  Suppressing the duplicate here preserves a single, clear
    /// tap target at the top of the screen.
    var showsBell = true
    @ScaledMetric(relativeTo: .headline) private var titleSize: CGFloat = 15
    var body: some View {
        ZStack {
            // The source of truth is the navigation stack, not each screen's
            // manually supplied flag. A pushed page must always expose a way
            // back; root workbenches keep the leading slot empty.
            if showsBack || !router.path.isEmpty {
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
            Text(title)
                .font(.system(size: titleSize, weight: .bold))
                .lineLimit(1)
                .minimumScaleFactor(0.72)
                .truncationMode(.tail)
                .padding(.horizontal, 48)
                .accessibilityLabel(title)
            if showsBell {
                HStack {
                    Spacer()
                    Button { router.push(.messageCenter(for: state.selectedRole)) } label: {
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
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    @State private var ringProgress = 0.0
    private var selectedChild: Student? { state.selectedChild }
    private var report: DiagnosisReport? {
        guard let child = state.selectedChild, state.hasPublishedSchoolReport(for: child) else { return nil }
        return state.visibleReport(for: child)
    }
    private var reportAwaitingSync: Bool {
        selectedChild.map { state.hasPublishedSchoolReport(for: $0) } == true && report == nil && state.repository.supportsRemoteAcknowledgement
    }
    private var reportProgress: Double { report?.scoreCompletionRatio ?? 0 }
    private var reduceMotion: Bool { state.localFeatures.settings.reduceMotion || systemReduceMotion }
    private var bodyHistory: [BodyAssessmentRecord] { selectedChild.map { state.bodyAssessmentHistory(for: $0) } ?? [] }
    private var measuredHeights: [Double] { bodyHistory.suffix(5).map(\.heightCentimeters) }
    private var latestHeightText: String { measuredHeights.last.map { String(format: "最新实测 %.1f cm", $0) } ?? "等待身体测评实测" }
    private var geneticHeightText: String {
        guard let child = selectedChild, let record = bodyHistory.last,
              let reference = record.geneticHeightReference(gender: child.gender) else {
            return "补充父母身高后显示遗传靶身高区间"
        }
        let range = record.geneticHeightRange(gender: child.gender)
        return String(format: "遗传靶身高中位：%.1f cm · 区间 %.1f–%.1f cm", reference, range?.lowerBound ?? reference - 5, range?.upperBound ?? reference + 5)
    }
    private var heightDevelopmentText: String {
        guard let child = selectedChild, let record = bodyHistory.last,
              let assessment = record.heightDevelopmentAssessment(ageMonths: child.bodyAssessmentAgeMonths, gender: child.gender) else {
            return "7–18 岁身高发育等级将在生日与实测值完整后显示"
        }
        return "当前身高发育：\(assessment.level.label) · \(assessment.ageYears)岁参考中位 \(String(format: "%.1f", assessment.median)) cm"
    }
    var body: some View { ScrollView { VStack(spacing: 9) { ParentPageNavigation(title: "我的测评"); ReferenceHeader(name: state.selectedChild?.name ?? "未选择孩子", school: "\(state.selectedChild?.className ?? "尚未绑定班级") · 成长小档案", initial: String((state.selectedChild?.name ?? "孩").prefix(1)), showsBell: false, avatarAsset: "ChildAvatar")
        HStack(spacing: 12) {
            ZStack {
                Circle().stroke(ReferenceColor.blue.opacity(0.15), lineWidth: 8)
                Circle().trim(from: 0, to: ringProgress).stroke(LinearGradient(colors: [ReferenceColor.blue, ReferenceColor.green], startPoint: .top, endPoint: .bottom), style: StrokeStyle(lineWidth: 8, lineCap: .round)).rotationEffect(.degrees(-90))
                VStack(spacing: 1) {
                    Text("\(Int(reportProgress * 100))%").font(.system(size: 16, weight: .bold)).foregroundStyle(ReferenceColor.blue)
                    Text("7 项").font(.system(size: 12)).foregroundStyle(.secondary)
                }
            }
            .frame(width: 78, height: 78)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("学校运动能力测评进度 \(Int(reportProgress * 100))%")
            VStack(alignment: .leading, spacing: 5) {
                Text("学校运动能力测评").font(.system(size: 15, weight: .bold)).foregroundStyle(ReferenceColor.navy).fixedSize(horizontal: false, vertical: true)
                Text(report.map { $0.isComplete ? $0.riskLevel.label : "待完成" } ?? (reportAwaitingSync ? "报告更新中" : "等待报告"))
                    .font(.system(size: 12, weight: .semibold)).foregroundStyle(ReferenceColor.blue)
                    .padding(.horizontal, 8).padding(.vertical, 3).background(ReferenceColor.blue.opacity(0.10), in: Capsule())
                AnimatedProgressLine(value: reportProgress).frame(height: 7)
                Text(report.map { $0.isComplete ? "已完成 7 项 · 总分 \(String(format: "%.1f", $0.totalScore)) / 35" : "已完成 \($0.scoredItemCount) 项 · 进度 \(Int(reportProgress * 100))%" } ?? (reportAwaitingSync ? "报告正在更新，点击刷新" : "完成学校体测后生成报告"))
                    .font(.system(size: 12)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Image("ChildAvatar").resizable().scaledToFit().frame(width: 48, height: 48).accessibilityHidden(true)
        }
        .padding(12)
        .background(LinearGradient(colors: [ReferenceColor.sky, Color.white], startPoint: .leading, endPoint: .trailing), in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(ReferenceColor.blue.opacity(0.12), lineWidth: 1))
        .padding(.horizontal, 12)
        if let child = selectedChild, (!state.repository.supportsRemoteAcknowledgement || report != nil) {
            Button("查看详细报告") { router.push(.report(child)) }
                .buttonStyle(.borderedProminent)
                .tint(ReferenceColor.blue)
                .accessibilityLabel("查看详细报告")
                .padding(.horizontal, 12)
        }
        ReferenceSectionTitle(title: "体质成长档案", trailing: latestHeightText).padding(.horizontal, 12)
        ReferenceCard { VStack(alignment: .leading, spacing: 8) { Text("身高实测趋势").font(.system(size: 14, weight: .bold)); if measuredHeights.isEmpty { Label("暂无实测趋势，完成身体测评后开始积累。", systemImage: "figure.stand").font(.system(size: 13)).foregroundStyle(.secondary).frame(maxWidth: .infinity, minHeight: 58, alignment: .leading) } else { HStack(alignment: .bottom, spacing: 13) { ForEach(Array(measuredHeights.enumerated()), id: \.offset) { index, value in VStack(spacing: 3) { RoundedRectangle(cornerRadius: 4).fill(ReferenceColor.blue.opacity(index == measuredHeights.count - 1 ? 1 : 0.35)).frame(width: 22, height: heightBarHeight(value)); Text(String(format: "%.0f", value)).font(.system(size: 12)).foregroundStyle(.secondary) } }; Spacer() } }; Text(geneticHeightText).font(.system(size: 12)).foregroundStyle(.secondary); Text(heightDevelopmentText).font(.system(size: 12)).foregroundStyle(.secondary) } }.padding(.horizontal, 12)
        ReferenceSectionTitle(title: "家庭健康记录", trailing: "家长填写").padding(.horizontal, 12)
        VStack(spacing: 7) { ParentHealthDimension(category: .vision, detail: "用眼习惯与家庭观察", color: ReferenceColor.green); ParentHealthDimension(category: .oral, detail: "口腔习惯与家庭观察", color: ReferenceColor.purple); ParentHealthDimension(category: .mental, detail: "情绪与同伴互动感受", color: ReferenceColor.pink) }.padding(.horizontal, 12)
    } }.background(ReferenceColor.canvas)
        .refreshable { await state.refreshDashboard() }
        .task(id: "\(reportProgress)-\(reduceMotion)") {
            guard !reduceMotion else { ringProgress = reportProgress; return }
            ringProgress = 0
            withAnimation(.easeOut(duration: 1.0)) { ringProgress = reportProgress }
        }
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
        Button { if let child = state.selectedChild { router.push(.report(child)) } else { router.push(.children(returnAfterBinding: true)) } } label: {
            ReferenceMetric(icon: icon, title: title, value: subtitle, color: color)
        }.buttonStyle(.plain).accessibilityLabel("查看\(title)学校运动体测报告")
    }
    private var healthSummary: String { report.map { "\($0.assessmentDate) · \($0.isComplete ? $0.riskLevel.label : "待完成")" } ?? (reportAwaitingSync ? "报告更新中" : "等待报告") }
    private func heightBarHeight(_ value: Double) -> CGFloat {
        let range = max((measuredHeights.max() ?? value) - (measuredHeights.min() ?? value), 1)
        return 20 + CGFloat((value - (measuredHeights.min() ?? value)) / range) * 36
    }
}

struct HealthProfileView: View { var body: some View { HealthDashboard() } }
struct HealthDashboard: View {
    @EnvironmentObject private var state: AppState
    @EnvironmentObject private var router: AppRouter
    @EnvironmentObject private var featureRollout: FeatureRollout
    @State private var checkInDetailShown = false
    @State private var checkInFormShown = false
    @State private var checkInActivityType = ""
    @State private var checkInDuration = "20"
    @State private var checkInIntensity = "moderate"
    @State private var checkInFeeling = ""
    @State private var checkInCompletedRecommended = false
    @State private var checkInNote = ""
    @State private var checkInValidationError: String?
    @State private var growthReportShown = false
    private var report: DiagnosisReport? {
        guard let child = state.selectedChild, state.hasPublishedSchoolReport(for: child) else { return nil }
        return state.visibleReport(for: child)
    }
    private var reportAwaitingSync: Bool {
        state.selectedChild.map { state.hasPublishedSchoolReport(for: $0) } == true && report == nil && state.repository.supportsRemoteAcknowledgement
    }
    private var currentMonthStart: Date { BusinessClock.calendar.date(from: BusinessClock.calendar.dateComponents([.year, .month], from: .now)) ?? .now }
    private var currentMonthCells: [Int?] {
        let calendar = BusinessClock.calendar
        let leading = max(calendar.component(.weekday, from: currentMonthStart) - 1, 0)
        let count = calendar.range(of: .day, in: .month, for: currentMonthStart)?.count ?? 30
        return Array(repeating: nil, count: leading) + (1...count).map(Optional.some)
    }
    private var currentMonthCheckInCount: Int { selectedChildCheckInDates.filter { $0.hasPrefix(Self.monthKeyFormatter.string(from: currentMonthStart)) }.count }
    private var selectedChildCheckInDates: Set<String> {
        guard let childID = state.selectedChild?.id else { return [] }
        return Set(state.localFeatures.healthCheckins.filter { $0.childID == childID }.map(\.checkInDate))
    }
    private var checkedInToday: Bool { selectedChildCheckInDates.contains(Self.todayKey) }
    private func key(forMonthDay day: Int) -> String { BusinessClock.day(BusinessClock.calendar.date(byAdding: .day, value: day - 1, to: currentMonthStart) ?? currentMonthStart) }
    var body: some View { ScrollView { VStack(spacing: 10) { ParentPageNavigation(title: "健康档案"); ReferenceHeader(name: state.selectedChild?.name ?? "未选择孩子", school: state.selectedChild?.className ?? "尚未绑定班级", initial: String((state.selectedChild?.name ?? "孩").prefix(1)), showsBell: false, avatarAsset: "ChildAvatar"); ReferenceSectionTitle(title: "学校运动体测报告", trailing: report != nil ? "查看 7 项报告" : (reportAwaitingSync ? "获取报告" : "等待报告"), action: { if let child = state.selectedChild { router.push(.report(child)) } }).padding(.horizontal, 12); HStack(spacing: 7) { healthMetric("figure.run", "7 项体测", reportSummary, ReferenceColor.blue); healthMetric("chart.bar.xaxis", "总分", totalScoreSummary, ReferenceColor.green) }.padding(.horizontal, 12)
        if featureRollout.isEnabled(.growthInsights) { Button { growthReportShown = true } label: {
            ReferenceCard {
                HStack(spacing: 11) {
                    Image(systemName: "chart.line.uptrend.xyaxis.circle.fill").font(.title2).foregroundStyle(ReferenceColor.blue)
                    VStack(alignment: .leading, spacing: 3) {
                        Text("成长周报与月报").font(.headline).foregroundStyle(ReferenceColor.navy)
                        Text("汇总真实打卡与测评记录，并说明计划调整原因").font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer(); Image(systemName: "chevron.right").foregroundStyle(ReferenceColor.blue)
                }
            }
        }.buttonStyle(.plain).padding(.horizontal, 12).accessibilityLabel("查看成长周报与月报") }
        if let child = state.selectedChild, let body = state.bodyAssessment(for: child) { Button { router.push(.bodyAssessment) } label: { ReferenceCard { HStack(spacing: 11) { Image(systemName: "figure.stand").font(.title2).foregroundStyle(ReferenceColor.green); VStack(alignment: .leading, spacing: 3) { Text("身体测评").font(.headline).foregroundStyle(ReferenceColor.navy); Text(String(format: "BMI %.1f · %@ · 建议复测 %@", body.bmi, body.attention(ageMonths: child.bodyAssessmentAgeMonths, gender: child.gender).label, Self.bodyDateFormatter.string(from: body.nextFollowUpDate))).font(.caption).foregroundStyle(.secondary).lineLimit(2) }; Spacer(); Image(systemName: "chevron.right").foregroundStyle(ReferenceColor.blue) } } }.buttonStyle(.plain).padding(.horizontal, 12) } else { Button { router.push(.bodyAssessment) } label: { ReferenceCard { Label("尚未完成身体测评，去录入 BMI 与姿态观察", systemImage: "figure.walk.motion").font(.subheadline.bold()).foregroundStyle(ReferenceColor.blue) } }.buttonStyle(.plain).padding(.horizontal, 12) }
        if let child = state.selectedChild {
            let archivedCategories = AssessmentCategory.allCases.filter { category in
                category != .fitness && state.familyHealthRecord(for: child, category: category) != nil
            }
            if !archivedCategories.isEmpty {
                ReferenceCard {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("家庭健康记录").font(.headline).foregroundStyle(ReferenceColor.navy)
                        ForEach(archivedCategories, id: \.self) { category in
                            let savedAt = state.familyHealthRecord(for: child, category: category).map { Self.familyRecordDateFormatter.string(from: $0.completedAt) } ?? "历史记录"
                            Button { router.push(.assessment(category)) } label: {
                                HStack { Image(systemName: category.icon).foregroundStyle(category.color); VStack(alignment: .leading, spacing: 2) { Text("\(category.rawValue)家庭记录已保存").font(.subheadline.weight(.semibold)).foregroundStyle(ReferenceColor.navy); Text("家长填写 · \(savedAt)").font(.caption2).foregroundStyle(.secondary) }; Spacer(); Text("查看").font(.caption.weight(.semibold)).foregroundStyle(ReferenceColor.blue); Image(systemName: "chevron.right").font(.caption).foregroundStyle(ReferenceColor.blue) }
                            }.buttonStyle(.plain)
                        }
                    }.padding(12)
                }.padding(.horizontal, 12)
            }
        }
        ReferenceCard {
            VStack(alignment: .leading, spacing: 8) {
                ReferenceSectionTitle(title: "本月打卡", trailing: "查看记录", action: { checkInDetailShown = true })
                Text(Self.monthTitleFormatter.string(from: currentMonthStart)).font(.caption.weight(.semibold)).foregroundStyle(ReferenceColor.navy)
                let weekdays = ["日", "一", "二", "三", "四", "五", "六"]
                HStack { ForEach(weekdays, id: \.self) { Text($0).font(.system(size: 12)).frame(maxWidth: .infinity).foregroundStyle(.secondary) } }
                LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 7), spacing: 8) {
                    ForEach(Array(currentMonthCells.enumerated()), id: \.offset) { _, day in
                        if let day {
                            let key = key(forMonthDay: day)
                            Text("\(day)").font(.system(size: 12, weight: key == Self.todayKey ? .bold : .regular)).foregroundStyle(selectedChildCheckInDates.contains(key) ? ReferenceColor.green : ReferenceColor.navy).frame(width: 17, height: 17).background(selectedChildCheckInDates.contains(key) ? ReferenceColor.green.opacity(0.12) : .clear, in: Circle())
                        } else { Color.clear.frame(width: 17, height: 17) }
                    }
                }
                Button { checkInValidationError = nil; checkInFormShown = true } label: { Label(checkedInToday ? "今日已打卡" : "记录今日运动", systemImage: checkedInToday ? "checkmark.circle.fill" : "checkmark.seal.fill").font(.system(size: 12, weight: .bold)).frame(maxWidth: .infinity).padding(.vertical, 9).foregroundStyle(.white).background(checkedInToday ? ReferenceColor.green : ReferenceColor.blue, in: RoundedRectangle(cornerRadius: 9)) }.buttonStyle(.plain).disabled(checkedInToday)
            }
        }.padding(.horizontal, 12)
        RecentFamilyActivities().padding(.horizontal, 12)
        CourseSuggestionBanner().padding(.horizontal, 12)
        UpcomingTrainingCard { router.push(.parentCourses) }.padding(.horizontal, 12)
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
                    Text("本月已保存 \(currentMonthCheckInCount) 次运动打卡").font(.headline)
                    Text("打卡记录会自动保存并同步。")
                        .font(.footnote).foregroundStyle(.secondary).multilineTextAlignment(.center)
                    Spacer()
                }.padding(24)
                .navigationTitle("本月运动打卡")
                .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("完成") { checkInDetailShown = false } } }
            }
        }
        .sheet(isPresented: $checkInFormShown) {
            NavigationStack {
                Form {
                    Section("今日运动") {
                        TextField("运动类型", text: $checkInActivityType)
                            .textInputAutocapitalization(.never)
                        TextField("运动时长（分钟）", text: $checkInDuration)
                            .keyboardType(.numberPad)
                        Picker("运动强度", selection: $checkInIntensity) {
                            Text("轻松").tag("low")
                            Text("适中").tag("moderate")
                            Text("较高").tag("high")
                        }
                    }
                    Section("训练反馈") {
                        TextField("运动后感受（选填）", text: $checkInFeeling, axis: .vertical)
                            .lineLimit(2...4)
                        Toggle("完成今日建议训练", isOn: $checkInCompletedRecommended)
                        TextField("家长备注（选填）", text: $checkInNote, axis: .vertical)
                            .lineLimit(2...4)
                    }
                    if let checkInValidationError {
                        Section { Text(checkInValidationError).foregroundStyle(.red) }
                    }
                }
                .navigationTitle("记录今日运动")
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("取消") { checkInFormShown = false } }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("保存") {
                            let minutes = Int(checkInDuration)
                            if checkInActivityType.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                                checkInValidationError = "请填写运动类型。"
                            } else if minutes == nil || !(1...1440).contains(minutes!) {
                                checkInValidationError = "请输入 1–1440 分钟。"
                            } else {
                                state.checkInToday(activityType: checkInActivityType, durationMinutes: minutes!, intensity: checkInIntensity, feeling: checkInFeeling, completedRecommended: checkInCompletedRecommended, parentNote: checkInNote)
                                checkInFormShown = false
                                checkInDetailShown = true
                            }
                        }
                    }
                }
            }
        }
        .sheet(isPresented: $growthReportShown) {
            GrowthInsightView { router.push(.parentCourses) }
                .environmentObject(state)
        }
    }
    private var reportSummary: String { report.map { "\($0.assessmentDate) · \($0.isComplete ? $0.riskLevel.label : "待完成")" } ?? (reportAwaitingSync ? "报告更新中" : "等待报告") }
    private var totalScoreSummary: String { report.map { $0.isComplete ? String(format: "%.1f / 35 分", $0.totalScore) : "待完成 \($0.scoredItemCount)/7 项" } ?? (reportAwaitingSync ? "点击获取最新报告" : "完成测评后生成") }
    private static let todayFormatter: DateFormatter = { let formatter = DateFormatter(); formatter.calendar = BusinessClock.calendar; formatter.locale = Locale(identifier: "en_US_POSIX"); formatter.timeZone = BusinessClock.timeZone; formatter.dateFormat = "yyyy-MM-dd"; return formatter }()
    private static let monthKeyFormatter: DateFormatter = { let formatter = DateFormatter(); formatter.calendar = BusinessClock.calendar; formatter.locale = Locale(identifier: "en_US_POSIX"); formatter.timeZone = BusinessClock.timeZone; formatter.dateFormat = "yyyy-MM"; return formatter }()
    private static let monthTitleFormatter: DateFormatter = { let formatter = DateFormatter(); formatter.calendar = BusinessClock.calendar; formatter.locale = Locale(identifier: "zh_CN"); formatter.timeZone = BusinessClock.timeZone; formatter.dateFormat = "yyyy年M月"; return formatter }()
    private static var todayKey: String { BusinessClock.day() }
    private static let bodyDateFormatter: DateFormatter = { let f = DateFormatter(); f.calendar = BusinessClock.calendar; f.locale = Locale(identifier: "zh_CN"); f.timeZone = BusinessClock.timeZone; f.dateFormat = "M月d日"; return f }()
    private static let familyRecordDateFormatter: DateFormatter = { let f = DateFormatter(); f.calendar = BusinessClock.calendar; f.locale = Locale(identifier: "zh_CN"); f.timeZone = BusinessClock.timeZone; f.dateFormat = "M月d日 HH:mm"; return f }()
    private func healthMetric(_ icon: String, _ title: String, _ subtitle: String, _ color: Color) -> some View {
        Button { if let child = state.selectedChild { router.push(.report(child)) } else { router.push(.children(returnAfterBinding: true)) } } label: {
            ReferenceMetric(icon: icon, title: title, value: subtitle, color: color)
        }.buttonStyle(.plain).accessibilityLabel("查看\(title)学校运动体测报告")
    }
}

struct RecentFamilyActivities: View {
    @EnvironmentObject private var router: AppRouter
    @State private var selectedActivity: String?
    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            ReferenceSectionTitle(title: "最近家庭运动", trailing: "查看全部", action: { router.push(.parentCourses) })
            HStack(spacing: 7) {
                activityTile("ActivityClassroom", "课间活力操", "本周完成 2 次", ReferenceColor.green)
                activityTile("ActivityFootball", "足球启蒙", "亲子运动日", ReferenceColor.blue)
                activityTile("ActivityBalance", "平衡挑战", "推荐给小明", ReferenceColor.yellow)
            }
        }
        .sheet(item: Binding(get: { selectedActivity.map(CourseSheetItem.init) }, set: { selectedActivity = $0?.name })) { item in
            CourseDetailSheet(title: item.name)
        }
    }

    private func activityTile(_ image: String, _ title: String, _ note: String, _ color: Color) -> some View {
        Button { selectedActivity = title } label: { VStack(alignment: .leading, spacing: 4) {
            Image(image).resizable().scaledToFill().frame(height: 48).frame(maxWidth: .infinity).clipped()
            Text(title).font(.system(size: 12, weight: .bold)).lineLimit(2)
            Text(note).font(.system(size: 12)).foregroundStyle(color).lineLimit(2)
        }
        .padding(4)
        .background(.white, in: RoundedRectangle(cornerRadius: 12))
        .frame(maxWidth: .infinity)
        }
        .buttonStyle(.plain)
    }
}

struct CourseSuggestionBanner: View {
    @State private var isPresented = false
    var body: some View {
        Button { isPresented = true } label: {
            HStack(spacing: 10) {
                Image("ActivityBalance")
                    .resizable().scaledToFill().frame(width: 58, height: 58)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                VStack(alignment: .leading, spacing: 3) {
                    Text("为孩子推荐").font(.system(size: 12)).foregroundStyle(.secondary)
                    Text("青少年体姿改善课程").font(.system(size: 14, weight: .bold))
                    Text("每周 2 次 · 适合 7-10 岁").font(.system(size: 12)).foregroundStyle(ReferenceColor.green)
                }
                Spacer()
                Text("查看课程").font(.system(size: 12, weight: .bold))
                    .padding(.horizontal, 10).padding(.vertical, 6)
                    .background(ReferenceColor.yellow, in: Capsule()).foregroundStyle(.white)
            }
            .padding(10)
            .background(.white, in: RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(ReferenceColor.yellow.opacity(0.16), lineWidth: 1))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("推荐课程：青少年体姿改善课程，查看课程")
        .sheet(isPresented: $isPresented) { CourseDetailSheet(title: "青少年体姿改善课程") }
    }
}

struct UpcomingTrainingCard: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 9) {
                Image(systemName: "calendar.badge.clock").font(.system(size: 18, weight: .semibold)).foregroundStyle(ReferenceColor.green)
                    .frame(width: 37, height: 37).background(ReferenceColor.green.opacity(0.12), in: RoundedRectangle(cornerRadius: 10))
                VStack(alignment: .leading, spacing: 3) {
                    Text("推荐训练").font(.system(size: 12, weight: .bold))
                    Text("每周 2 次 · 足球基础训练").font(.system(size: 12)).foregroundStyle(.secondary)
                }
                Spacer()
                Text("去查看").font(.system(size: 12, weight: .bold)).foregroundStyle(ReferenceColor.green)
                Image(systemName: "chevron.right").font(.system(size: 12, weight: .bold)).foregroundStyle(ReferenceColor.green)
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.white, in: RoundedRectangle(cornerRadius: 11))
            .overlay(RoundedRectangle(cornerRadius: 11).stroke(ReferenceColor.green.opacity(0.13), lineWidth: 1))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("推荐训练，每周 2 次，足球基础训练，查看课程")
    }
}

struct ParentMessagesView: View { var body: some View { ParentMessagesDashboard() } }
struct ParentMessageDetail: Identifiable {
    let message: MessageItem
    var id: String { message.id }
}
struct ParentMessagesDashboard: View {
    @EnvironmentObject private var state: AppState
    @EnvironmentObject private var router: AppRouter
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    @State private var selectedTab = 0
    @State private var selectedMessage: ParentMessageDetail?
    private var messages: [MessageItem] {
        let base = state.data?.messages ?? []
        guard let child = state.selectedChild, let body = state.bodyAssessment(for: child) else { return base }
        let level = body.attention(ageMonths: child.bodyAssessmentAgeMonths, gender: child.gender)
        let title: String
        switch level {
        case .red: title = "身体测评需优先关注"
        case .yellow: title = "身体测评复测提醒"
        case .pending: title = "请完成身体测评记录"
        case .unavailable: title = "请完善身体测评资料"
        case .green: title = "身体测评已完成"
        }
        let content = "BMI \(String(format: "%.1f", body.bmi)) · \(level.label)。建议复测：\(Self.reminderDateFormatter.string(from: body.nextFollowUpDate))。"
        return [MessageItem(id: "body-\(child.id)-\(Self.reminderDateFormatter.string(from: body.savedAt))", title: title, content: content, time: "刚刚", isRead: false, category: "健康提醒")] + base
    }
    private var reduceMotion: Bool { state.localFeatures.settings.reduceMotion || systemReduceMotion }
    private static let reminderDateFormatter: DateFormatter = { let f = DateFormatter(); f.locale = Locale(identifier: "en_US_POSIX"); f.dateFormat = "yyyyMMdd"; return f }()

    var body: some View {
        ScrollView {
            VStack(spacing: 8) {
                // This screen is the family message center itself; do not
                // render a second bell that points back to the same route.
                ParentPageNavigation(title: "健康提醒", showsBell: false)
                ReferenceHeader(name: state.selectedChild?.name ?? "未选择孩子", school: "\(state.selectedChild?.className ?? "尚未绑定班级") · 成长小档案", initial: String((state.selectedChild?.name ?? "孩").prefix(1)), showsBell: false, avatarAsset: "ChildAvatar")
                if state.unreadMessageCount > 0 {
                    HStack {
                        Spacer()
                        Button("全部已读") { state.markAllMessagesRead() }
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(ReferenceColor.blue)
                            .buttonStyle(.plain)
                            .accessibilityLabel("将全部消息标记为已读")
                    }
                    .padding(.horizontal, 14)
                }
                HStack(spacing: 0) {
                    tab("消息提醒", index: 0)
                    tab("系统通知", index: 1)
                }
                .padding(.horizontal, 12)
                let visibleMessages = messages.filter { selectedTab == 0 ? $0.category != "系统" : $0.category == "系统" }
                if visibleMessages.isEmpty {
                    EmptyStateView(title: selectedTab == 0 ? "暂无消息提醒" : "暂无系统通知", detail: "新的测评、班级和系统通知会显示在这里。")
                        .padding(.top, 26)
                }
                ForEach(visibleMessages) { item in
                    Button {
                        state.markMessageRead(item.id)
                        if !openBusinessRoute(item) {
                            let expired = isExpired(item)
                            selectedMessage = ParentMessageDetail(message: expired ? MessageItem(id: item.id, title: item.title, content: "该通知已过期，不能继续打开。", time: item.time, isRead: true, category: item.category) : routeFailureDetail(for: item))
                        }
                    } label: {
                        let isUnread = !item.isRead && !state.localFeatures.readMessageIDs.contains(item.id)
                        messageRow(item: item, unread: isUnread)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("\(item.title)，\(item.category)，查看详情")
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
                    Text(item.message.category).font(.caption.weight(.semibold)).foregroundStyle(ReferenceColor.blue)
                    Text(item.message.content).font(.body).foregroundStyle(ReferenceColor.navy)
                    Text(item.message.time).font(.caption).foregroundStyle(.secondary)
                    Spacer()
                }
                .padding()
                .navigationTitle(item.message.title)
                .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("关闭") { selectedMessage = nil } } }
            }
        }
    }

    private func tab(_ title: String, index: Int) -> some View {
        Button {
            if reduceMotion { var transaction = Transaction(); transaction.animation = nil; withTransaction(transaction) { selectedTab = index } }
            else { withAnimation(.easeInOut(duration: 0.2)) { selectedTab = index } }
        } label: {
            VStack(spacing: 6) {
                Text(title).font(.system(size: 12, weight: .semibold)).foregroundStyle(selectedTab == index ? ReferenceColor.blue : .secondary)
                Capsule().fill(selectedTab == index ? ReferenceColor.blue : .clear).frame(height: 2)
            }.frame(maxWidth: .infinity)
        }.buttonStyle(.plain)
    }

    private func isExpired(_ item: MessageItem) -> Bool {
        guard let value = item.expiresAt else { return false }
        let formatter = ISO8601DateFormatter()
        return formatter.date(from: value).map { $0 < Date() } ?? false
    }

    private func routeFailureDetail(for item: MessageItem) -> MessageItem {
        guard let route = normalizedRoute(item.businessRoute) else { return item }
        switch route {
        case "course", "lesson":
            guard item.childID != nil else {
                return MessageItem(id: item.id, title: item.title, content: "该课程通知缺少孩子档案信息，暂时不能打开指定课程。", time: item.time, isRead: true, category: item.category)
            }
            guard item.courseID != nil || item.lessonID != nil || item.businessID != nil else {
                return MessageItem(id: item.id, title: item.title, content: "该课程通知缺少课程或课节编号，请等待学校重新同步。", time: item.time, isRead: true, category: item.category)
            }
            return MessageItem(id: item.id, title: item.title, content: "当前家庭账号无权打开这节课程。", time: item.time, isRead: true, category: item.category)
        case "task", "retest", "report":
            return MessageItem(id: item.id, title: item.title, content: "当前账号无法打开这条通知关联的孩子、任务或报告。", time: item.time, isRead: true, category: item.category)
        case "activity", "expertappointment":
            return MessageItem(id: item.id, title: item.title, content: "该通知缺少可打开的业务编号，暂时只能查看通知内容。", time: item.time, isRead: true, category: item.category)
        case "classnotice":
            return item.businessID == nil
                ? MessageItem(id: item.id, title: item.title, content: "该班级通知缺少通知编号，暂时只能查看文字内容。", time: item.time, isRead: true, category: item.category)
                : item
        default:
            return item
        }
    }

    private func openBusinessRoute(_ item: MessageItem) -> Bool {
        guard !isExpired(item), let route = normalizedRoute(item.businessRoute) else { return false }
        switch route {
        case "report":
            guard let childID = item.childID, let child = state.boundChildren.first(where: { $0.id == childID }) else { return false }
            router.push(.report(child)); return true
        case "course", "lesson":
            guard let childID = item.childID,
                  state.boundChildren.contains(where: { $0.id == childID }),
                  item.courseID != nil || item.lessonID != nil || item.businessID != nil else { return false }
            state.openCourseTarget(
                for: childID,
                courseID: item.courseID ?? (route == "course" ? item.businessID : nil),
                lessonID: item.lessonID ?? (route == "lesson" ? item.businessID : nil),
                title: item.actionLabel ?? item.title
            )
            router.push(.parentCourses); return true
        case "activity":
            guard let businessID = item.businessID else { return false }
            state.openActivityTarget(businessID); router.push(.activityList); return true
        case "expertappointment":
            guard let businessID = item.businessID else { return false }
            state.openExpertAppointmentTarget(businessID); router.push(.expertList); return true
        case "childbinding":
            router.push(.children(returnAfterBinding: false)); return true
        case "classnotice":
            guard item.businessID?.isEmpty == false else { return false }
            selectedMessage = ParentMessageDetail(message: item)
            return true
        case "task", "retest":
            guard let taskID = item.taskID ?? item.businessID,
                  let childID = item.childID,
                  state.boundChildren.contains(where: { $0.id == childID }),
                  state.data?.tasks.contains(where: { $0.id == taskID }) == true else { return false }
            router.push(.parentEvaluations); return true
        default: return false
        }
    }

    private func normalizedRoute(_ value: String?) -> String? {
        value?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .replacingOccurrences(of: "-", with: "")
            .replacingOccurrences(of: "_", with: "")
    }

    private func messageRow(item: MessageItem, unread: Bool) -> some View {
        let presentation = messagePresentation(for: item)
        return HStack(spacing: 10) {
            Image(systemName: presentation.icon).font(.system(size: 16, weight: .semibold)).foregroundStyle(presentation.color)
                .frame(width: 34, height: 34).background(presentation.color.opacity(0.10), in: RoundedRectangle(cornerRadius: 10))
            VStack(alignment: .leading, spacing: 3) {
                Text(item.title).font(.system(size: 12, weight: .bold))
                Text(item.content).font(.system(size: 12)).foregroundStyle(.secondary).lineLimit(1)
                Text(item.category).font(.system(size: 12, weight: .bold)).foregroundStyle(presentation.color)
                    .padding(.horizontal, 5).padding(.vertical, 2).background(presentation.color.opacity(0.09), in: Capsule())
            }
            Spacer(minLength: 4)
            VStack(alignment: .trailing, spacing: 7) {
                HStack(spacing: 4) {
                    if unread { Circle().fill(.red).frame(width: 4, height: 4) }
                    Text(item.time).font(.system(size: 12)).foregroundStyle(.secondary)
                }
                Image(systemName: "chevron.right").font(.system(size: 12, weight: .bold)).foregroundStyle(.secondary)
            }
        }
        .padding(11)
        .background(.white, in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(ReferenceColor.blue.opacity(0.06), lineWidth: 1))
        .padding(.horizontal, 10)
    }

    private func messagePresentation(for item: MessageItem) -> (icon: String, color: Color) {
        if item.title.contains("体质") { return ("exclamationmark.circle.fill", .red) }
        if item.title.contains("视力") { return ("eye.fill", ReferenceColor.green) }
        if item.title.contains("口腔") { return ("mouth.fill", ReferenceColor.purple) }
        if item.title.contains("心理") { return ("brain.head.profile", ReferenceColor.pink) }
        if item.title.contains("打卡") { return ("star.fill", .orange) }
        return ("bell.fill", ReferenceColor.blue)
    }
}
