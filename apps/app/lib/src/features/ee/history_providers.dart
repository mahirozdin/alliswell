import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../auth/providers.dart';
import 'data/history_api.dart';
import 'data/history_models.dart';

/// History providers (EE-026). Server-only `AsyncValue` — the api_keys
/// pattern — because ADR-0005 keeps the audit log out of the sync protocol:
/// an unbounded log would poison every replica.

final eeHistoryApiProvider = Provider<EeHistoryApi>(
  (ref) => EeHistoryApi(ref.watch(apiClientProvider)),
);

/// Which entity a tab is showing. A record so the family key compares by
/// value: two tabs on the same entity share one request.
typedef EeHistoryTarget = ({String entityType, String entityId});

final eeHistoryProvider = FutureProvider.family<EeHistoryPage, EeHistoryTarget>(
  (ref, target) {
    return ref
        .watch(eeHistoryApiProvider)
        .forEntity(entityType: target.entityType, entityId: target.entityId);
  },
);

/// The team-wide feed's filters (EE-130). A record so the family key compares
/// by value: the same filters asked for twice are one request.
typedef EeAuditFilters = ({
  String? verb,
  String? entityType,
  DateTime? from,
  DateTime? to,
});

const eeAuditNoFilters = (
  verb: null,
  entityType: null,
  from: null,
  to: null,
);

final eeTeamAuditProvider =
    FutureProvider.family<EeHistoryPage, EeAuditFilters>((ref, filters) {
      return ref.watch(eeHistoryApiProvider).teamFeed(
        verb: filters.verb,
        entityType: filters.entityType,
        from: filters.from,
        to: filters.to,
      );
    });
