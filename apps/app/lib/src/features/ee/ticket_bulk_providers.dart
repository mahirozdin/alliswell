import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/reachability.dart';
import 'data/ticket_write_api.dart';
import 'providers.dart';
import 'ticket_write_providers.dart';
import 'tickets_providers.dart';

/// EE-227 — the most one batch may carry: the server's own ceiling
/// (`BULK_MAX`). A selection bigger than a screenful is a filter, not a
/// selection, and the bar says so instead of sending a request bound to 400.
const kBulkMax = 100;

/// Which requests the queue has selected. Empty means "not selecting".
///
/// Auto-disposed with the queue: a selection is a gesture on one screen, and
/// coming back to find fifty requests still ticked would be a trap.
///
/// It only ever holds rows that are ON SCREEN: a filter that hides a selected
/// request drops it from the selection. What the person sees is what the
/// batch touches — a count that included rows a filter had hidden would ask
/// them to trust a number they cannot check.
class TicketSelection extends Notifier<Set<String>> {
  @override
  Set<String> build() {
    ref.listen(filteredTicketsProvider, (_, next) {
      final rows = next.value;
      if (rows == null || state.isEmpty) return;
      final visible = {for (final row in rows) row.id};
      final kept = state.where(visible.contains).toSet();
      if (kept.length != state.length) state = kept;
    });
    return const {};
  }

  void toggle(String ticketId) => state = state.contains(ticketId)
      ? ({...state}..remove(ticketId))
      : {...state, ticketId};

  void selectAll(Iterable<String> ticketIds) =>
      state = {...state, ...ticketIds};

  void clear() => state = const {};
}

final ticketSelectionProvider =
    NotifierProvider.autoDispose<TicketSelection, Set<String>>(
      TicketSelection.new,
    );

/// What a batch may be offered, as the SERVER says it.
///
/// "The client writes no second state machine" (E19): the moves come from
/// the same detail endpoint the single sheet reads — asked once per STATUS
/// the selection holds, because every request in one status has the same
/// moves; the union is what at least one of them can make. A request that
/// cannot make a move it was offered (an approval holding it, a verb the
/// batch lacks) is refused by the server for that row, and the result says
/// so — which is EE-171's partial success, not a guess made here.
class EeBulkOptions {
  const EeBulkOptions({
    required this.moves,
    required this.waitingReasons,
    required this.priorities,
    required this.canAssignOthers,
  });

  /// In the order the server listed them, first appearance first.
  final List<String> moves;
  final List<String> waitingReasons;
  final List<String> priorities;
  final bool canAssignOthers;

  static EeBulkOptions? of(List<EeTicketActions?> answers) {
    final known = answers.whereType<EeTicketActions>().toList();
    if (known.isEmpty) return null;
    final moves = <String>[];
    for (final answer in known) {
      for (final to in answer.allowedTransitions) {
        if (!moves.contains(to)) moves.add(to);
      }
    }
    return EeBulkOptions(
      moves: moves,
      waitingReasons: known.first.waitingReasons,
      priorities: known.first.priorities,
      canAssignOthers: known.first.canAssignOthers,
    );
  }
}

/// Keyed by the representatives' ids, comma-joined (one per status held).
final eeBulkOptionsProvider = FutureProvider.autoDispose
    .family<EeBulkOptions?, String>((ref, representatives) async {
      if (!ref.watch(eeFeatureProvider('teams'))) return null;
      if (ref.watch(serverReachabilityProvider.select((up) => up == false))) {
        return null;
      }
      final api = ref.watch(eeTicketWriteApiProvider);
      final ids = representatives.split(',').where((id) => id.isNotEmpty);
      return EeBulkOptions.of(await Future.wait(ids.map(api.actions)));
    });
