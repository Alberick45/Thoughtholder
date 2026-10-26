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
                val pending = HomeWidgetLaunchIntent.getActivity(
                    context, MainActivity::class.java,
                    Uri.parse("thoughtholder://record")
                )
                setOnClickPendingIntent(R.id.widget_root, pending)
                setTextViewText(
                    R.id.widget_text,
                    widgetData.getString("last_thought", "Tap to record a thought")
                )
            }
            appWidgetManager.updateAppWidget(id, views)
        }
    }
}
