package com.alliswell.alliswell

import android.content.Context
import android.content.Intent
import android.graphics.Color
import android.view.View
import android.widget.RemoteViews
import android.widget.RemoteViewsService
import es.antonborri.home_widget.HomeWidgetPlugin
import org.json.JSONObject

/** Backs the widget's scrollable bucketed task list (OPH-133). */
class TasksWidgetService : RemoteViewsService() {
  override fun onGetViewFactory(intent: Intent): RemoteViewsFactory =
    TasksRemoteViewsFactory(applicationContext)
}

private data class Row(
  val section: String?, // bucket label, only on the first row of a bucket
  val title: String,
  val time: String?,
  val done: Boolean,
  val color: String?,
)

class TasksRemoteViewsFactory(
  private val context: Context,
) : RemoteViewsService.RemoteViewsFactory {

  private var rows: List<Row> = emptyList()

  override fun onCreate() {}
  override fun onDataSetChanged() { rows = load() }
  override fun onDestroy() { rows = emptyList() }
  override fun getCount(): Int = rows.size
  override fun getViewTypeCount(): Int = 1
  override fun getItemId(position: Int): Long = position.toLong()
  override fun hasStableIds(): Boolean = false
  override fun getLoadingView(): RemoteViews? = null

  override fun getViewAt(position: Int): RemoteViews {
    val row = rows[position]
    val views = RemoteViews(context.packageName, R.layout.tasks_widget_row)

    if (row.section != null) {
      views.setTextViewText(R.id.aw_section, row.section)
      views.setViewVisibility(R.id.aw_section, View.VISIBLE)
    } else {
      views.setViewVisibility(R.id.aw_section, View.GONE)
    }

    views.setTextViewText(R.id.aw_check, if (row.done) "●" else "○") // ● / ○
    views.setTextViewText(R.id.aw_title, row.title)

    if (!row.time.isNullOrEmpty()) {
      views.setTextViewText(R.id.aw_time, row.time)
      views.setViewVisibility(R.id.aw_time, View.VISIBLE)
    } else {
      views.setViewVisibility(R.id.aw_time, View.GONE)
    }

    val color = parseColor(row.color)
    if (color != null) {
      views.setTextViewText(R.id.aw_dot, "●")
      views.setTextColor(R.id.aw_dot, color)
      views.setViewVisibility(R.id.aw_dot, View.VISIBLE)
    } else {
      views.setViewVisibility(R.id.aw_dot, View.GONE)
    }

    // Fill-in intent → the provider's PendingIntent template opens the app.
    views.setOnClickFillInIntent(R.id.aw_row, Intent())
    return views
  }

  private fun load(): List<Row> {
    val raw = HomeWidgetPlugin.getData(context)
      .getString("aw_widget_snapshot", null) ?: return emptyList()
    return try {
      val buckets = JSONObject(raw).getJSONArray("buckets")
      val out = mutableListOf<Row>()
      for (b in 0 until buckets.length()) {
        val bucket = buckets.getJSONObject(b)
        val label = bucket.optString("label")
        val items = bucket.getJSONArray("items")
        for (i in 0 until items.length()) {
          val task = items.getJSONObject(i)
          out.add(
            Row(
              section = if (i == 0) label else null,
              title = task.optString("title"),
              time = task.optString("time"),
              done = task.optBoolean("done", false),
              color = task.optString("projectColor"),
            ),
          )
        }
        val more = bucket.optInt("more", 0)
        if (more > 0) out.add(Row(null, "+$more", null, false, null))
      }
      out
    } catch (_: Exception) {
      emptyList()
    }
  }

  private fun parseColor(hex: String?): Int? {
    if (hex.isNullOrEmpty()) return null
    return try {
      Color.parseColor(if (hex.startsWith("#")) hex else "#$hex")
    } catch (_: Exception) {
      null
    }
  }
}
