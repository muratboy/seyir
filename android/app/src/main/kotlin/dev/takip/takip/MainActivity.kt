package dev.takip.takip

import android.Manifest
import android.content.pm.PackageManager
import android.content.Intent
import android.os.Build
import android.os.Bundle
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private var pendingPermissionResult: MethodChannel.Result? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        if (intent?.data?.scheme == "takip" && intent.action == Intent.ACTION_VIEW) {
            intent.action = "es.antonborri.home_widget.action.LAUNCH"
        }
        super.onCreate(savedInstanceState)
    }

    override fun onNewIntent(intent: Intent) {
        if (intent.data?.scheme == "takip" && intent.action == Intent.ACTION_VIEW) {
            intent.action = "es.antonborri.home_widget.action.LAUNCH"
        }
        super.onNewIntent(intent)
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "dev.takip.takip/permissions")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "hasActivityRecognition" -> result.success(hasActivityRecognition())
                    "requestActivityRecognition" -> requestActivityRecognition(result)
                    else -> result.notImplemented()
                }
            }
    }

    // Adım sensörü Android 10'dan itibaren çalışma zamanı izni ister; pedometer eklentisi bunu sormaz,
    // izin yokken hata da vermez: sensör yalnızca susar.
    private fun hasActivityRecognition(): Boolean =
        Build.VERSION.SDK_INT < Build.VERSION_CODES.Q ||
            checkSelfPermission(Manifest.permission.ACTIVITY_RECOGNITION) == PackageManager.PERMISSION_GRANTED

    private fun requestActivityRecognition(result: MethodChannel.Result) {
        if (hasActivityRecognition()) {
            result.success(true)
            return
        }
        if (pendingPermissionResult != null) {
            result.success(false)
            return
        }
        pendingPermissionResult = result
        requestPermissions(arrayOf(Manifest.permission.ACTIVITY_RECOGNITION), ACTIVITY_RECOGNITION_REQUEST)
    }

    override fun onRequestPermissionsResult(requestCode: Int, permissions: Array<out String>, grantResults: IntArray) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode != ACTIVITY_RECOGNITION_REQUEST) return
        pendingPermissionResult?.success(
            grantResults.isNotEmpty() && grantResults[0] == PackageManager.PERMISSION_GRANTED
        )
        pendingPermissionResult = null
    }

    private companion object {
        const val ACTIVITY_RECOGNITION_REQUEST = 4711
    }
}
