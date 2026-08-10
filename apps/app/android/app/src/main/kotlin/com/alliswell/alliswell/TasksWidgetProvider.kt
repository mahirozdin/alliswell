package com.alliswell.alliswell

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.content.Context
import android.content.Intent
import android.content.SharedPreferences
import android.net.Uri
import android.view.View
import android.widget.RemoteViews
import es.antonborri.home_widget.HomeWidgetBackgroundIntent
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

  companion object {
    const val ACTION_ROW = "com.alliswell.alliswell.WIDGET_ROW"
  }

  /// A row tap. "open" launches the app at that task; "complete" runs the Dart
  /// callback in the background — the SAME `TaskStore.complete` the UI uses, so
  /// the write is an ordinary outbox mutation and syncs like any other
  /// (WIDGETS §4: the widget must not have its own write path).
  override fun onReceive(context: Context, intent: Intent) {
    if (intent.action == ACTION_ROW) {
      val taskId = intent.getStringExtra(EXTRA_TASK_ID).orEmpty()
      if (taskId.isNotEmpty()) {
        when (intent.getStringExtra(EXTRA_ACTION)) {
          "complete" -> {
            HomeWidgetBackgroundIntent.getBroadcast(
              context,
              Uri.parse("alliswell://complete?id=" + taskId),
            ).send()
            return
          }
          else -> {
            context.startActivity(
              Intent(context, MainActivity::class.java)
                .setData(Uri.parse("alliswell://task/" + taskId))
                .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK),
            )
            return
          }
        }
      }
    }
    super.onReceive(context, intent)
  }

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
          // OPH-253 (v3): the header clock's pattern. TextClock ticks on its own
          // — it needs no data from us — but it would otherwise pick 12h vs 24h
          // from the DEVICE, and which clock the user reads is a product rule
          // the app already settled for the rows below (OPH-174, W9). Setting
          // BOTH slots to the same resolved pattern is what makes the device
          // toggle unable to overrule the app's answer. A v2 snapshot has no
          // pattern and keeps the layout's device-driven defaults.
          val clockFormat = snap.optString("clockFormat")
          if (clockFormat.isNotEmpty()) {
            views.setCharSequence(R.id.aw_clock, "setFormat12Hour", clockFormat)
            views.setCharSequence(R.id.aw_clock, "setFormat24Hour", clockFormat)
          }
          // OPH-187 #4B: today's open count. `optInt` returns 0 for a v1
          // snapshot that has no such field — which is also the "hide it"
          // value, so an older app degrades to exactly the old header.
          val openToday = snap.optInt("openToday", 0)
          val openLabel = snap.optJSONObject("strings")?.optString("openToday")
          if (openToday > 0) {
            views.setTextViewText(
              R.id.aw_open_today,
              if (openLabel.isNullOrEmpty()) openToday.toString() else openLabel,
            )
            views.setViewVisibility(R.id.aw_open_today, View.VISIBLE)
          } else {
            views.setViewVisibility(R.id.aw_open_today, View.GONE)
          }
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

      // Tapping the header opens the app at Home (deep-link floor).
      val open = HomeWidgetLaunchIntent.getActivity(
        context,
        MainActivity::class.java,
        Uri.parse("alliswell://open"),
      )
      views.setOnClickPendingIntent(R.id.aw_header, open)
      // OPH-188: rows go through a BROADCAST template so a tap can either open
      // that task or complete it without launching anything. Which one is
      // decided by the fill-in extras the factory attaches per row.
      views.setPendingIntentTemplate(
        R.id.aw_list,
        PendingIntent.getBroadcast(
          context,
          0,
          Intent(context, TasksWidgetProvider::class.java).setAction(ACTION_ROW),
          PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_MUTABLE,
        ),
      )

      appWidgetManager.updateAppWidget(widgetId, views)
      appWidgetManager.notifyAppWidgetViewDataChanged(widgetId, R.id.aw_list)
    }
  }
}
