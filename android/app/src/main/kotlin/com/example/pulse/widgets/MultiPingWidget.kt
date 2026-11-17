package com.example.pulse.widgets

import android.net.Uri
import androidx.compose.runtime.Composable
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.glance.GlanceModifier
import androidx.glance.LocalSize
import androidx.glance.action.clickable
import androidx.glance.appwidget.action.actionRunCallback
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

/**
 * Up to six hosts side by side (router, DNS, servers). One refresh pings them
 * all in the background; tapping a row opens Ping for that host.
 */
class MultiPingWidget : PulseWidget() {
    @Composable
    override fun Content(env: WidgetEnv) {
        val p = env.palette
        val size = LocalSize.current
        val hosts = hostsFor(env.context, env.widgetId, this)
        val refresh = actionRunCallback<RefreshPingAction>()
        val snaps = hosts.map { it to env.store.ping(it.host) }
        val newest = snaps.mapNotNull { it.second?.at }.maxOrNull() ?: 0L

        fun open(t: Target) = openApp(env.context, "ping?host=${Uri.encode(t.host)}&name=${Uri.encode(t.title)}")

        if (size.height < 110.dp) {
            // One row: compact tiles.
            val fit = ((size.width.value - 52) / 74).toInt().coerceIn(1, 4)
            WidgetFrame(p, padding = 8.dp) {
                Row(GlanceModifier.fillMaxSize(), verticalAlignment = Alignment.CenterVertically) {
                    snaps.take(fit).forEach { (t, s) ->
                        Box(GlanceModifier.defaultWeight().padding(end = 6.dp)) {
                            Column(
                                GlanceModifier.fillMaxWidth().cornerRadius(16.dp).background(p.surfaceHigh).padding(horizontal = 8.dp, vertical = 6.dp).clickable(open(t)),
                            ) {
                                Label(t.title, p.muted, 10.sp)
                                Label(if (s?.lastLost == true) "Lost" else fmtMs(s?.last), if (s?.lastLost == true) p.error else p.latency(s?.last), 16.sp, FontWeight.Bold)
                            }
                        }
                    }
                    RoundButton(R.drawable.ic_w_refresh, p, refresh, env.busy, 30.dp, "Ping all")
                }
            }
            return
        }

        val rowsFit = ((size.height.value - 58) / 34).toInt().coerceIn(1, 6)
        val wide = size.width >= 250.dp
        WidgetFrame(p) {
            Column(GlanceModifier.fillMaxSize()) {
                Row(GlanceModifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
                    Badge(R.drawable.ic_w_signal, p.hero, p.onHero, 26.dp, 15.dp)
                    Spacer(GlanceModifier.width(8.dp))
                    Column(GlanceModifier.defaultWeight()) {
                        Label("Ping", p.onSurface, 14.sp, FontWeight.Bold)
                        Label(if (newest == 0L) "Tap ↻ to ping" else ago(newest), p.muted, 10.sp)
                    }
                    RoundButton(R.drawable.ic_w_refresh, p, refresh, env.busy, 30.dp, "Ping all")
                }
                Spacer(GlanceModifier.height(6.dp))
                snaps.take(rowsFit).forEach { (t, s) ->
                    val lost = s?.lastLost == true
                    Row(
                        GlanceModifier.fillMaxWidth().height(34.dp).clickable(open(t)),
                        verticalAlignment = Alignment.CenterVertically,
                    ) {
                        Dot(if (s == null) p.timeout else if (lost) p.error else p.latency(s.last), 8.dp)
                        Spacer(GlanceModifier.width(8.dp))
                        Column(GlanceModifier.defaultWeight()) {
                            Label(t.title, p.onSurface, 13.sp, FontWeight.Medium)
                            if (wide && t.host != GATEWAY_HOST && t.title != t.host) Label(t.host, p.muted, 10.sp)
                        }
                        if (wide && env.config.showChart && s != null) {
                            Sparkline(s.samples, p, 84.dp, 20.dp, maxBars = 12)
                            Spacer(GlanceModifier.width(10.dp))
                        }
                        Label(if (lost) "Lost" else fmtMs(s?.last), if (lost) p.error else p.latency(s?.last), 15.sp, FontWeight.Bold)
                        if (!lost && s?.last != null) Label(" ms", p.muted, 10.sp)
                    }
                }
            }
        }
    }
}

class MultiPingWidgetReceiver : PulseWidgetReceiver<MultiPingWidget>() {
    override val glanceAppWidget = MultiPingWidget()
}
