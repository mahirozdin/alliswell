package com.alliswell.alliswell

import android.content.Context
import android.net.Uri
import androidx.work.ExistingPeriodicWorkPolicy
import androidx.work.PeriodicWorkRequestBuilder
import androidx.work.WorkManager
import androidx.work.Worker
import androidx.work.WorkerParameters
import es.antonborri.home_widget.HomeWidgetBackgroundIntent
import java.util.concurrent.TimeUnit

/**
 * OPH-321 — the floor under the wake-up hint.
 *
 * A reminder created on a laptop reaches this phone when the phone syncs, and a
 * phone that is not running the app syncs when something wakes it. The data
 * message (OPH-322) is the elegant trigger and it is not guaranteed: FCM drops
 * priority for an app the user has not touched in days, and a device without
 * Play services never gets one at all. This is what makes the alarm arrive
 * anyway, late rather than never.
 *
 * ── WHY androidx.work AND NOT THE `workmanager` PLUGIN ────────────────────
 *
 * `androidx.work` is already inside the APK — home_widget uses it — and the app
 * already has a registered Dart background dispatcher, so all that was missing
 * was something to call it on a timer. The Flutter `workmanager` plugin would
 * have added a second dispatcher, a second Gradle plugin on AGP 9 and a second
 * thing to keep alive; ADR-0038 records that trade.
 *
 * The Dart side is reached the same way the widget's buttons reach it, with a
 * different host (`awAlarmRefreshUri`), so there is exactly one entry point to
 * keep `@pragma('vm:entry-point')` on.
 */
class AlarmRefreshWorker(context: Context, params: WorkerParameters) :
    Worker(context, params) {

    override fun doWork(): Result {
        HomeWidgetBackgroundIntent
            .getBroadcast(applicationContext, Uri.parse(REFRESH_URI))
            .send()
        // The Dart turn decides for itself whether there is anything to do —
        // it declines outright when the app is in the foreground (OPH-318) —
        // so this is success whatever it finds.
        return Result.success()
    }

    companion object {
        private const val REFRESH_URI = "alliswell://refresh-alarms"
        private const val UNIQUE_NAME = "aw-alarm-refresh"

        /**
         * Registers the periodic turn. KEEP, not REPLACE: replacing on every
         * launch would reset the interval each time the user opens the app,
         * which is exactly the user whose phone never needs to run it.
         *
         * Six hours because the work is a floor, not a schedule — the alarm
         * itself is armed locally once a sync has happened, and 15 minutes of
         * radio for a plan that rarely changes is a battery complaint waiting
         * to happen.
         */
        @JvmStatic
        fun enqueue(context: Context) {
            WorkManager.getInstance(context).enqueueUniquePeriodicWork(
                UNIQUE_NAME,
                ExistingPeriodicWorkPolicy.KEEP,
                PeriodicWorkRequestBuilder<AlarmRefreshWorker>(6, TimeUnit.HOURS)
                    .build(),
            )
        }
    }
}
