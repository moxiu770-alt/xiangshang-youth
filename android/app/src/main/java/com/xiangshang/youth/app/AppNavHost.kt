package com.xiangshang.youth.app

import android.app.Activity
import android.net.Uri
import androidx.compose.runtime.Composable
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.*
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.unit.dp
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.compositionLocalOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.navigation.NavHostController
import androidx.navigation.compose.NavHost
import androidx.navigation.compose.composable
import androidx.navigation.compose.rememberNavController
import androidx.navigation.compose.currentBackStackEntryAsState
import androidx.compose.ui.platform.LocalView
import androidx.core.view.WindowInsetsCompat
import androidx.core.view.WindowInsetsControllerCompat
import com.xiangshang.youth.feature.auth.*
import com.xiangshang.youth.feature.parent.*
import com.xiangshang.youth.feature.principal.*
import com.xiangshang.youth.feature.report.ReportDetailScreen
import com.xiangshang.youth.feature.teacher.*
import com.xiangshang.youth.core.model.UserRole
import com.xiangshang.youth.core.util.DeepLinkResolver
import com.xiangshang.youth.core.util.DeepLinkTarget
import com.xiangshang.youth.shared.component.*

object Destinations { const val Splash="splash"; const val Login="login"; const val Register="register"; const val PasswordReset="passwordReset"; const val Role="role"; const val Parent="parent"; const val Children="children"; const val ParentEvaluations="parentEvaluations"; const val Assessment="assessment"; const val Courses="courses"; const val CoursesRoute="courses?openSupport={openSupport}"; const val Circle="circle"; const val Account="account"; const val Messages="messages"; const val Notifications="notifications"; const val Health="health"; const val Report="report"; const val ReportRoute="report/{studentId}"; const val Teacher="teacher"; const val TeacherMessages="teacherMessages"; const val Classes="classes"; const val TeacherCircle="teacherCircle"; const val TeacherBoard="teacherBoard"; const val Students="students"; const val StudentsRoute="students?className={className}"; const val OutstandingStudents="outstandingStudents"; const val Tasks="tasks"; const val TaskDetail="taskDetail"; const val TaskDetailRoute="taskDetail/{taskId}"; const val Review="review"; const val Principal="principal"; const val PrincipalGrades="principalGrades"; const val PrincipalClassStats="principalClassStats"; const val PrincipalRisk="principalRisk"; const val Grades="grades"; const val ClassStats="classStats"; const val ClassStatsRoute="classStats?grade={grade}"; const val Risk="risk"; const val RiskRoute="risk?className={className}" }

/** Shared retry actions keep page-level failures actionable without threading
 * the same callbacks through every feature screen. */
val LocalDashboardRetry = compositionLocalOf<() -> Unit> { {} }
val LocalDashboardClearError = compositionLocalOf<() -> Unit> { {} }

/**
 * Role workbenches are true application roots. Replacing the root instead of
 * popping just the current page prevents Android's system back button from
 * revealing a previous role (for example principal → teacher) after an
 * account switch, exit action, or cold deep link.
 */
private fun NavHostController.replaceRoot(destination: String) {
    navigate(destination) {
        // The splash destination is intentionally removed after launch, so it
        // cannot be used as a reliable pop target. The root graph remains in
        // every back stack and clearing it removes every prior workbench.
        popUpTo(graph.id) { inclusive = true }
        launchSingleTop = true
        restoreState = false
    }
}

