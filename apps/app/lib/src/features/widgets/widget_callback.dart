import '../../core/deep_link.dart';
import '../../sync/db/connection.dart';
import '../../sync/db/database.dart';
import '../tasks/data/task_store.dart';

/// What the home-screen widget's buttons do (OPH-188, WIDGETS §4).
///
/// This runs in a **background isolate** with no UI, no Riverpod scope and no
/// engine the app is using — Android's `HomeWidgetBackgroundIntent` spins it up
/// for a single callback. So it opens its own database handle and closes it
/// again; it must not reach for anything the running app owns.
///
/// The write itself is deliberately the ordinary one: `TaskStore.complete`,
/// which is an optimistic replica row plus an outbox mutation in one
/// transaction. That is what makes a completion from the widget behave like a
/// completion anywhere else — it works offline, it syncs when the network
/// returns, and every other device converges. **The widget has no write path of
/// its own**, which is the rule this file exists to keep.
///
/// [openDatabase] is injectable so the routing can be tested without touching
/// the platform's real replica.
Future<bool> handleWidgetAction(
  Uri? uri, {
  AwDatabase Function()? openDatabase,
}) async {
  if (uri == null || !awIsBackgroundAction(uri)) return false;
  final taskId = uri.queryParameters['id'];
  if (taskId == null || taskId.isEmpty) return false;
  // Only `complete` today. `add` is in the queue's vocabulary but needs a
  // title, which a widget button cannot supply — it stays a deep link into the
  // app (WIDGETS §4), and saying so here is cheaper than a future reader
  // wondering whether it was forgotten.
  if (uri.host != 'complete') return false;

  // Close only what we opened. An injected handle belongs to its owner — the
  // callee disposing a caller's dependency is how a test (or a future caller
  // that wants two actions) ends up with "can't re-open a database".
  final injected = openDatabase != null;
  final db = injected ? openDatabase() : AwDatabase(openAwConnection());
  try {
    // No engine poke: there is no sync engine in this isolate. The outbox row
    // is what matters, and the app pushes it on its next foreground — the same
    // path an offline write already takes.
    await TaskStore(db, () {}).complete(taskId);
    return true;
  } finally {
    if (!injected) await db.close();
  }
}
