package com.xiangshang.youth

import android.content.Intent
import android.net.Uri
import android.os.Bundle
import android.view.WindowManager
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.core.view.WindowCompat
import androidx.core.view.WindowInsetsControllerCompat
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.lifecycle.ViewModelProvider
import com.xiangshang.youth.app.AppViewModel
import com.xiangshang.youth.app.XiangshangYouthTheme
import com.xiangshang.youth.app.AppNavHost
import com.xiangshang.youth.core.model.BodyCaptureQualityGate
import com.xiangshang.youth.feature.parent.ChildFollowAlongTuning

class MainActivity : ComponentActivity() {
    private var incomingDeepLink: Uri? by mutableStateOf(null)
    private var privacyShielded: Boolean by mutableStateOf(false)
    private lateinit var appViewModel: AppViewModel

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        preloadPostureCaptureProfiles()
        preloadFollowAlongProfiles()
        // The visual spec uses full-bleed artwork on the launch/login surfaces.
        // Draw behind system bars so Android does not add a black status-bar band.
        // AppNavHost restores normal system chrome as soon as the splash route
        // finishes; keeping this transition here avoids a cropped poster during
        // the first Compose-owned frame.
        WindowCompat.setDecorFitsSystemWindows(window, false)
        WindowInsetsControllerCompat(window, window.decorView).apply {
            // AppNavHost repeats this policy while Splash is the active route,
            // but applying it here also covers Android's first Compose frame.
            // Without this eager hide a time/signal strip can flash over the
            // approved pure-poster launch artwork during the handoff.
            systemBarsBehavior = WindowInsetsControllerCompat.BEHAVIOR_SHOW_TRANSIENT_BARS_BY_SWIPE
            hide(
                androidx.core.view.WindowInsetsCompat.Type.statusBars() or
                    androidx.core.view.WindowInsetsCompat.Type.navigationBars()
            )
            isAppearanceLightStatusBars = false
            isAppearanceLightNavigationBars = false
        }
        incomingDeepLink = intent?.data
        appViewModel = ViewModelProvider(this)[AppViewModel::class.java]
        setContent {
            XiangshangYouthTheme { AppNavHost(appViewModel, incomingDeepLink, privacyShielded = privacyShielded) }
        }
    }

    override fun onPause() {
        // The Android recent-apps thumbnail must not expose a student's health
        // report. Compose draws the same shield in the foreground, while this
        // temporary secure flag covers the system-owned task snapshot.
        privacyShielded = true
        window.setFlags(WindowManager.LayoutParams.FLAG_SECURE, WindowManager.LayoutParams.FLAG_SECURE)
        super.onPause()
    }

    override fun onResume() {
        super.onResume()
        window.clearFlags(WindowManager.LayoutParams.FLAG_SECURE)
        privacyShielded = false
        // Refresh only when an authenticated session exists; AppViewModel safely
        // no-ops during the splash/login flow. This keeps dashboards current after
        // returning from Settings, WeChat, file pickers, or another app.
        if (::appViewModel.isInitialized && !appViewModel.state.value.isOffline) {
            appViewModel.refreshDashboard()
            if (appViewModel.state.value.pendingSyncCount > 0) appViewModel.syncPendingRecords()
        }
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        incomingDeepLink = intent.data
    }

    /** Keeps instrumentation isolated from a prior manual session. The
     * production logout flow continues to use the same ViewModel operation. */
    fun resetSessionForUiTest() {
        if (::appViewModel.isInitialized) appViewModel.logout()
    }

    /** Explicit teacher fixture for instrumentation. It is never exposed by
     * public registration or production navigation. */
    fun startSchoolProvisionedTeacherFixtureForUiTest() {
        if (::appViewModel.isInitialized) appViewModel.startSchoolProvisionedTeacherFixtureForUiTest()
    }

    private fun preloadPostureCaptureProfiles() {
        runCatching {
            assets.open("body_pose_capture_profiles.json").bufferedReader().use { reader ->
                val raw = reader.readText()
                if (!BodyCaptureQualityGate.setProfileOverridesFromJson(raw)) {
                    BodyCaptureQualityGate.clearProfileOverrides()
                }
            }
        }.onFailure {
            BodyCaptureQualityGate.clearProfileOverrides()
        }
    }

    private fun preloadFollowAlongProfiles() {
        runCatching {
            assets.open("follow_along_action_profiles.json").bufferedReader().use { reader ->
                val raw = reader.readText()
                if (!ChildFollowAlongTuning.setProfileOverridesFromJson(raw)) {
                    ChildFollowAlongTuning.clearProfileOverrides()
                }
            }
        }.onFailure {
            ChildFollowAlongTuning.clearProfileOverrides()
        }
    }
}
