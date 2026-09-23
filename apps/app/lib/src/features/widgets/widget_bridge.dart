import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/date_format.dart';
import '../../core/day_boundary.dart';
import '../../core/kv/local_kv.dart';
import '../../core/persisted_prefs.dart';
import '../../sync/db/database.dart';
import '../projects/data/project_store.dart';
import '../projects/providers.dart';
import '../tasks/data/task.dart';
import '../tasks/data/task_store.dart';
import '../tasks/providers.dart';
import 'widget_host.dart';
import 'widget_snapshot.dart';

/// Writes the widget snapshot to the shared container and asks the OS to redraw
/// (OPH-130). The DB→widget bridge of ADR-0010: the widget renders this JSON, it
/// never reads the drift replica.
class WidgetBridge {
  WidgetBridge(this._host);

  final WidgetHost _host;
  bool _configured = false;

  /// Serialize [tasks] into the snapshot and push it. [projectColorById] maps a
  /// task's `projectId` to its `#RRGGBB` color.
  Future<void> publish(
    List<Task> tasks, {
    required DateTime now,
    Map<String, String> projectColorById = const {},
    String dateFormat = kAwSystemDateFormat,
  }) async {
    if (!_configured) {
      await _host.configure();
      _configured = true;
    }
    final snapshot = buildWidgetSnapshot(
      tasks,
      now: now,
      projectColorById: projectColorById,
      dateFormat: dateFormat,
    );
    await _host.save(kWidgetSnapshotKey, jsonEncode(snapshot.toJson()));
    await _host.requestUpdate();
  }
}

final widgetBridgeProvider = Provider<WidgetBridge>(
  (ref) => WidgetBridge(ref.watch(widgetHostProvider)),
);

/// The widget's snapshot rebuilt from the replica, with no provider graph —
/// the background turn's last step (OPH-334, `runHeadlessRefresh`).
///
/// It asks the SAME questions [widgetSyncProvider] asks the live graph, one
/// store call each: open tasks plus today's completed ones
/// (`watchOpen(completedSince:)` — OPH-185's dimmed rows), every project's
/// color, and the user's date format. A second definition of "what the widget
/// shows" is how a background redraw ends up disagreeing with the app.
///
/// [now] is the whole point of calling this at midnight: the rows are the
/// same, the day is not, so the buckets move.
///
/// Never throws. A widget is a view of the data, not a duty of the turn that
/// calls this: a host that is missing in some background isolate must not
/// take the alarms of that turn down with it.
Future<bool> publishWidgetFromReplica(
  AwDatabase db, {
  required String workspaceId,
  required DateTime now,
  WidgetHost host = const HomeWidgetHost(),
}) async {
  try {
    final tasks = await TaskStore(
      db,
      () {},
    ).watchOpen(workspaceId, completedSince: awStartOfDay(now)).first;
    final projects = await ProjectStore(db, () {}).watchAll(workspaceId).first;
    // Read from localKv directly, as the rest of the turn does: in a process
    // this short a `PersistedChoice` answers its fallback, not the user's pick.
    final dateFormat =
        await localKv.get(kDateFormatPrefKey) ?? kAwSystemDateFormat;
    await WidgetBridge(host).publish(
      tasks,
      now: now,
      projectColorById: {
        for (final project in projects) project.id: project.colorRgb,
      },
      dateFormat: dateFormat,
    );
    return true;
  } on Object {
    return false;
  }
}

/// Widgets exist only on iOS, iPadOS, Android and macOS (ADR-0010). Web/Windows/
/// Linux have no home-screen surface — the sync is a no-op there.
bool get widgetsSupportedPlatform {
  if (kIsWeb) return false;
  switch (defaultTargetPlatform) {
    case TargetPlatform.iOS:
    case TargetPlatform.android:
    case TargetPlatform.macOS:
      return true;
    default:
      return false;
  }
}

/// Keeps the home-screen widget in lock-step with tasks (OPH-130): republishes
/// the snapshot on every open-task or project change. Watch it where the app is
/// alive (HomeShell). While the app is foreground these pushes are budget-exempt
/// (WIDGETS.md §6), so the widget stays current for free.
final widgetSyncProvider = Provider<void>((ref) {
  if (!widgetsSupportedPlatform) return;
  final tasks = ref.watch(openTasksProvider).value;
  if (tasks == null) return;
  final projects = ref.watch(projectsByIdProvider);
  final colors = {
    for (final entry in projects.entries) entry.key: entry.value.colorRgb,
  };
  // Watched, not read: changing the date format republishes the snapshot, so
  // the widget never shows yesterday's format (OPH-174).
  final dateFormat = ref.watch(dateFormatProvider);
  // Fire-and-forget: a widget push must never block the UI.
  ref
      .read(widgetBridgeProvider)
      .publish(
        tasks,
        now: DateTime.now(),
        projectColorById: colors,
        dateFormat: dateFormat,
      );
});
