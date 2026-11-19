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
    private val UPDATER_CHANNEL = "com.thoughtholder.app/updater"

    private var recordingMethodChannel: MethodChannel? = null
    private var notificationsMethodChannel: MethodChannel? = null
    private var updaterMethodChannel: MethodChannel? = null

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

        // Updater Channel Handler
        updaterMethodChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, UPDATER_CHANNEL)
        updaterMethodChannel?.setMethodCallHandler { call, result ->
            when (call.method) {
                "canRequestPackageInstalls" -> {
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                        result.success(packageManager.canRequestPackageInstalls())
                    } else {
                        result.success(true)
                    }
                }
                "getAppVersion" -> {
                    try {
                        val pInfo = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                            packageManager.getPackageInfo(packageName, android.content.pm.PackageManager.PackageInfoFlags.of(0))
                        } else {
                            @Suppress("DEPRECATION")
                            packageManager.getPackageInfo(packageName, 0)
                        }
                        val versionCode = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
                            pInfo.longVersionCode
                        } else {
                            @Suppress("DEPRECATION")
                            pInfo.versionCode.toLong()
                        }
                        result.success(mapOf(
                            "versionName" to (pInfo.versionName ?: "1.3.0"),
                            "versionCode" to versionCode
                        ))
                    } catch (e: Exception) {
                        result.error("VERSION_ERROR", e.localizedMessage, null)
                    }
                }
                "openInstallPermissionSettings" -> {
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                        try {
                            val intent = Intent(android.provider.Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES).apply {
                                data = android.net.Uri.parse("package:$packageName")
                                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                            }
                            startActivity(intent)
                            result.success(true)
                        } catch (e: Exception) {
                            result.error("SETTINGS_ERROR", e.localizedMessage, null)
                        }
                    } else {
                        result.success(true)
                    }
                }
                "installApk" -> {
                    val filePath = call.argument<String>("filePath")
                    if (filePath != null) {
                        val file = java.io.File(filePath)
                        if (file.exists()) {
                            try {
                                val apkUri = androidx.core.content.FileProvider.getUriForFile(
                                    this,
                                    "${applicationContext.packageName}.fileprovider",
                                    file
                                )
                                val installIntent = Intent(Intent.ACTION_VIEW).apply {
                                    setDataAndType(apkUri, "application/vnd.android.package-archive")
                                    addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                                    addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                                }
                                startActivity(installIntent)
                                result.success(true)
                            } catch (e: Exception) {
                                result.error("INSTALL_ERROR", e.localizedMessage, null)
                            }
                        } else {
                            result.error("FILE_NOT_FOUND", "APK file does not exist at $filePath", null)
                        }
                    } else {
                        result.error("INVALID_ARGS", "filePath is required", null)
                    }
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
