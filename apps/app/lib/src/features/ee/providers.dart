import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/kv/local_kv.dart';
import '../auth/providers.dart';
import '../workspaces/workspaces.dart';
import 'data/ee_api.dart';
import 'data/ee_models.dart';

/// Instance entitlement providers (EE-008): the aiStatus pattern one level up
/// — instance-wide instead of workspace-scoped. No screen or route consults
/// these yet; surfaces arrive with their own features and watch
/// [eeFeatureProvider] as their withdrawal switch.

final eeApiProvider = Provider<EeApi>(
  (ref) => EeApi(ref.watch(apiClientProvider)),
);

const String _kEeStatusCachePrefix = 'alliswell_ee_status::';

/// What this instance is licensed for, cached in localKv so a fresh launch
/// has a last-known truth before the network answers (no flicker, honest
/// offline) — the aiStatus precedent, minus the workspace guard: entitlements
/// are instance state, so only the signed-in user is needed.
final eeStatusProvider = AsyncNotifierProvider<EeStatusController, EeStatus>(
  EeStatusController.new,
);

class EeStatusController extends AsyncNotifier<EeStatus> {
  String? _cacheKey;

  @override
  Future<EeStatus> build() async {
    final userId = ref.watch(currentUserIdProvider);
    if (userId == null) return EeStatus.none;
    // Keyed per user, not per instance: one device can serve two people, and
    // "signed out" must never inherit the previous account's capability list.
    _cacheKey = '$_kEeStatusCachePrefix$userId';
    final cached = await _readCache();
    try {
      final fresh = await ref.read(eeApiProvider).status();
      await _writeCache(fresh);
      return fresh;
    } catch (_) {
      // Offline keeps the last-known truth; surfaces stay withdrawn until one
      // successful check if we have never seen this instance.
      return cached ?? EeStatus.none;
    }
  }

  Future<void> refresh() async {
    state = await AsyncValue.guard(build);
  }

  Future<EeStatus?> _readCache() async {
    if (_cacheKey == null) return null;
    final raw = await localKv.get(_cacheKey!);
    if (raw == null) return null;
    try {
      return EeStatus.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } catch (_) {
      return null;
    }
  }

  Future<void> _writeCache(EeStatus status) async {
    if (_cacheKey != null) {
      await localKv.set(_cacheKey!, jsonEncode(status.toJson()));
    }
  }
}

/// The surface-withdrawal switch for one feature:
/// `ref.watch(eeFeatureProvider('teams'))`. Answers false while loading,
/// signed out, or offline with no cache — a surface may only exist on a yes.
final eeFeatureProvider = Provider.family<bool, String>(
  (ref, feature) => ref.watch(eeStatusProvider).value?.has(feature) ?? false,
);
