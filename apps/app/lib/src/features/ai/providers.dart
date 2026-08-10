import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/kv/local_kv.dart';
import '../../sync/providers.dart';
import '../auth/providers.dart';
import '../workspaces/workspaces.dart';
import 'data/ai_api.dart';
import 'data/ai_messages_store.dart';
import 'data/ai_models.dart';

/// AI feature providers (OPH-220). The status gate is the app's single
/// surface-withdrawal switch; consent is device-local per user+provider.

final aiApiProvider = Provider<AiApi>(
  (ref) => AiApi(ref.watch(apiClientProvider)),
);

/// Device-local AI chat history (OPH-221) — never synced.
final aiMessagesStoreProvider = Provider<AiMessagesStore>(
  (ref) => AiMessagesStore(ref.watch(databaseProvider)),
);

const String _kAiStatusCachePrefix = 'alliswell_ai_status::';
const String _kAiConsentPrefix = 'alliswell_ai_consent::';

/// Whether AI surfaces are reachable, cached in localKv so a fresh launch has
/// a last-known truth before the network answers (no flicker, honest offline).
final aiStatusProvider = AsyncNotifierProvider<AiStatusController, AiStatus>(
  AiStatusController.new,
);

class AiStatusController extends AsyncNotifier<AiStatus> {
  String? _cacheKey;

  @override
  Future<AiStatus> build() async {
    final userId = ref.watch(currentUserIdProvider);
    if (userId == null) return AiStatus.disabled;
    // OPH-243: the cache key is assigned and READ before the workspace guard,
    // not after it. The old order made the doc comment above a lie — a cold
    // start resolved to `disabled` while `currentWorkspaceProvider` was still
    // loading, the cache was never consulted, and something reads this on the
    // very first frame (the AI FAB does), so the placeholder stuck. A share
    // arriving in that window is exactly a cold start, so an AI user's share
    // went to the no-AI branch. "We have no workspace yet" and "this user has
    // no AI" are different facts and the cache is the only one that can tell
    // them apart before the network answers.
    _cacheKey = '$_kAiStatusCachePrefix$userId';
    final workspace = ref.watch(currentWorkspaceProvider).value;
    if (workspace == null) return await _readCache() ?? AiStatus.disabled;

    final cached = await _readCache();
    try {
      final fresh = await ref.read(aiApiProvider).status(workspace.id);
      await _writeCache(fresh);
      return fresh;
    } catch (_) {
      // Keep the last-known truth offline; surfaces stay withdrawn until one
      // successful check if we have never seen it.
      return cached ?? AiStatus.disabled;
    }
  }

  Future<void> refresh() async {
    state = await AsyncValue.guard(build);
  }

  Future<AiStatus?> _readCache() async {
    if (_cacheKey == null) return null;
    final raw = await localKv.get(_cacheKey!);
    if (raw == null) return null;
    try {
      return AiStatus.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } catch (_) {
      return null;
    }
  }

  Future<void> _writeCache(AiStatus status) async {
    if (_cacheKey != null) {
      await localKv.set(_cacheKey!, jsonEncode(status.toJson()));
    }
  }
}

/// The caller's own connections, in the current workspace.
final aiConnectionsProvider = FutureProvider<List<AiConnection>>((ref) async {
  final workspace = ref.watch(currentWorkspaceProvider).value;
  if (workspace == null) return const [];
  return ref.watch(aiApiProvider).connections(workspace.id);
});

/// The model catalog for one connection (or the default resolution).
final aiModelsProvider = FutureProvider.family<AiModelCatalog, String>((
  ref,
  connectionId,
) async {
  final workspace = ref.watch(currentWorkspaceProvider).value;
  if (workspace == null) {
    return const AiModelCatalog(chat: [], fast: []);
  }
  return ref
      .watch(aiApiProvider)
      .models(workspace.id, connectionId: connectionId);
});

/// Device-local consent, per user + provider (AI.md §7). It discloses what
/// leaves THIS device, so per-device first-use is the honest granularity; it
/// also covers instance_env mode where the user owns no connection row.
final aiConsentProvider =
    NotifierProvider<AiConsentController, Map<String, bool>>(
      AiConsentController.new,
    );

class AiConsentController extends Notifier<Map<String, bool>> {
  @override
  Map<String, bool> build() {
    return const {};
  }

  String _key(String provider) {
    final userId = ref.read(currentUserIdProvider) ?? 'anon';
    return '$_kAiConsentPrefix$userId::$provider';
  }

  /// Reads (and caches) whether this user has consented for `provider`.
  Future<bool> has(String provider) async {
    final key = _key(provider);
    if (state.containsKey(key)) return state[key]!;
    final stored = (await localKv.get(key)) == 'true';
    state = {...state, key: stored};
    return stored;
  }

  bool hasCached(String provider) => state[_key(provider)] ?? false;

  Future<void> grant(String provider) async {
    final key = _key(provider);
    state = {...state, key: true};
    await localKv.set(key, 'true');
  }
}
