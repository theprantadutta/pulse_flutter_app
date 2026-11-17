package com.example.pulse.widgets

import android.content.Context
import android.os.Build
import androidx.compose.ui.graphics.Color
import androidx.glance.color.ColorProvider
import androidx.glance.unit.ColorProvider

/**
 * Widget colours. "app" uses Pulse's own plum surfaces with the accent picked
 * in Settings (the same hex values as lib/core/theme/pulse_theme.dart);
 * "wallpaper" uses Material You system colours on Android 12+. Every role is a
 * day/night pair, so the widget follows the system theme without a redraw,
 * unless Pulse itself is set to Light or Dark.
 */
data class Palette(
    val surface: ColorProvider,
    val surfaceHigh: ColorProvider,
    val onSurface: ColorProvider,
    val muted: ColorProvider,
    val outline: ColorProvider,
    val primary: ColorProvider,
    val onPrimary: ColorProvider,
    val hero: ColorProvider,
    val onHero: ColorProvider,
    val secondary: ColorProvider,
    val secondaryContainer: ColorProvider,
    val onSecondaryContainer: ColorProvider,
    val fast: ColorProvider,
    val medium: ColorProvider,
    val slow: ColorProvider,
    val timeout: ColorProvider,
    val error: ColorProvider,
    val track: ColorProvider,
) {
    /** Latency semantics as in the app: < 10 ms fast, ≤ 40 ms medium, slower or lost = slow. */
    fun latency(ms: Double?): ColorProvider = when {
        ms == null || ms < 0 -> timeout
        ms < 10 -> fast
        ms <= 40 -> medium
        else -> slow
    }
}

private class Family(
    val darkPrimary: Long, val darkOnPrimary: Long, val darkContainer: Long, val darkOnContainer: Long,
    val lightPrimary: Long, val lightContainer: Long, val lightOnContainer: Long,
    val fixedDim: Long, val onFixed: Long,
)

private val families = mapOf(
    "PINK" to Family(0xFFFFAFD0, 0xFF5A1335, 0xFF7A2950, 0xFFFFD9E6, 0xFF8E3A60, 0xFFFFD9E6, 0xFF3B0720, 0xFFFFAFD0, 0xFF3B0720),
    "LAVENDER" to Family(0xFFDDBCFF, 0xFF3A1F57, 0xFF4B3466, 0xFFF0DBFF, 0xFF6B4F8A, 0xFFF0DBFF, 0xFF25074A, 0xFFDDBCFF, 0xFF25074A),
    "LIME" to Family(0xFFCDEB74, 0xFF2B3700, 0xFF3F5100, 0xFFE0F98A, 0xFF4A6200, 0xFFCDEB74, 0xFF141F00, 0xFFCDEB74, 0xFF141F00),
    "BLUE" to Family(0xFFA8C7FF, 0xFF003062, 0xFF1F4778, 0xFFD6E3FF, 0xFF3A5F94, 0xFFD6E3FF, 0xFF001B3E, 0xFFA8C7FF, 0xFF001B3E),
)

object WidgetTheme {
    /** Resolves the palette for one widget: its own colour choice, else the app's. */
    fun palette(context: Context, config: WidgetConfig?): Palette {
        val t = WidgetStore(context).theme()
        val wantsWallpaper = when (config?.colors) {
            "wallpaper" -> true
            "app" -> false
            else -> t.dynamic
        }
        val alpha = when (config?.background) {
            "translucent" -> 0.82f
            "clear" -> 0f
            else -> 1f
        }
        val p = if (wantsWallpaper && Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) dynamic(context, t.mode, alpha)
        else brand(t.accent, t.mode, alpha)
        return p
    }

    private fun pair(mode: String, light: Color, dark: Color): ColorProvider = when (mode) {
        "light" -> ColorProvider(light)
        "dark" -> ColorProvider(dark)
        else -> ColorProvider(day = light, night = dark)
    }

    private fun c(v: Long) = Color(v)

    private fun brand(accent: String, mode: String, alpha: Float): Palette {
        val f = families[accent] ?: families.getValue("PINK")
        fun p(light: Long, dark: Long) = pair(mode, c(light), c(dark))
        return Palette(
            surface = pair(mode, c(0xFFFFF7FA).copy(alpha = alpha), c(0xFF19121D).copy(alpha = alpha)),
            surfaceHigh = p(0xFFF1E4EA, 0xFF2F2535),
            onSurface = p(0xFF21181E, 0xFFF3E5F4),
            muted = p(0xFF524349, 0xFFD3C2D6),
            outline = p(0xFFD6C2CA, 0xFF5E4F63),
            primary = p(f.lightPrimary, f.darkPrimary),
            onPrimary = p(0xFFFFFFFF, f.darkOnPrimary),
            hero = p(f.lightContainer, f.fixedDim),
            onHero = p(f.lightOnContainer, f.onFixed),
            secondary = p(0xFF6B4F8A, 0xFFDDBCFF),
            secondaryContainer = p(0xFFF0DBFF, 0xFF4B3466),
            onSecondaryContainer = p(0xFF25074A, 0xFFF0DBFF),
            fast = p(0xFF4F6B00, 0xFFCDEB74),
            medium = p(0xFF72519C, 0xFFDDBCFF),
            slow = p(0xFFB0306A, 0xFFFFAFD0),
            timeout = p(0xFF847379, 0xFF9C8BA0),
            error = p(0xFFBA1A1A, 0xFFFFB4AB),
            track = p(0xFFEBDEE4, 0xFF3A2F40),
        )
    }

    @androidx.annotation.RequiresApi(Build.VERSION_CODES.S)
    private fun dynamic(context: Context, mode: String, alpha: Float): Palette {
        fun sys(id: Int) = Color(context.getColor(id))
        fun p(light: Int, dark: Int) = pair(mode, sys(light), sys(dark))
        return Palette(
            surface = pair(mode, sys(android.R.color.system_neutral1_10).copy(alpha = alpha), sys(android.R.color.system_neutral1_900).copy(alpha = alpha)),
            surfaceHigh = p(android.R.color.system_neutral2_100, android.R.color.system_neutral2_800),
            onSurface = p(android.R.color.system_neutral1_900, android.R.color.system_neutral1_100),
            muted = p(android.R.color.system_neutral2_700, android.R.color.system_neutral2_200),
            outline = p(android.R.color.system_neutral2_200, android.R.color.system_neutral2_600),
            primary = p(android.R.color.system_accent1_600, android.R.color.system_accent1_200),
            onPrimary = p(android.R.color.system_accent1_0, android.R.color.system_accent1_800),
            hero = p(android.R.color.system_accent1_100, android.R.color.system_accent1_200),
            onHero = p(android.R.color.system_accent1_900, android.R.color.system_accent1_900),
            secondary = p(android.R.color.system_accent2_600, android.R.color.system_accent2_200),
            secondaryContainer = p(android.R.color.system_accent2_100, android.R.color.system_accent2_700),
            onSecondaryContainer = p(android.R.color.system_accent2_900, android.R.color.system_accent2_100),
            fast = p(android.R.color.system_accent3_600, android.R.color.system_accent3_200),
            medium = p(android.R.color.system_accent2_600, android.R.color.system_accent2_200),
            slow = p(android.R.color.system_accent1_600, android.R.color.system_accent1_200),
            timeout = p(android.R.color.system_neutral2_500, android.R.color.system_neutral2_400),
            error = pair(mode, c(0xFFBA1A1A), c(0xFFFFB4AB)),
            track = p(android.R.color.system_neutral2_100, android.R.color.system_neutral2_700),
        )
    }
}
