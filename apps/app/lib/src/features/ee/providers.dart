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

const String _kEePermissionsCachePrefix = 'alliswell_ee_permissions::';

/// What the signed-in person may do in the CURRENT workspace (EE-052).
///
/// Same shape as [eeStatusProvider] one scope down, and cached in localKv for
/// the same reason: a screen must be able to draw itself before the network
/// answers, and it must draw the same thing it drew last time rather than
/// flickering between "allowed" and "not".
///
/// The cache is a UI HINT and nothing more. The server decides every actual
/// write (ADR-0007 §5), so a stale cache costs a refused request and a
/// message, never an unauthorised change. That is what makes it safe to trust
/// a value that may be minutes old — and why there is no invalidation
/// protocol here either.
final eePermissionsProvider =
    AsyncNotifierProvider<EePermissionsController, EePermissions>(
      EePermissionsController.new,
    );

class EePermissionsController extends AsyncNotifier<EePermissions> {
  String? _cacheKey;

  @override
  Future<EePermissions> build() async {
    final userId = ref.watch(currentUserIdProvider);
    if (userId == null) return EePermissions.unknown;
    // AWAITED, not read: `currentWorkspaceProvider` is a synchronous view over
    // an async list, so reading `.value` here answers null on the first build
    // — and null would be cached as "ungoverned" before the workspace even
    // arrived. Awaiting the future is the difference between asking and
    // guessing.
    final workspaces = await ref.watch(workspacesProvider.future);
    if (workspaces.isEmpty) return EePermissions.unknown;
    final workspaceId = workspaces.first.id;
    // Keyed per user AND per workspace: one device serves two people, and one
    // person can hold different roles in different workspaces.
    _cacheKey = '$_kEePermissionsCachePrefix$userId::$workspaceId';
    final cached = await _readCache();
    try {
      final fresh = await ref.read(eeApiProvider).myPermissions(workspaceId);
      await _writeCache(fresh);
      return fresh;
    } catch (_) {
      // Offline keeps the last known answer. With no cache at all the honest
      // fallback is UNGOVERNED — a first launch with no network must not
      // present a crippled app to somebody who has every right to use it.
      return cached ?? EePermissions.unknown;
    }
  }

  Future<void> refresh() async {
    state = await AsyncValue.guard(build);
  }

  Future<EePermissions?> _readCache() async {
    if (_cacheKey == null) return null;
    final raw = await localKv.get(_cacheKey!);
    if (raw == null) return null;
    try {
      return EePermissions.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } catch (_) {
      return null;
    }
  }

  Future<void> _writeCache(EePermissions permissions) async {
    if (_cacheKey != null) {
      await localKv.set(_cacheKey!, jsonEncode(permissions.toJson()));
    }
  }
}

/// `ref.watch(canProvider('tasks.create'))` — the one question a screen asks.
///
/// Answers TRUE while loading and while signed out, and that default is
/// deliberate: this gate exists to remove a button somebody genuinely may not
/// press, not to make the app unusable for a second on every launch. A wrong
/// TRUE costs one refused request with a clear message; a wrong FALSE is a
/// feature that silently is not there.
final canProvider = Provider.family<bool, String>(
  (ref, permission) =>
      ref.watch(eePermissionsProvider).value?.can(permission) ?? true,
);
