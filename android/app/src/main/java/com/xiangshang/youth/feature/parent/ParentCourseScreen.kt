package com.xiangshang.youth.feature.parent

import android.content.Intent
import android.app.DatePickerDialog
import android.graphics.BitmapFactory
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.animation.core.*
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.*
import androidx.compose.material.icons.filled.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.scale
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.asImageBitmap
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.role
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.navigation.NavHostController
import java.util.Calendar
import com.xiangshang.youth.R
import com.xiangshang.youth.app.*
import com.xiangshang.youth.core.model.Student
import com.xiangshang.youth.core.model.DiagnosisReport
import com.xiangshang.youth.core.model.UserRole
import com.xiangshang.youth.core.model.BodyAttentionLevel
import com.xiangshang.youth.core.model.bodyAssessmentAgeMonths
import com.xiangshang.youth.core.service.FeatureRollout
import com.xiangshang.youth.core.service.ClassPost
import com.xiangshang.youth.core.service.ClassPostAttachment
import com.xiangshang.youth.core.service.CourseAttachmentStore
import com.xiangshang.youth.core.service.LocalSubmissionStatus
import com.xiangshang.youth.core.service.RemoteLesson
import com.xiangshang.youth.core.service.RemoteActivity
import com.xiangshang.youth.core.service.RemoteExpert
import com.xiangshang.youth.core.service.ExpertAvailableSlot
import com.xiangshang.youth.core.service.CaptionTrack
import com.xiangshang.youth.shared.component.*
import kotlinx.coroutines.delay

private fun remoteCourseSelectionKey(lesson: RemoteLesson): String =
    "remote:${lesson.courseId}:${lesson.moduleId ?: "default"}:${lesson.lessonId}"

