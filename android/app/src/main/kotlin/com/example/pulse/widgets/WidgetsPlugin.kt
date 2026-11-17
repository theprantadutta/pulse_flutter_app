package com.example.pulse.widgets

import android.content.Context
import androidx.glance.appwidget.updateAll
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.launch

/**
 * `pulse/widgets`: what the Dart side needs beyond home_widget.
 * - `reschedule`: re-arms background refresh after a widget's settings change.
 * - `refreshPings`: pings a widget's hosts now (right after configuring), then redraws.
 */
class WidgetsPlugin : FlutterPlugin, MethodChannel.MethodCallHandler {
    private lateinit var channel: MethodChannel
    private lateinit var context: Context
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Main)

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        context = binding.applicationContext
        channel = MethodChannel(binding.binaryMessenger, "pulse/widgets")
        channel.setMethodCallHandler(this)
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel.setMethodCallHandler(null)
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "reschedule" -> {
                WidgetRefreshWorker.schedule(context)
                result.success(true)
            }
            "refreshPings" -> {
                val hosts = call.argument<List<String>>("hosts") ?: emptyList()
                val count = call.argument<Int>("count") ?: 4
                scope.launch {
                    try {
                        WidgetPinger.refresh(context, hosts, count)
                        PingWidget().updateAll(context)
                        MultiPingWidget().updateAll(context)
                        NetworkWidget().updateAll(context)
                        result.success(true)
                    } catch (e: Exception) {
                        result.error("ping", e.message, null)
                    }
                }
            }
            "gateway" -> result.success(WidgetNetwork.read(context).gateway)
            else -> result.notImplemented()
        }
    }
}
