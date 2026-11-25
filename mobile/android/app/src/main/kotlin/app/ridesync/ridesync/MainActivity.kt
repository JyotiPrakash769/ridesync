package app.ridesync.ridesync

import android.content.Context
import android.os.BatteryManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        // Battery % for leader assist (riders' low-battery warnings).
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "ridesync/battery")
            .setMethodCallHandler { call, result ->
                if (call.method == "level") {
                    val bm = getSystemService(Context.BATTERY_SERVICE) as BatteryManager
                    val level = bm.getIntProperty(BatteryManager.BATTERY_PROPERTY_CAPACITY)
                    if (level in 0..100) result.success(level) else result.success(null)
                } else {
                    result.notImplemented()
                }
            }
    }
}
