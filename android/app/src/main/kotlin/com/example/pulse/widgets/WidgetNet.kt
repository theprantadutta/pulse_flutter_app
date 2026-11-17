package com.example.pulse.widgets

import android.content.Context
import android.net.ConnectivityManager
import android.net.NetworkCapabilities
import android.net.wifi.WifiManager
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.async
import kotlinx.coroutines.awaitAll
import kotlinx.coroutines.coroutineScope
import kotlinx.coroutines.withContext
import java.net.Inet4Address
import java.net.Inet6Address
import java.net.InetAddress
import java.util.concurrent.TimeUnit

/**
 * ICMP echo for widgets, without starting Flutter: the system `ping` binary
 * (unprivileged on Android, the same one the app's Android prober falls back
 * to). Each round sends [count] echoes 200 ms apart.
 */
object WidgetPinger {
    private val timeRe = Regex("""icmp_seq=(\d+).*?time[=<]([\d.]+)""")

    data class Round(val samples: List<Double>, val error: String?)

    suspend fun ping(context: Context, host: String, count: Int): Round = withContext(Dispatchers.IO) {
        val target = if (host == GATEWAY_HOST) WidgetNetwork.read(context).gateway else host
        if (target.isNullOrBlank()) return@withContext Round(emptyList(), "No router on this network")
        val v6 = runCatching { InetAddress.getByName(target) }.getOrElse {
            return@withContext Round(List(count) { -1.0 }, "Can't resolve $target")
        } is Inet6Address
        val bin = if (v6) "/system/bin/ping6" else "/system/bin/ping"
        try {
            val p = ProcessBuilder(bin, "-n", "-c", "$count", "-i", "0.2", "-W", "2", target)
                .redirectErrorStream(true).start()
            val finished = p.waitFor(count * 200L + 4_000L, TimeUnit.MILLISECONDS)
            if (!finished) p.destroy()
            val bySeq = HashMap<Int, Double>()
            p.inputStream.bufferedReader().readLines().forEach { line ->
                timeRe.find(line)?.let { m -> bySeq[m.groupValues[1].toInt()] = m.groupValues[2].toDouble() }
            }
            val first = bySeq.keys.minOrNull()?.coerceAtMost(1) ?: 1
            val samples = (first until first + count).map { bySeq[it] ?: -1.0 }
            Round(samples, null)
        } catch (e: Exception) {
            Round(List(count) { -1.0 }, e.message ?: "Ping failed")
        }
    }

    /** Pings each host (in parallel) and stores the replies. */
    suspend fun refresh(context: Context, hosts: Collection<String>, count: Int) = coroutineScope {
        val store = WidgetStore(context)
        hosts.distinct().map { host ->
            async {
                val r = ping(context, host, count)
                store.addPings(host, r.samples, r.error)
            }
        }.awaitAll()
    }
}

/** What the device is connected to right now, read natively each time a widget draws. */
data class NetworkNow(
    val kind: String,
    val ssid: String?,
    val localIp: String?,
    val ipv6: String?,
    val gateway: String?,
    val dns: List<String>,
    val vpn: Boolean,
    val rssi: Int?,
    val linkMbps: Int?,
    val bandGhz: String?,
)

object WidgetNetwork {
    @Suppress("DEPRECATION")
    fun read(context: Context): NetworkNow {
        val cm = context.getSystemService(Context.CONNECTIVITY_SERVICE) as ConnectivityManager
        val net = cm.activeNetwork
        val caps = cm.getNetworkCapabilities(net)
        val lp = cm.getLinkProperties(net)
        val kind = when {
            caps == null -> "offline"
            caps.hasTransport(NetworkCapabilities.TRANSPORT_WIFI) -> "wifi"
            caps.hasTransport(NetworkCapabilities.TRANSPORT_ETHERNET) -> "ethernet"
            caps.hasTransport(NetworkCapabilities.TRANSPORT_CELLULAR) -> "cellular"
            caps.hasTransport(NetworkCapabilities.TRANSPORT_VPN) -> "vpn"
            else -> "other"
        }
        var v4: String? = null
        var v6: String? = null
        lp?.linkAddresses?.forEach { la ->
            val a = la.address
            if (a is Inet4Address && v4 == null) v4 = a.hostAddress
            if (a is Inet6Address && !a.isLinkLocalAddress && v6 == null) v6 = a.hostAddress?.substringBefore('%')
        }
        val gateway = lp?.routes?.firstOrNull { it.isDefaultRoute && it.gateway is Inet4Address }?.gateway?.hostAddress
        val vpn = cm.allNetworks.any { cm.getNetworkCapabilities(it)?.hasTransport(NetworkCapabilities.TRANSPORT_VPN) == true }
        var ssid: String? = null
        var rssi: Int? = null
        var link: Int? = null
        var band: String? = null
        if (kind == "wifi") {
            val wm = context.applicationContext.getSystemService(Context.WIFI_SERVICE) as WifiManager
            wm.connectionInfo?.let { info ->
                // Needs location permission and Location on; otherwise "<unknown ssid>".
                ssid = info.ssid?.trim('"')?.takeIf { it.isNotBlank() && it != "<unknown ssid>" }
                rssi = info.rssi.takeIf { it > -127 && it < 0 }
                link = info.linkSpeed.takeIf { it > 0 }
                band = when (info.frequency) {
                    in 2400..2500 -> "2.4 GHz"
                    in 4900..5900 -> "5 GHz"
                    in 5925..7125 -> "6 GHz"
                    else -> null
                }
            }
        }
        return NetworkNow(kind, ssid, v4, v6, gateway, lp?.dnsServers?.mapNotNull { it.hostAddress } ?: emptyList(), vpn, rssi, link, band)
    }
}
