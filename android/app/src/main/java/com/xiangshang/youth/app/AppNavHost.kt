package com.xiangshang.youth.app

import android.app.Activity
import android.animation.ValueAnimator
import android.database.ContentObserver
import android.net.Uri
import android.os.Handler
import android.os.Looper
import android.provider.Settings
import androidx.compose.runtime.Composable
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.*
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Security
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.unit.dp
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.compositionLocalOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.navigation.NavHostController
import androidx.navigation.compose.NavHost
import androidx.navigation.compose.composable
import androidx.navigation.compose.rememberNavController
import androidx.navigation.compose.currentBackStackEntryAsState
import androidx.compose.ui.platform.LocalView
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.core.view.WindowInsetsControllerCompat
import com.xiangshang.youth.feature.auth.*
import com.xiangshang.youth.feature.parent.*
import com.xiangshang.youth.feature.report.ReportDetailScreen
import com.xiangshang.youth.feature.report.SchoolReportPendingScreen
import com.xiangshang.youth.feature.teacher.*
import com.xiangshang.youth.core.model.UserRole
import com.xiangshang.youth.core.model.bodyAssessmentAgeMonths
import com.xiangshang.youth.core.util.DeepLinkResolver
import com.xiangshang.youth.core.util.DeepLinkTarget
import com.xiangshang.youth.shared.component.*

object Destinations { const val Splash="splash"; const val Login="login"; const val Register="register"; const val PasswordReset="passwordReset"; const val Role="role"; const val Parent="parent"; const val Children="children"; const val ChildrenBinding="childrenBinding"; const val ParentEvaluations="parentEvaluations"; const val BodyAssessment="bodyAssessment"; const val Assessment="assessment"; const val Activities="activities"; const val Experts="experts"; const val Courses="courses"; const val CoursesRoute="courses?openSupport={openSupport}"; const val Circle="circle"; const val Account="account"; const val Messages="messages"; const val Notifications="notifications"; const val Health="health"; const val Report="report"; const val ReportRoute="report/{studentId}"; const val Teacher="teacher"; const val TeacherMessages="teacherMessages"; const val Classes="classes"; const val TeacherCircle="teacherCircle"; const val TeacherBoard="teacherBoard"; const val Students="students"; const val StudentsRoute="students?classId={classId}"; const val OutstandingStudents="outstandingStudents"; const val UnassignedStudents="unassignedStudents"; const val Tasks="tasks"; const val SportsUpload="sportsUpload"; const val TaskDetail="taskDetail"; const val TaskDetailRoute="taskDetail/{taskId}"; const val Review="review"; const val BackendDashboard="backendDashboard" }

/** Shared retry actions keep page-level failures actionable without threading
 * the same callbacks through every feature screen. */
val LocalDashboardRetry = compositionLocalOf<() -> Unit> { {} }
val LocalDashboardClearError = compositionLocalOf<() -> Unit> { {} }
val LocalLoadMoreStudents = compositionLocalOf<() -> Unit> { {} }

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

