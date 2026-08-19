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
