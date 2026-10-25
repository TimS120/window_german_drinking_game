package com.timss.window.window_game

import android.Manifest
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    override fun onDestroy() {
        stopService(Intent(this, RoomHostingService::class.java))
        super.onDestroy()
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "window/hosting")
            .setMethodCallHandler { call, result ->
                try {
                    when (call.method) {
                        "start" -> {
                            if (Build.VERSION.SDK_INT >= 33 && checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) != PackageManager.PERMISSION_GRANTED) {
                                requestPermissions(arrayOf(Manifest.permission.POST_NOTIFICATIONS), 1001)
                            }
                            val intent = Intent(this, RoomHostingService::class.java)
                                .putExtra("roomCode", call.argument<String>("roomCode"))
                            if (Build.VERSION.SDK_INT >= 26) startForegroundService(intent) else startService(intent)
                            result.success(null)
                        }
                        "stop" -> {
                            stopService(Intent(this, RoomHostingService::class.java))
                            result.success(null)
                        }
                        else -> result.notImplemented()
                    }
                } catch (error: Exception) {
                    result.error("hosting_service", error.message, null)
                }
            }
    }
}
