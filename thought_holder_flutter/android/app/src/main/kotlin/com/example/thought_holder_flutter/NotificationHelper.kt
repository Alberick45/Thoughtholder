package com.example.thought_holder_flutter

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.provider.Settings
import androidx.core.app.NotificationCompat

object NotificationHelper {

    const val QUICK_CAPTURE_CHANNEL_ID = "thoughtholder_quick_capture"
    const val QUICK_CAPTURE_NOTIFICATION_ID = 2001

    const val NUDGES_CHANNEL_ID = "thoughtholder_nudges"
    const val START_HERE_NOTIFICATION_ID = 2002
    const val CAPTURE_REMINDER_NOTIFICATION_ID = 2003

    fun initChannels(context: Context) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val manager = context.getSystemService(NotificationManager::class.java) ?: return

            // 1. Quick Capture Channel
            val quickChannel = NotificationChannel(
                QUICK_CAPTURE_CHANNEL_ID,
                "Quick Capture Button",
                NotificationManager.IMPORTANCE_LOW
            ).apply {
                description = "Keeps a Capture button in notifications to quickly open ThoughtHolder"
                setSound(null, null)
                enableVibration(false)
            }
            manager.createNotificationChannel(quickChannel)

            // 2. Start Here Nudges & Reminders Channel
            val nudgesChannel = NotificationChannel(
                NUDGES_CHANNEL_ID,
                "Reminders and Nudges",
                NotificationManager.IMPORTANCE_DEFAULT
            ).apply {
                description = "Start here suggestions and gentle capture reminders"
            }
            manager.createNotificationChannel(nudgesChannel)
        }
    }

    // --- Quick Capture Notification (UPDATE 5 - Section C) ---
    fun showQuickCaptureNotification(context: Context, enabled: Boolean) {
        val manager = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        if (!enabled) {
            manager.cancel(QUICK_CAPTURE_NOTIFICATION_ID)
            return
        }

        initChannels(context)

        val appIntent = Intent(context, MainActivity::class.java).apply {
            action = Intent.ACTION_VIEW
            data = Uri.parse("thoughtholder://capture")
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP
        }
        val pendingIntent = PendingIntent.getActivity(
            context, 10, appIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )

        val notification = NotificationCompat.Builder(context, QUICK_CAPTURE_CHANNEL_ID)
            .setContentTitle("ThoughtHolder")
            .setContentText("Tap to capture a thought")
            .setSmallIcon(android.R.drawable.ic_input_add)
            .setOngoing(true)
            .setPriority(NotificationCompat.PRIORITY_LOW)
            .setContentIntent(pendingIntent)
            .build()

        manager.notify(QUICK_CAPTURE_NOTIFICATION_ID, notification)
    }

    // --- Start Here Nudge Notification (UPDATE 5 - Section D) ---
    fun showStartHereNudge(
        context: Context,
        title: String,
        body: String,
        targetRoute: String = "thoughtholder://starthere",
        showWordsOnLockScreen: Boolean = false
    ) {
        initChannels(context)
        val manager = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager

        val contentIntent = Intent(context, MainActivity::class.java).apply {
            action = Intent.ACTION_VIEW
            data = Uri.parse(targetRoute)
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP
        }
        val contentPending = PendingIntent.getActivity(
            context, 20, contentIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )

        // Actions: Snooze 1 hour & Not now
        val snoozeIntent = Intent(context, MainActivity::class.java).apply {
            action = Intent.ACTION_VIEW
            data = Uri.parse("thoughtholder://snooze_1h")
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP
        }
        val snoozePending = PendingIntent.getActivity(
            context, 21, snoozeIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )

        val notNowIntent = Intent(context, MainActivity::class.java).apply {
            action = Intent.ACTION_VIEW
            data = Uri.parse("thoughtholder://not_now")
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP
        }
        val notNowPending = PendingIntent.getActivity(
            context, 22, notNowIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )

        val builder = NotificationCompat.Builder(context, NUDGES_CHANNEL_ID)
            .setContentTitle(title)
            .setContentText(body)
            .setStyle(NotificationCompat.BigTextStyle().bigText(body))
            .setSmallIcon(android.R.drawable.ic_dialog_info)
            .setAutoCancel(true)
            .setContentIntent(contentPending)
            .addAction(0, "Snooze 1 hour", snoozePending)
            .addAction(0, "Not now", notNowPending)
            .setPriority(NotificationCompat.PRIORITY_DEFAULT)

        // Lock screen privacy (Section D)
        if (!showWordsOnLockScreen) {
            val publicNotification = NotificationCompat.Builder(context, NUDGES_CHANNEL_ID)
                .setContentTitle("ThoughtHolder")
                .setContentText("Your next step is ready")
                .setSmallIcon(android.R.drawable.ic_dialog_info)
                .setContentIntent(contentPending)
                .build()

            builder.setVisibility(NotificationCompat.VISIBILITY_PRIVATE)
            builder.setPublicVersion(publicNotification)
        } else {
            builder.setVisibility(NotificationCompat.VISIBILITY_PUBLIC)
        }

        manager.notify(START_HERE_NOTIFICATION_ID, builder.build())
    }

    // --- Gentle Capture Reminder (UPDATE 5 - Section E) ---
    fun showCaptureReminder(context: Context) {
        initChannels(context)
        val manager = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager

        val contentIntent = Intent(context, MainActivity::class.java).apply {
            action = Intent.ACTION_VIEW
            data = Uri.parse("thoughtholder://capture")
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP
        }
        val contentPending = PendingIntent.getActivity(
            context, 30, contentIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )

        val notification = NotificationCompat.Builder(context, NUDGES_CHANNEL_ID)
            .setContentTitle("ThoughtHolder")
            .setContentText("Got a thought? Tap to capture.")
            .setSmallIcon(android.R.drawable.ic_input_add)
            .setAutoCancel(true)
            .setContentIntent(contentPending)
            .setPriority(NotificationCompat.PRIORITY_DEFAULT)
            .build()

        manager.notify(CAPTURE_REMINDER_NOTIFICATION_ID, notification)
    }

    fun openBatteryOptimizationSettings(context: Context) {
        try {
            val intent = Intent(Settings.ACTION_IGNORE_BATTERY_OPTIMIZATION_SETTINGS).apply {
                flags = Intent.FLAG_ACTIVITY_NEW_TASK
            }
            context.startActivity(intent)
        } catch (_: Exception) {
            try {
                val intent = Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS).apply {
                    data = Uri.parse("package:${context.packageName}")
                    flags = Intent.FLAG_ACTIVITY_NEW_TASK
                }
                context.startActivity(intent)
            } catch (_: Exception) {}
        }
    }
}
