import SwiftUI

@main struct XiangshangYouthApp: App {
    @StateObject private var state: AppState
    @StateObject private var router = AppRouter()
    @StateObject private var featureRollout = FeatureRollout()
    init() {
        let appState = AppState()
        _state = StateObject(wrappedValue: appState)
        FrontendTelemetry.configure(enabled: appState.localFeatures.settings.analyticsEnabled && appState.usesRemoteDataSource)
        CrashMonitoring.configure()
        BodyCaptureQualityGate.loadCanonicalProfilesIfAvailable()
        ChildFollowAlongTuning.loadCanonicalProfilesIfAvailable()
        BackgroundSyncScheduler.register {
            guard appState.repository.supportsRemoteAcknowledgement else { return true }
            guard appState.profile != nil else { return appState.pendingSyncCount == 0 }
            if appState.data == nil { await appState.refreshDashboard() }
            guard appState.data != nil else { return false }
            await appState.syncPendingRecords()
            return appState.pendingSyncCount == 0
        }
    }
    var body: some Scene { WindowGroup { RootView().environmentObject(state).environmentObject(router).environmentObject(featureRollout).tint(AppTheme.primary).dynamicTypeSize(.xSmall ... .accessibility5).preferredColorScheme(.light) } }
}

struct RootView: View {
    @EnvironmentObject private var state: AppState
    @EnvironmentObject private var router: AppRouter
    @EnvironmentObject private var featureRollout: FeatureRollout
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.scenePhase) private var scenePhase
    // Respect both the in-app preference and the system accessibility setting.
    // The latter matters before a user has reached "我的 > 设置", and prevents
    // the launch/login artwork from drifting for people who reduce motion at
    // the OS level.
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    @StateObject private var networkMonitor = NetworkMonitor()
    var body: some View {
        ZStack {
            navigationRoot
            globalOverlay
        }
        // Splash artwork is a pure poster: do not let the root NavigationStack
        // reintroduce time, signal or the Home indicator while it is visible.
        .statusBarHidden(state.isShowingSplash)
        .persistentSystemOverlays(state.isShowingSplash ? .hidden : .visible)
        .onAppear { networkMonitor.start(); state.setOffline(networkMonitor.isOffline); Task { await featureRollout.refreshIfConfigured() } }
        .onChange(of: networkMonitor.isOffline) { _, value in state.setOffline(value) }
    }
    private var navigationRoot: some View {
        NavigationStack(path: $router.path) {
            rootContent
                .navigationDestination(for: AppRoute.self) { route in destination(for: route) }
                .frame(maxWidth: horizontalSizeClass == .regular ? 980 : .infinity)
                .frame(maxWidth: .infinity)
        }
        .toolbarBackground(.ultraThinMaterial, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        // NavigationStack owns the hosting controller's status-bar preference.
        // Apply the splash rule here (not only on the outer ZStack) so the
        // transition out of LaunchScreen cannot briefly show time/signal text.
        .statusBarHidden(state.isShowingSplash)
        .persistentSystemOverlays(state.isShowingSplash ? .hidden : .visible)
        .onOpenURL { url in
            router.receiveDeepLink(url)
            router.activatePendingDeepLink(using: state)
        }
        .onChange(of: state.selectedRole) { _, _ in router.activatePendingDeepLink(using: state) }
        .onChange(of: state.data?.students.count ?? 0) { _, _ in router.activatePendingDeepLink(using: state) }
        .onChange(of: router.path.count) { _, _ in router.syncStackToPathCount() }
        .onChange(of: scenePhase) { _, phase in
            if phase != .active {
                if phase == .background, state.pendingSyncCount > 0 {
                    BackgroundSyncScheduler.schedule()
                }
                return
            }
            guard !networkMonitor.isOffline, state.profile != nil, state.data != nil else { return }
            Task {
                await state.refreshDashboard()
                if state.pendingSyncCount > 0 { await state.syncPendingRecords() }
            }
        }
        .transaction { transaction in
            if state.localFeatures.settings.reduceMotion || systemReduceMotion {
                transaction.disablesAnimations = true
                transaction.animation = nil
            }
        }
    }
    @ViewBuilder private var rootContent: some View {
        if state.isShowingSplash {
            SplashView()
        } else if state.profile == nil {
            LoginView()
        } else if state.selectedRole == nil {
            RoleSelectView()
        } else if let role = state.selectedRole {
            homeForRole(role)
        }
    }
    @ViewBuilder private var globalOverlay: some View {
        if networkMonitor.isOffline && !state.isShowingSplash {
            OfflineBanner(message: "当前处于离线模式，本地数据仍可查看；联网后可刷新最新数据。")
                .transition(.move(edge: .top).combined(with: .opacity))
                .zIndex(10)
        }
        if let persistenceError = state.localPersistenceError, !state.isShowingSplash {
            VStack {
                HStack(spacing: 9) {
                    Image(systemName: "internaldrive.trianglebadge.exclamationmark")
                        .foregroundStyle(.red)
                    Text(persistenceError)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(ReferenceColor.navy)
                        .lineLimit(2)
                    Button { state.clearLocalPersistenceError() } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 12, weight: .bold))
                            .frame(width: 28, height: 28)
                    }
                    .accessibilityLabel("关闭本机保存受限提示")
                }
                .padding(.horizontal, 13)
                .padding(.vertical, 9)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
                .overlay(RoundedRectangle(cornerRadius: 14).stroke(.red.opacity(0.24), lineWidth: 1))
                .shadow(color: .black.opacity(0.10), radius: 7, y: 2)
                .padding(.horizontal, 16)
                .padding(.top, networkMonitor.isOffline ? 48 : 8)
                Spacer()
            }
            .accessibilityElement(children: .contain)
            .accessibilityLabel("本机保存受限：\(persistenceError)")
            .zIndex(11)
        }
        if state.loading && !state.isShowingSplash && state.profile != nil && state.data != nil {
            // Refreshing existing content must not turn a teacher/principal
            // board into a temporarily dead screen. Keep the existing data
            // interactive and announce refresh progress in a compact banner.
            VStack {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small).tint(ReferenceColor.blue)
                    Text("正在刷新数据")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(ReferenceColor.navy)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 9)
                .background(.ultraThinMaterial, in: Capsule())
                .shadow(color: .black.opacity(0.08), radius: 6, y: 2)
                .padding(.top, 8)
                Spacer()
            }
            .allowsHitTesting(false)
            .accessibilityElement(children: .combine)
            .accessibilityLabel("正在刷新数据，当前内容仍可操作")
            .zIndex(5)
        }
        if let error = state.error, !state.isShowingSplash, state.profile != nil, !state.restoringSession {
            if state.data == nil {
                Color.black.opacity(0.18).ignoresSafeArea()
                ErrorStateView(message: error) {
                    Task { await state.refreshDashboard() }
                } dismiss: {
                    state.error = nil
                }
                .background(.white, in: RoundedRectangle(cornerRadius: 20))
                .padding(32)
                .zIndex(8)
            } else {
            // A failed background refresh must not make a populated workbench
            // feel disabled. Keep its cards available and offer explicit retry
            // and dismiss actions in a compact, reachable banner instead.
            VStack {
                HStack(spacing: 9) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                    Text(error)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(ReferenceColor.navy)
                        .lineLimit(2)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Button("重试") { Task { await state.refreshDashboard() } }
                        .font(.system(size: 12, weight: .bold))
                        .buttonStyle(.borderedProminent)
                        .tint(ReferenceColor.blue)
                    Button {
                        state.error = nil
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(.secondary)
                            .frame(width: 24, height: 24)
                    }
                    .accessibilityLabel("关闭刷新失败提示")
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
                .overlay(RoundedRectangle(cornerRadius: 16).stroke(.orange.opacity(0.22), lineWidth: 1))
                .shadow(color: .black.opacity(0.10), radius: 8, y: 3)
                .padding(.horizontal, 16)
                .padding(.top, 8)
                Spacer()
            }
            .accessibilityElement(children: .contain)
            .accessibilityLabel("刷新失败：\(error)，可重试或关闭提示")
            .zIndex(8)
            }
        }
        // Derive the shield directly from scenePhase. Keeping a second Boolean
        // can race during sheet dismissal or system banners and leave an
        // invisible full-screen layer over an already-active app.
        if scenePhase != .active && !state.isShowingSplash {
            ZStack {
                ReferenceColor.canvas.ignoresSafeArea()
                VStack(spacing: 10) {
                    Image(systemName: "lock.shield.fill").font(.system(size: 34)).foregroundStyle(AppTheme.primary)
                    Text("向上少年").font(.headline).foregroundStyle(ReferenceColor.navy)
                    Text("已保护学生健康数据").font(.footnote).foregroundStyle(.secondary)
                }
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("学生健康数据已保护")
            .zIndex(100)
        }
    }
    @ViewBuilder private func homeForRole(_ role: UserRole) -> some View { switch role { case .parent: ParentHomeView(); case .teacher: TeacherHomeView(); case .principal: BackendDashboardNoticeView() } }
    @ViewBuilder private func destination(for route: AppRoute) -> some View {
        switch route {
        case .roleSelect: RoleSelectView(); case .backendDashboard: BackendDashboardNoticeView(); case .parentHome: ParentHomeView(); case .parentCourses: ParentCoursesDashboard(); case .children(let returnAfterBinding): ChildrenView(returnAfterBinding: returnAfterBinding); case .parentEvaluations: ParentEvaluationsView(); case .parentMessages: ParentMessagesView(); case .notifications: NotificationsView(); case .healthProfile: HealthProfileView(); case .bodyAssessment: BodyAssessmentView(); case .assessment(let category): if category == .fitness { BodyAssessmentView() } else { AssessmentFlowView(category: category) }; case .activityList: ActivityListView(); case .expertList: ExpertListView(); case .teacherHome: TeacherHomeView(); case .teacherMessages: TeacherMessagesView(); case .teacherNoticeComposer: TeacherNoticeComposerView(); case .teacherClasses: TeacherClassesView(); case .teacherClassBoard: TeacherClassBoardView(); case .studentList(let c): StudentListView(classInfo: c); case .outstandingStudents: StudentListView(classInfo: nil, mode: .outstanding); case .unassignedStudents: StudentListView(classInfo: nil, mode: .unassigned); case .teacherTasks: TeacherTasksView(); case .teacherTaskDetail(let task): TeacherTaskDetailView(task: task); case .reviewList: ReviewListView(); case .report(let student): if state.hasPublishedSchoolReport(for: student) { ReportDetailView(student: student) } else { SchoolReportPendingView(student: student) }
        }
    }
}
