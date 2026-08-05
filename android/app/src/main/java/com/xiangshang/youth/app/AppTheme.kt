package com.xiangshang.youth.app

import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.lightColorScheme
import androidx.compose.runtime.Composable
import androidx.compose.runtime.staticCompositionLocalOf
import androidx.compose.ui.graphics.Color

val Blue = Color(0xFF347CF1)
val Sky = Color(0xFFEAF4FF)
val Navy = Color(0xFF172B4D)
val Green = Color(0xFF21C46B)
val Canvas = Color(0xFFF7FAFF)
val LocalReduceMotion = staticCompositionLocalOf { false }

@Composable fun XiangshangYouthTheme(content: @Composable () -> Unit) =
    MaterialTheme(colorScheme = lightColorScheme(primary = Blue, secondary = Green, background = Canvas), content = content)
