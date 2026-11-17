package com.example.pulse.widgets

import androidx.compose.runtime.Composable
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.glance.GlanceModifier
import androidx.glance.LocalSize
import androidx.glance.action.clickable
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
import androidx.glance.layout.width
import androidx.glance.text.FontWeight
import com.example.pulse.R
import kotlin.math.max

/**
 * The latest speed test (download, upload, ping) and, when tall, the recent
 * runs. "Run" opens Pulse and starts a test: a speed test moves tens of MB,
 * so it never runs unseen from the home screen.
 */
class SpeedWidget : PulseWidget() {
    @Composable
    override fun Content(env: WidgetEnv) {
        val p = env.palette
        val size = LocalSize.current
        val s = env.store.speed()
        val run = openApp(env.context, "speed?run=1")
        val open = openApp(env.context, "speed")
        val sub = if (s == null) "No test yet" else ago(s.at)

        @Composable
        fun runButton(compact: Boolean = false) {
            Row(
                GlanceModifier.cornerRadius(18.dp).background(p.primary).clickable(run)
                    .padding(horizontal = if (compact) 9.dp else 12.dp, vertical = 7.dp),
                verticalAlignment = Alignment.CenterVertically,
            ) {
                Icon(R.drawable.ic_w_play, p.onPrimary, 14.dp, "Run a speed test")
                if (!compact) {
                    Spacer(GlanceModifier.width(4.dp))
                    Label("Run", p.onPrimary, 12.sp, FontWeight.Bold)
                }
            }
        }

        when {
            size.width < 110.dp && size.height < 110.dp -> WidgetFrame(p, if (s == null) run else open, padding = 8.dp) {
                Column(GlanceModifier.fillMaxSize(), horizontalAlignment = Alignment.CenterHorizontally, verticalAlignment = Alignment.CenterVertically) {
                    Icon(R.drawable.ic_w_down, p.primary, 14.dp)
                    Label(fmtMbps(s?.down), p.onSurface, 22.sp, FontWeight.Bold)
                    Label(if (s == null) "Run" else "Mbps", p.muted, 10.sp)
                }
            }
            size.height < 110.dp -> WidgetFrame(p, open, padding = 10.dp) {
                Row(GlanceModifier.fillMaxSize(), verticalAlignment = Alignment.CenterVertically) {
                    if (size.width >= 250.dp) {
                        Badge(R.drawable.ic_w_gauge, p.hero, p.onHero, 30.dp, 17.dp)
                        Spacer(GlanceModifier.width(10.dp))
                    }
                    Metric(R.drawable.ic_w_down, fmtMbps(s?.down), "Mbps", p, p.primary)
                    Spacer(GlanceModifier.width(12.dp))
                    Metric(R.drawable.ic_w_up, fmtMbps(s?.up), "Mbps", p, p.secondary)
                    if (size.width >= 280.dp) {
                        Spacer(GlanceModifier.width(12.dp))
                        Metric(R.drawable.ic_w_pulse, fmtMs(s?.ping), "ms", p, p.latency(s?.ping))
                    }
                    Spacer(GlanceModifier.defaultWeight())
                    runButton(compact = size.width < 250.dp)
                }
            }
            size.width < 190.dp -> WidgetFrame(p, open) {
                Column(GlanceModifier.fillMaxSize()) {
                    Row(GlanceModifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
                        Column(GlanceModifier.defaultWeight()) {
                            Label("Speed", p.onSurface, 13.sp, FontWeight.Bold)
                            Label(sub, p.muted, 10.sp)
                        }
                        runButton(compact = true)
                    }
                    Spacer(GlanceModifier.defaultWeight())
                    Row(verticalAlignment = Alignment.Bottom) {
                        Label(fmtMbps(s?.down), p.onSurface, 34.sp, FontWeight.Bold)
                        Label(" Mbps", p.muted, 12.sp, modifier = GlanceModifier.padding(bottom = 6.dp))
                    }
                    Row(verticalAlignment = Alignment.CenterVertically) {
                        Icon(R.drawable.ic_w_up, p.secondary, 12.dp)
                        Label(" ${fmtMbps(s?.up)}", p.onSurface, 12.sp, FontWeight.Medium)
                        Spacer(GlanceModifier.width(10.dp))
                        Icon(R.drawable.ic_w_pulse, p.latency(s?.ping), 12.dp)
                        Label(" ${fmtMs(s?.ping)} ms", p.onSurface, 12.sp, FontWeight.Medium)
                    }
                    if (size.height >= 250.dp && s != null && s.history.size > 1) {
                        Spacer(GlanceModifier.height(10.dp))
                        History(s.history, p, size.width - 28.dp, 60.dp)
                    }
                }
            }
            else -> WidgetFrame(p, open) {
                Column(GlanceModifier.fillMaxSize()) {
                    Row(GlanceModifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
                        Badge(R.drawable.ic_w_gauge, p.hero, p.onHero, 28.dp, 16.dp)
                        Spacer(GlanceModifier.width(8.dp))
                        Column(GlanceModifier.defaultWeight()) {
                            Label("Speed test", p.onSurface, 14.sp, FontWeight.Bold)
                            Label(if (s == null) sub else "${s.server.ifBlank { "Last test" }} · $sub", p.muted, 10.sp)
                        }
                        runButton()
                    }
                    Spacer(GlanceModifier.defaultWeight())
                    Row(GlanceModifier.fillMaxWidth(), verticalAlignment = Alignment.Bottom) {
                        Box(GlanceModifier.defaultWeight()) { Big(R.drawable.ic_w_down, "Download", fmtMbps(s?.down), "Mbps", p, p.primary) }
                        Box(GlanceModifier.defaultWeight()) { Big(R.drawable.ic_w_up, "Upload", fmtMbps(s?.up), "Mbps", p, p.secondary) }
                    }
                    if (size.height >= 150.dp) {
                        Spacer(GlanceModifier.height(8.dp))
                        Row(GlanceModifier.fillMaxWidth()) {
                            Box(GlanceModifier.defaultWeight()) { Stat("${fmtMs(s?.ping)} ms", "ping", p, p.latency(s?.ping), 13.sp) }
                            Box(GlanceModifier.defaultWeight()) { Stat("${fmtMs(s?.jitter)} ms", "jitter", p, size = 13.sp) }
                        }
                    }
                    if (size.height >= 250.dp && s != null && s.history.size > 1) {
                        Spacer(GlanceModifier.height(10.dp))
                        Label("Recent tests · download", p.muted, 10.sp)
                        Spacer(GlanceModifier.height(4.dp))
                        History(s.history, p, size.width - 28.dp, if (size.height >= 340.dp) 110.dp else 64.dp)
                    }
                }
            }
        }
    }

