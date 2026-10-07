import 'dart:convert';

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
    bool? owned,
  }) : owned = owned ?? role == 'owner',
       reportsOwnership = owned != null;

  factory WorkspaceSummary.fromJson(Map<String, dynamic> json) =>
      WorkspaceSummary(
        id: json['id'] as String,
        name: json['name'] as String,
        slug: json['slug'] as String,
        colorRgb: (json['colorRgb'] as String?) ?? '#2563EB',
        icon: json['icon'] as String?,
        role: json['role'] as String,
        owned: json['owned'] as bool?,
      );

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'slug': slug,
    'colorRgb': colorRgb,
    'icon': icon,
    'role': role,
    // Only what the server said: a cached guess read back would claim a
    // server that never sent the field did (see [reportsOwnership]).
    if (reportsOwnership) 'owned': owned,
  };

  final String id;
  final String name;
  final String slug;
  final String colorRgb;
  final String? icon;
  final String role;

  /// Whether this account OWNS the workspace (`/me` → `owned`). Not the same
  /// question as [role] `owner`, which a member can hold in a workspace an
  /// organisation created — the client decides which space is the person's own
  /// from this, never from the list's order.
  ///
  /// When it is not given — a server from before the field, or a summary built
  /// by hand — `role: owner` stands in for it: before organisations that was
  /// the one workspace an account could hold that role in.
  final bool owned;

  /// Whether [owned] came from the server rather than from [role]. A server
  /// that sends it also sends who made each task (`createdBy`), the fact
  /// "made by me" reads — see `repullOnceForCreatedBy`.
  final bool reportsOwnership;
}

const String kWorkspacesCachePrefix = 'alliswell_me_workspaces::';

/// The signed-in user's workspaces. Re-fetches whenever the session changes;
/// empty while signed out.
///
/// The last good answer is kept per user, and an offline start reads it: the
/// list decides WHICH workspaces the person's lists and the sync engines cover,
/// and a device that forgot it at every cold start without signal would open
/// onto nothing while its replica held everything.
final workspacesProvider = FutureProvider<List<WorkspaceSummary>>((ref) async {
  final session = ref.watch(authControllerProvider).value;
  if (session == null) return const [];
  final key = '$kWorkspacesCachePrefix${session.user.id}';
  final dio = ref.watch(apiClientProvider);
  try {
    final res = await dio.get<Map<String, dynamic>>('/api/v1/me');
    final list = (res.data?['workspaces'] as List?) ?? const [];
    final workspaces = list
        .map((w) => WorkspaceSummary.fromJson(w as Map<String, dynamic>))
        .toList();
    await localKv.set(
      key,
      jsonEncode([for (final w in workspaces) w.toJson()]),
    );
    return workspaces;
  } on DioException catch (e) {
    // A passing failure falls back to the last list: no answer at all (offline,
    // a timeout), a rate limit or a server error (UI-AUDIT #27 — a 429 at a
    // busy shift change used to blank Home and drop the unit switcher while
    // the replica held everything). An answer that MEANS something — a revoked
    // session, a deleted account, a refused request — is never papered over.
    if (isTransientMeFailure(e)) {
      final cached = await readCachedWorkspaces(session.user.id);
      if (cached != null) return cached;
    }
    throw asApiException(e);
  }
});

/// Whether a failed `/me` says nothing about the account — the network or the
/// server stumbled — so the last known list still stands. 401/403/404 and the
/// rest of 4xx are answers about the account and are not transient.
bool isTransientMeFailure(DioException e) {
  final status = e.response?.statusCode;
  if (status == null) return true;
  return status == 408 || status == 429 || status >= 500;
}

/// The last `/me` list this device saw for [userId], or null — also what a
/// background turn reads, since it has no provider graph and no network promise.
Future<List<WorkspaceSummary>?> readCachedWorkspaces(String userId) async {
  final raw = await localKv.get('$kWorkspacesCachePrefix$userId');
  if (raw == null) return null;
  try {
    return [
      for (final w in jsonDecode(raw) as List)
        WorkspaceSummary.fromJson(w as Map<String, dynamic>),
    ];
  } catch (_) {
    return null;
  }
}

