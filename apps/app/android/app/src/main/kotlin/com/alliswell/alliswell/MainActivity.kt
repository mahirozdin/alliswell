package com.alliswell.alliswell

import android.os.Bundle
import io.flutter.embedding.android.FlutterActivity

class MainActivity : FlutterActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        // OPH-321: register the periodic alarm refresh once the app has been
        // opened at least once. Doing it here rather than from Dart keeps it
        // out of the background isolate's path — the worker must exist whether
        // or not the engine is running, and `enqueueUniquePeriodicWork` with
        // KEEP makes every later launch a no-op.
        AlarmRefreshWorker.enqueue(applicationContext)
    }
}
