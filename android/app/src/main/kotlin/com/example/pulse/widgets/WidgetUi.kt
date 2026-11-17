package com.example.pulse.widgets

import android.content.Context
import android.net.Uri
import androidx.compose.runtime.Composable
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.TextUnit
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.glance.ColorFilter
import androidx.glance.GlanceModifier
import androidx.glance.Image
import androidx.glance.ImageProvider
import androidx.glance.LocalContext
import androidx.glance.action.Action
import androidx.glance.action.clickable
import androidx.glance.appwidget.CircularProgressIndicator
import androidx.glance.appwidget.appWidgetBackground
import androidx.glance.appwidget.cornerRadius
import androidx.glance.background
import androidx.glance.layout.Alignment
import androidx.glance.layout.Box
import androidx.glance.layout.Column
import androidx.glance.layout.Row
import androidx.glance.layout.Spacer
import androidx.glance.layout.fillMaxSize
import androidx.glance.layout.fillMaxWidth
import androidx.glance.layout.height
import androidx.glance.layout.padding
import androidx.glance.layout.size
import androidx.glance.layout.width
import androidx.glance.text.FontWeight
import androidx.glance.text.Text
import androidx.glance.text.TextStyle
import androidx.glance.unit.ColorProvider
import com.example.pulse.MainActivity
import com.example.pulse.R
import es.antonborri.home_widget.actionStartActivity
import java.util.Locale
import kotlin.math.max
import kotlin.math.roundToInt

/** Opens Pulse on a screen: `pulse://<path>?<query>` (handled by lib/services/widgets/home_widgets.dart). */
fun openApp(context: Context, link: String): Action = actionStartActivity<MainActivity>(context, Uri.parse("pulse://$link"))

/** The widget's card: rounded surface that fills the cell, optionally tappable. */
@Composable
fun WidgetFrame(
    palette: Palette,
    onClick: Action? = null,
    padding: Dp = 14.dp,
    content: @Composable () -> Unit,
) {
    var m = GlanceModifier.fillMaxSize().appWidgetBackground().cornerRadius(26.dp).background(palette.surface)
    if (onClick != null) m = m.clickable(onClick)
    Box(modifier = m.padding(padding)) { content() }
}

@Composable
fun Icon(res: Int, tint: ColorProvider, size: Dp = 18.dp, description: String? = null, modifier: GlanceModifier = GlanceModifier) {
    Image(
        provider = ImageProvider(res),
        contentDescription = description,
        colorFilter = ColorFilter.tint(tint),
        modifier = modifier.size(size),
    )
}

/** A filled circle with an icon, like the app's tool badges. */
@Composable
fun Badge(res: Int, bg: ColorProvider, fg: ColorProvider, size: Dp = 28.dp, iconSize: Dp = 16.dp) {
    Box(
        modifier = GlanceModifier.size(size).cornerRadius(size / 2).background(bg),
        contentAlignment = Alignment.Center,
    ) { Icon(res, fg, iconSize) }
}

@Composable
fun Label(
    text: String,
    color: ColorProvider,
    size: TextUnit = 12.sp,
    weight: FontWeight = FontWeight.Normal,
    maxLines: Int = 1,
    modifier: GlanceModifier = GlanceModifier,
) {
    Text(text = text, maxLines = maxLines, modifier = modifier, style = TextStyle(color = color, fontSize = size, fontWeight = weight))
}

@Composable
fun Dot(color: ColorProvider, size: Dp = 8.dp) {
    Box(modifier = GlanceModifier.size(size).cornerRadius(size / 2).background(color)) {}
}

/** Small round icon button (refresh, run). Shows a spinner while [busy]. */
@Composable
fun RoundButton(res: Int, palette: Palette, action: Action, busy: Boolean = false, size: Dp = 32.dp, description: String) {
    Box(
        modifier = GlanceModifier.size(size).cornerRadius(size / 2).background(palette.surfaceHigh).clickable(action),
        contentAlignment = Alignment.Center,
    ) {
        if (busy) {
            CircularProgressIndicator(modifier = GlanceModifier.size(size - 14.dp), color = palette.primary)
        } else {
            Icon(res, palette.onSurface, size * 0.5f, description)
        }
    }
}

