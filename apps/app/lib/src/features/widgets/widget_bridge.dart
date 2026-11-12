import 'dart:async';
import 'dart:convert';

import 'package:drift/drift.dart' show QueryRow, Selectable;
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart'
    show AppLifecycleListener, AppLifecycleState;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/date_format.dart';
import '../../core/day_boundary.dart';
import '../../core/kv/local_kv.dart';
import '../../core/persisted_prefs.dart';
import '../../core/server_url.dart';
import '../../sync/db/database.dart';
import '../../sync/providers.dart' show databaseProvider;
import '../calendar/data/external_event.dart';
import '../calendar/providers.dart';
import '../projects/data/project.dart';
import '../projects/data/project_store.dart';
import '../projects/providers.dart';
import '../tasks/data/task.dart';
import '../tasks/data/task_store.dart';
import '../tasks/providers.dart';
import 'widget_host.dart';
import 'widget_snapshot.dart';

/// What a fetch profile needs beyond the snapshot's own inputs (iOS self-fetch,
/// #50, WIDGETS §3.2): where the server is, whose lists, and how many local
/// writes have not gone out. [pendingOutbox] null = not known yet.
class WidgetFetchSource {
  const WidgetFetchSource({
    required this.baseUrl,
    required this.scope,
    this.pendingOutbox,
  });

  final String baseUrl;
  final TaskScope scope;
  final int? pendingOutbox;
}

/// Writes the widget snapshot to the shared container and asks the OS to redraw
/// (OPH-130). The DB→widget bridge of ADR-0010: the widget renders this JSON, it
/// never reads the drift replica.
///
/// Since #50 it also writes the iOS widget's fetch profile beside the snapshot
/// ([publish]'s `fetch`) and keeps its outbox count current
/// ([updatePendingOutbox]).
class WidgetBridge {
  WidgetBridge(this._host, {DateTime Function() clock = DateTime.now})
    // ignore: prefer_initializing_formals — a private named parameter.
    : _clock = clock;

  final WidgetHost _host;
  final DateTime Function() _clock;
  bool _configured = false;

  // The last profile's inputs, so a new outbox count can rewrite it alone.
  WidgetFetchSource? _fetch;
  bool _hideTitles = true;
  String _dateFormat = kAwSystemDateFormat;
  int? _pendingOutbox;
  DateTime? _localWrittenAt;

  /// What the last written profile asked the server for; a change drops the
  /// extension's copy of the old answer.
  String? _lastQuery;

  /// Serialize [tasks] into the snapshot and push it. [projectColorById] maps a
  /// task's `projectId` to its `#RRGGBB` color; [projects] are the lists a
  /// widget can be set to (OPH-336), in the app's order. [hideTitles] and
  /// [compact] are the widget settings (OPH-337).
  ///
  /// With [fetch] (iOS only, #50) the fetch profile is written after the
  /// snapshot, in the same publish — the caller passes it only once "Private
  /// widget" has been READ, which [hideTitles] then is. With the outbox count
  /// not known yet the profile waits for [updatePendingOutbox].
  Future<void> publish(
    List<Task> tasks, {
    List<ExternalEvent> events = const [],
    required DateTime now,
    Map<String, String> projectColorById = const {},
    Iterable<Project> projects = const [],
    String dateFormat = kAwSystemDateFormat,
    bool hideTitles = false,
    bool compact = false,
    WidgetFetchSource? fetch,
  }) async {
    if (!_configured) {
      await _host.configure();
      _configured = true;
    }
    final snapshot = buildWidgetSnapshot(
      tasks,
      events: events,
      now: now,
      projectColorById: projectColorById,
      projects: projects,
      dateFormat: dateFormat,
      hideTitles: hideTitles,
      compact: compact,
    );
    await _host.save(kWidgetSnapshotKey, jsonEncode(snapshot.toJson()));
    if (fetch != null) {
      _fetch = fetch;
      _hideTitles = hideTitles;
      _dateFormat = dateFormat;
      _pendingOutbox = fetch.pendingOutbox ?? _pendingOutbox;
      _localWrittenAt = _clock();
      await _writeProfile();
    }
    await _host.requestUpdate();
  }

