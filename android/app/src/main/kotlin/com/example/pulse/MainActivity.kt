package com.example.pulse

import android.os.Bundle
import androidx.activity.enableEdgeToEdge
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine

/**
 * A FlutterFragmentActivity (a ComponentActivity) so it can call
 * enableEdgeToEdge(): Flutter already draws behind the system bars, and this
 * makes Android 15+ (target SDK 35) and Play's edge-to-edge check agree,
 * with transparent bars on older versions too.
 */
open class MainActivity : FlutterFragmentActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        enableEdgeToEdge()
        super.onCreate(savedInstanceState)
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        flutterEngine.plugins.add(NetworkInfoPlugin())
        flutterEngine.plugins.add(com.example.pulse.widgets.WidgetsPlugin())
    }
}
