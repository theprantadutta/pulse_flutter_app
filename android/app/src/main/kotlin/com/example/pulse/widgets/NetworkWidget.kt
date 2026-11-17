package com.example.pulse.widgets

import androidx.compose.runtime.Composable
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.glance.GlanceModifier
import androidx.glance.LocalSize
import androidx.glance.appwidget.action.actionRunCallback
import androidx.glance.layout.Alignment
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
 * The connection right now: Wi-Fi name or network type, local address, router
 * (and its latency), DNS, and the public address Pulse last saw. Local values
 * are read live each time it draws; refresh also pings the router.
 */
class NetworkWidget : PulseWidget() {
    @Composable
    override fun Content(env: WidgetEnv) {
        val p = env.palette
        val size = LocalSize.current
        val n = WidgetNetwork.read(env.context)
        val router = env.store.ping(GATEWAY_HOST)
        val pub = env.store.publicIp()
        val refresh = actionRunCallback<RefreshPingAction>()
        val open = openApp(env.context, "open?to=/network")
        val icon = when (n.kind) {
            "wifi" -> R.drawable.ic_w_wifi
            "cellular" -> R.drawable.ic_w_signal
            "ethernet" -> R.drawable.ic_w_router
            "vpn" -> R.drawable.ic_w_shield
            "offline" -> R.drawable.ic_w_x
            else -> R.drawable.ic_w_globe
        }
        val kindName = when (n.kind) {
            "wifi" -> "Wi-Fi"
            "cellular" -> "Mobile data"
            "ethernet" -> "Ethernet"
            "vpn" -> "VPN"
            "offline" -> "Offline"
            else -> "Connected"
        }
        val title = n.ssid ?: kindName
        val subtitle = buildList {
            if (n.ssid != null) add(kindName)
            n.bandGhz?.let { add(it) }
            if (n.vpn && n.kind != "vpn") add("VPN on")
        }.joinToString(" · ").ifBlank { if (n.kind == "offline") "No connection" else kindName }
        val local = if (env.config.showLocalIp) n.localIp ?: "—" else maskIp(n.localIp)
        val publicIp = if (env.config.showPublicIp) pub?.ip ?: "—" else maskIp(pub?.ip)
        val routerMs = router?.takeIf { n.gateway != null }?.let { if (it.lastLost) "Lost" else "${fmtMs(it.last)} ms" }

        when {
            size.width < 110.dp && size.height < 110.dp -> WidgetFrame(p, open, padding = 8.dp) {
                Column(GlanceModifier.fillMaxSize(), horizontalAlignment = Alignment.CenterHorizontally, verticalAlignment = Alignment.CenterVertically) {
                    Badge(icon, if (n.kind == "offline") p.error else p.hero, if (n.kind == "offline") p.surface else p.onHero, 30.dp, 17.dp)
                    Spacer(GlanceModifier.height(4.dp))
                    Label(title, p.onSurface, 11.sp, FontWeight.Medium)
                }
            }
            size.height < 110.dp -> WidgetFrame(p, open, padding = 10.dp) {
                Row(GlanceModifier.fillMaxSize(), verticalAlignment = Alignment.CenterVertically) {
                    Badge(icon, if (n.kind == "offline") p.error else p.hero, if (n.kind == "offline") p.surface else p.onHero, 30.dp, 17.dp)
                    Spacer(GlanceModifier.width(10.dp))
                    Column(GlanceModifier.defaultWeight()) {
                        Label(title, p.onSurface, 14.sp, FontWeight.Bold)
                        Label(if (size.width >= 250.dp) "$subtitle · $local" else local, p.muted, 10.sp)
                    }
                    if (routerMs != null && size.width >= 250.dp) {
                        Stat(routerMs, "router", p, if (router?.lastLost == true) p.error else p.latency(router?.last), 13.sp)
                        Spacer(GlanceModifier.width(8.dp))
                    }
                    if (size.width >= 190.dp) RoundButton(R.drawable.ic_w_refresh, p, refresh, env.busy, 30.dp, "Refresh")
                }
            }
            else -> WidgetFrame(p, open) {
                Column(GlanceModifier.fillMaxSize()) {
                    Row(GlanceModifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
                        Badge(icon, if (n.kind == "offline") p.error else p.hero, if (n.kind == "offline") p.surface else p.onHero, 28.dp, 16.dp)
                        Spacer(GlanceModifier.width(8.dp))
                        Column(GlanceModifier.defaultWeight()) {
                            Label(title, p.onSurface, 14.sp, FontWeight.Bold)
                            Label(subtitle, p.muted, 10.sp)
                        }
                        RoundButton(R.drawable.ic_w_refresh, p, refresh, env.busy, 30.dp, "Refresh")
                    }
                    Spacer(GlanceModifier.height(8.dp))
                    val wide = size.width >= 190.dp
                    val rows = buildList {
                        add(Triple("Local IP", local, null as String?))
                        if (n.gateway != null) add(Triple("Router", n.gateway, routerMs))
                        if (size.height >= 150.dp || !wide) add(Triple("Public IP", publicIp, pub?.isp?.takeIf { wide }))
                        if (size.height >= 190.dp && n.dns.isNotEmpty()) add(Triple("DNS", n.dns.take(2).joinToString(", "), null))
                        if (size.height >= 250.dp && n.rssi != null) add(Triple("Signal", "${n.rssi} dBm", n.linkMbps?.let { "$it Mbps link" }))
                        if (size.height >= 250.dp && n.ipv6 != null) add(Triple("IPv6", if (env.config.showLocalIp) n.ipv6 else maskIp(n.ipv6), null))
                    }
                    val fit = ((size.height.value - 60) / (if (wide) 22 else 30)).toInt().coerceAtLeast(1)
                    rows.take(fit).forEach { (k, v, extra) ->
                        if (wide) {
                            Row(GlanceModifier.fillMaxWidth().padding(vertical = 2.dp), verticalAlignment = Alignment.CenterVertically) {
                                Label(k, p.muted, 11.sp, modifier = GlanceModifier.width(70.dp))
                                Label(v, p.onSurface, 12.sp, FontWeight.Medium, modifier = GlanceModifier.defaultWeight())
                                if (extra != null) Label(extra, if (extra == "Lost") p.error else p.muted, 11.sp, FontWeight.Medium)
                            }
                        } else {
                            Column(GlanceModifier.fillMaxWidth().padding(vertical = 2.dp)) {
                                Label(k, p.muted, 10.sp)
                                Label(if (extra != null && k == "Router") "$v · $extra" else v, p.onSurface, 12.sp, FontWeight.Medium)
                            }
                        }
                    }
                }
            }
        }
    }
}

class NetworkWidgetReceiver : PulseWidgetReceiver<NetworkWidget>() {
    override val glanceAppWidget = NetworkWidget()
}
