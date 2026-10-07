import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'providers.dart';

/// Keeps the sync engines (and the live socket that nudges them) running
/// while [child] is on screen (OPH-359, UI-AUDIT #32).
///
/// The shell does this for the sections. A page reached by its address — a
/// request link, a notification, a reload on the web — can be on screen with
/// no shell under it, and nothing pulled. Listened, not watched: nothing here
/// redraws when an engine changes. Signed out the workspace list is empty, so
/// no engine runs.
class AwKeepReplicaCurrent extends ConsumerWidget {
  const AwKeepReplicaCurrent({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.listen(syncEnginesProvider, (_, _) {});
    ref.listen(syncSocketProvider, (_, _) {});
    return child;
  }
}
