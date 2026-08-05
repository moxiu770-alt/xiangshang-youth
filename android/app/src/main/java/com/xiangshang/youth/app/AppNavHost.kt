package com.xiangshang.youth.app

import android.app.Activity
import android.net.Uri
import androidx.compose.runtime.Composable
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.*
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.unit.dp
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.SideEffect
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

object Destinations { const val Splash="splash"; const val Login="login"; const val Register="register"; const val Role="role"; const val Parent="parent"; const val Children="children"; const val ParentEvaluations="parentEvaluations"; const val Assessment="assessment"; const val Courses="courses"; const val Circle="circle"; const val Account="account"; const val Messages="messages"; const val Notifications="notifications"; const val Health="health"; const val Report="report"; const val Teacher="teacher"; const val TeacherMessages="teacherMessages"; const val Classes="classes"; const val TeacherCircle="teacherCircle"; const val TeacherBoard="teacherBoard"; const val Students="students"; const val StudentsRoute="students?className={className}"; const val Tasks="tasks"; const val TaskDetail="taskDetail"; const val TaskDetailRoute="taskDetail/{taskId}"; const val Review="review"; const val Principal="principal"; const val Grades="grades"; const val ClassStats="classStats"; const val ClassStatsRoute="classStats?grade={grade}"; const val Risk="risk"; const val RiskRoute="risk?className={className}" }
@Composable fun AppNavHost(viewModel: AppViewModel, incomingDeepLink: Uri? = null, nav: NavHostController = rememberNavController()) {
    val state by viewModel.state.collectAsState()
    val view = LocalView.current
    val currentEntry by nav.currentBackStackEntryAsState()
    val isSplash = currentEntry?.destination?.route == Destinations.Splash
    var handledDeepLink by rememberSaveable { mutableStateOf<String?>(null) }

    SideEffect {
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
        when (deepLink.target) {
            DeepLinkTarget.Report -> {
                viewModel.chooseRole(UserRole.Parent)
                deepLink.studentId?.let { studentId -> state.data?.students?.firstOrNull { it.id == studentId }?.let(viewModel::chooseChild) }
                nav.navigate(Destinations.Report) { launchSingleTop = true }
            }
            DeepLinkTarget.Review -> {
                viewModel.chooseRole(UserRole.Teacher)
                nav.navigate(Destinations.Review) { launchSingleTop = true }
            }
            DeepLinkTarget.Tasks -> {
                viewModel.chooseRole(UserRole.Teacher)
                nav.navigate(Destinations.Tasks) { launchSingleTop = true }
            }
            DeepLinkTarget.Risk -> {
                viewModel.chooseRole(UserRole.Principal)
                nav.navigate(Destinations.Risk) { launchSingleTop = true }
            }
        }
        handledDeepLink = value
    }
    CompositionLocalProvider(LocalReduceMotion provides state.local.settings.reduceMotion) {
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
                nav.navigate(destination) { popUpTo(Destinations.Splash) { inclusive = true } }
                },
                canFinish = { !state.restoringSession }
            )
        }
        composable(Destinations.Login) {
            LoginScreen(
                loading = state.loading,
                serverError = state.error,
                onClearError = viewModel::clearError,
                onLogin = { viewModel.login { nav.navigate(Destinations.Role) { popUpTo(Destinations.Login) { inclusive = true }; launchSingleTop = true } } },
                onRegister = { nav.navigate(Destinations.Register) }
            )
        }
        composable(Destinations.Register) { RegisterScreen(onBack = { nav.popBackStack() }, onRegistered = { viewModel.login { nav.navigate(Destinations.Role) { popUpTo(Destinations.Register) { inclusive = true }; launchSingleTop = true } } }) }
        composable(Destinations.Role) { RoleSelectScreen(onRole = { role ->
            viewModel.chooseRole(role)
            val destination = if (role.name == "Parent") Destinations.Parent else if (role.name == "Teacher") Destinations.Teacher else Destinations.Principal
            nav.navigate(destination) { popUpTo(Destinations.Role) { inclusive = true }; launchSingleTop = true }
        }, onLogout = { viewModel.logout(); nav.navigate(Destinations.Login) { popUpTo(Destinations.Role) { inclusive = true }; launchSingleTop = true } }) }
        composable(Destinations.Parent) { ParentHomeScreen(state, nav, viewModel::registerActivity, viewModel::checkInToday, viewModel::bookExpert, viewModel::saveDraft, viewModel::clearDraft) }
        composable(Destinations.Children) { ChildrenScreen(state, nav, viewModel::bindChild) { viewModel.chooseChild(it); nav.popBackStack() } }
        composable(Destinations.ParentEvaluations) { ParentEvaluationsScreen(state, nav, state.selectedChild?.let(viewModel::report)) }
        composable("${Destinations.Assessment}/{category}") { entry -> AssessmentFlowScreen(state, nav, entry.arguments?.getString("category") ?: "fitness", viewModel::completeAssessment, viewModel::saveDraft, viewModel::clearDraft) }
        composable(Destinations.Courses) { ParentCoursesScreen(state, nav, viewModel::updateCourseProgress, viewModel::sendSupport, viewModel::saveDraft, viewModel::clearDraft) }
        composable(Destinations.Circle) { ParentClassCircleScreen(state, nav, viewModel::publishPost, viewModel::saveDraft, viewModel::clearDraft, viewModel::togglePostLike, viewModel::addPostComment) }
        composable(Destinations.Account) { if (state.role?.name == "Teacher") TeacherAccountScreen(state, nav, viewModel::chooseRole, viewModel::logout, viewModel::updateSettings) else AccountScreen(state, nav, viewModel::chooseRole, viewModel::logout, viewModel::updateSettings, viewModel::sendSupport) }
        composable(Destinations.Messages) { ParentMessagesScreen(state, nav, viewModel::markMessageRead) }
        composable(Destinations.Notifications) { NotificationsScreen(state, nav, viewModel::markMessageRead) }
        composable(Destinations.Health) { HealthProfileScreen(state, nav) }
        composable(Destinations.Report) {
            val child = state.selectedChild
            when {
                state.loading || state.data == null -> com.xiangshang.youth.shared.component.LoadingState()
                child == null -> com.xiangshang.youth.shared.component.EmptyState("暂无孩子报告，请先完成孩子绑定。")
                else -> ReportDetailScreen(viewModel.report(child), state.loading, viewModel::refreshDashboard, nav)
            }
        }
        composable(Destinations.Teacher) { TeacherHomeScreen(state, nav) }
        composable(Destinations.TeacherMessages) { TeacherMessagesScreen(nav) }
        composable(Destinations.Classes) { TeacherClassesScreen(state, nav) }
        composable(Destinations.TeacherCircle) {
            TeacherClassCircleScreen(
                state = state,
                nav = nav,
                publishPost = viewModel::publishPost,
                updatePost = viewModel::updatePost,
                saveDraft = viewModel::saveDraft,
                clearDraft = viewModel::clearDraft
            )
        }
        composable(Destinations.TeacherBoard) { TeacherClassBoardScreen(state, nav) { student -> viewModel.chooseChild(student); nav.navigate(Destinations.Report) } }
        composable(Destinations.Students) { StudentListScreen(state, nav, null) { student -> viewModel.chooseChild(student); nav.navigate(Destinations.Report) } }
        composable(Destinations.StudentsRoute) { entry -> StudentListScreen(state, nav, entry.arguments?.getString("className")) { student -> viewModel.chooseChild(student); nav.navigate(Destinations.Report) } }
        composable(Destinations.Tasks) { TeacherTasksScreen(state, nav, viewModel::saveCourseUpload) }
        composable(Destinations.TaskDetailRoute) { entry -> TeacherTaskDetailScreen(state, nav, viewModel::updateStudentTaskStatus, entry.arguments?.getString("taskId")) }
        composable(Destinations.Review) { ReviewListScreen(state, nav, viewModel::submitReviewDecision) }
        composable(Destinations.Principal) { PrincipalHomeScreen(state, nav, viewModel::clearRoleSelection) }
        composable(Destinations.Grades) { GradeStatsScreen(state, nav) }
        composable(Destinations.ClassStats) { ClassStatsScreen(state, nav, null) }
        composable(Destinations.ClassStatsRoute) { entry -> ClassStatsScreen(state, nav, entry.arguments?.getString("grade")) }
        composable(Destinations.Risk) {
            RiskStudentsScreen(state, nav, null) { student -> viewModel.chooseChild(student); nav.navigate(Destinations.Report) }
        }
        composable(Destinations.RiskRoute) { entry ->
            RiskStudentsScreen(state, nav, entry.arguments?.getString("className")) { student ->
                viewModel.chooseChild(student)
                nav.navigate(Destinations.Report)
            }
        }
    }
    // Login renders its loading/error state inside the form.  The global mask/dialog
    // is reserved for authenticated dashboard refreshes, so no modal spinner window
    // flashes over the login page.
    if (state.loading && !state.restoringSession && state.profile != null) Box(Modifier.fillMaxSize().background(Color.White.copy(alpha = .72f)), contentAlignment = Alignment.Center) { com.xiangshang.youth.shared.component.LoadingState() }
    if (state.profile != null) state.error?.let { message -> AlertDialog(onDismissRequest = viewModel::clearError, title = { Text("加载失败") }, text = { Text(message.ifBlank { "请检查网络后重试。" }) }, confirmButton = { TextButton(onClick = viewModel::refreshDashboard) { Text("重试") } }, dismissButton = { TextButton(onClick = viewModel::clearError) { Text("关闭") } }) }
    }
    }
}