@Composable fun AppNavHost(viewModel: AppViewModel, incomingDeepLink: Uri? = null, nav: NavHostController = rememberNavController()) {
    val state by viewModel.state.collectAsState()
    val view = LocalView.current
    val currentEntry by nav.currentBackStackEntryAsState()
    // NavHost exposes a null entry for a short interval during the first frame.
    // Treat that interval as splash as well, otherwise the offline banner and
    // dashboard chrome can flash over the launch artwork before the route is
    // established.
    val isSplash = currentEntry?.destination?.route?.let { it == Destinations.Splash } ?: true
    var handledDeepLink by rememberSaveable { mutableStateOf<String?>(null) }

    // System-bar mutations are expensive IPC calls. Running them from a
    // SideEffect on every Compose recomposition can overwhelm Android System UI
    // during the animated splash, which presents as a misleading "System UI
    // isn't responding" dialog over the launch artwork. Reapply only when the
    // route/session chrome actually changes.
    LaunchedEffect(isSplash, state.profile != null, state.restoringSession) {
        (view.context as? Activity)?.window?.let { window ->
            WindowInsetsControllerCompat(window, view).apply {
                // Dark artwork/gradient surfaces use light icons; dashboard surfaces are
                // light and follow the reference screens with dark status-bar icons.
                if (isSplash) {
                    hide(WindowInsetsCompat.Type.statusBars() or WindowInsetsCompat.Type.navigationBars())
                } else {
                    show(WindowInsetsCompat.Type.statusBars() or WindowInsetsCompat.Type.navigationBars())
                    isAppearanceLightStatusBars = state.profile != null && !state.restoringSession
                    isAppearanceLightNavigationBars = true
                }
            }
        }
    }

    LaunchedEffect(incomingDeepLink, state.profile, state.data) {
        val link = incomingDeepLink ?: return@LaunchedEffect
        val value = link.toString()
        val deepLink = DeepLinkResolver.parse(value)
        if (handledDeepLink == value || deepLink == null || state.profile == null || state.data == null) return@LaunchedEffect
        fun navigateRoleRoot(role: UserRole): String {
            viewModel.chooseRole(role)
            val root = when (role) {
                UserRole.Parent -> Destinations.Parent
                UserRole.Teacher -> Destinations.Teacher
                UserRole.Principal -> Destinations.Principal
            }
            // A cold deep link is delivered while the launch route is still
            // visible. Establish the role workbench first so the destination
            // always has a valid back stack. Warm links keep the current stack
            // and switch roots only when needed.
            if (nav.currentDestination?.route != root) {
                nav.replaceRoot(root)
            }
            return root
        }
        when (deepLink.target) {
            DeepLinkTarget.Report -> {
                navigateRoleRoot(UserRole.Parent)
                val requestedStudent = deepLink.studentId?.let { studentId ->
                    state.data?.students?.firstOrNull { it.id == studentId }
                }
                // Never treat a deep-link student id as an implicit family
                // binding. A parent can open a report only for an already bound
                // child; all other links resolve to the explicit binding flow.
                if (requestedStudent != null && DeepLinkResolver.isBoundFamilyStudent(requestedStudent.id, state.local.boundChildIds)) {
                    viewModel.chooseChild(requestedStudent)
                    nav.navigate(Destinations.Report) { launchSingleTop = true }
                } else {
                    nav.navigate(Destinations.Children) { launchSingleTop = true }
                }
            }
            DeepLinkTarget.Review -> {
                navigateRoleRoot(UserRole.Teacher)
                nav.navigate(Destinations.Review) { launchSingleTop = true }
            }
            DeepLinkTarget.Tasks -> {
                navigateRoleRoot(UserRole.Teacher)
                nav.navigate(Destinations.Tasks) { launchSingleTop = true }
            }
            DeepLinkTarget.Risk -> {
                navigateRoleRoot(UserRole.Principal)
                nav.navigate(Destinations.Risk) { launchSingleTop = true }
            }
        }
        handledDeepLink = value
    }
    CompositionLocalProvider(
        LocalReduceMotion provides state.local.settings.reduceMotion,
        LocalDashboardRetry provides { viewModel.refreshDashboard() },
        LocalDashboardClearError provides viewModel::clearError
    ) {
    Box {
    NavHost(
        nav,
        startDestination = Destinations.Splash,
        modifier = Modifier.fillMaxWidth().widthIn(max = 1024.dp).fillMaxHeight().align(Alignment.TopCenter)
    ) {
        composable(Destinations.Splash) {
            // Session restoration runs behind the artwork.  Never replace the
            // supplied launch poster with a translucent spinner window.
            SplashScreen(
                onFinished = {
                val destination = when {
                    state.profile == null -> Destinations.Login
                    state.role == null -> Destinations.Role
                    state.role == UserRole.Parent -> Destinations.Parent
                    state.role == UserRole.Teacher -> Destinations.Teacher
                    else -> Destinations.Principal
                }
                nav.replaceRoot(destination)
                },
                canFinish = { !state.restoringSession }
            )
        }
        composable(Destinations.Login) {
            LoginScreen(
                loading = state.loading,
                serverError = state.error,
                onClearError = viewModel::clearError,
                onLogin = { identifier -> viewModel.login(identifier) { nav.replaceRoot(Destinations.Role) } },
                onRegister = { nav.navigate(Destinations.Register) },
                onForgotPassword = { nav.navigate(Destinations.PasswordReset) }
            )
        }
        composable(Destinations.Register) {
            RegisterScreen(
                onBack = { nav.popBackStack() },
                onRegistered = { phone -> viewModel.login(phone) { nav.replaceRoot(Destinations.Role) } },
                loading = state.loading,
                serverError = state.error,
                onClearError = viewModel::clearError
            )
        }
        composable(Destinations.PasswordReset) { PasswordResetScreen(onBack = { nav.popBackStack() }) }
        composable(Destinations.Role) { RoleSelectScreen(onRole = { role ->
            viewModel.chooseRole(role)
            val destination = if (role.name == "Parent") Destinations.Parent else if (role.name == "Teacher") Destinations.Teacher else Destinations.Principal
            nav.replaceRoot(destination)
        }, onLogout = { viewModel.logout(); nav.replaceRoot(Destinations.Login) }) }
        composable(Destinations.Parent) { ParentHomeScreen(state, nav, viewModel::registerActivity, viewModel::checkInToday, viewModel::bookExpert, viewModel::saveDraft, viewModel::clearDraft, { viewModel.refreshDashboard() }, { name, phone -> viewModel.submitActivityCommand(name, phone) }, { name, date, note -> viewModel.submitExpertCommand(name, date, note) }) }
        composable(Destinations.Children) { ChildrenScreen(state, nav, viewModel::bindChild, choose = { viewModel.chooseChild(it); nav.popBackStack() }, saveDraft = viewModel::saveDraft, clearDraft = viewModel::clearDraft, onBound = { nav.popBackStack() }) }
        composable(Destinations.ParentEvaluations) { ParentEvaluationsScreen(state, nav, state.selectedChild?.let(viewModel::report)) }
        composable("${Destinations.Assessment}/{category}") { entry -> AssessmentFlowScreen(state, nav, entry.arguments?.getString("category") ?: "fitness", viewModel::completeAssessment, viewModel::saveDraft, viewModel::clearDraft) }
        composable(Destinations.Courses) { ParentCoursesScreen(state, nav, viewModel::updateCourseProgress, viewModel::sendSupport, viewModel::saveDraft, viewModel::clearDraft, submitSupport = viewModel::submitSupportCommand, clearWorkflow = viewModel::clearWorkflowState) }
        composable(Destinations.CoursesRoute) { entry ->
            ParentCoursesScreen(
                state, nav, viewModel::updateCourseProgress, viewModel::sendSupport,
                viewModel::saveDraft, viewModel::clearDraft,
                openSupport = entry.arguments?.getString("openSupport") == "true",
                submitSupport = viewModel::submitSupportCommand,
                clearWorkflow = viewModel::clearWorkflowState
            )
        }
        composable(Destinations.Circle) { ParentClassCircleScreen(state, nav, viewModel::publishPost, viewModel::saveDraft, viewModel::clearDraft, viewModel::togglePostLike, viewModel::addPostComment, viewModel::submitClassPostCommand, viewModel::clearWorkflowState) }
        composable(Destinations.Account) {
            if (state.role?.name == "Teacher") {
                TeacherAccountScreen(state, nav, viewModel::logout, viewModel::updateSettings) {
                    viewModel.clearRoleSelection()
                    nav.replaceRoot(Destinations.Role)
                }
            } else {
                AccountScreen(
                    state, nav, viewModel::chooseRole, viewModel::logout, viewModel::updateSettings,
                    viewModel::sendSupport,
                    onRoleSelected = { role ->
                        viewModel.chooseRole(role)
                        nav.replaceRoot(if (role == UserRole.Parent) Destinations.Parent else if (role == UserRole.Teacher) Destinations.Teacher else Destinations.Principal)
                    },
                    submitSupport = viewModel::submitSupportCommand,
                    clearWorkflow = viewModel::clearWorkflowState,
                    saveDraft = viewModel::saveDraft,
                    clearDraft = viewModel::clearDraft
                )
            }
        }
        composable(Destinations.Messages) { ParentMessagesScreen(state, nav, viewModel::markMessageRead) }
        composable(Destinations.Notifications) { NotificationsScreen(state, nav, viewModel::markMessageRead) }
        composable(Destinations.Health) { HealthProfileScreen(state, nav) }
        composable(Destinations.Report) {
            val child = state.selectedChild
            when {
                state.error != null && state.data == null -> AppScaffold("体测报告", onBack = { nav.popBackStack() }) {
                    ErrorState(
                        state.error ?: "数据加载失败",
                        retry = { viewModel.refreshDashboard() },
                        dismiss = viewModel::clearError
                    )
                }
                state.loading || state.data == null -> AppScaffold("体测报告", onBack = { nav.popBackStack() }) { LoadingState() }
                child == null -> AppScaffold("体测报告", onBack = { nav.popBackStack() }) {
                    Column(horizontalAlignment = Alignment.CenterHorizontally, modifier = Modifier.fillMaxWidth()) {
                        EmptyState("暂无孩子报告，请先完成孩子绑定。")
                        androidx.compose.material3.Button(onClick = { nav.navigate(Destinations.Children) }) { Text("去绑定孩子") }
                    }
                }
                else -> ReportDetailScreen(
                    report = viewModel.report(child),
                    isRefreshing = state.reportLoadingStudentId == child.id,
                    onRefresh = { viewModel.refreshReport(child) },
                    reportError = state.reportError,
                    onDismissReportError = viewModel::clearReportError,
                    nav = nav
                )
            }
        }
        // Teachers and principals can inspect a student report without changing
        // the family's persisted child selection. This route intentionally keeps
        // the student identity in navigation state rather than AppViewModel.
        composable(Destinations.ReportRoute) { entry ->
            val student = state.data?.students?.firstOrNull { it.id == entry.arguments?.getString("studentId") }
            when {
                state.error != null && state.data == null -> AppScaffold("体测报告", onBack = { nav.popBackStack() }) {
                    ErrorState(state.error ?: "数据加载失败", retry = { viewModel.refreshDashboard() }, dismiss = viewModel::clearError)
                }
                state.loading || state.data == null -> AppScaffold("体测报告", onBack = { nav.popBackStack() }) { LoadingState() }
                student == null -> AppScaffold("体测报告", onBack = { nav.popBackStack() }) {
                    EmptyState("未找到该学生档案，返回后可刷新学生列表。")
                }
                else -> ReportDetailScreen(
                    report = viewModel.report(student),
                    isRefreshing = state.reportLoadingStudentId == student.id,
                    onRefresh = { viewModel.refreshReport(student) },
                    reportError = state.reportError,
                    onDismissReportError = viewModel::clearReportError,
                    nav = nav
                )
            }
        }
        composable(Destinations.Teacher) { TeacherHomeScreen(state, nav, viewModel::refreshDashboard) }
        composable(Destinations.TeacherMessages) { TeacherMessagesScreen(state, nav, viewModel::markMessageRead, viewModel::refreshDashboard) }
        composable(Destinations.Classes) { TeacherClassesScreen(state, nav) }
        composable(Destinations.TeacherCircle) {
            TeacherClassCircleScreen(
                state = state,
                nav = nav,
                publishPost = viewModel::publishPost,
                updatePost = viewModel::updatePost,
                saveDraft = viewModel::saveDraft,
                clearDraft = viewModel::clearDraft,
                refreshDashboard = viewModel::refreshDashboard,
                submitPost = viewModel::submitClassPostCommand,
                clearWorkflow = viewModel::clearWorkflowState
            )
        }
        composable(Destinations.TeacherBoard) { TeacherClassBoardScreen(state, nav) { student -> nav.navigateSingleTop("report/${student.id}") } }
        composable(Destinations.Students) { StudentListScreen(state, nav, null) { student -> nav.navigateSingleTop("report/${student.id}") } }
        composable(Destinations.StudentsRoute) { entry -> StudentListScreen(state, nav, entry.arguments?.getString("className")) { student -> nav.navigateSingleTop("report/${student.id}") } }
        composable(Destinations.OutstandingStudents) { StudentListScreen(state, nav, null, outstandingOnly = true) { student -> nav.navigateSingleTop("report/${student.id}") } }
        composable(Destinations.Tasks) { TeacherTasksScreen(state, nav, viewModel::saveCourseUpload, { taskId, attendance, notes, attachment -> viewModel.submitCourseUploadCommand(taskId, attendance, notes, attachment) }, viewModel::saveDraft, viewModel::clearDraft) }
        composable(Destinations.TaskDetailRoute) { entry -> TeacherTaskDetailScreen(state, nav, viewModel::updateStudentTaskStatus, entry.arguments?.getString("taskId"), viewModel::submitTaskStatusCommand) }
        composable(Destinations.Review) { ReviewListScreen(state, nav, viewModel::submitReviewDecision, viewModel::saveDraft, viewModel::clearDraft, viewModel::submitTaskStatusCommand) }
        composable(Destinations.Principal) {
            PrincipalHomeScreen(state, nav, onChooseAnotherRole = {
                viewModel.clearRoleSelection()
                nav.replaceRoot(Destinations.Role)
            }, refreshDashboard = viewModel::refreshDashboard)
        }
        composable(Destinations.PrincipalGrades) { GradeStatsScreen(state, nav, rootTab = true) }
        composable(Destinations.PrincipalClassStats) { ClassStatsScreen(state, nav, null, rootTab = true) }
        composable(Destinations.PrincipalRisk) { RiskStudentsScreen(state, nav, null, rootTab = true) { student -> nav.navigateSingleTop("report/${student.id}") } }
        composable(Destinations.Grades) { GradeStatsScreen(state, nav) }
        composable(Destinations.ClassStats) { ClassStatsScreen(state, nav, null) }
        composable(Destinations.ClassStatsRoute) { entry -> ClassStatsScreen(state, nav, entry.arguments?.getString("grade")) }
        composable(Destinations.Risk) {
            RiskStudentsScreen(state, nav, null) { student -> nav.navigateSingleTop("report/${student.id}") }
        }
        composable(Destinations.RiskRoute) { entry ->
            RiskStudentsScreen(state, nav, entry.arguments?.getString("className")) { student ->
                nav.navigateSingleTop("report/${student.id}")
        }
    }
    }
    // Keep refresh failures actionable on every authenticated route, including
    // secondary pages that intentionally keep their last successful content.
    // Login remains inline so the small loading/error window never covers the
    // authentication form.
    if (state.error != null && state.profile != null && state.data != null && !state.restoringSession) {
        androidx.compose.foundation.layout.Box(
            Modifier.fillMaxSize().background(Color.Black.copy(alpha = 0.16f)),
            contentAlignment = Alignment.Center
        ) {
            Surface(
                Modifier.fillMaxWidth().padding(horizontal = 28.dp),
                color = Color.White,
                shape = androidx.compose.foundation.shape.RoundedCornerShape(20.dp),
                shadowElevation = 8.dp
            ) {
                ErrorState(
                    state.error ?: "数据加载失败",
                    retry = { viewModel.refreshDashboard() },
                    dismiss = viewModel::clearError
                )
            }
        }
    }
    if (state.isOffline && !isSplash) {
        Column(Modifier.fillMaxSize(), verticalArrangement = Arrangement.Top) { OfflineBanner() }
    }
    // Login renders its loading/error state inside the form.  The global mask/dialog
    // is reserved for authenticated dashboard refreshes, so no modal spinner window
    // flashes over the login page.
    if (state.loading && !state.restoringSession && state.profile != null) Box(Modifier.fillMaxSize().background(Color.White.copy(alpha = .72f)), contentAlignment = Alignment.Center) { com.xiangshang.youth.shared.component.LoadingState() }
    }
    }
}
