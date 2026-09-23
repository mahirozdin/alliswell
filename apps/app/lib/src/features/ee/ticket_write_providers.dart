import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/reachability.dart';
import '../auth/providers.dart';
import 'data/ticket_write_api.dart';
import 'providers.dart';
import 'tickets_providers.dart';

/// Writing on a request (EE-223) — REST, online by decision (E19).
final eeTicketWriteApiProvider = Provider<EeTicketWriteApi>(
  (ref) => EeTicketWriteApi(ref.watch(apiClientProvider)),
);

/// The desk's saved replies, rendered against one request (EE-201, EE-223).
///
/// Read when the composer opens its list, not with the screen: most replies
/// are typed, and a request per detail screen for a list most people never
/// open would be traffic spent on nothing. An unlicensed or unreachable desk
/// answers "none", and the list says so.
final eeCannedRepliesProvider = FutureProvider.autoDispose
    .family<List<EeCannedReply>, String>((ref, ticketId) async {
      if (!ref.watch(eeFeatureProvider('teams'))) return const [];
      return ref.watch(eeTicketWriteApiProvider).cannedReplies(ticketId);
    });

/// What this caller may do to one request, as the server says (EE-224).
///
/// Asked again whenever the device's copy of the request moves — a pull that
/// brought somebody else's status change makes the last answer stale, and a
/// screen offering a move from a state the request has left is offering a
/// refusal. A LISTEN, not a watch, and only on a revision it had already
/// seen: the row arriving for the first time is not a move, and a watch
/// would ask the server twice on every cold open (measured — the test counts
/// the reads). Offline it is `null` WITHOUT asking: the screen already says
/// why, from the same signal, and a request bound to fail would only repeat
/// it; `select` so that a first answer from the server is not a change.
final eeTicketActionsProvider = FutureProvider.autoDispose
    .family<EeTicketActions?, String>((ref, ticketId) async {
      if (!ref.watch(eeFeatureProvider('teams'))) return null;
      if (ref.watch(serverReachabilityProvider.select((up) => up == false))) {
        return null;
      }
      ref.listen(
        ticketProvider(ticketId).select((row) => row.value?.revision),
        (seen, now) {
          if (seen != null && now != seen) ref.invalidateSelf();
        },
      );
      return ref.watch(eeTicketWriteApiProvider).actions(ticketId);
    });

/// The desk's impact × urgency table — read when the priority sheet opens,
/// not with every detail screen: most visits never change a priority.
final eePriorityMatrixProvider = FutureProvider.autoDispose<EePriorityMatrix?>((
  ref,
) async {
  if (!ref.watch(eeFeatureProvider('teams'))) return null;
  return ref.watch(eeTicketWriteApiProvider).priorityMatrix();
});

/// What somebody had typed on a request and not sent yet (EE-223).
class EeCommentDraft {
  const EeCommentDraft({this.text = '', this.internal = false});

  final String text;
  final bool internal;
}

/// The composer's text, kept per request for the whole session.
///
/// "Half-written text is not lost" is the task's words, and the case they are
/// about is the one where the connection drops mid-sentence: the box greys
/// out and says why, the person gives up for now, backs out, and comes back
/// when the signal does. Without this the paragraph would have died with the
/// widget. It is in memory on purpose — a reply is a conversation with
/// somebody waiting, not a document to keep across restarts.
class EeCommentDrafts extends Notifier<Map<String, EeCommentDraft>> {
  @override
  Map<String, EeCommentDraft> build() => const {};

  EeCommentDraft of(String ticketId) =>
      state[ticketId] ?? const EeCommentDraft();

  void keep(String ticketId, EeCommentDraft draft) {
    if (draft.text.isEmpty && !draft.internal) {
      clear(ticketId);
      return;
    }
    state = {...state, ticketId: draft};
  }

  void clear(String ticketId) {
    if (!state.containsKey(ticketId)) return;
    state = {...state}..remove(ticketId);
  }
}

final eeCommentDraftsProvider =
    NotifierProvider<EeCommentDrafts, Map<String, EeCommentDraft>>(
      EeCommentDrafts.new,
    );
