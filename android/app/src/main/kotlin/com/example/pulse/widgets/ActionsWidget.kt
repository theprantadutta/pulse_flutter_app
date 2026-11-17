package com.example.pulse.widgets

import androidx.compose.runtime.Composable
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
import androidx.glance.text.FontWeight
import com.example.pulse.R

/** A tool the Quick actions widget can launch. Ids match the Dart side (WidgetTool). */
data class Tool(val id: String, val label: String, val icon: Int, val link: String)

val widgetTools = listOf(
    Tool("ping", "Ping", R.drawable.ic_w_pulse, "open?to=/ping"),
    Tool("speed", "Speed", R.drawable.ic_w_gauge, "speed?run=1"),
    Tool("trace", "Trace", R.drawable.ic_w_route, "open?to=/traceroute"),
    Tool("lan", "LAN", R.drawable.ic_w_lan, "open?to=/lan"),
    Tool("geo", "Geo IP", R.drawable.ic_w_globe, "open?to=/geo"),
    Tool("ports", "Ports", R.drawable.ic_w_port, "open?to=/ports"),
    Tool("loss", "Loss", R.drawable.ic_w_loss, "open?to=/loss"),
    Tool("monitor", "Monitor", R.drawable.ic_w_monitor, "open?to=/monitor"),
    Tool("network", "Network", R.drawable.ic_w_wifi, "open?to=/network"),
    Tool("history", "History", R.drawable.ic_w_clock, "open?to=/history"),
).associateBy { it.id }

/** Shortcuts into Pulse's tools, laid out to fit: 1, a row, or a grid. */
class ActionsWidget : PulseWidget() {
    @Composable
    override fun Content(env: WidgetEnv) {
        val p = env.palette
        val size = LocalSize.current
        val tools = env.config.tools.mapNotNull { widgetTools[it] }.ifEmpty { WidgetConfig.defaultTools.mapNotNull { widgetTools[it] } }
        val tones = listOf(p.hero to p.onHero, p.secondaryContainer to p.onSecondaryContainer, p.surfaceHigh to p.onSurface)

        @Composable
        fun Tile(t: Tool, i: Int, labels: Boolean, modifier: GlanceModifier) {
            val (bg, fg) = tones[i % tones.size]
            Box(modifier.padding(3.dp)) {
                Column(
                    GlanceModifier.fillMaxSize().cornerRadius(20.dp).background(bg).clickable(openApp(env.context, t.link)),
                    horizontalAlignment = Alignment.CenterHorizontally,
                    verticalAlignment = Alignment.CenterVertically,
                ) {
                    Icon(t.icon, fg, if (labels) 20.dp else 24.dp, t.label)
                    if (labels) {
                        Spacer(GlanceModifier.height(3.dp))
                        Label(t.label, fg, 11.sp, FontWeight.Medium)
                    }
                }
            }
        }

        val cols: Int
        val rows: Int
        when {
            size.width < 110.dp && size.height < 110.dp -> { cols = 1; rows = 1 }
            size.height < 110.dp -> { cols = ((size.width.value) / 66).toInt().coerceIn(2, 5); rows = 1 }
            size.width < 190.dp -> { cols = 2; rows = if (size.height >= 250.dp) 3 else 2 }
            else -> { cols = ((size.width.value) / 68).toInt().coerceIn(3, 5); rows = if (size.height >= 250.dp) 3 else 2 }
        }
        val shown = tools.take(cols * rows)
        val labels = size.height / rows >= 54.dp && size.width / cols >= 54.dp
        WidgetFrame(p, padding = 5.dp) {
            if (shown.size == 1) {
                Tile(shown[0], 0, size.height >= 80.dp, GlanceModifier.fillMaxSize())
            } else {
                Column(GlanceModifier.fillMaxSize()) {
                    shown.chunked(cols).forEachIndexed { r, line ->
                        Row(GlanceModifier.fillMaxWidth().defaultWeight()) {
                            line.forEachIndexed { c, t -> Tile(t, r * cols + c, labels, GlanceModifier.defaultWeight().fillMaxSize()) }
                            repeat(cols - line.size) { Box(GlanceModifier.defaultWeight()) {} }
                        }
                    }
                }
            }
        }
    }
}

class ActionsWidgetReceiver : PulseWidgetReceiver<ActionsWidget>() {
    override val glanceAppWidget = ActionsWidget()
}
