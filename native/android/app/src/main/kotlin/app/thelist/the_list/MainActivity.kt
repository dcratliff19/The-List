package app.thelist.the_list

import android.content.Intent
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private var capture: MethodChannel? = null

    override fun configureFlutterEngine(engine: FlutterEngine) {
        super.configureFlutterEngine(engine)
        capture = MethodChannel(engine.dartExecutor.binaryMessenger, "thelist/capture")
        capture?.setMethodCallHandler { call, result ->
            if (call.method == "getInitialText") {
                result.success(sharedText(intent))
                // Consume the launch share once, including after engine recreation.
                intent?.removeExtra(Intent.EXTRA_TEXT)
            } else {
                result.notImplemented()
            }
        }
    }

    private fun sharedText(value: Intent?): String? =
        if (value?.action == Intent.ACTION_SEND && value.type == "text/plain") {
            value.getStringExtra(Intent.EXTRA_TEXT)?.take(32000)
        } else {
            null
        }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        sharedText(intent)?.let { capture?.invokeMethod("capture", it) }
        intent.removeExtra(Intent.EXTRA_TEXT)
    }
}
