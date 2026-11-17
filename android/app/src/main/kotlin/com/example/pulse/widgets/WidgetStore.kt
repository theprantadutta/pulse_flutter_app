package com.example.pulse.widgets

import android.content.Context
import android.content.SharedPreferences
import org.json.JSONArray
import org.json.JSONObject
import kotlin.math.abs
import kotlin.math.sqrt

/**
 * The data the home screen widgets show, shared with the Flutter app through
 * home_widget's preferences file (`HomeWidget.saveWidgetData` in Dart writes
 * the same keys; see lib/services/widgets/home_widgets.dart).
 *
 * Every value is a JSON string so Dart, Kotlin and Swift agree on one shape.
 */
object WidgetKeys {
    const val PREFS = "HomeWidgetPreferences"
    const val THEME = "w.theme"
    const val TARGETS = "w.targets"
    const val SPEED = "w.speed"
    const val MONITOR = "w.monitor"
    const val PUBLIC = "w.net.public"
    const val GATEWAY = "w.gateway"
    fun ping(host: String) = "w.ping.${host.lowercase()}"
    fun config(widgetId: Int) = "w.cfg.$widgetId"
    fun busy(widgetId: Int) = "w.busy.$widgetId"
}

/** The router: resolved to the current default gateway when pinged. */
const val GATEWAY_HOST = "gateway"

data class Target(val host: String, val name: String? = null) {
    val title: String get() = name?.takeIf { it.isNotBlank() } ?: if (host == GATEWAY_HOST) "Router" else host

    fun toJson() = JSONObject().put("host", host).put("name", name ?: JSONObject.NULL)

    companion object {
        fun from(o: JSONObject) = Target(o.optString("host"), o.optString("name").takeIf { it.isNotBlank() && it != "null" })
    }
}

/** What the person picked for one widget instance (the Flutter configure screen writes it). */
data class WidgetConfig(
    val targets: List<Target>,
    /** Background refresh, minutes. 0 = only when tapped. */
    val intervalMin: Int,
    val tools: List<String>,
    val showPublicIp: Boolean,
    val showLocalIp: Boolean,
    /** "app" (Pulse colours) or "wallpaper" (Material You). */
    val colors: String,
    /** "solid", "translucent" or "clear". */
    val background: String,
    val probes: Int,
    val showChart: Boolean,
) {
    companion object {
        val defaultTools = listOf("ping", "speed", "trace", "lan", "geo", "ports", "loss", "monitor")

        fun parse(json: String?): WidgetConfig {
            val o = json?.let { runCatching { JSONObject(it) }.getOrNull() } ?: JSONObject()
            val targets = o.optJSONArray("targets")?.let { a -> (0 until a.length()).map { Target.from(a.getJSONObject(it)) } }
                ?.filter { it.host.isNotBlank() }
            val tools = o.optJSONArray("tools")?.let { a -> (0 until a.length()).map { a.getString(it) } }
            return WidgetConfig(
                targets = targets ?: emptyList(),
                intervalMin = o.optInt("interval", 30),
                tools = tools?.takeIf { it.isNotEmpty() } ?: defaultTools,
                showPublicIp = o.optBoolean("publicIp", false),
                showLocalIp = o.optBoolean("localIp", true),
                colors = o.optString("colors", ""),
                background = o.optString("background", "solid"),
                probes = o.optInt("probes", 4).coerceIn(1, 10),
                showChart = o.optBoolean("chart", true),
            )
        }
    }
}

/** Recent replies to one host. Lost replies are stored as -1. */
data class PingSnapshot(val host: String, val at: Long, val samples: List<Double>, val error: String? = null) {
    val replies get() = samples.filter { it >= 0 }
    val last: Double? get() = samples.lastOrNull()?.takeIf { it >= 0 }
    val lastLost get() = samples.isNotEmpty() && samples.last() < 0
    val avg: Double? get() = replies.takeIf { it.isNotEmpty() }?.average()
    val min: Double? get() = replies.minOrNull()
    val max: Double? get() = replies.maxOrNull()
    val lossPct: Double? get() = if (samples.isEmpty()) null else samples.count { it < 0 } * 100.0 / samples.size
    val jitter: Double?
        get() {
            val r = replies
            if (r.size < 2) return null
            return r.zipWithNext { a, b -> abs(b - a) }.average()
        }
    val stdDev: Double?
        get() {
            val r = replies
            if (r.size < 2) return null
            val m = r.average()
            return sqrt(r.sumOf { (it - m) * (it - m) } / r.size)
        }

    fun toJson(): String = JSONObject()
        .put("host", host).put("at", at).put("error", error ?: JSONObject.NULL)
        .put("samples", JSONArray(samples.map { if (it < 0) -1 else Math.round(it * 10) / 10.0 }))
        .toString()

    companion object {
        const val KEEP = 30

        fun parse(json: String?): PingSnapshot? {
            val o = json?.let { runCatching { JSONObject(it) }.getOrNull() } ?: return null
            val a = o.optJSONArray("samples") ?: JSONArray()
            return PingSnapshot(
                host = o.optString("host"),
                at = o.optLong("at"),
                samples = (0 until a.length()).map { a.optDouble(it, -1.0) },
                error = o.optString("error").takeIf { it.isNotBlank() && it != "null" },
            )
        }
    }
}

data class SpeedRun(val at: Long, val down: Double?, val up: Double?, val ping: Double?)

