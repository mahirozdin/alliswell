import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api_exception.dart';
import '../../core/reachability.dart';
import '../auth/providers.dart';
import 'providers.dart';
import 'ticket_tag_names.dart';
import 'tickets_providers.dart';

export 'ticket_tag_names.dart';

/// Request tags on the device (EE-235).
///
/// ── READ FROM THE REPLICA, WRITTEN OVER REST ─────────────────────────────
///
/// The words a request carries ride on its row (`tickets.tag_names`, OPH-350),
/// so the chips on the detail and the queue's tag filter work with no signal.
/// Putting a word on or taking one off is a WRITE, and request writes are
/// online (the rule EE-223 set for every door onto a request): no queue, the
/// buttons grey out with a reason. After a write the engine is poked, and the
/// next pull brings the row down with the new list.

/// One word of the team's vocabulary.
class EeTagWord {
  const EeTagWord({required this.id, required this.name, this.uses = 0});

  factory EeTagWord.fromJson(Map<String, dynamic> json) => EeTagWord(
    id: json['id'] as String,
    name: json['name'] as String,
    uses: (json['uses'] as num?)?.toInt() ?? 0,
  );

  final String id;
  final String name;
  final int uses;
}

class EeTicketTagsApi {
  EeTicketTagsApi(this._dio);

  final Dio _dio;

  /// The team's words, with how many requests carry each.
  Future<List<EeTagWord>> vocabulary() async {
    try {
      final res = await _dio.get<Map<String, dynamic>>(
        '/api/v1/ee/team/ticket-tags',
      );
      return [
        for (final row
            in ((res.data?['tags'] as List?) ?? const [])
                .cast<Map<String, dynamic>>())
          EeTagWord.fromJson(row),
      ];
    } on DioException catch (e) {
      throw asApiException(e);
    }
  }

  /// The request's words after the change, as the server now holds them.
  Future<List<EeTagWord>> tag(String ticketId, String name) async {
    try {
      final res = await _dio.post<Map<String, dynamic>>(
        '/api/v1/ee/team/tickets/$ticketId/tags',
        data: {'name': name},
      );
      return [
        for (final row
            in ((res.data?['tags'] as List?) ?? const [])
                .cast<Map<String, dynamic>>())
          EeTagWord.fromJson(row),
      ];
    } on DioException catch (e) {
      throw asApiException(e);
    }
  }

  Future<void> untag(String ticketId, String tagId) async {
    try {
      await _dio.delete<void>('/api/v1/ee/team/tickets/$ticketId/tags/$tagId');
    } on DioException catch (e) {
      throw asApiException(e);
    }
  }
}

final eeTicketTagsApiProvider = Provider<EeTicketTagsApi>(
  (ref) => EeTicketTagsApi(ref.watch(apiClientProvider)),
);

/// The team's vocabulary — what the "add a tag" box suggests, and how a word
/// on a chip is turned back into the id the server removes it by.
///
/// Asked only while the server is reachable (a known-offline device asks
/// nothing, EE-271's rule for a read that retries), and never without the
/// licence: no extension, no capability.
final eeTagVocabularyProvider = FutureProvider.autoDispose<List<EeTagWord>>((
  ref,
) async {
  if (!ref.watch(eeFeatureProvider('teams'))) return const [];
  if (ref.watch(serverReachabilityProvider.select((up) => up == false))) {
    return const [];
  }
  return ref.watch(eeTicketTagsApiProvider).vocabulary();
});

/// Every word on this desk's requests, as the device holds them — the queue
/// filter's choices, with no signal. Each word once (by the server's fold),
/// in a stable order.
final queueTagNamesProvider = Provider<List<String>>((ref) {
  final rows = ref.watch(ticketQueueProvider).value ?? const [];
  final seen = <String, String>{};
  for (final row in rows) {
    for (final name in decodeTagNames(row.tagNames)) {
      seen.putIfAbsent(foldTag(name), () => name);
    }
  }
  final keys = seen.keys.toList()..sort();
  return [for (final key in keys) seen[key]!];
});
