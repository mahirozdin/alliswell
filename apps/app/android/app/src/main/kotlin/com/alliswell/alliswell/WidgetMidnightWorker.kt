package com.alliswell.alliswell

import android.content.Context
import android.net.Uri
import androidx.work.ExistingWorkPolicy
import androidx.work.OneTimeWorkRequestBuilder
import androidx.work.WorkManager
import androidx.work.Worker
import androidx.work.WorkerParameters
import es.antonborri.home_widget.HomeWidgetBackgroundIntent
import java.util.Calendar
import java.util.TimeZone
import java.util.concurrent.TimeUnit

/**
 * OPH-334 — the widget's day turns over at midnight, without the app.
 *
 * The widget's buckets (Overdue, Today, Tomorrow…) are computed in Dart from the
 * replica — one grouping, `groupTasksForWidget` (ADR-0010) — so a native redraw
 * would only re-render the SAME snapshot: yesterday's "Today". The turn has to
 * run the Dart side, and the background turn now ends by republishing the
 * widget (OPH-334, `runHeadlessRefresh`).
 *
 * ── WHY A SECOND WORKER ──────────────────────────────────────────────────
 *
 * Measured, not assumed: [AlarmRefreshWorker] runs every SIX hours — a floor
 * for alarms, deliberately lazy for the battery. Left to it, a phone looked at
 * at 7 a.m. could still show yesterday's buckets. So this is one extra,
 * one-time turn at the next local midnight, and it schedules the next one.
 *
 * Not exact, by design: WorkManager may hold it in Doze until a maintenance
 * window. The promise is "before the morning", not "at 00:00:00" — an exact
 * alarm for a list redraw would spend the permission OPH-304 argued for on
 * something that is not an alarm.
 */
class WidgetMidnightWorker(context: Context, params: WorkerParameters) :
    Worker(context, params) {

    override fun doWork(): Result {
        // The same Dart turn the periodic worker asks for — one entry point to
        // keep `@pragma('vm:entry-point')` on (OPH-321).
        HomeWidgetBackgroundIntent
            .getBroadcast(applicationContext, Uri.parse(REFRESH_URI))
            .send()
        // The next midnight. REPLACE cancels THIS run's record, which is
        // harmless here: the broadcast has already gone, and KEEP would see the
        // running work and enqueue nothing — the chain would end tonight.
        enqueue(applicationContext)
        return Result.success()
    }

    companion object {
        private const val REFRESH_URI = "alliswell://refresh-alarms"
        private const val UNIQUE_NAME = "aw-widget-midnight"

        /**
         * Schedules the turn for the next local midnight. REPLACE, unlike the
         * periodic worker's KEEP: the only pending turn worth having is the
         * NEXT midnight, and a stale one — a time zone crossed, a clock the
         * user set — is worth nothing.
         */
        @JvmStatic
        fun enqueue(context: Context) {
            val delay = delayToNextMidnight(System.currentTimeMillis(), TimeZone.getDefault())
            WorkManager.getInstance(context).enqueueUniqueWork(
                UNIQUE_NAME,
                ExistingWorkPolicy.REPLACE,
                OneTimeWorkRequestBuilder<WidgetMidnightWorker>()
                    .setInitialDelay(delay, TimeUnit.MILLISECONDS)
                    .build(),
            )
        }

        /**
         * Milliseconds from [nowMillis] to one minute past the next local
         * midnight in [zone]. The minute is margin, not decoration: a turn that
         * fired at 23:59:59.9 would compute yesterday's buckets once more.
         * `Calendar` rather than java.time so nothing here leans on desugaring,
         * and it walks a DST night by the zone's own rules.
         */
        @JvmStatic
        fun delayToNextMidnight(nowMillis: Long, zone: TimeZone): Long {
            val next = Calendar.getInstance(zone).apply {
                timeInMillis = nowMillis
                add(Calendar.DAY_OF_YEAR, 1)
                set(Calendar.HOUR_OF_DAY, 0)
                set(Calendar.MINUTE, 1)
                set(Calendar.SECOND, 0)
                set(Calendar.MILLISECOND, 0)
            }
            return next.timeInMillis - nowMillis
        }
    }
}
