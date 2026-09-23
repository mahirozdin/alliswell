package com.alliswell.alliswell

import android.content.Context
import android.graphics.Color
import org.json.JSONObject

/**
 * OPH-336 — which list one placed widget shows, and the part of the snapshot
 * that list is.
 *
 * The app writes every list a widget can be set to into the snapshot (`lists`)
 * and computes each project's rows, count and next task itself (`views`) — the
 * filter is Dart's (`filterTasksForWidgetList`, W9). Native code only PICKS an
 * id, remembers it per widget, and draws the matching part.
 */

/** Snapshot key — `kWidgetSnapshotKey` in widget_host.dart. */
const val KEY_SNAPSHOT = "aw_widget_snapshot"

/** The whole list's id — `kWidgetListAll` in widget_grouping.dart. */
const val WIDGET_LIST_ALL = "all"

/** One entry of the configure screen — `WidgetListChoice` in Dart. */
data class WidgetListChoice(val id: String, val name: String, val color: String?)

/** The list each placed widget is set to. Nothing but the id is stored. */
object TasksWidgetConfig {
  private const val PREFS = "aw_widget_config"

  private fun key(widgetId: Int) = "list_$widgetId"

  /** Never chosen means the whole list — what every widget showed before. */
  fun listFor(context: Context, widgetId: Int): String =
    context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
      .getString(key(widgetId), WIDGET_LIST_ALL) ?: WIDGET_LIST_ALL

  fun setList(context: Context, widgetId: Int, listId: String) {
    context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
      .edit().putString(key(widgetId), listId).apply()
  }

  /** A removed widget's choice goes with it. */
  fun forget(context: Context, widgetIds: IntArray) {
    val editor = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE).edit()
    for (widgetId in widgetIds) editor.remove(key(widgetId))
    editor.apply()
  }
}

/**
 * The lists the app offered in its last snapshot, in its order. Before the app
 * has written a v4 snapshot there is one: the whole list, under the only name
 * native code may carry — a fallback, as the layout's "All caught up" is.
 */
fun widgetListChoices(snapshot: JSONObject?): List<WidgetListChoice> {
  val out = mutableListOf<WidgetListChoice>()
  val lists = snapshot?.optJSONArray("lists")
  if (lists != null) {
    for (i in 0 until lists.length()) {
      val item = lists.optJSONObject(i) ?: continue
      val id = item.optString("id")
      if (id.isEmpty()) continue
      out.add(WidgetListChoice(id, item.optString("name"), item.optString("color").ifEmpty { null }))
    }
  }
  if (out.isEmpty()) out.add(WidgetListChoice(WIDGET_LIST_ALL, "All tasks", null))
  return out
}

/**
 * The part of the snapshot a widget set to [listId] draws: a project's `views`
 * entry, or the top level for the whole list. An id the snapshot no longer
 * carries — a project deleted or archived since the widget was set up — draws
 * the whole list: an empty "all caught up" for a list that no longer exists
 * would be a lie about the person's day. (An EMPTY project still has a view,
 * so it does say "all caught up".)
 */
fun selectWidgetView(snapshot: JSONObject, listId: String): JSONObject {
  if (listId == WIDGET_LIST_ALL) return snapshot
  return snapshot.optJSONObject("views")?.optJSONObject(listId) ?: snapshot
}

/** The project a widget is set to, for its title line — null for the whole list. */
fun selectedWidgetList(snapshot: JSONObject, listId: String): WidgetListChoice? {
  if (listId == WIDGET_LIST_ALL) return null
  if (snapshot.optJSONObject("views")?.has(listId) != true) return null
  return widgetListChoices(snapshot).firstOrNull { it.id == listId }
}

/** `#RRGGBB` (or `RRGGBB`) to a color int; null when absent or malformed. */
fun parseWidgetColor(hex: String?): Int? {
  if (hex.isNullOrEmpty()) return null
  return try {
    Color.parseColor(if (hex.startsWith("#")) hex else "#$hex")
  } catch (_: Exception) {
    null
  }
}