/// Workspaces this account works in but does not own — an organisation's.
///
/// Empty for a person using the app on their own (their one workspace is
/// theirs). When it is not empty the account is a member's account: the
/// person's lists gather their work from all of these, the content screens
/// show the one selected among them, and the workspace the account owns is
/// kept out of every list (it only carries unsent drafts — see
/// `draftWorkspaceIdProvider`).
List<WorkspaceSummary> sharedWorkspacesOf(List<WorkspaceSummary> all) => [
  for (final w in all)
    if (!w.owned) w,
];

final sharedWorkspacesProvider = Provider<List<WorkspaceSummary>>(
  (ref) => sharedWorkspacesOf(ref.watch(workspacesProvider).value ?? const []),
);

/// True when the account works in an organisation's workspaces (see
/// [sharedWorkspacesOf]). False while loading and for a person on their own.
final inSharedWorkspacesProvider = Provider<bool>(
  (ref) => ref.watch(sharedWorkspacesProvider).isNotEmpty,
);

/// The unit a row of the person's own list comes from, by workspace id —
/// the label under a task on Home when the person works in several of an
/// organisation's units (EE-296). Empty otherwise: with one unit, or on one's
/// own, every row would carry the same word, and a label that never changes
/// says nothing.
final unitLabelsProvider = Provider<Map<String, String>>((ref) {
  final shared = ref.watch(sharedWorkspacesProvider);
  if (shared.length < 2) return const {};
  return {for (final w in shared) w.id: w.name};
});

/// The workspace this account owns, or null.
final ownWorkspaceProvider = Provider<WorkspaceSummary?>((ref) {
  for (final w in ref.watch(workspacesProvider).value ?? const []) {
    if (w.owned) return w;
  }
  return null;
});

/// The workspaces the switcher offers: an organisation's when the account
/// works in one, otherwise every workspace it has.
List<WorkspaceSummary> switchableWorkspacesOf(List<WorkspaceSummary> all) {
  final shared = sharedWorkspacesOf(all);
  return shared.isEmpty ? all : shared;
}

/// Where [SelectedWorkspace] keeps its choice, one key per user.
const String kSelectedWorkspacePrefix = 'alliswell_selected_workspace::';

/// Which workspace this person last chose — persisted, and keyed PER USER.
///
/// One device serves two people (the permission cache learned this first), so
/// a single global key would hand the second person the first one's choice.
/// Null means "not chosen yet", which is not the same as "chose the first
/// one": the fallback below has to keep working for somebody who never picked.
class SelectedWorkspace extends Notifier<String?> {
  String? _key(String? userId) =>
      userId == null ? null : '$kSelectedWorkspacePrefix$userId';

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

/// The workspace the content screens read and the switcher shows as chosen —
/// so switching is one provider changing.
///
/// EE-061 lifted the v1 constraint that lived here as `list.first`. What
/// replaced it is deliberately forgiving in one direction: an unknown or
/// vanished selection falls back to the first workspace rather than resolving
/// to null. That case is not hypothetical — losing a unit removes a workspace
/// from this list (EE-058), and a person whose selected unit was revoked must
/// land somewhere, not on an empty app.
///
/// It chooses among [switchableWorkspacesOf]: in an organisation's workspaces
/// the one the account owns is never "current" — there is nothing of the
/// person's own to show there.
final currentWorkspaceProvider = Provider<AsyncValue<WorkspaceSummary?>>((ref) {
  final selected = ref.watch(selectedWorkspaceIdProvider);
  return ref.watch(workspacesProvider).whenData((all) {
    final list = switchableWorkspacesOf(all);
    if (list.isEmpty) return null;
    if (selected == null) return list.first;
    return list.firstWhere((w) => w.id == selected, orElse: () => list.first);
  });
});

/// The id the content screens read and write in (notes, projects, files, tags,
/// quick access, a task's create sheet): the current workspace, awaited — a
/// screen must not draw "nothing here" while the list is still loading.
///
/// For a person on their own this is their one workspace, exactly the
/// `workspaces.first` every one of these read before; in an organisation it is
/// the one selected in the switcher.
final activeWorkspaceIdProvider = FutureProvider<String?>((ref) async {
  await ref.watch(workspacesProvider.future);
  return ref.watch(currentWorkspaceProvider).value?.id;
});

/// The signed-in user's id, or null while signed out / restoring (OPH-198).
///
/// Quick Access is the protocol's first user-scoped entity (ADR-0018), so it
/// is the first feature that needs to know WHO is signed in: the replica
/// outlives a sign-out, and one device can serve two people.
final currentUserIdProvider = Provider<String?>(
  (ref) => ref.watch(authControllerProvider).value?.user.id,
);
