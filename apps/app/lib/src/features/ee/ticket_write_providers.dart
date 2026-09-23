import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../auth/providers.dart';
import 'data/ticket_write_api.dart';
import 'providers.dart';

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
