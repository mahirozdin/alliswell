import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/kv/local_kv.dart';

import '../../core/api_exception.dart';
import '../auth/providers.dart';

/// A workspace as returned by `GET /api/v1/me` (id + display data + my role).
class WorkspaceSummary {
  const WorkspaceSummary({
    required this.id,
    required this.name,
    required this.slug,
    required this.colorRgb,
    required this.role,
    this.icon,
  });

  factory WorkspaceSummary.fromJson(Map<String, dynamic> json) =>
      WorkspaceSummary(
        id: json['id'] as String,
        name: json['name'] as String,
        slug: json['slug'] as String,
        colorRgb: (json['colorRgb'] as String?) ?? '#2563EB',
        icon: json['icon'] as String?,
        role: json['role'] as String,
      );

  final String id;
  final String name;
  final String slug;
  final String colorRgb;
  final String? icon;
  final String role;
}

/// The signed-in user's workspaces. Re-fetches whenever the session changes;
/// empty while signed out.
final workspacesProvider = FutureProvider<List<WorkspaceSummary>>((ref) async {
  final session = ref.watch(authControllerProvider).value;
  if (session == null) return const [];
  final dio = ref.watch(apiClientProvider);
  try {
    final res = await dio.get<Map<String, dynamic>>('/api/v1/me');
    final list = (res.data?['workspaces'] as List?) ?? const [];
    return list
        .map((w) => WorkspaceSummary.fromJson(w as Map<String, dynamic>))
        .toList();
  } on DioException catch (e) {
    throw asApiException(e);
  }
});

/// Which workspace this person last chose — persisted, and keyed PER USER.
///
/// One device serves two people (the permission cache learned this first), so
/// a single global key would hand the second person the first one's choice.
/// Null means "not chosen yet", which is not the same as "chose the first
/// one": the fallback below has to keep working for somebody who never picked.
class SelectedWorkspace extends Notifier<String?> {
  static const _prefix = 'alliswell_selected_workspace';

  String? _key(String? userId) => userId == null ? null : '$_prefix::$userId';

  @override
  String? build() {
    _hydrate(_key(ref.watch(currentUserIdProvider)));
    return null;
  }

  Future<void> _hydrate(String? key) async {
    if (key == null) return;
    final stored = await localKv.get(key);
    // The list may already have moved on (a fast switch, a sign-out): only
    // adopt the stored value if nothing newer has been chosen.
    if (stored != null && state == null) state = stored;
  }

  Future<void> select(String workspaceId) async {
    state = workspaceId;
    final key = _key(ref.read(currentUserIdProvider));
    if (key != null) await localKv.set(key, workspaceId);
  }
}

final selectedWorkspaceIdProvider =
    NotifierProvider<SelectedWorkspace, String?>(SelectedWorkspace.new);

/// The workspace everything else reads (16 call sites) — so switching is one
/// provider changing, and the sync engine follows because it WATCHES this.
///
/// EE-061 lifted the v1 constraint that lived here as `list.first`. What
/// replaced it is deliberately forgiving in one direction: an unknown or
/// vanished selection falls back to the first workspace rather than resolving
/// to null. That case is not hypothetical — losing a unit removes a workspace
/// from this list (EE-058), and a person whose selected unit was revoked must
/// land somewhere, not on an empty app.
final currentWorkspaceProvider = Provider<AsyncValue<WorkspaceSummary?>>((ref) {
  final selected = ref.watch(selectedWorkspaceIdProvider);
  return ref.watch(workspacesProvider).whenData((list) {
    if (list.isEmpty) return null;
    if (selected == null) return list.first;
    return list.firstWhere((w) => w.id == selected, orElse: () => list.first);
  });
});

/// The signed-in user's id, or null while signed out / restoring (OPH-198).
///
/// Quick Access is the protocol's first user-scoped entity (ADR-0018), so it
/// is the first feature that needs to know WHO is signed in: the replica
/// outlives a sign-out, and one device can serve two people.
final currentUserIdProvider = Provider<String?>(
  (ref) => ref.watch(authControllerProvider).value?.user.id,
);
