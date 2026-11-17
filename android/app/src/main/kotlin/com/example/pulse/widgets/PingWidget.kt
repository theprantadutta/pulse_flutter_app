package com.example.pulse.widgets

import android.net.Uri
import androidx.compose.runtime.Composable
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.glance.GlanceModifier
import androidx.glance.LocalSize
import androidx.glance.appwidget.action.actionRunCallback
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
 * One host: live latency, a reply sparkline and stats. Refresh pings in the
 * background (no app launch); tapping the card opens Ping for that host.
 *
 * Sizes: 1×1 number only · 2×1 number + host · 2×2 number + chart ·
 * 4×1 strip · 4×2 number, chart and stats · 4×3+ everything.
 */
class PingWidget : PulseWidget() {
    @Composable
    override fun Content(env: WidgetEnv) {
        val target = env.config.targets.firstOrNull() ?: defaultPingTarget
        val snap = env.store.ping(target.host)
        val p = env.palette
        val size = LocalSize.current
        val refresh = actionRunCallback<RefreshPingAction>()
        val open = openApp(env.context, "ping?host=${Uri.encode(target.host)}&name=${Uri.encode(target.title)}")
        val last = snap?.last
        val lost = snap?.lastLost == true
        val number = when {
            snap == null -> "—"
            lost -> "Lost"
            else -> fmtMs(last)
        }
        val numberColor = if (lost) p.error else p.latency(last)
        val status = when {
            snap == null -> "Tap ↻ to ping"
            snap.error != null && snap.replies.isEmpty() -> snap.error
            lost -> "No reply · ${ago(snap.at)}"
            else -> ago(snap.at)
        }

        when {
            // 1×1: the number, tap to refresh.
            size.width < 110.dp && size.height < 110.dp -> WidgetFrame(p, refresh, padding = 8.dp) {
                Column(GlanceModifier.fillMaxSize(), horizontalAlignment = Alignment.CenterHorizontally, verticalAlignment = Alignment.CenterVertically) {
                    if (env.busy) Label("…", p.muted, 22.sp, FontWeight.Bold) else Label(number, numberColor, if (number.length > 3) 18.sp else 24.sp, FontWeight.Bold)
                    Label(if (lost || snap == null) target.title else "ms", p.muted, 10.sp)
                }
            }
            // One row high: a strip.
            size.height < 110.dp -> WidgetFrame(p, open, padding = 10.dp) {
                Row(GlanceModifier.fillMaxSize(), verticalAlignment = Alignment.CenterVertically) {
                    Dot(numberColor, 10.dp)
                    Spacer(GlanceModifier.width(8.dp))
                    Column(GlanceModifier.defaultWeight()) {
                        Label(target.title, p.onSurface, 13.sp, FontWeight.Medium)
                        Label(status, p.muted, 10.sp)
                    }
                    if (size.width >= 270.dp && env.config.showChart && snap != null) {
                        Sparkline(snap.samples, p, 90.dp, 26.dp, maxBars = 14)
                        Spacer(GlanceModifier.width(8.dp))
                    }
                    Label(number, numberColor, 20.sp, FontWeight.Bold)
                    if (!lost && snap != null) Label(" ms", p.muted, 11.sp)
                    if (size.width >= 190.dp) {
                        Spacer(GlanceModifier.width(8.dp))
                        RoundButton(R.drawable.ic_w_refresh, p, refresh, env.busy, 30.dp, "Ping ${target.title}")
                    }
                }
            }
            // 2×2 and narrower tall shapes.
            size.width < 190.dp -> WidgetFrame(p, open) {
                Column(GlanceModifier.fillMaxSize()) {
                    Row(GlanceModifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
                        Column(GlanceModifier.defaultWeight()) {
                            Label(target.title, p.onSurface, 13.sp, FontWeight.Bold)
                            if (target.name != null && target.host != GATEWAY_HOST) Label(target.host, p.muted, 10.sp)
                        }
                        RoundButton(R.drawable.ic_w_refresh, p, refresh, env.busy, 30.dp, "Ping ${target.title}")
                    }
                    Spacer(GlanceModifier.defaultWeight())
                    Row(verticalAlignment = Alignment.Bottom) {
                        Label(number, numberColor, if (number.length > 3) 28.sp else 36.sp, FontWeight.Bold)
                        if (!lost && snap != null) Label(" ms", p.muted, 13.sp, modifier = GlanceModifier.padding(bottom = 6.dp))
                    }
                    Label(status, p.muted, 10.sp)
                    if (env.config.showChart && size.height >= 150.dp) {
                        Spacer(GlanceModifier.height(6.dp))
                        Sparkline(snap?.samples ?: emptyList(), p, size.width - 28.dp, if (size.height >= 250.dp) 56.dp else 22.dp, maxBars = 16)
                    }
                    if (size.height >= 250.dp && snap != null) {
                        Spacer(GlanceModifier.height(8.dp))
                        Row(GlanceModifier.fillMaxWidth()) {
                            Box(GlanceModifier.defaultWeight()) { Stat(fmtMs(snap.avg), "avg ms", p) }
                            Box(GlanceModifier.defaultWeight()) { Stat(fmtPct(snap.lossPct, 0), "loss", p) }
                        }
                    }
                }
            }
            // Wide: number on the left, chart and stats on the right.
            else -> WidgetFrame(p, open) {
                Column(GlanceModifier.fillMaxSize()) {
                    Row(GlanceModifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
                        Badge(R.drawable.ic_w_pulse, p.hero, p.onHero, 28.dp, 16.dp)
                        Spacer(GlanceModifier.width(8.dp))
                        Column(GlanceModifier.defaultWeight()) {
                            Label(target.title, p.onSurface, 14.sp, FontWeight.Bold)
                            Label(if (target.title != target.host && target.host != GATEWAY_HOST) "${target.host} · $status" else status, p.muted, 10.sp)
                        }
                        RoundButton(R.drawable.ic_w_refresh, p, refresh, env.busy, 32.dp, "Ping ${target.title}")
                    }
                    Spacer(GlanceModifier.defaultWeight())
                    Row(GlanceModifier.fillMaxWidth(), verticalAlignment = Alignment.Bottom) {
                        Row(verticalAlignment = Alignment.Bottom) {
                            Label(number, numberColor, if (size.height >= 180.dp) 44.sp else 34.sp, FontWeight.Bold)
                            if (!lost && snap != null) Label(" ms", p.muted, 13.sp, modifier = GlanceModifier.padding(bottom = 7.dp))
                        }
                        Spacer(GlanceModifier.defaultWeight())
                        if (env.config.showChart) {
                            Sparkline(snap?.samples ?: emptyList(), p, (size.width * 0.5f), if (size.height >= 180.dp) 48.dp else 34.dp, maxBars = 24)
                        }
                    }
                    if (snap != null && size.height >= 150.dp) {
                        Spacer(GlanceModifier.height(10.dp))
                        Row(GlanceModifier.fillMaxWidth()) {
                            Box(GlanceModifier.defaultWeight()) { Stat(fmtMs(snap.avg), "avg ms", p) }
                            Box(GlanceModifier.defaultWeight()) { Stat("${fmtMs(snap.min)}–${fmtMs(snap.max)}", "min–max", p) }
                            Box(GlanceModifier.defaultWeight()) { Stat(fmtMs(snap.jitter), "jitter", p) }
                            Box(GlanceModifier.defaultWeight()) { Stat(fmtPct(snap.lossPct, 0), "loss", p, if ((snap.lossPct ?: 0.0) > 0) p.error else p.onSurface) }
                        }
                    }
                }
            }
        }
    }
}

class PingWidgetReceiver : PulseWidgetReceiver<PingWidget>() {
    override val glanceAppWidget = PingWidget()
}