/**
 * Bar sparkline of recent replies (lost replies are full-height timeout bars).
 * Glance allows at most 10 children per Row, so bars are grouped in rows of 8.
 */
@Composable
fun Sparkline(samples: List<Double>, palette: Palette, width: Dp, height: Dp, maxBars: Int = 24) {
    val values = samples.takeLast(maxBars)
    if (values.isEmpty()) {
        Box(modifier = GlanceModifier.width(width).height(height), contentAlignment = Alignment.Center) {
            Label("No replies yet", palette.muted, 11.sp)
        }
        return
    }
    val peak = max(values.filter { it >= 0 }.maxOrNull() ?: 1.0, 1.0)
    val slot = (width.value / maxBars).coerceAtLeast(3f)
    val barW = (slot * 0.62f).coerceIn(2f, 8f).dp
    val gap = (slot - barW.value).coerceAtLeast(1f).dp
    val groups = values.chunked(8)
    Row(modifier = GlanceModifier.height(height), verticalAlignment = Alignment.Bottom) {
        groups.forEach { g ->
            Row(verticalAlignment = Alignment.Bottom) {
                g.forEach { v ->
                    val lost = v < 0
                    val h = if (lost) height else (height.value * (0.18f + 0.82f * (v / peak).toFloat())).coerceAtLeast(3f).dp
                    Box(modifier = GlanceModifier.padding(end = gap)) {
                        Box(
                            modifier = GlanceModifier.width(barW).height(h).cornerRadius(barW / 2)
                                .background(if (lost) palette.track else palette.latency(v)),
                        ) {}
                    }
                }
            }
        }
    }
}

/** Value with a small caption under it ("14 ms" / "avg"). */
@Composable
fun Stat(value: String, caption: String, palette: Palette, valueColor: ColorProvider = palette.onSurface, size: TextUnit = 15.sp) {
    Column {
        Label(value, valueColor, size, FontWeight.Bold)
        Label(caption, palette.muted, 10.sp)
    }
}

/** A horizontal meter (uptime, share of a range). */
@Composable
fun Meter(fraction: Float, palette: Palette, color: ColorProvider, width: Dp, height: Dp = 6.dp) {
    val f = fraction.coerceIn(0f, 1f)
    Box(modifier = GlanceModifier.width(width).height(height).cornerRadius(height / 2).background(palette.track)) {
        if (f > 0f) {
            Box(modifier = GlanceModifier.width((width.value * f).coerceAtLeast(height.value).dp).height(height).cornerRadius(height / 2).background(color)) {}
        }
    }
}

@Composable
fun Expand() = Spacer(modifier = GlanceModifier.fillMaxWidth().height(0.dp))

fun fmtMs(ms: Double?): String = when {
    ms == null || ms < 0 -> "—"
    ms < 1 -> "<1"
    ms < 10 -> String.format(Locale.US, "%.1f", ms)
    else -> ms.roundToInt().toString()
}

fun fmtMbps(v: Double?): String = when {
    v == null -> "—"
    v < 10 -> String.format(Locale.US, "%.1f", v)
    else -> v.roundToInt().toString()
}

fun fmtPct(v: Double?, digits: Int = 1): String = when {
    v == null -> "—"
    v >= 99.995 -> "100%"
    else -> String.format(Locale.US, "%.${digits}f%%", v)
}

fun ago(at: Long): String {
    if (at <= 0) return "never"
    val s = (System.currentTimeMillis() - at) / 1000
    return when {
        s < 45 -> "just now"
        s < 3600 -> "${(s / 60).coerceAtLeast(1)} min ago"
        s < 86_400 -> "${s / 3600} h ago"
        else -> "${s / 86_400} d ago"
    }
}

/** Hides most of an address unless the person chose to show it. */
fun maskIp(ip: String?): String {
    if (ip.isNullOrBlank()) return "—"
    if (ip.contains(':')) return ip.split(':').take(2).joinToString(":") + ":••••"
    val p = ip.split('.')
    return if (p.size == 4) "${p[0]}.••.••.${p[3]}" else "••••"
}

val pulseIcon = R.drawable.ic_w_pulse

@Composable
fun context(): Context = LocalContext.current