@Composable fun ParentCoursesScreen(state: AppUiState, nav: NavHostController, updateCourseProgress: (String, Float) -> Unit, sendSupport: (String) -> Unit, saveDraft: (String, String) -> Unit, clearDraft: (String) -> Unit, loadCourses: (String) -> Unit = {}, loadPlayback: (String) -> Unit = {}, clearPlayback: () -> Unit = {}, saveRemoteProgress: (String, RemoteLesson, Int, Boolean) -> Unit = { _, _, _, _ -> }, clearRecommendedCourse: () -> Unit = {}, openSupport: Boolean = false, submitSupport: (String) -> Unit = sendSupport, clearWorkflow: (String) -> Unit = {}) {
    var paid by remember { mutableStateOf(false) }
    var detail by rememberSaveable(openSupport) { mutableStateOf<String?>(if (openSupport) "客服咨询" else null) }
    var selectedCourseKey by rememberSaveable { mutableStateOf<String?>(null) }
    var selectedCourseTitle by rememberSaveable { mutableStateOf<String?>(null) }
    var catalogOpen by rememberSaveable { mutableStateOf(false) }
    var recommendationError by rememberSaveable { mutableStateOf<String?>(null) }
    LaunchedEffect(openSupport) { if (openSupport) clearWorkflow("support") }
    ParentTabScaffold(nav, Destinations.Courses) {
        val dashboardError = state.error
        if (dashboardError != null && state.data == null) { ErrorState(dashboardError, retry = LocalDashboardRetry.current, dismiss = LocalDashboardClearError.current); return@ParentTabScaffold }
        if (state.loading || state.data == null) { LoadingState(); return@ParentTabScaffold }
        if (state.selectedChild == null) { EmptyState("暂无孩子档案，请先完成孩子绑定。"); Button(onClick = { nav.navigate(Destinations.ChildrenBinding) }) { Text("去绑定孩子") }; return@ParentTabScaffold }
        val selectedChild = state.selectedChild
        LaunchedEffect(selectedChild.id) { if (state.repositoryAcknowledged) loadCourses(selectedChild.id) }
        LaunchedEffect(state.courseRecommendationTarget, state.coursesLoading, state.coursesChildId, state.remoteCourses) {
            val target = state.courseRecommendationTarget ?: return@LaunchedEffect
            if (target.childId != selectedChild.id) return@LaunchedEffect
            if (!state.repositoryAcknowledged) {
                selectedCourseKey = "recommendation:${target.courseId ?: target.lessonId ?: "unassigned"}"
                selectedCourseTitle = target.title
                clearRecommendedCourse()
                return@LaunchedEffect
            }
            // `coursesChildId` makes a fast child switch safe: no result or
            // error from a former child's request can open a lesson here.
            if (state.coursesChildId != selectedChild.id || state.coursesLoading) return@LaunchedEffect
            val courseId = target.courseId
            val lessonId = target.lessonId
            if (courseId.isNullOrBlank() || lessonId.isNullOrBlank()) {
                recommendationError = "该报告的课程建议尚未包含可播放课程信息，请在学校同步课程后再试。"
            } else if (state.coursesError == null) {
                val lesson = state.remoteCourses.firstOrNull { it.courseId == courseId && it.lessonId == lessonId }
                if (lesson != null) {
                    selectedCourseKey = remoteCourseSelectionKey(lesson)
                    selectedCourseTitle = lesson.title
                }
                else recommendationError = "学校暂未为该孩子分配这节推荐课程。"
            }
            if (state.coursesError == null) clearRecommendedCourse()
        }
        Text("我的课程", color = Navy, fontWeight = FontWeight.Bold, fontSize = 18.sp, modifier = Modifier.padding(top = 10.dp)); Text("${selectedChild.name} · ${selectedChild.className}", color = Color.Gray, fontSize = 12.sp); Spacer(Modifier.height(8.dp))
        Row(Modifier.fillMaxWidth().background(Sky, RoundedCornerShape(9.dp))) { listOf("公益课程", "学校课程").forEachIndexed { index, text -> Text(text, color = if (paid == (index == 1)) Color.White else Blue, fontWeight = FontWeight.Bold, fontSize = 12.sp, textAlign = TextAlign.Center, modifier = Modifier.weight(1f).padding(8.dp).semantics { role = Role.Tab; contentDescription = "切换到$text" }.background(if (paid == (index == 1)) Blue else Color.Transparent, RoundedCornerShape(8.dp)).clickable { paid = index == 1 }) } }
        Spacer(Modifier.height(10.dp)); ParentSection(if (paid) "精选学校课程" else "公益课堂", "全部课程") { catalogOpen = true }
        val items = if (state.repositoryAcknowledged) state.remoteCourses.map { Triple(remoteCourseSelectionKey(it), it.title, Icons.Filled.PlayCircle) } else if (paid) {
            listOf(
                Triple("local:school-fitness", "校内体能提升课", Icons.AutoMirrored.Filled.DirectionsRun),
                Triple("local:school-vision", "校园视力守护课", Icons.Filled.RemoveRedEye),
                Triple("local:school-after-class", "课后运动巩固课", Icons.Filled.FitnessCenter),
                Triple("local:school-family", "亲子运动指导课", Icons.Filled.Groups)
            )
        } else {
            listOf(
                Triple("local:public-fitness", "体质成长课", Icons.AutoMirrored.Filled.DirectionsRun),
                Triple("local:public-vision", "视力守护课", Icons.Filled.RemoveRedEye),
                Triple("local:public-oral", "口腔健康课", Icons.Filled.MedicalServices),
                Triple("local:public-wellbeing", "心理舒展课", Icons.Filled.Favorite)
            )
        }
        when {
            state.repositoryAcknowledged && state.coursesLoading -> LoadingState()
            state.repositoryAcknowledged && state.coursesError != null -> ErrorState(state.coursesError, retry = { loadCourses(selectedChild.id) })
            state.repositoryAcknowledged && items.isEmpty() -> EmptyState("暂无已分配课程，学校或平台分配后会显示在这里。")
            else -> items.chunked(2).forEach { row -> Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(8.dp)) { row.forEach { (itemKey, displayTitle, icon) -> val remote = state.remoteCourses.firstOrNull { remoteCourseSelectionKey(it) == itemKey }; Surface(Modifier.weight(1f).height(105.dp).semantics { role = Role.Button; contentDescription = "打开课程：$displayTitle" }.clickable { selectedCourseKey = itemKey; selectedCourseTitle = displayTitle }, color = Sky, shape = RoundedCornerShape(10.dp)) { Column(Modifier.padding(12.dp)) { Icon(icon, null, tint = Blue); Spacer(Modifier.height(8.dp)); Text(displayTitle, color = Navy, fontWeight = FontWeight.Bold, fontSize = 12.sp); val key = if (remote == null) com.xiangshang.youth.app.AppViewModel.courseProgressKey(selectedChild.id, itemKey, lessonId = itemKey) else com.xiangshang.youth.app.AppViewModel.courseProgressKey(selectedChild.id, remote.courseId, remote.moduleId ?: "default", remote.lessonId); val progress = state.local.courseProgress[key] ?: remote?.let { if (it.completed) 1f else (it.lastPositionMs.toFloat() / it.durationMs.coerceAtLeast(1)).coerceIn(0f,1f) } ?: 0f; Text(if (progress > 0f) "学习进度 ${(progress * 100).toInt()}%" else "开始学习", color = Green, fontSize = 12.sp) } } }; if (row.size == 1) Spacer(Modifier.weight(1f)) }; Spacer(Modifier.height(8.dp)) }
        }
        Surface(Modifier.fillMaxWidth().semantics { role = Role.Button; contentDescription = "打开课程咨询" }.clickable { clearWorkflow("support"); detail = "客服咨询" }, color = Color.White, shape = RoundedCornerShape(10.dp)) { Row(Modifier.padding(12.dp), verticalAlignment = Alignment.CenterVertically) { Icon(Icons.AutoMirrored.Filled.Message, null, tint = Blue); Spacer(Modifier.width(9.dp)); Column(Modifier.weight(1f)) { Text("课程咨询", color = Navy, fontWeight = FontWeight.Bold, fontSize = 12.sp); Text("填写后自动保存并同步", color = Color.Gray, fontSize = 12.sp) }; Icon(Icons.Filled.ChevronRight, null, tint = Color.Gray) } }
    }
    detail?.let { title -> SimpleDialog(title = title, messages = state.local.supportMessages, drafts = state.local.drafts, send = sendSupport, submit = submitSupport, command = state.workflowStates["support"] ?: WorkflowCommandState(), commandDriven = title == "客服咨询", saveDraft = saveDraft, clearDraft = clearDraft, dismiss = { detail = null }) }
    if (catalogOpen) CourseCatalogDialog(
        paid = paid,
        onOpenCourse = { courseId, title -> catalogOpen = false; selectedCourseKey = courseId; selectedCourseTitle = title },
        dismiss = { catalogOpen = false }
    )
    selectedCourseKey?.let { courseKey ->
      val selectedRemote = state.remoteCourses.firstOrNull { remoteCourseSelectionKey(it) == courseKey }
      val title = selectedRemote?.title ?: selectedCourseTitle ?: "课程"
      LaunchedEffect(selectedRemote?.lessonId) { selectedRemote?.let { loadPlayback(it.lessonId) } }
      val remotePlayback = state.coursePlayback?.takeIf { it.lessonId == selectedRemote?.lessonId }
      CourseLessonDialog(
        lessonKey = selectedRemote?.lessonId ?: courseKey,
        title = title,
        initialProgress = selectedRemote?.let { if (it.completed) 1f else (it.lastPositionMs.toFloat() / it.durationMs.coerceAtLeast(1)).coerceIn(0f,1f) } ?: state.selectedChild?.let { state.local.courseProgress[com.xiangshang.youth.app.AppViewModel.courseProgressKey(it.id, courseKey, lessonId = courseKey)] } ?: 0f,
        updateCourseProgress = { _, progress -> state.selectedChild?.let { child ->
            selectedRemote?.let { lesson ->
                updateCourseProgress(com.xiangshang.youth.app.AppViewModel.courseProgressKey(child.id, lesson.courseId, lesson.moduleId ?: "default", lesson.lessonId), progress)
            } ?: updateCourseProgress(com.xiangshang.youth.app.AppViewModel.courseProgressKey(child.id, courseKey, lessonId = courseKey), progress)
        } },
        videoSource = remotePlayback?.videoSource,
        captions = remotePlayback?.captions ?: selectedRemote?.captions.orEmpty(),
        playbackSessionKey = remotePlayback?.playbackSessionId,
        refreshAfterSeconds = remotePlayback?.refreshAfterSeconds,
        playbackLoading = selectedRemote != null && state.coursePlaybackLoading,
        playbackError = selectedRemote?.let { state.coursePlaybackError },
        progressSaving = selectedRemote != null && state.courseProgressSaveLessonId == selectedRemote.lessonId && state.courseProgressSaving,
        progressSaveError = selectedRemote?.takeIf { state.courseProgressSaveLessonId == it.lessonId }?.let { state.courseProgressSaveError },
        progressSaveConflict = selectedRemote != null && state.courseProgressSaveLessonId == selectedRemote.lessonId && state.courseProgressSaveConflict,
        refreshProgressVersion = { state.selectedChild?.let { loadCourses(it.id) } },
        retryPlayback = { selectedRemote?.let { loadPlayback(it.lessonId) } },
        mockVideoAllowed = !state.repositoryAcknowledged,
        initialPositionMs = selectedRemote?.lastPositionMs ?: 0,
        onRemoteSave = { position, completed -> state.selectedChild?.let { child -> selectedRemote?.let { lesson -> saveRemoteProgress(child.id, lesson, position, completed) } } },
        dismiss = { clearPlayback(); selectedCourseKey = null; selectedCourseTitle = null }
      )
    }
    recommendationError?.let { message ->
        AlertDialog(
            onDismissRequest = { recommendationError = null },
            title = { Text("暂无法打开课程") },
            text = { Text(message) },
            confirmButton = { TextButton(onClick = { recommendationError = null }) { Text("知道了") } }
        )
    }
}

