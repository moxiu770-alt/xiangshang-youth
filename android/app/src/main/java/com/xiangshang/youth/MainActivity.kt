package com.xiangshang.youth

import android.content.Intent
import android.net.Uri
import android.os.Bundle
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
    private lateinit var appViewModel: AppViewModel

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        ApiClient.initialize(this)
        // The visual spec uses full-bleed artwork on the launch/login surfaces.
        // Draw behind system bars so Android does not add a black status-bar band.
        WindowCompat.setDecorFitsSystemWindows(window, false)
        window.statusBarColor = android.graphics.Color.TRANSPARENT
        window.navigationBarColor = android.graphics.Color.TRANSPARENT
        WindowInsetsControllerCompat(window, window.decorView).apply {
            isAppearanceLightStatusBars = false
            isAppearanceLightNavigationBars = true
        }
        incomingDeepLink = intent?.data
        appViewModel = ViewModelProvider(this)[AppViewModel::class.java]
        setContent {
            XiangshangYouthTheme { AppNavHost(appViewModel, incomingDeepLink) }
        }
    }

    override fun onResume() {
        super.onResume()
        // Refresh only when an authenticated session exists; AppViewModel safely
        // no-ops during the splash/login flow. This keeps dashboards current after
        // returning from Settings, WeChat, file pickers, or another app.
        if (::appViewModel.isInitialized) appViewModel.refreshDashboard()
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        incomingDeepLink = intent.data
    }
}
