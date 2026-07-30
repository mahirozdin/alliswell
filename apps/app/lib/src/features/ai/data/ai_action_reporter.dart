import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/kv/local_kv.dart';
import '../providers.dart';
import 'ai_api.dart';

/// Best-effort accept reporting (OPH-222). The server logged the proposal at
/// extract time; acceptance is reported here. Offline accept must still work,
/// so a report is queued in localKv, attempted immediately, and drained on the
/// next opportunity. The endpoint is idempotent, so retries are safe.
///
/// The honest guarantee: a local wipe loses the queued report and the server
/// row stays "proposed, unconfirmed" — accuracy degrades to under-claiming,
/// never to a lie.
const String _kPendingActions = 'alliswell_ai_pending_actions';

final aiActionReporterProvider = Provider<AiActionReporter>(
  (ref) => AiActionReporter(ref.watch(aiApiProvider)),
);

class AiActionReporter {
  AiActionReporter(this._api);
  final AiApi _api;

  /// Reports acceptance now; queues it if the call fails.
  Future<void> reportAccept(
    String actionId, {
    List<Map<String, String>> entityRefs = const [],
  }) async {
    try {
      await _api.decideAction(actionId, accepted: true, entityRefs: entityRefs);
    } catch (_) {
      await _enqueue(actionId, entityRefs);
    }
  }

  /// Reports a rejection (fire-and-forget — a lost reject only under-claims).
  Future<void> reportReject(String actionId) async {
    try {
      await _api.decideAction(actionId, accepted: false);
    } catch (_) {
      // A rejection that never reaches the server just stays "proposed".
    }
  }

  /// Retries every queued accept; keeps the ones that still fail.
  Future<void> drain() async {
    final queue = await _readQueue();
    if (queue.isEmpty) return;
    final remaining = <Map<String, dynamic>>[];
    for (final item in queue) {
      try {
        await _api.decideAction(
          item['actionId'] as String,
          accepted: true,
          entityRefs: (item['entityRefs'] as List)
              .map((e) => (e as Map).cast<String, String>())
              .toList(),
        );
      } catch (_) {
        remaining.add(item);
      }
    }
    await _writeQueue(remaining);
  }

  Future<void> _enqueue(
    String actionId,
    List<Map<String, String>> entityRefs,
  ) async {
    final queue = await _readQueue();
    queue.add({'actionId': actionId, 'entityRefs': entityRefs});
    await _writeQueue(queue);
  }

  Future<List<Map<String, dynamic>>> _readQueue() async {
    final raw = await localKv.get(_kPendingActions);
    if (raw == null) return [];
    try {
      return (jsonDecode(raw) as List).cast<Map<String, dynamic>>();
    } catch (_) {
      return [];
    }
  }

  Future<void> _writeQueue(List<Map<String, dynamic>> queue) =>
      localKv.set(_kPendingActions, jsonEncode(queue));
}
