import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api_exception.dart';
import '../../core/kv/local_kv.dart';
import '../../core/reachability.dart';
import '../../sync/providers.dart';
import '../auth/providers.dart';
import '../workspaces/workspaces.dart';
import 'data/approvals_api.dart';
import 'data/approvals_models.dart';
import 'providers.dart';
import 'team_origin.dart';
import 'unit_tickets_providers.dart';

/// Approval providers (EE-184, EE-294).
///
/// A decision re-reads the whole list rather than patching the row out of it —
/// EE-099's idiom, and it earns its keep here: deciding one approval can
/// change ANOTHER row's meaning (the second signature on the same request is
/// now the only thing holding it), and a controller that removed one item
/// would leave the rest describing a world that had moved on.
final eeApprovalsApiProvider = Provider<EeApprovalsApi>(
  (ref) => EeApprovalsApi(ref.watch(apiClientProvider)),
);

// ── The badge and the door (EE-294) ─────────────────────────────────────────

const String kEeApprovalsDoorCachePrefix = 'alliswell_ee_approvals_door::';

String? _doorCacheKey(Ref ref) {
  final userId = ref.watch(currentUserIdProvider);
  final origin = ref.watch(teamOriginProvider);
  if (userId == null || origin == null) return null;
  return '$kEeApprovalsDoorCachePrefix$userId::${origin.slug}';
}

/// The last answer the server gave about the door — read before the network
/// answers, so a navigation entry that was there yesterday is there on this
/// launch's first frame rather than appearing a second later, and is still
/// there with no signal. A UI hint and nothing more: the server decides
/// every approval (ADR-0018), a stale "yes" costs an empty screen.
final _eeApprovalsDoorCacheProvider =
    FutureProvider.autoDispose<EeApprovalsSummary?>((ref) async {
      final key = _doorCacheKey(ref);
      if (key == null) return null;
      final raw = await localKv.get(key);
      if (raw == null) return null;
      try {
        final json = jsonDecode(raw) as Map<String, dynamic>;
        return EeApprovalsSummary(
          authority: json['authority'] == true,
          answersForRole: json['answersForRole'] == true,
          personal: 0,
          role: 0,
        );
      } catch (_) {
        return null;
      }
    });

/// How many `approval.requested` notifications the replica holds — only
/// ever read as a SIGNAL: when it moves, somebody asked somebody here for a
/// decision, and the badge asks the server again at once instead of waiting
/// for the next pull.
final _eeApprovalRequestsLandedProvider = StreamProvider.autoDispose<int>((
  ref,
) {
  final db = ref.watch(databaseProvider);
  final count = db.notifications.id.count();
  final query = db.selectOnly(db.notifications)
    ..addColumns([count])
    ..where(db.notifications.eventClass.equals('approval.requested'));
  return query.map((row) => row.read(count) ?? 0).watchSingle();
});

/// The summary the navigation draws from (EE-292's `GET /approvals/summary`):
/// whether this person has an Approvals door at all, whether they answer for
/// their role, and how many of each are waiting.
///
/// Asked again on every pull of the unit on screen (the heartbeat
/// `eeOtherUnitsAlertsProvider` rides — no Timer: a provider that owns one
/// breaks every suite that pumps its screen), whenever a new approval request
/// lands in the replica, and after this person decides or corrects one.
/// Quiet on every failure. With no signal it keeps the door (from the cache)
/// and drops the count — a number from an hour ago is not a number.
final eeApprovalsSummaryProvider =
    FutureProvider.autoDispose<EeApprovalsSummary>((ref) async {
      // The door exists only on a team's own address, and only where the
      // instance has teams — the same two questions the Requests tab asks
      // (EE-290), so a personal account and a plain server never draw it.
      final teams = ref.watch(eeFeatureProvider('teams'));
      if (!teams || ref.watch(teamOriginProvider) == null) {
        return EeApprovalsSummary.none;
      }
      // Every dependency is declared before the first await, so a rebuild is
      // always one of these moving and never a question asked mid-flight.
      final key = _doorCacheKey(ref);
      final offline = ref.watch(
        serverReachabilityProvider.select((up) => up == false),
      );
      ref.watch(eeCurrentUnitPulledAtProvider);
      ref.watch(_eeApprovalRequestsLandedProvider);
      final cached = ref.watch(_eeApprovalsDoorCacheProvider.future);
      final api = ref.watch(eeApprovalsApiProvider);
      if (offline) return await cached ?? EeApprovalsSummary.none;
      try {
        final fresh = await api.summary();
        if (key != null) {
          await localKv.set(
            key,
            jsonEncode({
              'authority': fresh.authority,
              'answersForRole': fresh.answersForRole,
            }),
          );
        }
        return fresh;
      } on ApiException {
        return await cached ?? EeApprovalsSummary.none;
      }
    });

