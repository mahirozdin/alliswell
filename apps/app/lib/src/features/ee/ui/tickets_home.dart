import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers.dart';
import 'my_tickets_screen.dart';
import 'ticket_queue_screen.dart';

/// The "Talepler" tab's root (EE-253): the desk's queue for somebody who
/// works a desk, "my requests" for everybody else.
///
/// Before, every person with the feature opened the tab onto the queue of
/// whichever workspace was current — which, for somebody who only ASKS, is
/// never a unit's, so the tab was an empty list above a button that did not
/// help. Which one a person gets is the server's word (`desk`, from the same
/// answer the permission cache keeps), not a guess from the workspace list.
class EeTicketsHome extends ConsumerWidget {
  const EeTicketsHome({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) => ref.watch(eeDeskProvider)
      ? const EeTicketQueueScreen()
      : const EeMyTicketsScreen();
}
