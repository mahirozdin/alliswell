import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/server_url.dart';
import '../../i18n/i18n.dart';
import '../auth/providers.dart';
import '../auth/ui/sign_out.dart';

/// Lets the user point this install at a different AllisWell server.
///
/// AllisWell is self-hostable, so this is not an advanced escape hatch — it is
/// how anyone running their own instance uses the same App Store build. Shown
/// from the sign-in screen (before there is an account) and from Settings.
///
/// Changing the address SIGNS THE USER OUT: tokens are issued by one server and
/// meaningless to another, and the local replica belongs to the old account.
Future<void> showServerUrlSheet(BuildContext context) => showDialog<void>(
  context: context,
  // Round 13 #2: dialogs go to the ROOT navigator for the same
  // reason sheets do (OPH-212) — inside a shell branch the
  // Scaffold's own bar and FAB paint over them.
  useRootNavigator: true,
  builder: (_) => const _ServerUrlDialog(),
);

/// Points this install at [target] (OPH-390, E-01).
///
/// Signed in, the session ends FIRST, while the address is still the server
/// that issued it: the refresh token is revoked where it means something, the
/// device leaves that server's push registry, and the engines stop and the
/// replica and the person's cached facts go (OPH-355) — before anything is
/// asked of the new server. Moving the address first sent the old refresh
/// token to the new host and briefly restored the old account against it.
///
/// Takes the container, not a widget's ref: the dialog that asked is closed
/// by the time this runs.
Future<void> switchServer(ProviderContainer container, String target) async {
  if (container.read(authControllerProvider).value != null) {
    await container.read(authControllerProvider.notifier).logout();
  }
  // Stored as "" when it matches the built-in default, so the app keeps
  // following that default if it ever changes.
  await container
      .read(serverUrlOverrideProvider.notifier)
      .set(target == compiledApiBaseUrl ? '' : target);
}

class _ServerUrlDialog extends ConsumerStatefulWidget {
  const _ServerUrlDialog();

  @override
  ConsumerState<_ServerUrlDialog> createState() => _ServerUrlDialogState();
}

class _ServerUrlDialogState extends ConsumerState<_ServerUrlDialog> {
  late final TextEditingController _controller = TextEditingController(
    text: ref.read(apiBaseUrlProvider),
  );
  String? _error;
  bool _saving = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _apply(String? normalized) async {
    final target = normalized ?? compiledApiBaseUrl;
    // Only disturb the session when the address actually moves.
    if (target == ref.read(apiBaseUrlProvider)) {
      Navigator.of(context).pop();
      return;
    }
    setState(() => _saving = true);
    // The sign-out deletes the replica (OPH-355): ask BEFORE anything moves,
    // while backing out still leaves everything as it was.
    final signedIn = ref.read(authControllerProvider).value != null;
    if (signedIn && !await confirmSignOut(context, ref)) {
      if (mounted) setState(() => _saving = false);
      return;
    }
    if (!mounted) return;
    // Close FIRST, while the page under the dialog is still the one it was
    // opened over (OPH-390, E-02). The switch rebuilds the session, and the
    // router answers by replacing that page — a pop after it took the
    // router's last page instead of this dialog. The work goes on in the
    // container, which outlives the dialog.
    final container = ProviderScope.containerOf(context, listen: false);
    Navigator.of(context).pop();
    await switchServer(container, target);
  }

  @override
  Widget build(BuildContext context) {
    final isCustom = ref.watch(usesCustomServerProvider);
    return AlertDialog(
      title: Text('settings.serverUrl.title'.tr()),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('settings.serverUrl.body'.tr()),
          const SizedBox(height: 16),
          TextField(
            key: const Key('server-url-field'),
            controller: _controller,
            autocorrect: false,
            enableSuggestions: false,
            keyboardType: TextInputType.url,
            textInputAction: TextInputAction.done,
            decoration: InputDecoration(
              labelText: 'settings.serverUrl.label'.tr(),
              hintText: kHostedApiBaseUrl,
              errorText: _error,
              prefixIcon: const Icon(Icons.dns_outlined),
            ),
            onSubmitted: (_) => _save(),
          ),
        ],
      ),
      actions: [
        if (isCustom)
          TextButton(
            onPressed: _saving ? null : () => _apply(null),
            child: Text('settings.serverUrl.useDefault'.tr()),
          ),
        TextButton(
          onPressed: _saving ? null : () => Navigator.of(context).pop(),
          child: Text('common.cancel'.tr()),
        ),
        FilledButton(
          onPressed: _saving ? null : _save,
          child: Text('common.save'.tr()),
        ),
      ],
    );
  }

  void _save() {
    final normalized = normalizeServerUrl(_controller.text);
    if (normalized == null) {
      setState(() => _error = 'settings.serverUrl.invalid'.tr());
      return;
    }
    setState(() => _error = null);
    _apply(normalized);
  }
}

/// The one-line "you are talking to X — tap to change" affordance, shared by
/// the sign-in screen and Settings so both always agree.
class ServerUrlTile extends ConsumerWidget {
  const ServerUrlTile({this.dense = false, super.key});

  /// Compact form for the sign-in card, where it is a footnote rather than a row.
  final bool dense;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final url = ref.watch(apiBaseUrlProvider);
    if (dense) {
      return TextButton.icon(
        key: const Key('server-url-button'),
        onPressed: () => showServerUrlSheet(context),
        icon: const Icon(Icons.dns_outlined, size: 16),
        label: Text(
          'settings.serverUrl.short'.tr(args: {'server': prettyServerUrl(url)}),
          style: Theme.of(context).textTheme.bodySmall,
        ),
      );
    }
    return ListTile(
      key: const Key('server-url-tile'),
      leading: const Icon(Icons.dns_outlined),
      title: Text('settings.server'.tr()),
      subtitle: Text(url),
      trailing: const Icon(Icons.chevron_right),
      onTap: () => showServerUrlSheet(context),
    );
  }
}
