package com.xiangshang.youth.app

import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Typography
import androidx.compose.material3.lightColorScheme
import androidx.compose.runtime.Composable
import androidx.compose.runtime.staticCompositionLocalOf
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp

val Blue = Color(0xFF347CF1)
val Sky = Color(0xFFEAF4FF)
val Navy = Color(0xFF172B4D)
val Green = Color(0xFF21C46B)
val Canvas = Color(0xFFF7FAFF)
val LocalReduceMotion = staticCompositionLocalOf { false }

object AppDimens {
    val PagePadding = 18.dp
    val SectionSpacing = 24.dp
    val CardSpacing = 14.dp
    val CardPadding = 18.dp
    val ControlHeight = 54.dp
    val MinimumTouchTarget = 48.dp
}

private val ReadableTypography = Typography(
    displaySmall = TextStyle(fontSize = 32.sp, lineHeight = 40.sp, fontWeight = FontWeight.Bold),
    headlineSmall = TextStyle(fontSize = 24.sp, lineHeight = 32.sp, fontWeight = FontWeight.Bold),
    titleLarge = TextStyle(fontSize = 22.sp, lineHeight = 30.sp, fontWeight = FontWeight.Bold),
    titleMedium = TextStyle(fontSize = 20.sp, lineHeight = 28.sp, fontWeight = FontWeight.SemiBold),
    titleSmall = TextStyle(fontSize = 18.sp, lineHeight = 26.sp, fontWeight = FontWeight.SemiBold),
    bodyLarge = TextStyle(fontSize = 17.sp, lineHeight = 25.sp),
    bodyMedium = TextStyle(fontSize = 16.sp, lineHeight = 24.sp),
    bodySmall = TextStyle(fontSize = 14.sp, lineHeight = 21.sp),
    labelLarge = TextStyle(fontSize = 17.sp, lineHeight = 24.sp, fontWeight = FontWeight.SemiBold),
    labelMedium = TextStyle(fontSize = 15.sp, lineHeight = 22.sp, fontWeight = FontWeight.Medium),
    labelSmall = TextStyle(fontSize = 14.sp, lineHeight = 20.sp, fontWeight = FontWeight.Medium)
)

@Composable fun XiangshangYouthTheme(content: @Composable () -> Unit) =
    MaterialTheme(
        colorScheme = lightColorScheme(primary = Blue, secondary = Green, background = Canvas),
        typography = ReadableTypography,
        content = content
    )
