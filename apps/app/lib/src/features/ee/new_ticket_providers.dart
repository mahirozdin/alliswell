import 'dart:async';

import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../sync/providers.dart';
import '../../sync/sync_engine.dart';
import '../auth/providers.dart';
import '../workspaces/workspaces.dart';
import 'data/kb_models.dart';
import 'data/new_ticket_api.dart';
import 'kb_providers.dart';
import 'providers.dart';

/// Filing a request from the app (EE-225).
final eeNewTicketApiProvider = Provider<EeNewTicketApi>(
  (ref) => EeNewTicketApi(ref.watch(apiClientProvider)),
);

/// What this desk can be asked for — kept for the SESSION, not per screen.
///
/// A person who opened the form with signal and lost it half way down still
/// has the list they were choosing from: the offline path files a draft, and
/// a draft that names its service converts the moment it arrives. Asked again
/// only on an explicit refresh (pull-to-refresh on the form).
final eeCatalogProvider = FutureProvider<EeCatalog?>((ref) async {
  if (!ref.watch(eeFeatureProvider('teams'))) return null;
  return ref.watch(eeNewTicketApiProvider).catalog();
});

/// EE-226 — published answers for the subject being typed.
///
/// From the SERVER, and that is measured rather than chosen: an article lives
/// in the workspace of the unit that wrote it, and somebody asking the desk is
/// not in that unit — EE-196's device search has nothing to look through on
/// their phone. The form only asks while it has signal, and says so when it
/// does not, so "no answers" never stands in for "no network".
///
/// Three characters before asking: a single letter matches half the
/// knowledge base, and a list that jumps under every keystroke is noise.
final eeKbAnswersForProvider = FutureProvider.autoDispose
    .family<List<EeKbSuggestion>, String>((ref, query) async {
      final words = query.trim();
      if (words.length < 3) return const [];
      if (!ref.watch(eeFeatureProvider('teams'))) return const [];
      return ref.watch(eeKbApiProvider).suggestions(words);
    });

/// Where this person's drafts live (EE-216, EE-243): their OWN workspace.
///
/// The server refuses a draft anywhere else — a unit's workspace would carry
/// it to every agent in the unit — and the membership role on `/me` names the
/// right one: team workspaces are owned by the team's service identity, so
/// `owner` marks exactly the person's own space. Null when there is none to
/// name, and the form then says a draft cannot be kept on this device.
final draftWorkspaceIdProvider = Provider<String?>((ref) {
  final workspaces = ref.watch(workspacesProvider).value ?? const [];
  for (final workspace in workspaces) {
    if (workspace.role == 'owner') return workspace.id;
  }
  return null;
});

/// Draft writes still in a workspace's outbox.
final pendingDraftWritesProvider = StreamProvider.family<int, String>((
  ref,
  workspaceId,
) {
  final db = ref.watch(databaseProvider);
  return (db.select(db.pendingMutations)..where(
        (m) =>
            m.workspaceId.equals(workspaceId) &
            m.entityType.equals('ee_ticket_draft'),
      ))
      .watch()
      .map((rows) => rows.length);
});

/// EE-225 — the courier for drafts written away from the workspace on screen.
///
/// The sync engine runs ONE workspace, the one on screen, and a draft lives
/// in the author's own workspace. For a requester those are the same place.
/// For an agent working in their unit they are not, and without this the
/// draft would wait on the phone until they happened to switch to their own
/// space — the opposite of "it goes when the signal comes back", which is the
/// whole feature.
///
/// So while that workspace holds draft writes and is not the one on screen, a
/// second engine runs for it: it pushes, and the same round pulls the
/// tombstone of every draft the server converted. When the outbox is empty
/// the engine is dropped. It follows the outbox only across ZERO (`select`),
/// so a draft landing while another is in flight does not restart it.
final draftCourierProvider = Provider<SyncEngine?>((ref) {
  final own = ref.watch(draftWorkspaceIdProvider);
  final current = ref.watch(currentWorkspaceProvider).value?.id;
  if (own == null || own == current) return null;
  final waiting = ref.watch(
    pendingDraftWritesProvider(own).select((count) => (count.value ?? 0) > 0),
  );
  if (!waiting) return null;
  final engine = SyncEngine(
    db: ref.watch(databaseProvider),
    api: ref.watch(syncApiProvider),
    workspaceId: own,
    pullInterval: ref.watch(syncPullIntervalProvider),
    debounce: ref.watch(syncDebounceProvider),
  );
  ref.onDispose(engine.dispose);
  unawaited(engine.start());
  return engine;
});