data class SpeedSnapshot(
    val at: Long,
    val down: Double?,
    val up: Double?,
    val ping: Double?,
    val jitter: Double?,
    val server: String,
    val history: List<SpeedRun>,
) {
    companion object {
        fun parse(json: String?): SpeedSnapshot? {
            val o = json?.let { runCatching { JSONObject(it) }.getOrNull() } ?: return null
            val h = o.optJSONArray("history") ?: JSONArray()
            return SpeedSnapshot(
                at = o.optLong("at"),
                down = o.optNum("down"),
                up = o.optNum("up"),
                ping = o.optNum("ping"),
                jitter = o.optNum("jitter"),
                server = o.optString("server"),
                history = (0 until h.length()).map {
                    val r = h.getJSONObject(it)
                    SpeedRun(r.optLong("at"), r.optNum("down"), r.optNum("up"), r.optNum("ping"))
                },
            )
        }
    }
}

data class MonitorTarget(
    val name: String,
    val host: String,
    val down: Boolean,
    val ms: Double?,
    val uptime: Double?,
    val incident: Boolean,
    /** One char per hour slot, oldest first: 0 empty, 1 healthy, 2 degraded, 3 down. */
    val blocks: String,
)

data class MonitorSnapshot(
    val at: Long,
    val live: Boolean,
    val uptime: Double?,
    val incidents: Int,
    val targets: List<MonitorTarget>,
) {
    val down get() = targets.count { it.down }
    val healthy get() = targets.count { !it.down && !it.incident }

    companion object {
        fun parse(json: String?): MonitorSnapshot? {
            val o = json?.let { runCatching { JSONObject(it) }.getOrNull() } ?: return null
            val a = o.optJSONArray("targets") ?: JSONArray()
            return MonitorSnapshot(
                at = o.optLong("at"),
                live = o.optBoolean("live"),
                uptime = o.optNum("uptime"),
                incidents = o.optInt("incidents"),
                targets = (0 until a.length()).map {
                    val t = a.getJSONObject(it)
                    MonitorTarget(
                        name = t.optString("name"),
                        host = t.optString("host"),
                        down = t.optBoolean("down"),
                        ms = t.optNum("ms"),
                        uptime = t.optNum("uptime"),
                        incident = t.optBoolean("incident"),
                        blocks = t.optString("blocks"),
                    )
                },
            )
        }
    }
}

data class PublicIp(val ip: String?, val isp: String?, val city: String?, val country: String?)

data class ThemePrefs(val accent: String, val dynamic: Boolean, val mode: String)

fun JSONObject.optNum(key: String): Double? = if (isNull(key) || !has(key)) null else optDouble(key).takeIf { !it.isNaN() }

class WidgetStore(context: Context) {
    val prefs: SharedPreferences = context.getSharedPreferences(WidgetKeys.PREFS, Context.MODE_PRIVATE)

    fun config(widgetId: Int) = WidgetConfig.parse(prefs.getString(WidgetKeys.config(widgetId), null))

    fun hasConfig(widgetId: Int) = prefs.contains(WidgetKeys.config(widgetId))

    fun removeConfig(widgetId: Int) = prefs.edit().remove(WidgetKeys.config(widgetId)).remove(WidgetKeys.busy(widgetId)).apply()

    fun ping(host: String) = PingSnapshot.parse(prefs.getString(WidgetKeys.ping(host), null))

    /** Appends a fresh round of replies, keeping the last [PingSnapshot.KEEP]. */
    fun addPings(host: String, fresh: List<Double>, error: String?) {
        val old = ping(host)?.samples ?: emptyList()
        val merged = (old + fresh).takeLast(PingSnapshot.KEEP)
        prefs.edit().putString(WidgetKeys.ping(host), PingSnapshot(host, System.currentTimeMillis(), merged, error).toJson()).apply()
    }

    fun speed() = SpeedSnapshot.parse(prefs.getString(WidgetKeys.SPEED, null))

    fun monitor() = MonitorSnapshot.parse(prefs.getString(WidgetKeys.MONITOR, null))

    fun publicIp(): PublicIp? {
        val o = prefs.getString(WidgetKeys.PUBLIC, null)?.let { runCatching { JSONObject(it) }.getOrNull() } ?: return null
        fun s(k: String) = o.optString(k).takeIf { it.isNotBlank() && it != "null" }
        return PublicIp(s("ip"), s("isp"), s("city"), s("country"))
    }

    fun gateway(): String? = prefs.getString(WidgetKeys.GATEWAY, null)?.takeIf { it.isNotBlank() }

    fun targets(): List<Target> {
        val a = prefs.getString(WidgetKeys.TARGETS, null)?.let { runCatching { JSONArray(it) }.getOrNull() } ?: return emptyList()
        return (0 until a.length()).map { Target.from(a.getJSONObject(it)) }
    }

    fun theme(): ThemePrefs {
        val o = prefs.getString(WidgetKeys.THEME, null)?.let { runCatching { JSONObject(it) }.getOrNull() } ?: JSONObject()
        return ThemePrefs(o.optString("accent", "PINK"), o.optBoolean("dynamic", false), o.optString("mode", "system"))
    }

    fun isBusy(widgetId: Int) = prefs.getLong(WidgetKeys.busy(widgetId), 0L) > System.currentTimeMillis() - 30_000

    fun setBusy(widgetId: Int, busy: Boolean) {
        prefs.edit().apply { if (busy) putLong(WidgetKeys.busy(widgetId), System.currentTimeMillis()) else remove(WidgetKeys.busy(widgetId)) }.apply()
    }
}
