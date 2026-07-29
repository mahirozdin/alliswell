import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/linkify.dart';
import '../../../i18n/i18n.dart';
import '../../workspaces/workspaces.dart';
import '../data/quick_link.dart';
import '../providers.dart';
import 'quick_access_row.dart';

/// The add/remove paths (OPH-201, BLUEPRINT §12.15).
///
/// One helper per surface shape — popup menu item, sheet tile — and ONE action
/// behind both, so "is it already there?" is answered in a single place and
/// the label can never disagree with what the tap does.

/// A menu entry that reads "Add to quick access" or "Remove from quick
/// access", already reflecting the current state.
PopupMenuItem<T> quickAccessMenuItem<T>({
  required T value,
  required bool isSaved,
}) => PopupMenuItem<T>(
  value: value,
  child: ListTile(
    contentPadding: EdgeInsets.zero,
    // Always `bolt`, never the favourite star: the star sorts a list in place,
    // Quick Access composes a personal navigation list (DESIGN §23 Q2).
    leading: const Icon(kQuickAccessIcon),
    title: Text(isSaved ? 'quick.removeFrom'.tr() : 'quick.addTo'.tr()),
  ),
);

/// The same entry as a bottom-sheet row (Files uses sheets, not menus).
Widget quickAccessSheetTile({
  required bool isSaved,
  required VoidCallback onTap,
}) => ListTile(
  key: const Key('quick-sheet-toggle'),
  leading: const Icon(kQuickAccessIcon),
  title: Text(isSaved ? 'quick.removeFrom'.tr() : 'quick.addTo'.tr()),
  onTap: onTap,
);

/// Adds the target to the rail, or removes it if it is already there.
///
/// There is deliberately no "add again": a target is on the rail or it is not,
/// and the menu says which. A refusal (the 50 cap) is spoken out loud rather
/// than swallowed — the same message the server's 422 resolves to.
Future<void> toggleQuickAccess(
  BuildContext context,
  WidgetRef ref, {
  required QuickKind kind,
  required String targetId,
  required String suggestedTitle,
}) async {
  final messenger = ScaffoldMessenger.of(context);
  final existing = ref.read(quickAccessSavedProvider((kind, targetId)));
  final store = ref.read(quickAccessStoreProvider);
  if (existing != null) {
    await store.remove(existing.id);
    return;
  }
  final workspaces = await ref.read(workspacesProvider.future);
  final userId = ref.read(currentUserIdProvider);
  if (workspaces.isEmpty || userId == null) return;
  final id = await store.add(
    workspaceId: workspaces.first.id,
    userId: userId,
    kind: kind,
    targetId: targetId,
    title: suggestedTitle.trim().isEmpty ? kind.name : suggestedTitle,
  );
  messenger.showSnackBar(
    SnackBar(
      content: Text(
        id == null ? 'quick.limitReached'.tr() : 'quick.added'.tr(),
      ),
    ),
  );
}

/// Whether a target already sits on the rail — what every menu label reads.
bool isInQuickAccess(WidgetRef ref, QuickKind kind, String targetId) =>
    ref.watch(quickAccessSavedProvider((kind, targetId))) != null;

/// The "+" dialog: an address, an optional name (the host if left empty).
///
/// No Open Graph title fetch in v1 — that needs an unfurl proxy, and it is in
/// the parking lot with its reason.
Future<void> showQuickLinkDialog(BuildContext context, WidgetRef ref) async {
  // Captured before the await: after it, this context may be gone.
  final messenger = ScaffoldMessenger.of(context);
  // The dialog owns its controllers: disposing them here would run while the
  // route is still animating out, and the fields rebuild during that frame.
  final result = await showDialog<({String url, String title})>(
    context: context,
    // Round 13 #2: dialogs go to the ROOT navigator for the same
    // reason sheets do (OPH-212) — inside a shell branch the
    // Scaffold's own bar and FAB paint over them.
    useRootNavigator: true,
    builder: (dialogContext) => const _QuickLinkDialog(),
  );
  if (result == null) return;

  final workspaces = await ref.read(workspacesProvider.future);
  final userId = ref.read(currentUserIdProvider);
  if (workspaces.isEmpty || userId == null) return;
  final id = await ref
      .read(quickAccessStoreProvider)
      .add(
        workspaceId: workspaces.first.id,
        userId: userId,
        kind: QuickKind.url,
        url: result.url,
        title: result.title,
      );
  if (id == null) {
    messenger.showSnackBar(SnackBar(content: Text('quick.limitReached'.tr())));
  }
}

/// Normalizes what the user typed into a real http(s) address, or null.
///
/// `linkUriOf` is the same normalizer task descriptions use (OPH-164), so a
/// bare `www.…` becomes https there and here alike — one behaviour, one
/// implementation.
Uri? quickLinkUri(String raw) {
  final trimmed = raw.trim();
  if (trimmed.isEmpty) return null;
  final typed = Uri.tryParse(trimmed);
  // Something that already declares a scheme is taken at its word — prefixing
  // `https://` onto `mailto:…` would manufacture a nonsense address that
  // passes every later check.
  final uri = typed != null && typed.hasScheme
      ? typed
      : (linkUriOf(trimmed) ?? Uri.tryParse('https://$trimmed'));
  if (uri == null || !uri.hasAuthority) return null;
  if (uri.scheme != 'http' && uri.scheme != 'https') return null;
  return uri;
}

class _QuickLinkDialog extends StatefulWidget {
  const _QuickLinkDialog();

  @override
  State<_QuickLinkDialog> createState() => _QuickLinkDialogState();
}

class _QuickLinkDialogState extends State<_QuickLinkDialog> {
  final _urlController = TextEditingController();
  final _titleController = TextEditingController();
  String? _error;

  @override
  void dispose() {
    _urlController.dispose();
    _titleController.dispose();
    super.dispose();
  }

  void _submit() {
    final uri = quickLinkUri(_urlController.text);
    if (uri == null) {
      setState(() => _error = 'quick.invalidUrl'.tr());
      return;
    }
    final typed = _titleController.text.trim();
    Navigator.of(context).pop((
      url: uri.toString(),
      // An empty name is not an error: the host is a decent name, and the user
      // can rename it later (BLUEPRINT §4.12 — the title is theirs).
      title: typed.isEmpty ? uri.host : typed,
    ));
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('quick.addLink'.tr()),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            key: const Key('quick-link-url'),
            controller: _urlController,
            autofocus: true,
            keyboardType: TextInputType.url,
            decoration: InputDecoration(
              labelText: 'quick.linkUrl'.tr(),
              errorText: _error,
            ),
            onChanged: (_) {
              if (_error != null) setState(() => _error = null);
            },
          ),
          TextField(
            key: const Key('quick-link-title'),
            controller: _titleController,
            maxLength: 200,
            decoration: InputDecoration(labelText: 'quick.linkTitle'.tr()),
            onSubmitted: (_) => _submit(),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text('common.cancel'.tr()),
        ),
        FilledButton(
          key: const Key('quick-link-save'),
          onPressed: _submit,
          child: Text('common.add'.tr()),
        ),
      ],
    );
  }
}