/** A course is a real local workflow even while the production media endpoint
 * is unavailable: progress is only recorded after the learner starts it. */
@Composable
private fun CourseLessonDialog(
    lessonKey: String,
    title: String,
    initialProgress: Float,
    updateCourseProgress: (String, Float) -> Unit,
    videoSource: String? = null,
    captions: List<CaptionTrack> = emptyList(),
    playbackSessionKey: String? = null,
    refreshAfterSeconds: Int? = null,
    playbackLoading: Boolean = false,
    playbackError: String? = null,
    progressSaving: Boolean = false,
    progressSaveError: String? = null,
    progressSaveConflict: Boolean = false,
    refreshProgressVersion: () -> Unit = {},
    retryPlayback: () -> Unit = {},
    mockVideoAllowed: Boolean = true,
    initialPositionMs: Int = 0,
    onRemoteSave: ((Int, Boolean) -> Unit)? = null,
    dismiss: () -> Unit
) {
    val context = LocalContext.current
    val resolvedSource = videoSource ?: if (mockVideoAllowed) "android.resource://${context.packageName}/${R.raw.follow_along_training}" else null
    var snapshot by remember(lessonKey) { mutableStateOf(CoursePlaybackSnapshot(initialPositionMs.toLong(), 0, CoursePlaybackStatus.Paused)) }
    var progress by rememberSaveable(lessonKey) { mutableFloatStateOf(initialProgress) }
    var playRequested by rememberSaveable(lessonKey) { mutableStateOf(false) }
    var retryToken by rememberSaveable(lessonKey) { mutableIntStateOf(0) }
    var lastSavedPositionMs by rememberSaveable(lessonKey) { mutableLongStateOf(-1L) }
    var lastSavedCompleted by rememberSaveable(lessonKey) { mutableStateOf(false) }
    fun persist(positionMs: Long = snapshot.positionMs, completed: Boolean = snapshot.status == CoursePlaybackStatus.Ended || progress >= .999f) {
        val nextProgress = if (completed) 1f else progress
        if (nextProgress > initialProgress) updateCourseProgress(lessonKey, nextProgress)
        val boundedPosition = positionMs.coerceIn(0, Int.MAX_VALUE.toLong())
        if ((boundedPosition > 0 || completed) && (boundedPosition != lastSavedPositionMs || completed != lastSavedCompleted)) {
            lastSavedPositionMs = boundedPosition
            lastSavedCompleted = completed
            onRemoteSave?.invoke(boundedPosition.toInt(), completed)
        }
    }
    LaunchedEffect(lessonKey, playbackSessionKey, refreshAfterSeconds) {
        val refreshDelay = refreshAfterSeconds?.takeIf { it > 0 } ?: return@LaunchedEffect
        delay(refreshDelay * 1_000L)
        persist()
        retryPlayback()
    }
    AlertDialog(
        onDismissRequest = {
            persist()
            dismiss()
        },
        title = { Text(title) },
        text = {
            Column(horizontalAlignment = Alignment.CenterHorizontally, modifier = Modifier.fillMaxWidth()) {
                when {
                    playbackLoading -> Box(Modifier.fillMaxWidth().height(160.dp).background(Color.Black, RoundedCornerShape(10.dp)), contentAlignment = Alignment.Center) { CircularProgressIndicator(color = Color.White) }
                    resolvedSource != null -> CourseVideoPlayer(
                        source = resolvedSource,
                        captions = captions,
                        initialPositionMs = initialPositionMs.toLong(),
                        playRequested = playRequested,
                        retryToken = retryToken xor (playbackSessionKey?.hashCode() ?: 0),
                        onSnapshot = { value -> snapshot = value; progress = maxOf(progress, value.progress); if (value.status == CoursePlaybackStatus.Failed) playRequested = false },
                        onCheckpoint = { position, completed ->
                            val checkpointProgress = courseProgressFraction(position, snapshot.durationMs, completed)
                            progress = maxOf(progress, checkpointProgress)
                            persist(position, completed)
                        },
                        onEnded = { progress = 1f; playRequested = false; updateCourseProgress(lessonKey, 1f) },
                        onCredentialsExpired = { playRequested = false; retryPlayback() },
                        modifier = Modifier.fillMaxWidth().height(160.dp).clip(RoundedCornerShape(10.dp))
                    )
                    else -> Box(Modifier.fillMaxWidth().height(160.dp).background(Color(0xFF101828), RoundedCornerShape(10.dp)), contentAlignment = Alignment.Center) { Text("课程视频待同步", color = Color.White) }
                }
                (playbackError ?: snapshot.errorMessage)?.let { error ->
                    Text(error, color = Color(0xFFD64545), fontSize = 12.sp, modifier = Modifier.padding(top = 7.dp))
                    TextButton(onClick = { if (playbackError != null) retryPlayback() else { retryToken += 1; playRequested = true } }) { Text("重试播放") }
                }
                progressSaveError?.let { error ->
                    Text(error, color = Color(0xFFD64545), fontSize = 12.sp, modifier = Modifier.padding(top = 7.dp))
                    TextButton(onClick = {
                        if (progressSaveConflict) refreshProgressVersion()
                        else { lastSavedPositionMs = -1L; persist() }
                    }, enabled = !progressSaving) { Text(if (progressSaveConflict) "刷新课程" else "重试同步进度") }
                }
                if (progressSaving) Row(Modifier.padding(top = 6.dp), verticalAlignment = Alignment.CenterVertically) {
                    CircularProgressIndicator(Modifier.size(14.dp), strokeWidth = 2.dp)
                    Spacer(Modifier.width(6.dp)); Text("正在同步播放进度", color = Color.Gray, fontSize = 12.sp)
                }
                Text("课程播放进度会自动保存，联网后同步。", color = Color.Gray, fontSize = 12.sp, textAlign = TextAlign.Center, modifier = Modifier.padding(top = 8.dp))
                LinearProgressIndicator({ progress }, Modifier.fillMaxWidth().padding(top = 16.dp).height(7.dp).clip(CircleShape), color = Green, trackColor = Sky)
                Text("学习进度 ${(progress * 100).toInt()}%", color = Green, fontSize = 12.sp, modifier = Modifier.padding(top = 7.dp))
            }
        },
        confirmButton = {
            TextButton(onClick = {
                playRequested = !playRequested
            }, enabled = resolvedSource != null && !playbackLoading && playbackError == null) {
                Icon(if (playRequested) Icons.Filled.Pause else Icons.Filled.PlayArrow, null, modifier = Modifier.size(17.dp))
                Spacer(Modifier.width(4.dp))
                Text(if (playRequested) "暂停学习" else if (progress >= 1f) "再次学习" else "播放课程")
            }
        },
        dismissButton = { TextButton(onClick = { persist(); dismiss() }) { Text("完成") } }
    )
}

