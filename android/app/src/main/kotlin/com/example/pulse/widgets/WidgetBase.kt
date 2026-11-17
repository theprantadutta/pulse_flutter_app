package com.example.pulse.widgets

import android.appwidget.AppWidgetManager
import android.content.Context
import androidx.compose.runtime.Composable
import androidx.compose.ui.unit.DpSize
import androidx.compose.ui.unit.dp
import androidx.glance.GlanceId
import androidx.glance.appwidget.GlanceAppWidget
import androidx.glance.appwidget.GlanceAppWidgetManager
import androidx.glance.appwidget.SizeMode
import androidx.glance.appwidget.action.ActionCallback
import androidx.glance.appwidget.provideContent
import androidx.glance.action.ActionParameters
import androidx.glance.currentState
import es.antonborri.home_widget.HomeWidgetGlanceState
import es.antonborri.home_widget.HomeWidgetGlanceStateDefinition
import es.antonborri.home_widget.HomeWidgetGlanceWidgetReceiver

/** What every widget gets to draw with. */
class WidgetEnv(
    val context: Context,
    val widgetId: Int,
    val config: WidgetConfig,
    val palette: Palette,
    val store: WidgetStore,
    val busy: Boolean,
)

/**
 * Base for Pulse's widgets: reads the instance's configuration and colours,
 * then draws [Content] at the closest responsive size.
 */
abstract class PulseWidget : GlanceAppWidget() {
    override val stateDefinition = HomeWidgetGlanceStateDefinition()

    override val sizeMode: SizeMode = SizeMode.Responsive(
        setOf(
            DpSize(60.dp, 60.dp), DpSize(120.dp, 60.dp), DpSize(200.dp, 60.dp), DpSize(280.dp, 60.dp),
            DpSize(60.dp, 120.dp), DpSize(120.dp, 120.dp), DpSize(200.dp, 120.dp), DpSize(280.dp, 120.dp),
            DpSize(120.dp, 190.dp), DpSize(200.dp, 190.dp), DpSize(280.dp, 190.dp),
            DpSize(200.dp, 270.dp), DpSize(280.dp, 270.dp), DpSize(280.dp, 360.dp),
        ),
    )

    override suspend fun provideGlance(context: Context, id: GlanceId) {
        val widgetId = runCatching { GlanceAppWidgetManager(context).getAppWidgetId(id) }.getOrDefault(AppWidgetManager.INVALID_APPWIDGET_ID)
        provideContent {
            // Reading the Glance state makes each update() recompose with fresh data
            // (home_widget emits a new state object per update).
            val state = currentState<HomeWidgetGlanceState>()
            val store = WidgetStore(context, state.preferences)
            val config = store.config(widgetId)
            val env = WidgetEnv(context, widgetId, config, WidgetTheme.palette(context, config), store, store.isBusy(widgetId))
            Content(env)
        }
    }

    @Composable
    abstract fun Content(env: WidgetEnv)
}

/** Receivers clean up an instance's settings when it is removed from the home screen. */
abstract class PulseWidgetReceiver<T : PulseWidget> : HomeWidgetGlanceWidgetReceiver<T>() {
    override fun onDeleted(context: Context, appWidgetIds: IntArray) {
        super.onDeleted(context, appWidgetIds)
        val store = WidgetStore(context)
        appWidgetIds.forEach { store.removeConfig(it) }
        WidgetRefreshWorker.schedule(context)
    }

    override fun onEnabled(context: Context) {
        super.onEnabled(context)
        WidgetRefreshWorker.schedule(context)
    }
}

val actionWidgetId = ActionParameters.Key<Int>("widgetId")

/** Pings the hosts of the tapped widget in the background, then redraws it. */
class RefreshPingAction : ActionCallback {
    override suspend fun onAction(context: Context, glanceId: GlanceId, parameters: ActionParameters) {
        val manager = GlanceAppWidgetManager(context)
        val widgetId = manager.getAppWidgetId(glanceId)
        val store = WidgetStore(context)
        val widget = widgetFor(context, widgetId) ?: return
        val hosts = hostsFor(context, widgetId, widget)
        store.setBusy(widgetId, true)
        widget.update(context, glanceId)
        try {
            WidgetPinger.refresh(context, hosts.map { it.host }, store.config(widgetId).probes)
        } finally {
            store.setBusy(widgetId, false)
            widget.update(context, glanceId)
        }
    }
}

/** Redraws a widget whose data is read live (Network). */
class RedrawAction : ActionCallback {
    override suspend fun onAction(context: Context, glanceId: GlanceId, parameters: ActionParameters) {
        val widgetId = GlanceAppWidgetManager(context).getAppWidgetId(glanceId)
        widgetFor(context, widgetId)?.update(context, glanceId)
    }
}

fun widgetFor(context: Context, widgetId: Int): PulseWidget? {
    val info = AppWidgetManager.getInstance(context).getAppWidgetInfo(widgetId) ?: return null
    return when (info.provider.className) {
        PingWidgetReceiver::class.java.name -> PingWidget()
        MultiPingWidgetReceiver::class.java.name -> MultiPingWidget()
        NetworkWidgetReceiver::class.java.name -> NetworkWidget()
        SpeedWidgetReceiver::class.java.name -> SpeedWidget()
        MonitorWidgetReceiver::class.java.name -> MonitorWidget()
        ActionsWidgetReceiver::class.java.name -> ActionsWidget()
        else -> null
    }
}

val defaultPingTarget = Target("1.1.1.1", "Cloudflare")

val defaultBoard = listOf(Target(GATEWAY_HOST, "Router"), Target("1.1.1.1", "Cloudflare"), Target("8.8.8.8", "Google"), Target("9.9.9.9", "Quad9"))

/** The hosts a ping widget shows: its own choice, else sensible defaults. */
fun hostsFor(context: Context, widgetId: Int, widget: PulseWidget): List<Target> {
    val config = WidgetStore(context).config(widgetId)
    return when (widget) {
        is PingWidget -> listOf(config.targets.firstOrNull() ?: defaultPingTarget)
        is MultiPingWidget -> config.targets.takeIf { it.isNotEmpty() }?.take(6) ?: defaultBoard
        is NetworkWidget -> listOf(Target(GATEWAY_HOST, "Router"))
        else -> emptyList()
    }
}
