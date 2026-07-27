import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/server_url.dart';
import '../../i18n/i18n.dart';
import '../auth/providers.dart';

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
  builder: (_) => const _ServerUrlDialog(),
);

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
    final current = ref.read(apiBaseUrlProvider);
    final target = normalized ?? compiledApiBaseUrl;
    setState(() => _saving = true);

    // Only disturb the session when the address actually moves.
    if (target != current) {
      final signedIn = ref.read(authControllerProvider).value != null;
      // Store the override as "" when it matches the built-in default, so the
      // app keeps following that default if it ever changes.
      await ref
          .read(serverUrlOverrideProvider.notifier)
          .set(target == compiledApiBaseUrl ? '' : target);
      if (signedIn) {
        await ref.read(authControllerProvider.notifier).logout();
      }
    }
    if (mounted) Navigator.of(context).pop();
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