@Composable
private fun CourseCatalogDialog(paid: Boolean, onOpenCourse: (String, String) -> Unit, dismiss: () -> Unit) {
    val courses = if (paid) listOf("local:school-fitness" to "校内体能提升课", "local:school-vision" to "校园视力守护课", "local:school-after-class" to "课后运动巩固课", "local:school-family" to "亲子运动指导课") else listOf("local:public-fitness" to "体质成长课", "local:public-vision" to "视力守护课", "local:public-oral" to "口腔健康课", "local:public-wellbeing" to "心理舒展课")
    AlertDialog(
        onDismissRequest = dismiss,
        title = { Text(if (paid) "学校课程目录" else "公益课程目录") },
        text = {
            Column {
                Text("选择课程后可开始学习，进度会自动保存。", color = Color.Gray, fontSize = 12.sp)
                courses.forEach { (courseId, course) ->
                    Row(
                        Modifier.fillMaxWidth().padding(top = 8.dp).semantics { role = Role.Button; contentDescription = "学习$course" }.clickable { onOpenCourse(courseId, course) }.padding(vertical = 6.dp),
                        verticalAlignment = Alignment.CenterVertically
                    ) {
                        Icon(Icons.Filled.PlayCircle, null, tint = Blue, modifier = Modifier.size(20.dp))
                        Spacer(Modifier.width(8.dp))
                        Text(course, color = Navy, fontWeight = FontWeight.SemiBold, modifier = Modifier.weight(1f))
                        Icon(Icons.Filled.ChevronRight, null, tint = Color.Gray, modifier = Modifier.size(17.dp))
                    }
                }
            }
        },
        confirmButton = { TextButton(onClick = dismiss) { Text("关闭") } }
    )
}
