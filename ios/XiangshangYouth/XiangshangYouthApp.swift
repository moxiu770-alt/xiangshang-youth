import SwiftUI

@main struct XiangshangYouthApp: App {
    @StateObject private var state = AppState()
    @StateObject private var router = AppRouter()
    var body: some Scene { WindowGroup { RootView().environmentObject(state).environmentObject(router).tint(AppTheme.primary).dynamicTypeSize(.xSmall ... .accessibility3).preferredColorScheme(.light) } }
}

struct RootView: View {
    @EnvironmentObject private var state: AppState
    @EnvironmentObject private var router: AppRouter
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.scenePhase) private var scenePhase
    var body: some View {
        ZStack {
        NavigationStack(path: $router.path) {
            Group {
                if state.isShowingSplash {
                    SplashView()
                } else if state.profile == nil {
                    LoginView()
                } else if state.selectedRole == nil {
                    RoleSelectView()
                } else {
                    homeForRole(state.selectedRole!)
                }
            }
                .navigationDestination(for: AppRoute.self) { route in destination(for: route) }
                // The supplied visual system is mobile-first. On iPad retain a readable
                // dashboard column instead of stretching cards across the whole canvas.
                .frame(maxWidth: horizontalSizeClass == .regular ? 980 : .infinity)
                .frame(maxWidth: .infinity)
        }
        .toolbarBackground(.ultraThinMaterial, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .onOpenURL { url in
            router.receiveDeepLink(url)
            router.activatePendingDeepLink(using: state)
        }
        .onChange(of: state.selectedRole) { _, _ in router.activatePendingDeepLink(using: state) }
        .onChange(of: state.data?.students.count ?? 0) { _, _ in router.activatePendingDeepLink(using: state) }
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active, state.profile != nil, state.data != nil else { return }
            Task { await state.refreshDashboard() }
        }
        .transaction { transaction in
            if state.localFeatures.settings.reduceMotion {
                transaction.disablesAnimations = true
                transaction.animation = nil
            }
        }
        // Authentication loading is rendered inside the login button.  Keeping the
        // global mask for dashboard refreshes avoids the small modal spinner window
        // appearing over the login screen.
        if state.loading && !state.isShowingSplash && state.profile != nil && state.data != nil {
            Color.black.opacity(0.08).ignoresSafeArea()
            LoadingStateView().background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 18)).padding(58)
        }
        // Login errors are inline on LoginView; dashboard errors retain the retry card.
        if let error = state.error, !state.isShowingSplash, state.profile != nil, state.data != nil {
            Color.black.opacity(0.18).ignoresSafeArea()
            ErrorStateView(message: error) { Task { if state.profile == nil { await state.login(phone: "13800138000") } else { await state.refreshDashboard() } } }
                .background(.white, in: RoundedRectangle(cornerRadius: 20)).padding(32)
        }
        }
    }
    @ViewBuilder private func homeForRole(_ role: UserRole) -> some View { switch role { case .parent: ParentHomeView(); case .teacher: TeacherHomeView(); case .principal: PrincipalHomeView() } }
    @ViewBuilder private func destination(for route: AppRoute) -> some View {
        switch route {
        case .roleSelect: RoleSelectView(); case .parentHome: ParentHomeView(); case .parentCourses: ParentCoursesDashboard(); case .children: ChildrenView(); case .parentEvaluations: ParentEvaluationsView(); case .parentMessages: ParentMessagesView(); case .notifications: NotificationsView(); case .healthProfile: HealthProfileView(); case .assessment(let category): AssessmentFlowView(category: category); case .expertList: ExpertListView(); case .teacherHome: TeacherHomeView(); case .teacherMessages: TeacherMessagesView(); case .teacherClasses: TeacherClassesView(); case .teacherClassBoard: TeacherClassBoardView(); case .studentList(let c): StudentListView(classInfo: c); case .teacherTasks: TeacherTasksView(); case .teacherTaskDetail(let task): TeacherTaskDetailView(task: task); case .reviewList: ReviewListView(); case .principalHome: PrincipalHomeView(); case .gradeStats: GradeStatsView(showsBack: true); case .classStats: ClassStatsView(initialGrade: router.pendingGradeFilter, showsBack: true); case .riskStudents: RiskStudentsView(initialClass: router.pendingClassFilter, showsBack: true); case .report(let student): ReportDetailView(student: student)
        }
    }
}
