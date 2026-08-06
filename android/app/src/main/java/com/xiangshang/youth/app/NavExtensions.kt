package com.xiangshang.youth.app

import androidx.navigation.NavHostController

/**
 * Repeated taps on a dashboard card or notification bell should reuse the
 * current destination instead of creating an identical back-stack entry.
 */
fun NavHostController.navigateSingleTop(route: String) {
    navigate(route) { launchSingleTop = true }
}
