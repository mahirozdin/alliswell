package com.alliswell.alliswell

import android.content.Intent
import android.os.Bundle
import io.flutter.embedding.android.FlutterActivity

class MainActivity : FlutterActivity() {
    /// True once Flutter has drawn its first frame — from then on the router
    /// exists and a pushed route is handled.
    private var uiDisplayed = false

    /// An `alliswell://` link that arrived before [uiDisplayed]; re-pushed then.
    private var pendingLink: String? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        // OPH-321: register the periodic alarm refresh once the app has been
        // opened at least once. Doing it here rather than from Dart keeps it
        // out of the background isolate's path — the worker must exist whether
        // or not the engine is running, and `enqueueUniquePeriodicWork` with
        // KEEP makes every later launch a no-op.
        AlarmRefreshWorker.enqueue(applicationContext)
        // OPH-334: the widget's midnight turn. It re-schedules itself; this
        // launch just makes sure the pending one is for the NEXT midnight.
        WidgetMidnightWorker.enqueue(applicationContext)
    }

    /// A widget tap after the system killed the process but kept the activity
    /// record (an ordinary background death): Android recreates this activity
    /// with its ORIGINAL launch intent and hands the widget's link to
    /// `onNewIntent` — before Dart has a router. Flutter pushes the route
    /// right away and nobody is listening yet, so the tap opened plain Home
    /// (measured: `alliswell://task/…` and `alliswell://day/…` both lost).
    /// Keep the link and push it again once the first frame is up; the router
    /// parks it while the session restores. A second delivery is harmless —
    /// every routed link is a `go`, not a push.
    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        val data = intent.data
        if (!uiDisplayed && data != null && data.scheme == "alliswell") {
            pendingLink = data.toString()
        }
    }

    override fun onFlutterUiDisplayed() {
        super.onFlutterUiDisplayed()
        uiDisplayed = true
        val link = pendingLink ?: return
        pendingLink = null
        flutterEngine?.navigationChannel?.pushRouteInformation(link)
    }
}
