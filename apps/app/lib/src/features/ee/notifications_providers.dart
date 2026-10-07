import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../i18n/i18n.dart';
import '../../sync/db/database.dart';
import '../../sync/outbox.dart';
import '../../sync/providers.dart';
import '../workspaces/workspaces.dart';

/// The notification centre's data (EE-077, on EE-073's synced inbox).
///
/// Everything here reads the REPLICA, never the network. That is what makes
/// the centre and its badge right with no signal — the acceptance's "offline"
/// is not a mode this screen has, it is the only mode it has.
///
/// It is also the entitlement gate, by construction rather than by a check: on
/// a build with no overlay the table is simply empty, so the badge is zero and
/// the centre says "nothing yet". No screen has to ask whether the feature
/// exists, and none of them can get that question wrong.
///
/// ── SCOPED TO THE CURRENT WORKSPACE, AND THAT IS A REAL LIMIT ─────────────
///
/// The sync engine runs for one workspace at a time (`SyncEngine.workspaceId`),
/// so rows belonging to a unit this device is not currently syncing would be
/// however stale the last visit left them. Showing them would make the centre
/// quietly wrong; scoping makes it quietly incomplete. Incomplete is the
/// better failure, and it matches every other EE surface here ("assigned to
/// me", "shared with me"). The consequence, stated rather than discovered:
/// somebody in two units sees the badge of the unit they are looking at.
/// Fixing that is a multi-workspace SYNC question, not a screen question.
class NotificationItem {
  const NotificationItem({
    required this.id,
    required this.eventClass,
    required this.titleKey,
    required this.params,
    this.bodyKey,
    this.entityType,
    this.entityId,
    this.readAt,
    this.createdAt,
  });

  factory NotificationItem.fromRow(NotificationRecord row) => NotificationItem(
    id: row.id,
    eventClass: row.eventClass,
    titleKey: row.titleKey,
    bodyKey: row.bodyKey,
    // Decoded HERE rather than at sync time: a malformed payload should cost
    // one row its subtitle, not stall a pull.
    params: _decode(row.params),
    entityType: row.entityType,
    entityId: row.entityId,
    readAt: row.readAt,
    createdAt: row.createdAt,
  );

  final String id;
  final String eventClass;
  final String titleKey;
  final String? bodyKey;
  final Map<String, dynamic> params;
  final String? entityType;
  final String? entityId;
  final DateTime? readAt;
  final DateTime? createdAt;

  bool get isUnread => readAt == null;

  /// Where tapping it goes, or null when there is nowhere to go. A row that
  /// points at a type this build has no route for stays a plain line rather
  /// than a button that does nothing (DESIGN §22).
  String? get destination => switch (entityType) {
    'task' when entityId != null => '/tasks/$entityId',
    // EE-251: a request opens at its address. Until then every ticket
    // notification — assigned, commented, status — was a line with nowhere
    // to go, although the server has always named the ticket.
    'ee_ticket' when entityId != null => '/tickets/$entityId',
    // EE-230: an approval opens where it is answered — since EE-295 the
    // approval itself, read whole (the notification names it).
    'ee_approval' when entityId != null => '/approvals/$entityId',
    'ee_approval' => '/approvals',
    _ => null,
  };

  /// What the title and body are drawn with.
  ///
  /// Every param as text — and a param whose name ends in `Key` is an i18n
  /// KEY the server chose (EE-230: an approval's outcome), translated HERE,
  /// into the language this device is set to now, and handed on under its
  /// name without the suffix. The row keeps the key rather than the word for
  /// the reason it keeps `titleKey`: it may be read years later on a phone
  /// set to another language. The translation wins over a raw param of the
  /// same name, because that one (`decision: rejected`) is the machine word
  /// an integration reads, not a sentence for a person.
  Map<String, String> get args {
    final out = {
      for (final entry in params.entries) entry.key: '${entry.value}',
    };
    for (final entry in params.entries) {
      final name = entry.key;
      final value = entry.value;
      if (name.length > 3 && name.endsWith('Key') && value is String) {
        out[name.substring(0, name.length - 3)] = value.tr();
      }
    }
    // OPH-358 (UI-AUDIT #28): a request's new status, in this device's
    // language. The server sends the machine word — as `status` since EE-302,
    // and before that under `statusLabel`, which despite its name always held
    // the raw key ("#209 artık in_progress"). Either is read as a key; a word
    // this build does not know is a neutral phrase, never the raw value.
    if (eventClass == 'ticket.status_changed' ||
        titleKey == 'ee.notif.ticket.status_changed.title') {
      final raw = params['status'] ?? params['statusLabel'];
      if (raw is String) {
        out['statusLabel'] =
            AwI18n.instance.maybeTranslate('ee.tickets.status.$raw') ??
            'ee.tickets.statusUnknown'.tr();
      }
    }
    return out;
  }

  static Map<String, dynamic> _decode(String? raw) {
    if (raw == null || raw.isEmpty) return const {};
    try {
      final decoded = jsonDecode(raw);
      return decoded is Map<String, dynamic> ? decoded : const {};
    } catch (_) {
      return const {};
    }
  }
}