/// Is there an Approvals entry to draw? The live answer when there is one,
/// the cached one before it arrives. Never `canProvider`: that says yes on a
/// workspace nothing governs (EE-282), and a door is drawn on a positive
/// answer, never on a default (DESIGN §32 S7).
final eeApprovalsDoorProvider = Provider.autoDispose<bool>((ref) {
  if (!ref.watch(eeFeatureProvider('teams'))) return false;
  if (ref.watch(teamOriginProvider) == null) return false;
  final live = ref.watch(eeApprovalsSummaryProvider).value;
  if (live != null) return live.authority;
  return ref.watch(_eeApprovalsDoorCacheProvider).value?.authority ?? false;
});

/// The number on the entry's badge: what names me plus what my role is
/// asked, that a decision can still change. Zero draws nothing.
final eeApprovalsBadgeProvider = Provider.autoDispose<int>(
  (ref) => ref.watch(eeApprovalsSummaryProvider).value?.total ?? 0,
);

// ── The screen's rows ──────────────────────────────────────────────────────

final eeApprovalsProvider =
    AsyncNotifierProvider<EeApprovalsController, List<EeApproval>>(
      EeApprovalsController.new,
    );

/// What is waiting on me — by name AND through my role — in one read: the
/// screen splits it into its two tabs by `addressedTo`, so the tabs and the
/// badge count the same rows the server counted.
class EeApprovalsController extends AsyncNotifier<List<EeApproval>> {
  @override
  Future<List<EeApproval>> build() async {
    if (!ref.watch(eeFeatureProvider('teams'))) return const [];
    return ref.watch(eeApprovalsApiProvider).list(status: 'pending');
  }

  /// Pull-to-refresh, and after anything this person changed.
  Future<void> refresh() async {
    ref.invalidate(eeApprovalsSummaryProvider);
    state = await AsyncValue.guard(
      () => ref.read(eeApprovalsApiProvider).list(status: 'pending'),
    );
  }

  /// Answers one, then re-reads. The reason is required here as well as on the
  /// server: a client that let it through empty would turn a 400 into the
  /// user's problem at the end of a form they already filled in.
  Future<void> decide(
    String id, {
    required bool approve,
    required String reason,
  }) async {
    await ref
        .read(eeApprovalsApiProvider)
        .decide(id, approve: approve, reason: reason);
    ref.invalidate(eeApprovalsOthersProvider);
    await refresh();
  }
}

/// The rest of the team's queue — waiting on somebody else — for the one
/// group under "Takımda" that keeps the old team-wide view (EE-184's
/// `scope=team`). Read only when that group is opened.
final eeApprovalsOthersProvider = FutureProvider.autoDispose<List<EeApproval>>((
  ref,
) async {
  if (!ref.watch(eeFeatureProvider('teams'))) return const [];
  final all = await ref.watch(eeApprovalsApiProvider).list(mine: false);
  return all
      .where((a) => a.addressedTo == 'other' && a.isPending && a.live)
      .toList(growable: false);
});

// ── One approval, whole (EE-295) ────────────────────────────────────────────

/// The approver's window onto one approval. Asked every time the screen
/// opens and after anything this person does to it; never with no signal —
/// a copy of somebody's request from before would be old words passing for
/// what they say now.
final eeApprovalDetailProvider = FutureProvider.autoDispose
    .family<EeApprovalDetail, String>((ref, id) async {
      if (ref.watch(serverReachabilityProvider.select((up) => up == false))) {
        throw const ApiException('NETWORK_ERROR', 'No connection');
      }
      return ref.watch(eeApprovalsApiProvider).detail(id);
    });

final eeApprovalActionsProvider = Provider<EeApprovalActions>(
  EeApprovalActions.new,
);

/// What the approver does from the window: correct the request, or answer.
/// Each re-reads what it moved — the window, the queue, the badge.
class EeApprovalActions {
  EeApprovalActions(this._ref);
  final Ref _ref;

  Future<EeApprovalDetail> correct(
    String id, {
    String? subject,
    String? body,
    Map<String, Object?>? answers,
  }) async {
    final detail = await _ref
        .read(eeApprovalsApiProvider)
        .correct(id, subject: subject, body: body, answers: answers);
    _ref.invalidate(eeApprovalDetailProvider(id));
    _ref.invalidate(eeApprovalsProvider);
    return detail;
  }

  Future<void> decide(
    String id, {
    required bool approve,
    required String reason,
  }) async {
    await _ref
        .read(eeApprovalsApiProvider)
        .decide(id, approve: approve, reason: reason);
    _ref.invalidate(eeApprovalDetailProvider(id));
    _ref.invalidate(eeApprovalsProvider);
    _ref.invalidate(eeApprovalsOthersProvider);
    _ref.invalidate(eeApprovalsSummaryProvider);
  }
}
