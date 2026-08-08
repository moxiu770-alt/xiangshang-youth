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
import com.xiangshang.youth.core.service.ApiClient

class MainActivity : ComponentActivity() {
    private var incomingDeepLink: Uri? by mutableStateOf(null)
    private var privacyShielded: Boolean by mutableStateOf(false)
    private lateinit var appViewModel: AppViewModel

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        ApiClient.initialize(this)
        // The visual spec uses full-bleed artwork on the launch/login surfaces.
        // Draw behind system bars so Android does not add a black status-bar band.
        WindowCompat.setDecorFitsSystemWindows(window, false)
        WindowInsetsControllerCompat(window, window.decorView).apply {
            isAppearanceLightStatusBars = false
            isAppearanceLightNavigationBars = true
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
        if (::appViewModel.isInitialized && !appViewModel.state.value.isOffline) appViewModel.refreshDashboard()
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
}
