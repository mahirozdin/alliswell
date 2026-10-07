import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../i18n/i18n.dart';
import '../../../sync/local_data.dart';
import '../../../sync/providers.dart';
import '../providers.dart';

/// Whether a sign-out may go ahead (OPH-355).
///
/// Sign-out deletes the replica, and the outbox lives in it: a change made
/// with no signal exists on this device and nowhere else. So when there is
/// any, the person is told how many and asked — never a silent loss. With
/// none, there is nothing to ask.
Future<bool> confirmSignOut(BuildContext context, WidgetRef ref) async {
  int unsent;
  try {
    unsent = await unsentChangeCount(ref.read(databaseProvider));
  } on Object {
    unsent = 0;
  }
  if (unsent == 0) return true;
  if (!context.mounted) return false;
  final confirmed = await showDialog<bool>(
    context: context,
    // Dialogs go to the ROOT navigator (OPH-212): inside a shell branch the
    // Scaffold's own bar and FAB paint over them.
    useRootNavigator: true,
    builder: (dialogContext) {
      final scheme = Theme.of(dialogContext).colorScheme;
      return AlertDialog(
        key: const Key('sign-out-unsent-dialog'),
        title: Text('settings.signOutUnsent.title'.tr()),
        content: Text(
          'settings.signOutUnsent.body'.tr(args: {'count': '$unsent'}),
        ),
        actions: [
          TextButton(
            key: const Key('sign-out-unsent-cancel'),
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text('common.cancel'.tr()),
          ),
          FilledButton(
            key: const Key('sign-out-unsent-confirm'),
            style: FilledButton.styleFrom(
              backgroundColor: scheme.error,
              foregroundColor: scheme.onError,
            ),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text('settings.signOutUnsent.confirm'.tr()),
          ),
        ],
      );
    },
  );
  return confirmed == true;
}

/// The sign-out every screen offers: ask when something would be lost, then
/// sign out (which wipes this person's local data).
Future<void> signOutWithConfirm(BuildContext context, WidgetRef ref) async {
  if (!await confirmSignOut(context, ref)) return;
  await ref.read(authControllerProvider.notifier).logout();
}
