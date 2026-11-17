package com.example.pulse.widgets

import androidx.compose.runtime.Composable
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.glance.GlanceModifier
import androidx.glance.LocalSize
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
import androidx.glance.unit.ColorProvider
import com.example.pulse.R

/**
 * Monitor targets at a glance: overall state, 24 h uptime, each target's
 * latency and (when tall) its last 24 hours as blocks. Pulse's monitor
 * (foreground service or in-app) writes the snapshot after every check.
 */
class MonitorWidget : PulseWidget() {
    @Composable
    override fun Content(env: WidgetEnv) {
        val p = env.palette
        val size = LocalSize.current
        val m = env.store.monitor()
        val open = openApp(env.context, "monitor")
        val targets = m?.targets ?: emptyList()
        val down = m?.down ?: 0
        val stateColor: ColorProvider = when {
            targets.isEmpty() -> p.timeout
            down > 0 -> p.error
            targets.any { it.incident } -> p.slow
            else -> p.fast
        }
        val headline = when {
            m == null || targets.isEmpty() -> "No targets"
            down > 0 -> "$down down"
            targets.any { it.incident } -> "Degraded"
            else -> "All up"
        }
        val sub = when {
            m == null || targets.isEmpty() -> "Add targets in Pulse"
            !m.live -> "Monitoring paused · ${ago(m.at)}"
            else -> "Checked ${ago(m.at)}"
        }

        when {
            size.width < 110.dp && size.height < 110.dp -> WidgetFrame(p, open, padding = 8.dp) {
                Column(GlanceModifier.fillMaxSize(), horizontalAlignment = Alignment.CenterHorizontally, verticalAlignment = Alignment.CenterVertically) {
                    Dot(stateColor, 10.dp)
                    Spacer(GlanceModifier.height(4.dp))
                    Label(if (targets.isEmpty()) "—" else "${targets.size - down}/${targets.size}", p.onSurface, 20.sp, FontWeight.Bold)
                    Label("up", p.muted, 10.sp)
                }
            }
            size.height < 110.dp -> WidgetFrame(p, open, padding = 10.dp) {
                Row(GlanceModifier.fillMaxSize(), verticalAlignment = Alignment.CenterVertically) {
                    Badge(R.drawable.ic_w_monitor, stateColor, p.surface, 30.dp, 17.dp)
                    Spacer(GlanceModifier.width(10.dp))
                    Column(GlanceModifier.defaultWeight()) {
                        Label(headline, p.onSurface, 14.sp, FontWeight.Bold)
                        Label(sub, p.muted, 10.sp)
                    }
                    if (m?.uptime != null) Stat(fmtPct(m.uptime, 2), "24 h uptime", p)
                }
            }
            size.width < 190.dp -> WidgetFrame(p, open) {
                Column(GlanceModifier.fillMaxSize()) {
                    Row(GlanceModifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
                        Badge(R.drawable.ic_w_monitor, stateColor, p.surface, 26.dp, 15.dp)
                        Spacer(GlanceModifier.width(8.dp))
                        Label("Monitor", p.onSurface, 13.sp, FontWeight.Bold)
                    }
                    Spacer(GlanceModifier.defaultWeight())
                    Label(headline, stateColor, 22.sp, FontWeight.Bold)
                    if (m?.uptime != null) Label("${fmtPct(m.uptime, 2)} uptime", p.onSurface, 12.sp, FontWeight.Medium)
                    Label(sub, p.muted, 10.sp, maxLines = 2)
                    if (size.height >= 250.dp) {
                        Spacer(GlanceModifier.height(8.dp))
                        targets.take(4).forEach { t -> TargetRow(t, p, compact = true, width = size.width - 28.dp) }
                    }
                }
            }
            else -> WidgetFrame(p, open) {
                Column(GlanceModifier.fillMaxSize()) {
                    Row(GlanceModifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
                        Badge(R.drawable.ic_w_monitor, stateColor, p.surface, 28.dp, 16.dp)
                        Spacer(GlanceModifier.width(8.dp))
                        Column(GlanceModifier.defaultWeight()) {
                            Label("Monitor · $headline", p.onSurface, 14.sp, FontWeight.Bold)
                            Label(sub, p.muted, 10.sp)
                        }
                        if (m?.uptime != null) Stat(fmtPct(m.uptime, 2), "uptime", p, size = 14.sp)
                    }
                    Spacer(GlanceModifier.height(8.dp))
                    if (targets.isEmpty()) {
                        Label("Add a host to Monitor in Pulse to see its uptime and incidents here.", p.muted, 12.sp, maxLines = 3)
                    } else {
                        val blocks = size.height >= 250.dp
                        val rowH = if (blocks) 44 else 28
                        val fit = ((size.height.value - 64) / rowH).toInt().coerceIn(1, 7)
                        targets.take(fit).forEach { t -> TargetRow(t, p, compact = !blocks, width = size.width - 28.dp) }
                        if (targets.size > fit) Label("+${targets.size - fit} more", p.muted, 10.sp)
                    }
                }
            }
        }
    }

    @Composable
    private fun TargetRow(t: MonitorTarget, p: Palette, compact: Boolean, width: Dp) {
        val color = when {
            t.down -> p.error
            t.incident -> p.slow
            else -> p.latency(t.ms)
        }
        Column(GlanceModifier.fillMaxWidth().padding(vertical = 3.dp)) {
            Row(GlanceModifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
                Dot(color, 8.dp)
                Spacer(GlanceModifier.width(8.dp))
                Label(t.name.ifBlank { t.host }, p.onSurface, 12.sp, FontWeight.Medium, modifier = GlanceModifier.defaultWeight())
                if (!compact || width >= 200.dp) {
                    Label(fmtPct(t.uptime, 1), p.muted, 11.sp)
                    Spacer(GlanceModifier.width(8.dp))
                }
                Label(if (t.down) "Down" else "${fmtMs(t.ms)} ms", color, 12.sp, FontWeight.Bold)
            }
            if (!compact && t.blocks.isNotEmpty()) {
                Spacer(GlanceModifier.height(4.dp))
                Blocks(t.blocks, p, width)
            }
        }
    }

    /** The last 24 hours, one block per hour (grouped by 8: Glance rows hold at most 10 children). */
    @Composable
    private fun Blocks(blocks: String, p: Palette, width: Dp) {
        val list = blocks.takeLast(24)
        val w = ((width.value - 4) / 24f - 2f).coerceAtLeast(3f).dp
        Row {
            list.chunked(8).forEach { group ->
                Row {
                    group.forEach { c ->
                        Box(GlanceModifier.padding(end = 2.dp)) {
                            Box(
                                GlanceModifier.width(w).height(10.dp).cornerRadius(3.dp).background(
                                    when (c) {
                                        '1' -> p.fast
                                        '2' -> p.slow
                                        '3' -> p.error
                                        else -> p.track
                                    },
                                ),
                            ) {}
                        }
                    }
                }
            }
        }
    }
}

class MonitorWidgetReceiver : PulseWidgetReceiver<MonitorWidget>() {
    override val glanceAppWidget = MonitorWidget()
}
