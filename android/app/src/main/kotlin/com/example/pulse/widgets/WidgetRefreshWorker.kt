package com.example.pulse.widgets

import android.appwidget.AppWidgetManager
import android.content.ComponentName
import android.content.Context
import androidx.glance.appwidget.updateAll
import androidx.work.Constraints
import androidx.work.CoroutineWorker
import androidx.work.ExistingPeriodicWorkPolicy
import androidx.work.NetworkType
import androidx.work.PeriodicWorkRequestBuilder
import androidx.work.WorkManager
import androidx.work.WorkerParameters
import java.util.concurrent.TimeUnit

/**
 * Background refresh for the ping-based widgets (Ping, Multi-host ping,
 * Network). Runs at the shortest interval any placed widget asked for
 * (WorkManager's floor is 15 minutes) and only pings widgets whose own
 * interval has passed. Widgets set to "Only when tapped" are skipped.
 */
class WidgetRefreshWorker(context: Context, params: WorkerParameters) : CoroutineWorker(context, params) {
    override suspend fun doWork(): Result {
        val ctx = applicationContext
        val store = WidgetStore(ctx)
        val now = System.currentTimeMillis()
        val due = HashMap<String, Int>()
        for ((id, widget) in pingWidgets(ctx)) {
            val config = store.config(id)
            if (config.intervalMin <= 0) continue
            for (t in hostsFor(ctx, id, widget)) {
                val last = store.ping(t.host)?.at ?: 0L
                // 2 minutes of slack: WorkManager runs periodic work a little early or late.
                if (now - last >= (config.intervalMin - 2) * 60_000L) due[t.host] = maxOf(due[t.host] ?: 0, config.probes)
            }
        }
        if (due.isEmpty()) return Result.success()
        val byCount = due.entries.groupBy({ it.value }, { it.key })
        byCount.forEach { (count, hosts) -> WidgetPinger.refresh(ctx, hosts, count) }
        PingWidget().updateAll(ctx)
        MultiPingWidget().updateAll(ctx)
        NetworkWidget().updateAll(ctx)
        return Result.success()
    }

    companion object {
        private const val WORK = "pulse-widget-refresh"

        fun pingWidgets(context: Context): List<Pair<Int, PulseWidget>> {
            val am = AppWidgetManager.getInstance(context)
            fun ids(c: Class<*>) = am.getAppWidgetIds(ComponentName(context, c)).toList()
            return ids(PingWidgetReceiver::class.java).map { it to PingWidget() } +
                ids(MultiPingWidgetReceiver::class.java).map { it to MultiPingWidget() } +
                ids(NetworkWidgetReceiver::class.java).map { it to NetworkWidget() }
        }

        /** (Re)arms or cancels the periodic refresh to match the placed widgets. */
        fun schedule(context: Context) {
            val store = WidgetStore(context)
            val intervals = pingWidgets(context).map { store.config(it.first).intervalMin }.filter { it > 0 }
            val wm = WorkManager.getInstance(context)
            if (intervals.isEmpty()) {
                wm.cancelUniqueWork(WORK)
                return
            }
            val minutes = intervals.min().coerceAtLeast(15).toLong()
            val request = PeriodicWorkRequestBuilder<WidgetRefreshWorker>(minutes, TimeUnit.MINUTES)
                .setConstraints(Constraints.Builder().setRequiredNetworkType(NetworkType.CONNECTED).build())
                .addTag("interval-$minutes")
                .build()
            wm.enqueueUniquePeriodicWork(WORK, ExistingPeriodicWorkPolicy.UPDATE, request)
        }
    }
}