    @Composable
    private fun Metric(icon: Int, value: String, unit: String, p: Palette, tint: androidx.glance.unit.ColorProvider) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            Icon(icon, tint, 14.dp)
            Spacer(GlanceModifier.width(3.dp))
            Label(value, p.onSurface, 17.sp, FontWeight.Bold)
            Label(" $unit", p.muted, 10.sp)
        }
    }

    @Composable
    private fun Big(icon: Int, caption: String, value: String, unit: String, p: Palette, tint: androidx.glance.unit.ColorProvider) {
        Column {
            Row(verticalAlignment = Alignment.CenterVertically) {
                Icon(icon, tint, 13.dp)
                Label(" $caption", p.muted, 11.sp)
            }
            Row(verticalAlignment = Alignment.Bottom) {
                Label(value, p.onSurface, 30.sp, FontWeight.Bold)
                Label(" $unit", p.muted, 11.sp, modifier = GlanceModifier.padding(bottom = 5.dp))
            }
        }
    }

    /** Download of the recent runs, oldest left; the newest bar uses the accent. */
    @Composable
    private fun History(runs: List<SpeedRun>, p: Palette, width: Dp, height: Dp) {
        val list = runs.take(8).reversed()
        val peak = max(list.mapNotNull { it.down }.maxOrNull() ?: 1.0, 1.0)
        val slot = width.value / list.size
        val barW = (slot * 0.7f).coerceAtMost(26f).dp
        Row(GlanceModifier.fillMaxWidth().height(height), verticalAlignment = Alignment.Bottom) {
            list.forEachIndexed { i, r ->
                val h = (height.value * ((r.down ?: 0.0) / peak).toFloat()).coerceAtLeast(4f).dp
                Box(GlanceModifier.defaultWeight(), contentAlignment = Alignment.BottomCenter) {
                    Box(GlanceModifier.width(barW).height(h).cornerRadius(6.dp).background(if (i == list.lastIndex) p.primary else p.secondaryContainer)) {}
                }
            }
        }
    }
}

class SpeedWidgetReceiver : PulseWidgetReceiver<SpeedWidget>() {
    override val glanceAppWidget = SpeedWidget()
}
