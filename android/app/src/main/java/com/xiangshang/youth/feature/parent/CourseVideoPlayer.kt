package com.xiangshang.youth.feature.parent

import android.app.Activity
import android.app.PictureInPictureParams
import android.content.Context
import android.content.ContextWrapper
import android.os.Build
import android.util.Rational
import androidx.annotation.OptIn
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.CloseFullscreen
import androidx.compose.material.icons.filled.Fullscreen
import androidx.compose.material.icons.filled.PictureInPictureAlt
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.Surface
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableLongStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberUpdatedState
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.viewinterop.AndroidView
import androidx.compose.ui.unit.dp
import androidx.compose.ui.window.Dialog
import androidx.compose.ui.window.DialogProperties
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.LifecycleEventObserver
import androidx.lifecycle.compose.LocalLifecycleOwner
import androidx.media3.common.C
import androidx.media3.common.MediaItem
import androidx.media3.common.MimeTypes
import androidx.media3.common.PlaybackException
import androidx.media3.common.Player
import androidx.media3.common.util.UnstableApi
import androidx.media3.datasource.HttpDataSource
import androidx.media3.exoplayer.ExoPlayer
import androidx.media3.ui.PlayerView
import androidx.core.net.toUri
import com.xiangshang.youth.core.service.CaptionTrack
import kotlinx.coroutines.delay
import kotlin.math.abs

enum class CoursePlaybackStatus { Preparing, Ready, Playing, Paused, Ended, Failed }

data class CoursePlaybackSnapshot(
    val positionMs: Long = 0,
    val durationMs: Long = 0,
    val status: CoursePlaybackStatus = CoursePlaybackStatus.Preparing,
    val errorMessage: String? = null
) {
    val progress: Float get() = courseProgressFraction(positionMs, durationMs, status == CoursePlaybackStatus.Ended)
}

internal fun courseProgressFraction(positionMs: Long, durationMs: Long, completed: Boolean): Float =
    if (completed) 1f else if (durationMs <= 0) 0f else (positionMs.toFloat() / durationMs.toFloat()).coerceIn(0f, 1f)

internal fun shouldCheckpoint(previousPositionMs: Long, currentPositionMs: Long, intervalMs: Long = 15_000): Boolean =
    currentPositionMs > 0 && abs(currentPositionMs - previousPositionMs) >= intervalMs

/**
 * Lifecycle-owned Media3 player for school and public-benefit lessons.
 * The source may be local, progressive, HLS or DASH. Subtitle URLs are added
 * to the MediaItem rather than interpreted by a WebView or a custom parser.
 */
