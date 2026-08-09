import 'package:drift/drift.dart';

import '../../../sync/db/database.dart';

/// Share-log event names (OPH-242). Small on purpose: this records what
/// ARRIVED, never what we hope the OS sent.
abstract final class ShareLogEvent {
  /// A share was waiting when the app started cold.
  static const initialShare = 'initial_share';

  /// A share arrived while the app was already running.
  static const warmShare = 'warm_share';

  /// A document (a `.md` file) was waiting at cold start.
  static const initialDocument = 'initial_document';

  /// A document arrived warm.
  static const warmDocument = 'warm_document';

  /// The OS named a file we could not read — an expired security scope, a
  /// permission-scoped URI, a file that is simply gone.
  static const readFailed = 'read_failed';

  /// A surface took the payload and did something with it.
  static const consumed = 'consumed';
}

/// What shape the payload had.
abstract final class ShareLogKind {
  static const text = 'text';
  static const url = 'url';
  static const markdown = 'markdown';
}

/// The device's own record of every inbound share (DESIGN §30 neighbourhood,
/// OPH-242). The alarm log's twin, and it exists for the same reason.
///
/// Round 17 opened with *"I shared a text, chose AllisWell, and nothing
/// happened — there wasn't even a crash report."* Nothing in the app could
/// confirm or deny that, which made the report unfalsifiable and cost a round.
/// From now on every arrival leaves a row.
///
/// **The most valuable reading of this log is an empty one.** Zero rows after a
/// share attempt is not a missing feature — it is the finding: the payload
/// never reached Dart, so the fault is native (the URL scheme, the App Group,
/// or the OS refusing the hand-off), not in how the app routes it.
///
/// Content never enters the table — only its size — so a user can paste the
/// whole log into a bug report without leaking what they shared.
class ShareLog {
  ShareLog(this._db);

  final AwDatabase _db;

  /// Records one arrival, then trims the buffer. Never throws: a diagnostic
  /// that can break the thing it observes is worse than no diagnostic.
  Future<void> record({
    required String event,
    String? payloadKind,
    int? bytes,
    String? detail,
    DateTime? at,
  }) async {
    try {
      await _db
          .into(_db.shareEvents)
          .insert(
            ShareEventsCompanion.insert(
              at: (at ?? DateTime.now()).toUtc(),
              event: event,
              payloadKind: Value(payloadKind),
              bytes: Value(bytes),
              detail: Value(detail),
            ),
          );
      await _trim();
    } on Object {
      // Swallowed on purpose — see the doc comment.
    }
  }

  /// Newest first. The Settings screen watches this.
  Stream<List<ShareEvent>> watchRecent({int limit = kShareLogLimit}) =>
      (_db.select(_db.shareEvents)
            ..orderBy([(e) => OrderingTerm.desc(e.at)])
            ..limit(limit))
          .watch();

  Future<List<ShareEvent>> recent({int limit = kShareLogLimit}) =>
      (_db.select(_db.shareEvents)
            ..orderBy([(e) => OrderingTerm.desc(e.at)])
            ..limit(limit))
          .get();

  Future<void> clear() => _db.delete(_db.shareEvents).go();

  /// Ring buffer: drop everything older than the newest [kShareLogLimit].
  Future<void> _trim() async {
    final keep =
        await (_db.select(_db.shareEvents)
              ..orderBy([(e) => OrderingTerm.desc(e.at)])
              ..limit(kShareLogLimit))
            .get();
    if (keep.length < kShareLogLimit) return;
    final cutoff = keep.last.at;
    await (_db.delete(
      _db.shareEvents,
    )..where((e) => e.at.isSmallerThanValue(cutoff))).go();
  }
}

/// One line of the log, as the diagnostic screen (and a copy-paste into a bug
/// report) shows it. Data only — no localization, on purpose: this is the part
/// a developer reads. `formatAlarmLogLine`'s twin.
String formatShareLogLine(ShareEvent e) {
  final parts = <String>[
    e.at.toIso8601String(),
    e.event,
    if (e.payloadKind != null) e.payloadKind!,
    if (e.bytes != null) '${e.bytes} B',
    if (e.detail != null) e.detail!,
  ];
  return parts.join(' · ');
}
