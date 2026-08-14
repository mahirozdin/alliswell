import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_slidable/flutter_slidable.dart';

import '../core/pending_deletes.dart';
import '../i18n/i18n.dart';
import '../theme/tokens.dart';
import 'snackbars.dart';

/// Swipe-from-the-trailing-edge delete (OPH-184, DESIGN §19).
///
/// The interaction is the Apple one the user asked for: the swipe **half-opens
/// and waits**, revealing a red `Sil` button, and the button is what deletes.
/// A single fling never destroys anything — which is why this is a
/// [Slidable] action pane and NOT a `Dismissible` (ADR-0017).
///
/// The widget also owns the *hiding* half of the undo model: while [id] is in
/// [pendingDeletesProvider] the row renders as nothing, so every list that
/// contains it agrees without knowing anything about deletion (D4). Callers
/// that delete through a confirmation dialog simply never put their id in that
/// set, and this collapses to a plain swipe affordance.
class AwSwipeToDelete extends ConsumerWidget {
  const AwSwipeToDelete({
    super.key,
    required this.id,
    required this.child,
    required this.onDelete,
    this.enabled = true,
    this.semanticLabel,
  });

  /// The row's entity id — the key both the pending set and the group filters
  /// use. Also namespaces the [Slidable] group so opening one row closes any
  /// other open row in the same list.
  final String id;
  final Widget child;

  /// What the revealed button does. Usually [awDeleteWithUndo]; for cascading
  /// deletes (project, folder, tag) it is that entity's own confirm dialog.
  final Future<void> Function() onDelete;

  /// Off where a horizontal gesture belongs to something else — the board's
  /// pager (D6), or a row that is already inside a dismissible surface.
  final bool enabled;

  /// Spoken name for the action ("Delete <title>"), so the gesture has a
  /// screen-reader equivalent even before the visible fallbacks of D2.
  final String? semanticLabel;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // D4: hidden the instant the user taps Delete, restored by undo, gone for
    // real when the window closes and the row leaves the replica.
    if (ref.watch(pendingDeletesProvider).contains(id)) {
      return const SizedBox.shrink();
    }
    if (!enabled) return child;

    final scheme = Theme.of(context).colorScheme;
    return Slidable(
      key: ValueKey('swipe-$id'),
      groupTag: 'aw-delete',
      endActionPane: ActionPane(
        // Reveal-and-wait: the pane opens to a fixed fraction and stays there.
        // `extentRatio` is what makes it a "half open" affordance rather than
        // a swipe-through gesture.
        motion: const DrawerMotion(),
        extentRatio: 0.28,
        children: [
          CustomSlidableAction(
            key: Key('swipe-delete-$id'),
            onPressed: (_) => unawaited(onDelete()),
            backgroundColor: scheme.error,
            foregroundColor: scheme.onError,
            borderRadius: const BorderRadius.all(Radius.circular(AwRadius.l)),
            // The action is already a button (an OutlinedButton inside the
            // pane); this only replaces its spoken name with the row's, so a
            // screen reader says "Delete Teklifi bitir", not just "Delete".
            child: Semantics(
              label: semanticLabel,
              excludeSemantics: semanticLabel != null,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.delete_outline, size: 22),
                  const SizedBox(height: 2),
                  Text(
                    'common.delete'.tr(),
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
      child: child,
    );
  }
}

/// Delete [id] the recoverable way: hide it now, tell the user, commit later.
///
/// DESIGN §19 D3 — this is the **leaf** grade (task, note): no dialog, because
/// a confirmation on an action that is trivially reversible is friction without
/// safety. Deletes that cascade keep their dialog and do not come through here.
///
/// [commit] runs from a timer AFTER the row has left the list, so it must not
/// close over a widget's [WidgetRef] — resolve the store before calling this.
///
/// The bar and the window are held together deliberately (OPH-257): the bar
/// going away is what commits the delete, and the delete committing is what
/// takes the bar away. Before that they were two timers that merely hoped to
/// agree — and the bar's never even started, so the control sat on screen
/// indefinitely, its button quietly doing nothing once the window had passed.
Future<void> awDeleteWithUndo(
  BuildContext context,
  WidgetRef ref, {
  required String id,
  required String message,
  required Future<void> Function() commit,
}) async {
  final messenger = ScaffoldMessenger.of(context);
  final window = ref.read(undoWindowProvider);
  final pending = ref.read(pendingDeletesProvider.notifier);

  // This also ends the PREVIOUS delete's window: its bar closes, so its commit
  // lands. One rule — an undo you cannot see is an undo you do not have.
  messenger.clearSnackBars();

  var onScreen = true;
  pending.schedule(id, () async {
    // The backstop. It exists for the case where the bar never got to run
    // its own clock (no scaffold, a queue behind it), and it takes the
    // control off screen at the exact moment that control stops working.
    if (onScreen) messenger.hideCurrentSnackBar();
    await commit();
  }, window: window);

  final bar = showAwActionSnackBar(
    messenger,
    key: Key('undo-delete-$id'),
    content: Text(message),
    duration: window,
    actionLabel: 'common.undo'.tr(),
    onAction: () {
      if (pending.undo(id)) return;
      // The tap landed after the window closed — possible in the frames the
      // bar spends animating away. Silence would look exactly like a working
      // undo; it isn't one, and the row is not coming back.
      messenger.showSnackBar(
        SnackBar(content: Text('common.undoTooLate'.tr())),
      );
    },
  );

  unawaited(
    bar.closed.then((reason) {
      onScreen = false;
      // Dismissing the undo accepts the delete: sooner than the window when the
      // user swipes it away or the next delete clears it, never later.
      if (reason != SnackBarClosedReason.action) pending.commitNow(id);
    }),
  );
}

/// Confirmation dialog for the deletes that cascade or cannot be taken back
/// (DESIGN §19 D3/D5): destructive action in the error role, cancel always
/// present. Returns true when the user confirmed.
Future<bool> awConfirmDelete(
  BuildContext context, {
  required String title,
  required String body,
  String? confirmLabel,
}) async {
  final scheme = Theme.of(context).colorScheme;
  final ok = await showDialog<bool>(
    context: context,
    // Round 13 #2: dialogs go to the ROOT navigator for the same
    // reason sheets do (OPH-212) — inside a shell branch the
    // Scaffold's own bar and FAB paint over them.
    useRootNavigator: true,
    builder: (ctx) => AlertDialog(
      title: Text(title),
      content: Text(body),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, false),
          child: Text('common.cancel'.tr()),
        ),
        FilledButton(
          key: const Key('confirm-delete'),
          style: FilledButton.styleFrom(
            backgroundColor: scheme.error,
            foregroundColor: scheme.onError,
          ),
          onPressed: () => Navigator.pop(ctx, true),
          child: Text(confirmLabel ?? 'common.delete'.tr()),
        ),
      ],
    ),
  );
  return ok ?? false;
}
