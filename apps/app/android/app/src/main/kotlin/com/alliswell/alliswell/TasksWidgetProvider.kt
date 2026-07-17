package com.alliswell.alliswell

import android.appwidget.AppWidgetManager
import android.content.Context
import android.content.Intent
import android.content.SharedPreferences
import android.net.Uri
import android.view.View
import android.widget.RemoteViews
import es.antonborri.home_widget.HomeWidgetLaunchIntent
import es.antonborri.home_widget.HomeWidgetProvider
import org.json.JSONObject

/**
 * Android home-screen widget (Epic 12, OPH-133). Renders the JSON snapshot the
 * Flutter app writes to the home_widget SharedPreferences (see
 * apps/app/lib/src/features/widgets/). The widget does NO i18n and NO DB access —
 * it draws this pre-localized snapshot. Scrollable bucketed task list via a
 * RemoteViews collection (TasksWidgetService).
 *
 * Snapshot key must match widget_host.dart (`aw_widget_snapshot`).
 */
class TasksWidgetProvider : HomeWidgetProvider() {

  override fun onUpdate(
    context: Context,
    appWidgetManager: AppWidgetManager,
    appWidgetIds: IntArray,
    widgetData: SharedPreferences,
  ) {
    for (widgetId in appWidgetIds) {
      val views = RemoteViews(context.packageName, R.layout.tasks_widget)

      // Date header (from the snapshot).
      val raw = widgetData.getString("aw_widget_snapshot", null)
      if (raw != null) {
        try {
          val snap = JSONObject(raw)
          val date = snap.getJSONObject("date")
          views.setTextViewText(R.id.aw_day, date.optString("day"))
          views.setTextViewText(R.id.aw_weekday, date.optString("weekday"))
          views.setTextViewText(R.id.aw_month, date.optString("month"))
          views.setViewVisibility(R.id.aw_header, View.VISIBLE)
          // Localized empty state (shown by setEmptyView when the list is empty).
          val empty = snap.optJSONObject("strings")?.optString("allCaughtUp")
          if (!empty.isNullOrEmpty()) views.setTextViewText(R.id.aw_empty, empty)
        } catch (_: Exception) {
          views.setViewVisibility(R.id.aw_header, View.GONE)
        }
      } else {
        views.setViewVisibility(R.id.aw_header, View.GONE)
      }

      // Scrollable bucketed list, backed by the collection service.
      val serviceIntent = Intent(context, TasksWidgetService::class.java).apply {
        putExtra(AppWidgetManager.EXTRA_APPWIDGET_ID, widgetId)
        data = Uri.parse(toUri(Intent.URI_INTENT_SCHEME)) // unique per widget id
      }
      views.setRemoteAdapter(R.id.aw_list, serviceIntent)
      views.setEmptyView(R.id.aw_list, R.id.aw_empty)

      // Tapping the widget (or a row) opens the app (deep-link floor; row-level
      // routing lands with interactivity in OPH-132/135).
      val open = HomeWidgetLaunchIntent.getActivity(
        context,
        MainActivity::class.java,
        Uri.parse("alliswell://open"),
      )
      views.setOnClickPendingIntent(R.id.aw_header, open)
      views.setPendingIntentTemplate(R.id.aw_list, open)

      appWidgetManager.updateAppWidget(widgetId, views)
      appWidgetManager.notifyAppWidgetViewDataChanged(widgetId, R.id.aw_list)
    }
  }
}
