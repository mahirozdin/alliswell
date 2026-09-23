package com.alliswell.alliswell

import android.app.Activity
import android.appwidget.AppWidgetManager
import android.content.ComponentName
import android.content.Intent
import android.os.Bundle
import android.view.LayoutInflater
import android.view.View
import android.view.ViewGroup
import android.widget.BaseAdapter
import android.widget.CheckedTextView
import android.widget.ListView
import android.widget.TextView
import es.antonborri.home_widget.HomeWidgetPlugin
import org.json.JSONObject

/**
 * OPH-336 — which list one placed widget shows: the whole list, or one project.
 *
 * It offers what the app wrote into the snapshot's `lists` — names already in
 * the app's language (W9: native code carries no translations) — and stores
 * nothing but the chosen id (TasksWidgetConfig). Which tasks belong to that id
 * was decided in Dart; the widget draws the matching `views` entry.
 *
 * The launcher starts it. On Android 12+ that is the widget's "reconfigure",
 * and a new widget is placed set to the whole list without asking
 * (`configuration_optional`). Before 12 it opens as the widget is placed, and
 * backing out cancels the placement — the platform's contract, kept by the
 * RESULT_CANCELED set first thing below.
 */
class TasksWidgetConfigureActivity : Activity() {

  override fun onCreate(savedInstanceState: Bundle?) {
    super.onCreate(savedInstanceState)
    setResult(RESULT_CANCELED)

    val widgetId = intent?.extras?.getInt(
      AppWidgetManager.EXTRA_APPWIDGET_ID,
      AppWidgetManager.INVALID_APPWIDGET_ID,
    ) ?: AppWidgetManager.INVALID_APPWIDGET_ID
    // Exported because the launcher has to start it, so anyone can: only this
    // app's own widgets are configured here.
    val ours = ComponentName(this, TasksWidgetProvider::class.java)
    val info = AppWidgetManager.getInstance(this).getAppWidgetInfo(widgetId)
    if (widgetId == AppWidgetManager.INVALID_APPWIDGET_ID || info?.provider != ours) {
      finish()
      return
    }

    val snapshot = HomeWidgetPlugin.getData(this).getString(KEY_SNAPSHOT, null)
      ?.let { raw -> runCatching { JSONObject(raw) }.getOrNull() }
    snapshot?.optJSONObject("strings")?.optString("chooseList")
      ?.takeIf { it.isNotEmpty() }
      ?.let { title = it }
    val choices = widgetListChoices(snapshot)
    val current = TasksWidgetConfig.listFor(this, widgetId)

    val list = ListView(this)
    list.adapter = ChoiceAdapter(choices, current)
    list.setOnItemClickListener { _, _, position, _ ->
      TasksWidgetConfig.setList(this, widgetId, choices[position].id)
      // Redraw this widget now, set to its new list — the provider reads the
      // choice back, and its list re-reads through notifyAppWidgetViewDataChanged.
      sendBroadcast(
        Intent(this, TasksWidgetProvider::class.java)
          .setAction(AppWidgetManager.ACTION_APPWIDGET_UPDATE)
          .putExtra(AppWidgetManager.EXTRA_APPWIDGET_IDS, intArrayOf(widgetId)),
      )
      setResult(RESULT_OK, Intent().putExtra(AppWidgetManager.EXTRA_APPWIDGET_ID, widgetId))
      finish()
    }
    setContentView(list)
  }

  /** Rows of `widget_config_row`: the project's color, its name, a check on the current choice. */
  private inner class ChoiceAdapter(
    private val choices: List<WidgetListChoice>,
    private val current: String,
  ) : BaseAdapter() {
    override fun getCount(): Int = choices.size
    override fun getItem(position: Int): Any = choices[position]
    override fun getItemId(position: Int): Long = position.toLong()

    override fun getView(position: Int, convertView: View?, parent: ViewGroup): View {
      val row = convertView
        ?: LayoutInflater.from(parent.context).inflate(R.layout.widget_config_row, parent, false)
      val choice = choices[position]
      val name = row.findViewById<CheckedTextView>(R.id.aw_config_name)
      name.text = choice.name
      name.isChecked = choice.id == current
      val dot = row.findViewById<TextView>(R.id.aw_config_dot)
      val color = parseWidgetColor(choice.color)
      if (color != null) {
        dot.setTextColor(color)
        dot.visibility = View.VISIBLE
      } else {
        // The whole list has no color; keep the names aligned, not shifted.
        dot.visibility = View.INVISIBLE
      }
      return row
    }
  }
}
