import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../auth/providers.dart';
import '../workspaces/workspaces.dart';
import 'data/api_key_models.dart';
import 'data/api_keys_api.dart';

/// API-key providers (OPH-265). An ONLINE surface, on purpose: the list is
/// fetched when the screen opens and never cached in the drift replica — a
/// device that has been offline for a week should not be showing a confident
/// list of credentials that may all have been revoked since.

final apiKeysApiProvider = Provider<ApiKeysApi>(
  (ref) => ApiKeysApi(ref.watch(apiClientProvider)),
);

/// The current workspace's keys. Refetches on invalidate — every mutation
/// invalidates rather than patching a local list, so what the screen shows is
/// always what the server just said.
///
/// The workspace is read through its ERROR, not through `.value`: an
/// unreachable server makes the workspace lookup fail too, and `.value` would
/// quietly turn that into `null` → an empty list → a screen saying "no keys
/// yet". That sentence is a claim about the server, and on a failed load we
/// have not heard from it. Rethrowing keeps the screen honest (the test that
/// caught this is the one that asserts the empty state is absent offline).
final apiKeysProvider = FutureProvider<List<ApiKey>>((ref) async {
  final workspace = ref.watch(currentWorkspaceProvider);
  if (workspace.hasError) {
    Error.throwWithStackTrace(workspace.error!, workspace.stackTrace!);
  }
  final current = workspace.value;
  if (current == null) return const [];
  return ref.watch(apiKeysApiProvider).list(current.id);
});