@Suppress("DEPRECATION")
@Composable fun AppNavHost(viewModel: AppViewModel, incomingDeepLink: Uri? = null, nav: NavHostController = rememberNavController(), privacyShielded: Boolean = false) {
    val state by viewModel.state.collectAsState()
    val view = LocalView.current
    val currentEntry by nav.currentBackStackEntryAsState()
    // NavHost exposes a null entry for a short interval during the first frame.
    // Treat that interval as splash as well, otherwise the offline banner and
    // dashboard chrome can flash over the launch artwork before the route is
    // established.
    val isSplash = currentEntry?.destination?.route?.let { it == Destinations.Splash } ?: true
    var handledDeepLink by rememberSaveable { mutableStateOf<String?>(null) }
    // Android's “移除动画” setting changes the global animator duration
    // scale. Observe it while the app is foregrounded so the product setting
    // and the system accessibility preference both control the same motion.
    var systemAnimationsEnabled by remember { mutableStateOf(ValueAnimator.areAnimatorsEnabled()) }
    DisposableEffect(view.context) {
        val resolver = view.context.contentResolver
        val observer = object : ContentObserver(Handler(Looper.getMainLooper())) {
            override fun onChange(selfChange: Boolean) {
                systemAnimationsEnabled = ValueAnimator.areAnimatorsEnabled()
            }
        }
        resolver.registerContentObserver(
            Settings.Global.getUriFor(Settings.Global.ANIMATOR_DURATION_SCALE),
            false,
            observer
        )
        onDispose { resolver.unregisterContentObserver(observer) }
    }

    // The approved launch experience is a pure poster.  Keep Android's
    // status/navigation overlays out of both the system-splash handoff and
    // the Compose poster, then restore normal system chrome as soon as Login
    // or a role workbench is visible.  Merely tinting a reserved system-bar
    // strip still leaves time, signal and gesture UI over the supplied art.
    LaunchedEffect(isSplash, state.profile != null, state.restoringSession) {
        (view.context as? Activity)?.window?.let { window ->
            WindowInsetsControllerCompat(window, view).apply {
                if (isSplash) {
                    systemBarsBehavior = WindowInsetsControllerCompat.BEHAVIOR_SHOW_TRANSIENT_BARS_BY_SWIPE
                    hide(
                        androidx.core.view.WindowInsetsCompat.Type.statusBars() or
                            androidx.core.view.WindowInsetsCompat.Type.navigationBars()
                    )
                    window.statusBarColor = 0xFF7452A5.toInt()
                    window.navigationBarColor = 0xFF7452A5.toInt()
                    isAppearanceLightStatusBars = false
                    isAppearanceLightNavigationBars = false
                } else {
                    systemBarsBehavior = WindowInsetsControllerCompat.BEHAVIOR_DEFAULT
                    // Root and detail pages use the same light canvas as the
                    // Material top chrome; do not leave a blue status-bar band
                    // above white pages.
                    window.statusBarColor = 0xFFF7FAFF.toInt()
                    window.navigationBarColor = android.graphics.Color.WHITE
                    show(androidx.core.view.WindowInsetsCompat.Type.statusBars() or androidx.core.view.WindowInsetsCompat.Type.navigationBars())
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
        if (handledDeepLink == value || deepLink == null) return@LaunchedEffect
        if (deepLink.target == DeepLinkTarget.WechatCallback) {
            handledDeepLink = value
            if (!deepLink.code.isNullOrBlank() && !deepLink.state.isNullOrBlank()) viewModel.exchangeWechat(deepLink.code, deepLink.state) { nav.replaceRoot(Destinations.Role) }
            return@LaunchedEffect
        }
        if (state.profile == null || state.data == null) return@LaunchedEffect
        // A notification URL is not a role grant. Ignore an unauthorized link
        // without disturbing the current workbench; cold launch still follows
        // the normal splash/session restoration path.
        if (!DeepLinkResolver.isAuthorized(deepLink.target, state.repositoryAcknowledged, state.profile?.availableRoles.orEmpty().toSet())) {
            handledDeepLink = value
            return@LaunchedEffect
        }
        fun navigateRoleRoot(role: UserRole): String {
            if (!viewModel.canUseRole(role)) return nav.currentDestination?.route ?: Destinations.Login
            viewModel.chooseRole(role)
            val root = when (role) {
                UserRole.Parent -> Destinations.Parent
                UserRole.Teacher -> Destinations.Teacher
                UserRole.Principal -> Destinations.BackendDashboard
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
                    nav.navigate(Destinations.ChildrenBinding) { launchSingleTop = true }
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
                // Risk dashboards belong to the school-management backend.
                // Keep the route's authority explicit instead of displaying a
                // principal notice over a parent/teacher session.
                viewModel.chooseRole(UserRole.Principal)
                nav.replaceRoot(Destinations.BackendDashboard)
            }
            // Consumed by the callback branch above; retained for exhaustive
            // routing so future deep-link targets cannot fall through silently.
            DeepLinkTarget.WechatCallback -> Unit
        }
        handledDeepLink = value
    }
    // The instrumentation fixture enters through the same role root as a
    // signed-in school account. It does not add a public login shortcut.
    LaunchedEffect(state.uiTestSchoolProvisionedTeacher, state.role, state.data) {
        if (state.uiTestSchoolProvisionedTeacher && state.role == UserRole.Teacher && state.data != null && currentEntry?.destination?.route != Destinations.Teacher) {
            nav.replaceRoot(Destinations.Teacher)
        }
    }
    CompositionLocalProvider(
        LocalReduceMotion provides (state.local.settings.reduceMotion || !systemAnimationsEnabled),
        LocalDashboardRetry provides { viewModel.refreshDashboard() },
        LocalDashboardClearError provides viewModel::clearError,
        LocalLoadMoreStudents provides { viewModel.loadMoreStudents() }
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
                    else -> Destinations.BackendDashboard
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
                onLogin = { identifier, verificationCode, password -> viewModel.login(identifier, verificationCode = verificationCode, password = password, onSuccess = { nav.replaceRoot(Destinations.Role) }) },
                onRequestCode = { account, purpose, result -> viewModel.requestVerificationCode(account, purpose, result) },
                onRegister = { nav.navigate(Destinations.Register) },
                onForgotPassword = { nav.navigate(Destinations.PasswordReset) }
            )
        }
        composable(Destinations.Register) {
            RegisterScreen(
                onBack = { nav.popBackStack() },
                onRegistered = { name, phone, verificationCode, password, role ->
                    viewModel.register(name, phone, verificationCode, password, role, onSuccess = {
                        nav.replaceRoot(when (role) {
                            UserRole.Parent -> Destinations.Parent
                            UserRole.Teacher -> Destinations.Teacher
                            UserRole.Principal -> Destinations.BackendDashboard
                        })
                    })
                },
                loading = state.loading,
                serverError = state.error,
                onClearError = viewModel::clearError,
                onRequestCode = { account, purpose, result -> viewModel.requestVerificationCode(account, purpose, result) }
            )
        }
        composable(Destinations.PasswordReset) { PasswordResetScreen(onBack = { nav.popBackStack() }, onReset = { phone, code, password, result -> viewModel.resetPassword(phone, code, password, result) }, onRequestCode = { account, purpose, result -> viewModel.requestVerificationCode(account, purpose, result) }) }
        composable(Destinations.Role) { RoleSelectScreen(availableRoles = state.profile?.availableRoles.orEmpty(), onRole = { role ->
            if (viewModel.canUseRole(role)) {
                viewModel.chooseRole(role)
                val destination = if (role.name == "Parent") Destinations.Parent else if (role.name == "Teacher") Destinations.Teacher else Destinations.BackendDashboard
                nav.replaceRoot(destination)
            }
        }, onLogout = { viewModel.logout(); nav.replaceRoot(Destinations.Login) }) }
        composable(Destinations.Parent) { ParentHomeScreen(state, nav, viewModel::saveDraft, viewModel::clearDraft, { viewModel.refreshDashboard() }, { name, date, note, expertId, serviceId, slotId, startAt, endAt -> viewModel.submitExpertCommand(name, date, note, expertId, serviceId, slotId, startAt, endAt) }, viewModel::clearWorkflowState, viewModel::loadActivities, viewModel::loadExperts, viewModel::loadExpertSlots) }
        composable(Destinations.Activities) { ActivityListScreen(state, nav, viewModel::loadActivities, { name, phone, activityId -> viewModel.submitActivityCommand(name, phone, activityId) }, viewModel::saveDraft, viewModel::clearDraft, viewModel::clearWorkflowState, { activityId -> viewModel.cancelActivityRegistrationCommand(activityId) }, state.pendingActivityId, viewModel::clearActivityTarget) }
        composable(Destinations.Experts) { ExpertListScreen(state, nav, viewModel::loadExperts, viewModel::loadExpertSlots, { name, date, note, expertId, serviceId, slotId, startAt, endAt -> viewModel.submitExpertCommand(name, date, note, expertId, serviceId, slotId, startAt, endAt) }, { name, date, note, expertId, serviceId, slotId, startAt, endAt -> viewModel.rescheduleExpertCommand(name, date, note, expertId, serviceId, slotId, startAt, endAt) }, { expertId, _ -> viewModel.cancelExpertCommand(expertId) }, viewModel::saveDraft, viewModel::clearDraft, viewModel::clearWorkflowState, state.pendingExpertAppointmentId?.let { pendingId -> state.expertAppointmentHistory.firstOrNull { it.appointmentId == pendingId }?.expertId }, viewModel::clearExpertAppointmentTarget) }
        // The family manager remains visible after a successful binding, so a
        // parent can bind more than one child in the same household. Entry
        // points that merely need a child to unlock a report/task use the
        // separate ChildrenBinding route below and return to their origin.
        composable(Destinations.Children) { ChildrenScreen(state, nav, viewModel::bindChild, choose = { viewModel.chooseChild(it); nav.popBackStack() }, saveDraft = viewModel::saveDraft, clearDraft = viewModel::clearDraft, clearWorkflow = viewModel::clearWorkflowState, onBound = {}) }
        composable(Destinations.ChildrenBinding) { ChildrenScreen(state, nav, viewModel::bindChild, choose = { viewModel.chooseChild(it); nav.popBackStack() }, saveDraft = viewModel::saveDraft, clearDraft = viewModel::clearDraft, clearWorkflow = viewModel::clearWorkflowState, onBound = { nav.popBackStack() }) }
        // `visibleReport` deliberately stays empty in remote mode until ReportApi
        // returns.  Do not use the synchronous Mock-shaped fallback here.
        composable(Destinations.ParentEvaluations) { ParentEvaluationsScreen(state, nav, state.selectedChild?.takeIf(state::hasPublishedSchoolReport)?.let(viewModel::visibleReport)) }
        composable(Destinations.BodyAssessment) { BodyAssessmentScreen(state, nav, viewModel::saveBodyAssessment, viewModel::saveBodyAssessmentDraft, viewModel::toggleBodyPlanDay, viewModel::saveFollowAlongSession, updateVoiceGuidance = { viewModel.updateSettings(voiceGuidanceEnabled = it) }, recordHealthConsent = viewModel::recordHealthConsent) }
        composable("${Destinations.Assessment}/{category}") { entry ->
            // Legacy local routes may still contain /assessment/fitness. The
            // product's only body-test surface is the BMI + live camera flow;
            // never let those routes reveal the retired text-only form.
            val category = entry.arguments?.getString("category") ?: "fitness"
            if (category == "fitness") {
                BodyAssessmentScreen(state, nav, viewModel::saveBodyAssessment, viewModel::saveBodyAssessmentDraft, viewModel::toggleBodyPlanDay, viewModel::saveFollowAlongSession, updateVoiceGuidance = { viewModel.updateSettings(voiceGuidanceEnabled = it) }, recordHealthConsent = viewModel::recordHealthConsent)
            } else {
                AssessmentFlowScreen(state, nav, category, viewModel::completeAssessment, viewModel::saveDraft, viewModel::clearDraft, viewModel::loadFamilyHealthObservations)
            }
        }
        composable(Destinations.Courses) { ParentCoursesScreen(state, nav, viewModel::updateCourseProgress, viewModel::sendSupport, viewModel::saveDraft, viewModel::clearDraft, loadCourses = viewModel::loadCourses, loadPlayback = viewModel::loadLessonPlayback, clearPlayback = viewModel::clearLessonPlayback, saveRemoteProgress = viewModel::saveRemoteLessonProgress, clearRecommendedCourse = viewModel::clearRecommendedCourseTarget, submitSupport = viewModel::submitSupportCommand, clearWorkflow = viewModel::clearWorkflowState) }
        composable(Destinations.CoursesRoute) { entry ->
            ParentCoursesScreen(
                state, nav, viewModel::updateCourseProgress, viewModel::sendSupport,
                viewModel::saveDraft, viewModel::clearDraft,
                loadCourses = viewModel::loadCourses,
                loadPlayback = viewModel::loadLessonPlayback,
                clearPlayback = viewModel::clearLessonPlayback,
                saveRemoteProgress = viewModel::saveRemoteLessonProgress,
                clearRecommendedCourse = viewModel::clearRecommendedCourseTarget,
                openSupport = entry.arguments?.getString("openSupport") == "true",
                submitSupport = viewModel::submitSupportCommand,
                clearWorkflow = viewModel::clearWorkflowState
            )
        }
        composable(Destinations.Circle) { ParentClassCircleScreen(state, nav, viewModel::publishPost, viewModel::saveDraft, viewModel::clearDraft, viewModel::togglePostLike, viewModel::addPostComment, viewModel::submitClassPostCommand, viewModel::clearWorkflowState, viewModel::loadClassPosts, viewModel::loadClassPostAttachment, viewModel::deleteClassPostCommand, viewModel::reportClassPostCommand) }
        composable(Destinations.Account) {
            if (state.role?.name == "Teacher") {
                TeacherAccountScreen(state, nav, viewModel::logout, viewModel::updateSettings, {
                    viewModel.clearRoleSelection()
                    nav.replaceRoot(Destinations.Role)
                }, viewModel::syncPendingRecords, viewModel::submitAccountDeletionRequest)
            } else {
                AccountScreen(
                    state, nav, viewModel::chooseRole, viewModel::logout, viewModel::updateSettings,
                    viewModel::sendSupport,
                    onRoleSelected = { role ->
                        if (viewModel.canUseRole(role)) {
                            viewModel.chooseRole(role)
                            nav.replaceRoot(if (role == UserRole.Parent) Destinations.Parent else if (role == UserRole.Teacher) Destinations.Teacher else Destinations.BackendDashboard)
                        }
                    },
                    submitSupport = viewModel::submitSupportCommand,
                    clearWorkflow = viewModel::clearWorkflowState,
                    saveDraft = viewModel::saveDraft,
                    clearDraft = viewModel::clearDraft,
                    syncPending = viewModel::syncPendingRecords,
                    submitPrivacyRequest = viewModel::submitPrivacyRequest,
                    revokeHealthConsent = viewModel::revokeHealthConsent
                    ,submitAccountDeletionRequest = viewModel::submitAccountDeletionRequest
                )
            }
        }
        composable(Destinations.Messages) { ParentMessagesScreen(state, nav, viewModel::markMessageRead, viewModel::markAllMessagesRead, viewModel::openRecommendedCourse, viewModel::openActivityTarget, viewModel::openExpertAppointmentTarget) }
        composable(Destinations.Notifications) { NotificationsScreen(state, nav, viewModel::markMessageRead, viewModel::markAllMessagesRead, viewModel::openRecommendedCourse, viewModel::openActivityTarget, viewModel::openExpertAppointmentTarget, viewModel::loadClassNoticeDetail, viewModel::acknowledgeClassNotice) }
        composable(Destinations.Health) { HealthProfileScreen(state, nav, { type, minutes, intensity, feeling, completed, note -> viewModel.checkInToday(type, minutes, intensity, feeling, completed, note) }, viewModel::visibleReport) }
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
                        androidx.compose.material3.Button(onClick = { nav.navigate(Destinations.ChildrenBinding) }) { Text("去绑定孩子") }
                    }
                }
                !state.hasPublishedSchoolReport(child) -> SchoolReportPendingScreen(child, nav)
                else -> {
                    val report = viewModel.visibleReport(child)
                    if (report == null) {
                        AppScaffold("体测报告", onBack = { nav.popBackStack() }) {
                            if (state.reportError != null) ErrorState(state.reportError ?: "报告获取失败", retry = { viewModel.refreshReport(child) }, dismiss = viewModel::clearReportError)
                            else LoadingState()
                            LaunchedEffect(child.id) { viewModel.refreshReport(child) }
                        }
                    } else ReportDetailScreen(
                    report = report,
                    isRefreshing = state.reportLoadingStudentId == child.id,
                    onRefresh = { viewModel.refreshReport(child) },
                    reportError = state.reportError,
                    onDismissReportError = viewModel::clearReportError,
                    bodyAssessment = state.local.bodyAssessments[child.id],
                    bodyAgeMonths = child.bodyAssessmentAgeMonths,
                    studentGender = child.gender,
                    nav = nav,
                    openRecommendedCourse = { suggestion ->
                        viewModel.openRecommendedCourse(child.id, suggestion.courseId, suggestion.lessonId, suggestion.title)
                        // Courses is a parent tab root, not a second detail
                        // stack layered on top of a report.
                        nav.navigate(Destinations.Courses) {
                            popUpTo(Destinations.Parent) { saveState = true }
                            launchSingleTop = true
                            restoreState = true
                        }
                    }
                )
                }
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
                !state.hasPublishedSchoolReport(student) -> SchoolReportPendingScreen(student, nav)
                else -> {
                    val report = viewModel.visibleReport(student)
                    if (report == null) {
                        AppScaffold("体测报告", onBack = { nav.popBackStack() }) {
                            if (state.reportError != null) ErrorState(state.reportError ?: "报告获取失败", retry = { viewModel.refreshReport(student) }, dismiss = viewModel::clearReportError)
                            else LoadingState()
                            LaunchedEffect(student.id) { viewModel.refreshReport(student) }
                        }
                    } else ReportDetailScreen(
                    report = report,
                    isRefreshing = state.reportLoadingStudentId == student.id,
                    onRefresh = { viewModel.refreshReport(student) },
                    reportError = state.reportError,
                    onDismissReportError = viewModel::clearReportError,
                    bodyAssessment = state.local.bodyAssessments[student.id],
                    bodyAgeMonths = student.bodyAssessmentAgeMonths,
                    studentGender = student.gender,
                    nav = nav
                )
                }
            }
        }
        composable(Destinations.Teacher) { TeacherHomeScreen(state, nav, viewModel::setTeacherSportsWorkbench, viewModel::refreshDashboard, viewModel::visibleReport) }
        composable(Destinations.TeacherMessages) { TeacherMessagesScreen(state, nav, viewModel::markMessageRead, viewModel::markAllMessagesRead, viewModel::refreshDashboard, viewModel::loadClassNoticeDetail, viewModel::acknowledgeClassNotice) }
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
                loadNotificationDrafts = viewModel::loadNotificationDrafts,
                saveNotificationDraft = viewModel::saveNotificationDraft,
                sendNotificationDraft = viewModel::sendNotificationDraft,
                discardNotificationDraft = viewModel::discardNotificationDraft,
                clearWorkflow = viewModel::clearWorkflowState,
                loadClassPosts = viewModel::loadClassPosts,
                deleteClassPost = viewModel::deleteClassPostCommand,
                reportClassPost = viewModel::reportClassPostCommand,
                setClassPostPinned = viewModel::setClassPostPinnedCommand
            )
        }
        composable(Destinations.TeacherBoard) { TeacherClassBoardScreen(state, nav, onOpenReport = { student -> nav.navigateSingleTop("report/${student.id}") }, reportForStudent = viewModel::visibleReport, loadOverview = viewModel::loadTeacherOverview) }
        composable(Destinations.Students) { StudentListScreen(state, nav, null, onOpenStudent = { student -> nav.navigateSingleTop("report/${student.id}") }, reportForStudent = viewModel::visibleReport) }
        composable(Destinations.UnassignedStudents) { StudentListScreen(state, nav, null, unassignedOnly = true, onOpenStudent = { student -> nav.navigateSingleTop("report/${student.id}") }, reportForStudent = viewModel::visibleReport) }
        composable(Destinations.StudentsRoute) { entry -> StudentListScreen(state, nav, entry.arguments?.getString("classId"), onOpenStudent = { student -> nav.navigateSingleTop("report/${student.id}") }, reportForStudent = viewModel::visibleReport) }
        composable(Destinations.OutstandingStudents) { StudentListScreen(state, nav, null, outstandingOnly = true, onOpenStudent = { student -> nav.navigateSingleTop("report/${student.id}") }, reportForStudent = viewModel::visibleReport) }
        composable(Destinations.Tasks) { TeacherTasksScreen(state, nav, viewModel::saveCourseUpload, { taskId, attendance, notes, attachment, attachmentReference -> viewModel.submitCourseUploadCommand(taskId, attendance, notes, attachment, attachmentReference) }, viewModel::saveDraft, viewModel::clearDraft) }
        composable(Destinations.SportsUpload) { TeacherTasksScreen(state, nav, viewModel::saveCourseUpload, { taskId, attendance, notes, attachment, attachmentReference -> viewModel.submitCourseUploadCommand(taskId, attendance, notes, attachment, attachmentReference) }, viewModel::saveDraft, viewModel::clearDraft, root = true) }
        composable(Destinations.TaskDetailRoute) { entry ->
            val taskId = entry.arguments?.getString("taskId")
            LaunchedEffect(taskId) { taskId?.let(viewModel::loadTaskStudents) }
            TeacherTaskDetailScreen(state, nav, taskId) { studentId, status, note -> viewModel.submitTaskStatusCommand(studentId, status, note, taskId) }
        }
        composable(Destinations.Review) { ReviewListScreen(state, nav, viewModel::submitReviewDecision, viewModel::saveDraft, viewModel::clearDraft) { studentId, status, note, taskId -> viewModel.submitTaskStatusCommand(studentId, status, note, taskId) } }
        composable(Destinations.BackendDashboard) {
            BackendDashboardNoticeScreen(
                onLogout = { viewModel.logout(); nav.replaceRoot(Destinations.Login) }
            )
        }
        // Deprecated principal routes resolve to the backend notice instead of
        // reopening a mobile principal workbench from an old deep link.
        // Historical mobile principal routes are intentionally collapsed into
        // the backend notice. This prevents old deep links or stale navigation
        // state from silently reopening a removed principal workbench.
    }
    // Keep refresh failures actionable without covering a populated dashboard.
    // Existing cards remain usable; the banner owns only its small top area.
    if (state.error != null && state.profile != null && state.data != null && !state.restoringSession) {
        Box(Modifier.fillMaxSize(), contentAlignment = Alignment.TopCenter) {
            Surface(
                Modifier
                    .fillMaxWidth()
                    .padding(horizontal = 16.dp, vertical = 8.dp)
                    .semantics { contentDescription = "刷新失败：${state.error}，可重试或关闭提示" },
                color = Color.White.copy(alpha = .96f),
                shape = androidx.compose.foundation.shape.RoundedCornerShape(16.dp),
                shadowElevation = 6.dp
            ) {
                Row(
                    Modifier.padding(horizontal = 12.dp, vertical = 7.dp),
                    verticalAlignment = Alignment.CenterVertically,
                    horizontalArrangement = Arrangement.spacedBy(6.dp)
                ) {
                    Text("⚠", color = Color(0xFFFF9700))
                    Text(
                        state.error ?: "数据加载失败",
                        modifier = Modifier.weight(1f),
                        color = Color(0xFF20385F),
                        maxLines = 2
                    )
                    TextButton(onClick = viewModel::refreshDashboard) { Text("重试") }
                    TextButton(onClick = viewModel::clearError) { Text("关闭") }
                }
            }
        }
    }
    if (state.isOffline && !isSplash) {
        Column(Modifier.fillMaxSize(), verticalArrangement = Arrangement.Top) { OfflineBanner() }
    }
    // Login renders loading inline. For an authenticated refresh, preserve the
    // current board's interaction instead of placing a full-screen blocker over
    // teacher/principal actions; this compact banner is deliberately passive.
    if (state.loading && !state.restoringSession && state.profile != null && state.data != null) {
        Box(Modifier.fillMaxSize(), contentAlignment = Alignment.TopCenter) {
            Surface(
                modifier = Modifier.padding(top = 10.dp).semantics { contentDescription = "正在刷新数据，当前内容仍可操作" },
                color = Color.White.copy(alpha = .94f),
                shape = androidx.compose.foundation.shape.RoundedCornerShape(22.dp),
                shadowElevation = 5.dp
            ) {
                Row(
                    Modifier.padding(horizontal = 14.dp, vertical = 9.dp),
                    horizontalArrangement = Arrangement.spacedBy(8.dp),
                    verticalAlignment = Alignment.CenterVertically
                ) {
                    CircularProgressIndicator(Modifier.size(15.dp), color = Blue, strokeWidth = 2.dp)
                    Text("正在刷新数据", color = Navy, style = androidx.compose.material3.MaterialTheme.typography.labelMedium)
                }
            }
        }
    }
    if (privacyShielded && !isSplash) {
        Box(Modifier.fillMaxSize().background(Canvas), contentAlignment = Alignment.Center) {
            Column(horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(10.dp)) {
                androidx.compose.material3.Icon(Icons.Filled.Security, contentDescription = null, tint = Blue, modifier = Modifier.size(34.dp))
                Text("向上少年", color = Navy, style = androidx.compose.material3.MaterialTheme.typography.titleMedium)
                Text("已保护学生健康数据", color = Color.Gray, style = androidx.compose.material3.MaterialTheme.typography.bodySmall)
            }
        }
    }
    }
    }
}