@OptIn(UnstableApi::class)
@Composable
internal fun CourseVideoPlayer(
    source: String,
    captions: List<CaptionTrack>,
    initialPositionMs: Long,
    playRequested: Boolean,
    retryToken: Int,
    onSnapshot: (CoursePlaybackSnapshot) -> Unit,
    onCheckpoint: (positionMs: Long, completed: Boolean) -> Unit,
    onEnded: () -> Unit,
    modifier: Modifier = Modifier,
    repeat: Boolean = false,
    showController: Boolean = true,
    snapshotIntervalMs: Long = 1_000,
    accessibilityLabel: String = "课程视频播放器",
    allowFullscreenAndPip: Boolean = showController,
    onCredentialsExpired: () -> Unit = {}
) {
    val context = LocalContext.current
    val lifecycleOwner = LocalLifecycleOwner.current
    val latestPlayRequested by rememberUpdatedState(playRequested)
    val latestSnapshot by rememberUpdatedState(onSnapshot)
    val latestCheckpoint by rememberUpdatedState(onCheckpoint)
    val latestEnded by rememberUpdatedState(onEnded)
    val latestCredentialsExpired by rememberUpdatedState(onCredentialsExpired)
    var fullscreen by remember { mutableStateOf(false) }
    var pipRequested by remember { mutableStateOf(false) }
    var bufferingStartedAt by remember { mutableLongStateOf(0L) }
    val player = remember(source, captions, retryToken) {
        ExoPlayer.Builder(context).build().apply {
            val subtitleConfigurations = captions.mapIndexedNotNull { index, track ->
                val subtitleUri = track.url?.takeIf(String::isNotBlank) ?: track.uri?.takeIf(String::isNotBlank) ?: return@mapIndexedNotNull null
                MediaItem.SubtitleConfiguration.Builder(subtitleUri.toUri())
                    .setMimeType(track.mimeType?.takeIf(String::isNotBlank) ?: MimeTypes.TEXT_VTT)
                    .setLanguage(track.language)
                    .setLabel(track.label)
                    .setSelectionFlags(if (index == 0) C.SELECTION_FLAG_DEFAULT else 0)
                    .build()
            }
            setMediaItem(MediaItem.Builder().setUri(source).setSubtitleConfigurations(subtitleConfigurations).build())
            repeatMode = if (repeat) Player.REPEAT_MODE_ONE else Player.REPEAT_MODE_OFF
            if (initialPositionMs > 0) seekTo(initialPositionMs)
            prepare()
        }
    }

    DisposableEffect(player) {
        val listener = object : Player.Listener {
            private fun publish(status: CoursePlaybackStatus, error: String? = null) {
                latestSnapshot(CoursePlaybackSnapshot(player.currentPosition.coerceAtLeast(0), player.duration.coerceAtLeast(0), status, error))
            }
            override fun onPlaybackStateChanged(playbackState: Int) {
                when (playbackState) {
                    Player.STATE_IDLE -> publish(CoursePlaybackStatus.Preparing)
                    Player.STATE_BUFFERING -> {
                        if (bufferingStartedAt == 0L) bufferingStartedAt = System.currentTimeMillis()
                        publish(CoursePlaybackStatus.Preparing)
                    }
                    Player.STATE_READY -> {
                        bufferingStartedAt = 0L
                        publish(if (player.isPlaying) CoursePlaybackStatus.Playing else CoursePlaybackStatus.Ready)
                    }
                    Player.STATE_ENDED -> {
                        publish(CoursePlaybackStatus.Ended)
                        latestCheckpoint(player.duration.coerceAtLeast(player.currentPosition).coerceAtLeast(0), true)
                        latestEnded()
                    }
                }
            }
            override fun onIsPlayingChanged(isPlaying: Boolean) {
                if (player.playbackState == Player.STATE_READY) publish(if (isPlaying) CoursePlaybackStatus.Playing else CoursePlaybackStatus.Paused)
            }
            override fun onPlayerError(error: PlaybackException) {
                val responseCode = generateSequence<Throwable>(error) { it.cause }
                    .filterIsInstance<HttpDataSource.InvalidResponseCodeException>()
                    .firstOrNull()?.responseCode
                if (responseCode == 401 || responseCode == 403) latestCredentialsExpired()
                publish(CoursePlaybackStatus.Failed, "课程视频暂时无法播放，请检查网络后重试。")
            }
        }
        player.addListener(listener)
        onDispose { player.removeListener(listener); player.release() }
    }

    DisposableEffect(lifecycleOwner, player) {
        var resumeAfterForeground = false
        val observer = LifecycleEventObserver { _, event ->
            when (event) {
                Lifecycle.Event.ON_STOP -> {
                    resumeAfterForeground = player.isPlaying
                    val activity = context.findActivity()
                    if (!pipRequested && activity?.isInPictureInPictureMode != true) player.pause()
                    latestCheckpoint(player.currentPosition.coerceAtLeast(0), false)
                }
                Lifecycle.Event.ON_START -> {
                    pipRequested = false
                    if (resumeAfterForeground && latestPlayRequested) player.play()
                }
                else -> Unit
            }
        }
        lifecycleOwner.lifecycle.addObserver(observer)
        onDispose { lifecycleOwner.lifecycle.removeObserver(observer) }
    }

    LaunchedEffect(player, playRequested) {
        if (playRequested) {
            if (player.playbackState == Player.STATE_ENDED) player.seekTo(0)
            player.play()
        } else player.pause()
    }
    LaunchedEffect(player) {
        var checkpointPosition = initialPositionMs
        while (true) {
            val position = player.currentPosition.coerceAtLeast(0)
            val duration = player.duration.coerceAtLeast(0)
            val status = when {
                player.playerError != null -> CoursePlaybackStatus.Failed
                player.playbackState == Player.STATE_ENDED -> CoursePlaybackStatus.Ended
                player.playbackState == Player.STATE_BUFFERING -> CoursePlaybackStatus.Preparing
                player.isPlaying -> CoursePlaybackStatus.Playing
                else -> CoursePlaybackStatus.Paused
            }
            val bufferingDuration = if (bufferingStartedAt > 0) System.currentTimeMillis() - bufferingStartedAt else 0
            val playbackMessage = when {
                status == CoursePlaybackStatus.Failed -> "课程视频暂时无法播放，请重试。"
                bufferingDuration >= 12_000 -> "网络连接不稳定，可暂停后重试。"
                bufferingDuration >= 4_000 -> "网络较慢，正在继续缓冲…"
                else -> null
            }
            latestSnapshot(CoursePlaybackSnapshot(position, duration, status, playbackMessage))
            if (shouldCheckpoint(checkpointPosition, position)) {
                checkpointPosition = position
                latestCheckpoint(position, false)
            }
            delay(snapshotIntervalMs.coerceAtLeast(100))
        }
    }

    val playerSurface: @Composable (Modifier) -> Unit = { surfaceModifier ->
        AndroidView(
            factory = { viewContext -> PlayerView(viewContext).also { view -> view.player = player; view.useController = showController } },
            update = {
                it.player = player
                it.useController = showController
                it.setShowSubtitleButton(captions.isNotEmpty())
            },
            modifier = surfaceModifier.fillMaxSize().semantics { contentDescription = accessibilityLabel }
        )
    }

    @Composable fun PlaybackActions(onExitFullscreen: (() -> Unit)? = null) {
        if (!allowFullscreenAndPip) return
        Surface(color = Color.Black.copy(alpha = .62f), modifier = Modifier.padding(6.dp)) {
            androidx.compose.foundation.layout.Row {
                IconButton(onClick = {
                    val activity = context.findActivity() ?: return@IconButton
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                        pipRequested = true
                        val params = PictureInPictureParams.Builder().setAspectRatio(Rational(16, 9)).apply {
                            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) setAutoEnterEnabled(false)
                        }.build()
                        activity.enterPictureInPictureMode(params)
                    }
                }, modifier = Modifier.size(44.dp).semantics { contentDescription = "画中画播放" }) {
                    Icon(Icons.Filled.PictureInPictureAlt, contentDescription = null, tint = Color.White)
                }
                IconButton(onClick = { onExitFullscreen?.invoke() ?: run { fullscreen = true } }, modifier = Modifier.size(44.dp).semantics { contentDescription = if (onExitFullscreen == null) "全屏播放" else "退出全屏" }) {
                    Icon(if (onExitFullscreen == null) Icons.Filled.Fullscreen else Icons.Filled.CloseFullscreen, contentDescription = null, tint = Color.White)
                }
            }
        }
    }

    if (fullscreen) {
        Dialog(onDismissRequest = { fullscreen = false }, properties = DialogProperties(usePlatformDefaultWidth = false, decorFitsSystemWindows = false)) {
            Box(Modifier.fillMaxSize().background(Color.Black)) {
                playerSurface(Modifier.fillMaxSize())
                Box(Modifier.align(Alignment.TopEnd)) { PlaybackActions { fullscreen = false } }
            }
        }
    } else {
        Box(modifier.background(Color.Black)) {
            playerSurface(Modifier.fillMaxSize())
            Box(Modifier.align(Alignment.TopEnd)) { PlaybackActions() }
        }
    }
}

private tailrec fun Context.findActivity(): Activity? = when (this) {
    is Activity -> this
    is ContextWrapper -> baseContext.findActivity()
    else -> null
}
