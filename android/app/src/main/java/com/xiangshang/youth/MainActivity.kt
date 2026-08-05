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
import androidx.lifecycle.viewmodel.compose.viewModel
import com.xiangshang.youth.app.AppViewModel
import com.xiangshang.youth.app.XiangshangYouthTheme
import com.xiangshang.youth.app.AppNavHost

class MainActivity : ComponentActivity() {
    private var incomingDeepLink: Uri? by mutableStateOf(null)

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
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
        setContent {
            val appViewModel: AppViewModel = viewModel()
            XiangshangYouthTheme { AppNavHost(appViewModel, incomingDeepLink) }
        }
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        incomingDeepLink = intent.data
    }
}