  /// A new count of unsent local writes (every sync push round changes it):
  /// rewrites the profile with it, the snapshot's stamp unchanged. Before the
  /// first profile-carrying [publish] it is only remembered.
  Future<void> updatePendingOutbox(int count) async {
    if (_pendingOutbox == count) return;
    _pendingOutbox = count;
    if (_fetch == null) return;
    await _writeProfile();
  }

  /// Sign-out (#50): the profile's inputs were the person's. Forgotten, so a
  /// new outbox count cannot write the old scope back after the keys are
  /// cleared (`WidgetTokenLifecycle.signOut`); the next profile-carrying
  /// [publish] starts afresh.
  void forgetFetch() {
    _fetch = null;
    _pendingOutbox = null;
    _localWrittenAt = null;
    _lastQuery = null;
  }

  Future<void> _writeProfile() async {
    final fetch = _fetch, pending = _pendingOutbox, at = _localWrittenAt;
    if (fetch == null || pending == null || at == null) return;
    final profile = buildWidgetFetchProfile(
      baseUrl: fetch.baseUrl,
      scope: fetch.scope,
      hideTitles: _hideTitles,
      dateFormat: _dateFormat,
      pendingOutbox: pending,
      localWrittenAt: at,
    );
    // WIDGETS §3.2: a change of scope or of "Private widget" removes the
    // extension's copy of the old answer when the profile is rewritten. (The
    // extension also refuses a copy whose query differs from the profile's.)
    final query = jsonEncode([
      profile['baseUrl'],
      profile['scope'],
      profile['private'],
    ]);
    final changed = _lastQuery != null && _lastQuery != query;
    _lastQuery = query;
    // The new profile first, then the removal: the extension stores an answer
    // only while the profile it asked with is still the stored one and looks
    // again after storing it, so an answer for the old profile landing on
    // either side of the removal is refused or removed. Removed first, one
    // landing in between would still match the old profile and keep its
    // titles in the App Group (§9).
    await _host.save(kWidgetFetchProfileKey, jsonEncode(profile));
    final host = _host;
    if (changed && host is WidgetKeyRemover) {
      await (host as WidgetKeyRemover).remove(kWidgetServerSnapshotKey);
    }
  }
}

final widgetBridgeProvider = Provider<WidgetBridge>(
  (ref) => WidgetBridge(ref.watch(widgetHostProvider)),
);

/// What the widget is built from, read from the replica (OPH-334): the open
/// tasks plus today's finished ones, every project and the calendar.
typedef WidgetReplica = ({
  List<Task> tasks,
  List<Project> projects,
  List<ExternalEvent> events,
});

/// The replica's answer to the questions [widgetSyncProvider] asks the live
/// graph, one store call each, over the same [TaskScope]: open tasks plus
/// today's completed ones (`watchOpenIn(completedSince:)` — OPH-185's dimmed
/// rows), every project (its color, and since OPH-336 the lists a widget can
/// be set to) and the calendar. The background turn draws from it, and the
/// shared grouping fixture (#50) is written from it — so the server's port is
/// held to the same selection.
Future<WidgetReplica> readWidgetReplica(
  AwDatabase db, {
  required TaskScope scope,
  required DateTime now,
}) async {
  final tasks = await TaskStore(
    db,
    () {},
  ).watchOpenIn(scope, completedSince: awStartOfDay(now)).first;
  final projects = await ProjectStore(
    db,
    () {},
  ).watchAllIn(scope.workspaceIds).first;
  // v5: the calendar, under the rule `externalEventsProvider` keeps — one
  // workspace's own calendar, and none at all in an organisation's shared
  // workspaces (a person's calendar must not reach everyone there). A
  // `mine` scope IS the shared case (`taskScopeProvider` builds it only
  // there).
  final events = scope.mineFor != null || scope.workspaceIds.length != 1
      ? const <ExternalEvent>[]
      : await ExternalEventStore(db).watchAll(scope.workspaceIds.single).first;
  return (tasks: tasks, projects: projects, events: events);
}

