package com.example.pulse.widgets

import android.appwidget.AppWidgetManager
import com.example.pulse.MainActivity

/**
 * Opened by the launcher when a widget is added (and from "Reconfigure" on
 * Android 12+). It is Pulse itself, started on the Flutter configure screen
 * (`/widgets/configure`); that screen saves the choices and calls
 * HomeWidget.finishHomeWidgetConfigure(), which returns RESULT_OK here.
 */
class WidgetConfigActivity : MainActivity() {
    override fun getInitialRoute(): String {
        val id = intent?.getIntExtra(AppWidgetManager.EXTRA_APPWIDGET_ID, AppWidgetManager.INVALID_APPWIDGET_ID)
            ?: AppWidgetManager.INVALID_APPWIDGET_ID
        // Until the person saves, backing out cancels adding the widget.
        setResult(RESULT_CANCELED)
        if (id == AppWidgetManager.INVALID_APPWIDGET_ID) return "/"
        return "/widgets/configure?id=$id&kind=${kindOf(id)}"
    }

    private fun kindOf(id: Int): String {
        val name = AppWidgetManager.getInstance(this).getAppWidgetInfo(id)?.provider?.className ?: return "ping"
        return when (name) {
            PingWidgetReceiver::class.java.name -> "ping"
            MultiPingWidgetReceiver::class.java.name -> "multiping"
            SpeedWidgetReceiver::class.java.name -> "speed"
            MonitorWidgetReceiver::class.java.name -> "monitor"
            ActionsWidgetReceiver::class.java.name -> "actions"
            NetworkWidgetReceiver::class.java.name -> "network"
            else -> "ping"
        }
    }
}