/// The badge, live from the replica's own stream.
///
/// A count query rather than a list: the badge is on screen constantly and
/// must not pay for rows nobody is looking at. It updates the moment a pull
/// writes a row, because drift's `watch` is the same mechanism the rest of the
/// app already uses to stay live.
///
/// Every synced workspace counts: what happened to a person in one unit is
/// news whichever unit is on screen — a request assigned to them in another
/// unit showed up only once they happened to switch to it.
///
/// And only the signed-in person's rows (UI-AUDIT #3). A notification is
/// addressed to ONE person; the replica is wiped when the person changes
/// (OPH-355), and this filter is the second wall — a row that outlived a
/// sign-out must still never reach the next person's centre.
final unreadNotificationCountProvider = StreamProvider<int>((ref) {
  final workspaceIds = ref.watch(syncWorkspaceIdsProvider);
  final userId = ref.watch(currentUserIdProvider);
  if (workspaceIds.isEmpty || userId == null) return Stream.value(0);
  final db = ref.watch(databaseProvider);
  final count = db.notifications.id.count();
  final query = db.selectOnly(db.notifications)
    ..addColumns([count])
    ..where(
      db.notifications.workspaceId.isIn(workspaceIds) &
          db.notifications.userId.equals(userId) &
          db.notifications.readAt.isNull(),
    );
  return query.map((row) => row.read(count) ?? 0).watchSingle();
});

/// The centre's list: newest first, unread and read together, from every
/// synced workspace (see [unreadNotificationCountProvider]).
///
/// Not split into two sections. A notification you have read is still the
/// record of what happened, and hiding it behind a filter turns the centre
/// into a to-do list — which is a different screen this app already has.
final notificationCenterProvider = StreamProvider<List<NotificationItem>>((
  ref,
) {
  final workspaceIds = ref.watch(syncWorkspaceIdsProvider);
  final userId = ref.watch(currentUserIdProvider);
  if (workspaceIds.isEmpty || userId == null) {
    return Stream.value(const <NotificationItem>[]);
  }
  final db = ref.watch(databaseProvider);
  final query = db.select(db.notifications)
    ..where((n) => n.workspaceId.isIn(workspaceIds) & n.userId.equals(userId))
    ..orderBy([
      (n) => OrderingTerm.desc(n.createdAt),
      (n) => OrderingTerm.desc(n.id),
    ])
    // A centre is a recent history, not an archive. The server keeps the rest.
    ..limit(200);
  return query.watch().map(
    (rows) => rows.map(NotificationItem.fromRow).toList(growable: false),
  );
});

/// Marking read, offline-first.
///
/// The local write and its outbox mutation go in ONE transaction, exactly as
/// every other local write here does: a badge that dropped without a queued
/// mutation behind it would be a promise nothing keeps.
///
/// `readAt` is the only field this app ever pushes for this type — the server
/// accepts no other, and a device that could author a notification could
/// author an alert nobody should trust.
class NotificationStore {
  NotificationStore(this._db, {void Function()? onMutation})
    : _poke = onMutation ?? (() {});

  final AwDatabase _db;
  final void Function() _poke;

  Future<void> markRead(String id, {bool read = true}) async {
    final row = await (_db.select(
      _db.notifications,
    )..where((n) => n.id.equals(id))).getSingleOrNull();
    if (row == null) return;
    // A no-op writes nothing — not a row, not a mutation, not a push. Tapping
    // something already read must not queue traffic.
    if ((row.readAt != null) == read) return;

    final at = read ? DateTime.now().toUtc() : null;
    await _db.transaction(() async {
      await (_db.update(
        _db.notifications,
      )..where((n) => n.id.equals(id))).write(
        NotificationsCompanion(readAt: Value(at), updatedAt: Value(at)),
      );
      await enqueueMutation(
        _db,
        workspaceId: row.workspaceId,
        entityType: 'ee_notification',
        entityId: id,
        operation: 'update',
        patch: {'readAt': at?.toIso8601String()},
      );
    });
    _poke();
  }

  /// "Mark everything read" — everything the centre lists, from
  /// [workspaceIds] and, when given, addressed to [userId] (the centre's own
  /// filter); one mutation per row, on purpose.
  ///
  /// The server has no bulk verb for this and inventing a client-only one
  /// would make the two paths disagree the first time a push failed halfway.
  /// The outbox is built for exactly this: a queue of small, independently
  /// retryable facts. Each row's mutation goes to its own workspace.
  Future<int> markAllRead(List<String> workspaceIds, {String? userId}) async {
    if (workspaceIds.isEmpty) return 0;
    final unread =
        await (_db.select(_db.notifications)..where(
              (n) =>
                  n.workspaceId.isIn(workspaceIds) &
                  n.readAt.isNull() &
                  (userId == null
                      ? const Constant(true)
                      : n.userId.equals(userId)),
            ))
            .get();
    for (final row in unread) {
      await markRead(row.id);
    }
    return unread.length;
  }
}

final notificationStoreProvider = Provider<NotificationStore>(
  (ref) => NotificationStore(
    ref.watch(databaseProvider),
    onMutation: () => pokeSync(ref),
  ),
);