/// Local writes not yet sent to the server: the outbox (#50). Rejected writes
/// are not in it — they will never be sent.
Future<int> widgetPendingOutboxCount(AwDatabase db) async =>
    (await _pendingOutboxQuery(db).getSingle()).read<int>('n');

Selectable<QueryRow> _pendingOutboxQuery(AwDatabase db) => db.customSelect(
  'SELECT COUNT(*) AS n FROM pending_mutations',
  readsFrom: {db.pendingMutations},
);

/// The widget's snapshot rebuilt from the replica, with no provider graph —
/// the background turn's last step (OPH-334, `runHeadlessRefresh`).
///
/// It reads [readWidgetReplica], and since OPH-337 the two widget settings —
/// a midnight redraw that forgot "Private widget" would put every title back
/// while the phone sleeps. A second definition of "what the widget shows" is
/// how a background redraw ends up disagreeing with the app.
///
/// [now] is the whole point of calling this at midnight: the rows are the
/// same, the day is not, so the buckets move.
///
/// [selfFetch] (iOS, #50) also writes the fetch profile, from the stored
/// server address and the replica's outbox: a snapshot drawn from local
/// changes must say so, or the extension would prefer an older server answer.
///
/// Never throws. A widget is a view of the data, not a duty of the turn that
/// calls this: a host that is missing in some background isolate must not
/// take the alarms of that turn down with it.
Future<bool> publishWidgetFromReplica(
  AwDatabase db, {
  required TaskScope scope,
  required DateTime now,
  WidgetHost? host,
  bool? selfFetch,
}) async {
  try {
    final replica = await readWidgetReplica(db, scope: scope, now: now);
    // Read from localKv directly, as the rest of the turn does: in a process
    // this short a `PersistedChoice` answers its fallback, not the user's pick.
    final dateFormat =
        await localKv.get(kDateFormatPrefKey) ?? kAwSystemDateFormat;
    final hideTitles = await localKv.get(kWidgetPrivatePrefKey) == 'true';
    final compact = await localKv.get(kWidgetCompactPrefKey) == 'true';
    final fetch = (selfFetch ?? widgetSelfFetchSupported)
        ? WidgetFetchSource(
            baseUrl: widgetStoredBaseUrl(await localKv.get(kServerUrlPrefKey)),
            scope: scope,
            pendingOutbox: await widgetPendingOutboxCount(db),
          )
        : null;
    await WidgetBridge(host ?? defaultWidgetHost()).publish(
      replica.tasks,
      events: replica.events,
      now: now,
      projectColorById: {
        for (final project in replica.projects) project.id: project.colorRgb,
      },
      projects: replica.projects,
      dateFormat: dateFormat,
      hideTitles: hideTitles,
      compact: compact,
      fetch: fetch,
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

/// Whether this platform's widget fetches its own days (#50, WIDGETS §3.2):
/// iOS only. Android's background turn runs Dart, and the macOS widget's
/// self-fetch is a later candidate.
bool get widgetSelfFetchSupported =>
    !kIsWeb && defaultTargetPlatform == TargetPlatform.iOS;

/// The server address as stored: the user's override, else the built-in one.
/// An empty override is "the default" ([serverUrlOverrideProvider]'s rule).
String widgetStoredBaseUrl(String? stored) =>
    stored == null || stored.isEmpty ? compiledApiBaseUrl : stored;

/// The server address for the fetch profile, read from storage — not
/// [apiBaseUrlProvider], which answers the built-in address until the stored
/// override has been read: a self-hoster's widget would ask the wrong server
/// for that moment. Watches the override so a change rewrites the profile.
final widgetFetchBaseUrlProvider = FutureProvider<String>((ref) async {
  ref.watch(serverUrlOverrideProvider);
  return widgetStoredBaseUrl(await localKv.get(kServerUrlPrefKey));
});

/// The outbox count, live (#50): it rises with every local write and falls
/// with every sync push round.
final widgetPendingOutboxProvider = StreamProvider<int>(
  (ref) => _pendingOutboxQuery(
    ref.watch(databaseProvider),
  ).watchSingle().map((row) => row.read<int>('n')),
);

/// Keeps the home-screen widget in lock-step with tasks (OPH-130): republishes
/// the snapshot on every open-task or project change. Watch it where the app is
/// alive (HomeShell). While the app is foreground these pushes are budget-exempt
/// (WIDGETS.md §6), so the widget stays current for free — and the move to the
/// background writes it once more (OPH-438).
final widgetSyncProvider = Provider<void>((ref) {
  if (!widgetsSupportedPlatform) return;
  final tasks = ref.watch(openTasksProvider).value;
  if (tasks == null) return;
  // OPH-337: nothing goes out until "Private widget" has been READ. Publishing
  // on a default would write every title once per start, a moment before the
  // stored setting arrived — see WidgetPrivacy.
  final hideTitles = ref.watch(widgetPrivateProvider).value;
  if (hideTitles == null) return;
  final projects = ref.watch(projectsByIdProvider);
  final colors = {
    for (final entry in projects.entries) entry.key: entry.value.colorRgb,
  };
  // Watched, not read: changing the date format republishes the snapshot, so
  // the widget never shows yesterday's format (OPH-174).
  final dateFormat = ref.watch(dateFormatProvider);
  // v5: the user's calendar rides along, as on Home. Empty until it loads, and
  // always empty in a shared workspace (the provider's own rule).
  final events = ref.watch(externalEventsProvider).value ?? const [];
  final compact = ref.watch(widgetCompactProvider);
  final bridge = ref.read(widgetBridgeProvider);
  // #50: on iOS the widget fetches its own days with what the profile says.
  // Written with the snapshot, and only here — after "Private widget" has
  // been read above — so no profile ever says less than the user chose. No
  // scope or no address yet: no profile, and no profile means no fetch.
  WidgetFetchSource? fetch;
  if (widgetSelfFetchSupported) {
    final scope = ref.watch(taskScopeProvider).value;
    final baseUrl = ref.watch(widgetFetchBaseUrlProvider).value;
    if (scope != null && baseUrl != null) {
      // Listened, not watched: a new count rewrites the profile alone, not
      // the whole snapshot. The bridge holds the live count from here on, so
      // the source carries none: a count captured in it would be put back by
      // every later publish of this build — the write on the way out would
      // restore a count sync has since drained, and the extension would keep
      // preferring the local snapshot over the server's answer.
      ref.listen<AsyncValue<int>>(widgetPendingOutboxProvider, (_, next) {
        final count = next.value;
        if (count != null) unawaited(bridge.updatePendingOutbox(count));
      }, fireImmediately: true);
      fetch = WidgetFetchSource(baseUrl: baseUrl, scope: scope);
    }
  }
  Future<void> publish() => bridge.publish(
    tasks,
    events: events,
    now: DateTime.now(),
    projectColorById: colors,
    // The map keeps the list's order (sort order, then creation) — the
    // order the widget's list picker offers them in (OPH-336).
    projects: projects.values,
    dateFormat: dateFormat,
    hideTitles: hideTitles,
    compact: compact,
    fetch: fetch,
  );
  // Fire-and-forget: a widget push must never block the UI.
  unawaited(publish());
  // OPH-438 (#50): the last fresh write happens on the way out. A reload
  // asked for while the app is in front is outside WidgetKit's budget; once
  // the app is in the background the widget moves only when the OS grants it
  // one. So leaving the screen writes the same rows once more, under a fresh
  // `now`, and asks for a reload — the widget is never older than the last
  // app session. Once per trip: `hidden` and `paused` both arrive.
  var written = false;
  final lifecycle = AppLifecycleListener(
    onStateChange: (state) {
      switch (state) {
        case AppLifecycleState.hidden || AppLifecycleState.paused:
          if (written) return;
          written = true;
          unawaited(publish());
        case AppLifecycleState.resumed:
          written = false;
        case AppLifecycleState.inactive || AppLifecycleState.detached:
          break;
      }
    },
  );
  ref.onDispose(lifecycle.dispose);
});
