package com.example.thought_holder_flutter

import android.content.Intent
import android.os.Build
import android.os.Bundle
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {

    private val RECORDING_CHANNEL = "com.thoughtholder.app/background_recording"
    private val NOTIFICATIONS_CHANNEL = "com.thoughtholder.app/notifications"

    private var recordingMethodChannel: MethodChannel? = null
    private var notificationsMethodChannel: MethodChannel? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        NotificationHelper.initChannels(this)
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        recordingMethodChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, RECORDING_CHANNEL)
        recordingMethodChannel?.setMethodCallHandler { call, result ->
            when (call.method) {
                "startRecording" -> {
                    val outputPath = call.argument<String>("outputPath")
                    if (outputPath != null) {
                        val intent = Intent(this, RecordingService::class.java).apply {
                            action = RecordingService.ACTION_START
                            putExtra(RecordingService.EXTRA_OUTPUT_PATH, outputPath)
                        }
                        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                            startForegroundService(intent)
                        } else {
                            startService(intent)
                        }
                        result.success(true)
                    } else {
                        result.error("INVALID_ARGS", "outputPath is required", null)
                    }
                }
                "stopRecording" -> {
                    val intent = Intent(this, RecordingService::class.java).apply {
                        action = RecordingService.ACTION_STOP
                    }
                    startService(intent)
                    result.success(true)
                }
                "pauseRecording" -> {
                    val intent = Intent(this, RecordingService::class.java).apply {
                        action = RecordingService.ACTION_PAUSE
                    }
                    startService(intent)
                    result.success(true)
                }
                "resumeRecording" -> {
                    val intent = Intent(this, RecordingService::class.java).apply {
                        action = RecordingService.ACTION_RESUME
                    }
                    startService(intent)
                    result.success(true)
                }
                "isRecording" -> {
                    result.success(RecordingService.isServiceRunning)
                }
                "openBatteryOptimizationSettings" -> {
                    NotificationHelper.openBatteryOptimizationSettings(this)
                    result.success(true)
                }
                else -> result.notImplemented()
            }
        }

        // Connect RecordingService callbacks back into Flutter
        RecordingService.listener = object : RecordingService.RecordingListener {
            override fun onTick(seconds: Int) {
                runOnUiThread {
                    recordingMethodChannel?.invokeMethod("onTimerTick", seconds)
                }
            }

            override fun onStatus(status: String, reason: String?) {
                runOnUiThread {
                    recordingMethodChannel?.invokeMethod("onStatusChanged", mapOf(
                        "status" to status,
                        "reason" to reason
                    ))
                }
            }

            override fun onFinished(filePath: String) {
                runOnUiThread {
                    recordingMethodChannel?.invokeMethod("onRecordingStopped", filePath)
                }
            }
        }

        // Notification Channel Handler
        notificationsMethodChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, NOTIFICATIONS_CHANNEL)
        notificationsMethodChannel?.setMethodCallHandler { call, result ->
            when (call.method) {
                "setQuickCapture" -> {
                    val enabled = call.argument<Boolean>("enabled") ?: false
                    NotificationHelper.showQuickCaptureNotification(this, enabled)
                    result.success(true)
                }
                "showStartHereNudge" -> {
                    val title = call.argument<String>("title") ?: "Start here"
                    val body = call.argument<String>("body") ?: "Your next step is ready"
                    val targetRoute = call.argument<String>("targetRoute") ?: "thoughtholder://starthere"
                    val showWordsOnLockScreen = call.argument<Boolean>("showWordsOnLockScreen") ?: false
                    NotificationHelper.showStartHereNudge(this, title, body, targetRoute, showWordsOnLockScreen)
                    result.success(true)
                }
                "showCaptureReminder" -> {
                    NotificationHelper.showCaptureReminder(this)
                    result.success(true)
                }
                else -> result.notImplemented()
            }
        }

        // Handle initial intent if app was opened via notification or widget link
        handleIntent(intent)
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        handleIntent(intent)
    }

    private fun handleIntent(intent: Intent?) {
        val uri = intent?.data ?: return
        val route = uri.toString()
        runOnUiThread {
            notificationsMethodChannel?.invokeMethod("onNotificationTapped", route)
        }
    }
}
