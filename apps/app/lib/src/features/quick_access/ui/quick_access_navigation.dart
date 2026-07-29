import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../i18n/i18n.dart';
import '../../files/providers.dart';
import '../../files/ui/file_widgets.dart';
import '../../integrations/providers.dart';
import '../data/quick_link.dart';
import '../providers.dart';

/// Where a shortcut goes (OPH-199/203, BLUEPRINT §12.15).
///
/// A sealed result rather than "just navigate": the mapping is a pure function
/// that can be table-tested, and the one impure step ([openQuickDestination])
/// stays in a single place.
sealed class QuickDestination {
  const QuickDestination();
}

/// A branch route — `context.go`, which is what makes the section switch.
final class QuickGo extends QuickDestination {
  const QuickGo(this.location);
  final String location;
}

/// A root-navigator route (task detail) — `context.push`, so it stacks above
/// the shell exactly like every other detail screen.
final class QuickPush extends QuickDestination {
  const QuickPush(this.location);
  final String location;
}

/// Files has no per-file route; the file's "action page" IS the sheet
/// (`showFileActionsSheet`), so a file shortcut opens it directly.
final class QuickFileSheet extends QuickDestination {
  const QuickFileSheet(this.fileId);
  final String fileId;
}

/// An external link — the system browser, never an in-app webview.
final class QuickExternal extends QuickDestination {
  const QuickExternal(this.url);
  final Uri url;
}

/// The target is not in the replica: the server's cascade will drop the row
/// shortly, so this is the honest state of the race window (OPH-203).
final class QuickBroken extends QuickDestination {
  const QuickBroken(this.rowId);
  final String rowId;
}

/// PURE — the whole kind × target-state table lives here.
QuickDestination quickDestinationFor(QuickAccessRow row) {
  final link = row.link;
  if (link.kind == QuickKind.url) {
    final parsed = Uri.tryParse(link.url ?? '');
    if (parsed == null || !parsed.hasScheme || !parsed.hasAuthority) {
      return QuickBroken(row.id);
    }
    return QuickExternal(parsed);
  }
  // Broken dominates kind: a missing target has nowhere to go, archived does
  // (archives are reversible — the detail screen shows its own banner).
  if (row.isBroken || link.targetId == null) return QuickBroken(row.id);
  final id = link.targetId!;
  return switch (link.kind) {
    QuickKind.project => QuickGo('/projects/$id'),
    QuickKind.note => QuickGo('/notes/$id'),
    QuickKind.folder => QuickGo('/files/folder/$id'),
    QuickKind.task => QuickPush('/tasks/$id'),
    QuickKind.file => QuickFileSheet(id),
    QuickKind.url => QuickBroken(row.id), // unreachable, kept exhaustive
  };
}

/// The one impure step: performs [destination] and, for a broken row, offers
/// to remove it instead of navigating nowhere.
Future<void> openQuickDestination(
  BuildContext context,
  WidgetRef ref,
  QuickAccessRow row,
) async {
  final destination = quickDestinationFor(row);
  final messenger = ScaffoldMessenger.of(context);
  switch (destination) {
    case QuickGo(:final location):
      context.go(location);
    case QuickPush(:final location):
      context.push(location);
    case QuickFileSheet(:final fileId):
      final file = await ref.read(fileByIdProvider(fileId).future);
      if (!context.mounted) return;
      if (file == null) {
        _offerRemoval(messenger, ref, row.id);
        return;
      }
      await showFileActionsSheet(context, ref, file);
    case QuickExternal(:final url):
      final opened = await ref.read(urlLauncherProvider)(url);
      // The launcher's boolean has been ignored everywhere until now; an
      // offline device answers false, and the honest message beats the OS's
      // silence (OPH-203).
      if (!opened) {
        messenger.showSnackBar(
          SnackBar(content: Text('quick.offlineLink'.tr())),
        );
      }
    case QuickBroken(:final rowId):
      _offerRemoval(messenger, ref, rowId);
  }
}

void _offerRemoval(
  ScaffoldMessengerState messenger,
  WidgetRef ref,
  String rowId,
) {
  final store = ref.read(quickAccessStoreProvider);
  messenger.showSnackBar(
    SnackBar(
      content: Text('quick.brokenBody'.tr()),
      action: SnackBarAction(
        label: 'common.remove'.tr(),
        onPressed: () => store.remove(rowId),
      ),
    ),
  );
}
