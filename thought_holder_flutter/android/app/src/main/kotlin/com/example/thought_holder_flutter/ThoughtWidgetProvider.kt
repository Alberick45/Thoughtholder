package com.example.thought_holder_flutter

import android.appwidget.AppWidgetManager
import android.content.Context
import android.content.SharedPreferences
import android.net.Uri
import android.widget.RemoteViews
import es.antonborri.home_widget.HomeWidgetLaunchIntent
import es.antonborri.home_widget.HomeWidgetProvider

class ThoughtWidgetProvider : HomeWidgetProvider() {
    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray,
        widgetData: SharedPreferences
    ) {
        appWidgetIds.forEach { id ->
            val views = RemoteViews(context.packageName, R.layout.thought_widget).apply {
                // UPDATE 5: One small widget with a single big "Capture" button and the app name.
                // Tapping opens Capture idle. No recording, no text from user ideas on the widget.
                val pending = HomeWidgetLaunchIntent.getActivity(
                    context, MainActivity::class.java,
                    Uri.parse("thoughtholder://capture")
                )
                setOnClickPendingIntent(R.id.widget_root, pending)
                setOnClickPendingIntent(R.id.widget_capture_btn, pending)
            }
            appWidgetManager.updateAppWidget(id, views)
        }
    }
}
