import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api_exception.dart';
import '../../../core/date_format.dart';
import '../../../core/error_messages.dart';
import '../../../core/persisted_prefs.dart';
import '../../../core/server_url.dart';
import '../../../i18n/i18n.dart';
import '../../integrations/providers.dart' show urlLauncherProvider;
import '../../../theme/tokens.dart';
import '../../../widgets/fabs.dart';
import '../../../widgets/status_views.dart';
import '../../workspaces/workspaces.dart';
import '../data/api_key_models.dart';
import '../providers.dart';
import 'api_docs_row.dart';

/// API access (OPH-265, ADR-0032): the keys a person hands to their own
/// scripts.
///
/// The screen has one job the rest of Settings does not: it shows a secret
/// exactly once. Everything about it is arranged around that — the dialog
/// cannot be dismissed by accident, it says plainly that the value will not
/// come back, and the copy button is the primary action.
class ApiKeysScreen extends ConsumerStatefulWidget {
  const ApiKeysScreen({super.key});

  @override
  ConsumerState<ApiKeysScreen> createState() => _ApiKeysScreenState();
}

class _ApiKeysScreenState extends ConsumerState<ApiKeysScreen> {
  bool _busy = false;

  Future<void> _guard(Future<void> Function() action) async {
    if (_busy) return;
    setState(() => _busy = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      await action();
    } on ApiException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(localizedError(e))));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final keys = ref.watch(apiKeysProvider);
    return Scaffold(
      appBar: AppBar(title: Text('apiKeys.title'.tr())),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 720),
          child: keys.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            // The server is the only source here (no replica to fall back on),
            // so an unreachable server says so instead of showing an empty
            // list that would read as "you have no keys".
            error: (_, _) => AwErrorState(
              message: 'apiKeys.couldNotLoad'.tr(),
              onRetry: () => ref.invalidate(apiKeysProvider),
            ),
            data: (list) => list.isEmpty ? _empty() : _list(list),
          ),
        ),
      ),
      floatingActionButton: AwExtendedFab(
        key: const Key('api-key-create'),
        onPressed: _busy ? null : _startCreate,
        icon: const Icon(Icons.add),
        label: Text('apiKeys.create'.tr()),
      ),
    );
  }

  Widget _empty() => AwEmptyState(
    icon: Icons.vpn_key_outlined,
    title: 'apiKeys.emptyTitle'.tr(),
    message: 'apiKeys.emptyBody'.tr(),
    // OPH-296: the slot was here and empty. Somebody with no keys is
    // deciding whether the API can do what they need — which is a question
    // the reference answers and this screen cannot.
    action: OutlinedButton.icon(
      key: const Key('api-key-docs-empty'),
      onPressed: () => ref.read(urlLauncherProvider)(Uri.parse(kApiDocsUrl)),
      icon: const Icon(Icons.open_in_new),
      label: Text('apiKeys.docsCta'.tr()),
    ),
  );

  Widget _list(List<ApiKey> list) {
    final dateFormat = ref.watch(dateFormatProvider);
    return ListView(
      padding: awListPadding(context, top: AwSpace.x2),
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(AwSpace.x4),
            child: Text(
              'apiKeys.intro'.tr(),
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ),
        ),
        const SizedBox(height: AwSpace.x3),
        for (final key in list)
          _ApiKeyCard(
            apiKey: key,
            dateFormat: dateFormat,
            busy: _busy,
            onRevoke: () => _revoke(key),
          ),
        // OPH-296: the reference, one tap from the key you just minted.
        // This is the moment the original complaint names — the secret is
        // in your hand and nothing tells you what to do with it.
        const SizedBox(height: AwSpace.x3),
        const Card(child: ApiDocsRow()),
        // The FAB sits over the tail of the list.
        const SizedBox(height: AwSpace.x8),
      ],
    );
  }

  Future<void> _startCreate() async {
    final draft = await showModalBottomSheet<({String name, int? days})>(
      context: context,
      useRootNavigator: true,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      constraints: const BoxConstraints(maxWidth: 560),
      builder: (sheetContext) => const _CreateKeySheet(),
    );
    if (draft == null || !mounted) return;

    final workspace = ref.read(currentWorkspaceProvider).value;
    if (workspace == null) return;

    await _guard(() async {
      final created = await ref
          .read(apiKeysApiProvider)
          .create(workspace.id, name: draft.name, expiresInDays: draft.days);
      ref.invalidate(apiKeysProvider);
      if (mounted) await _showSecretOnce(created);
    });
  }

  /// The one time this value is ever visible. Barrier-dismiss is off and there
  /// is no cancel: the only way out is acknowledging that you have it.
  Future<void> _showSecretOnce(NewApiKey created) => showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (dialogContext) => AlertDialog(
      key: const Key('api-key-secret-dialog'),
      title: Text('apiKeys.secretTitle'.tr()),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('apiKeys.secretOnce'.tr()),
          const SizedBox(height: AwSpace.x3),
          Container(
            padding: const EdgeInsets.all(AwSpace.x3),
            decoration: BoxDecoration(
              color: Theme.of(dialogContext).colorScheme.surfaceContainerHigh,
              borderRadius: BorderRadius.circular(AwRadius.s),
            ),
            child: SelectableText(
              created.key,
              key: const Key('api-key-secret-value'),
              style: Theme.of(dialogContext).textTheme.bodySmall?.copyWith(
                fontFamily: 'monospace',
                fontFamilyFallback: const ['Courier'],
              ),
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          key: const Key('api-key-secret-done'),
          onPressed: () => Navigator.of(dialogContext).pop(),
          child: Text('common.done'.tr()),
        ),
        FilledButton.icon(
          key: const Key('api-key-secret-copy'),
          // Close FIRST, then write to the clipboard: the dialog must not stay
          // open waiting on a platform channel, and if that channel is
          // unavailable the user has still seen (and can still select) the
          // value — the dialog closing is not the part that can fail.
          onPressed: () {
            Navigator.of(dialogContext).pop();
            unawaited(_copySecret(created.key));
          },
          icon: const Icon(Icons.copy_outlined),
          label: Text('apiKeys.copy'.tr()),
        ),
      ],
    ),
  );

  Future<void> _copySecret(String secret) async {
    await Clipboard.setData(ClipboardData(text: secret));
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text('apiKeys.copied'.tr())));
  }

  Future<void> _revoke(ApiKey key) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('apiKeys.revokeConfirmTitle'.tr(args: {'name': key.name})),
        content: Text('apiKeys.revokeConfirmBody'.tr()),
        actions: [
          TextButton(
            key: const Key('api-key-revoke-cancel'),
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text('common.cancel'.tr()),
          ),
          FilledButton(
            key: const Key('api-key-revoke-confirm'),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text('apiKeys.revoke'.tr()),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    await _guard(() async {
      await ref.read(apiKeysApiProvider).revoke(key.id);
      ref.invalidate(apiKeysProvider);
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('apiKeys.revoked'.tr())));
      }
    });
  }
}

class _ApiKeyCard extends StatelessWidget {
  const _ApiKeyCard({
    required this.apiKey,
    required this.dateFormat,
    required this.busy,
    required this.onRevoke,
  });

  final ApiKey apiKey;
  final String dateFormat;
  final bool busy;
  final VoidCallback onRevoke;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tokens = context.awTokens;
    final live = apiKey.isLive;
    String date(DateTime value) => awFormatDate(value, format: dateFormat);

    // The state line is the answer to "can I revoke this?" — never a colour
    // alone (DESIGN §3: colour is never the only carrier of meaning).
    final String status;
    if (apiKey.isRevoked) {
      status = 'apiKeys.stateRevoked'.tr(
        args: {'date': date(apiKey.revokedAt!)},
      );
    } else if (apiKey.isExpired) {
      status = 'apiKeys.stateExpired'.tr(
        args: {'date': date(apiKey.expiresAt!)},
      );
    } else if (apiKey.lastUsedAt != null) {
      status = 'apiKeys.stateUsed'.tr(args: {'date': date(apiKey.lastUsedAt!)});
    } else {
      status = 'apiKeys.stateNeverUsed'.tr();
    }

    return Card(
      key: Key('api-key-${apiKey.id}'),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          AwSpace.x4,
          AwSpace.x3,
          AwSpace.x2,
          AwSpace.x3,
        ),
        child: Row(
          children: [
            Icon(
              live ? Icons.vpn_key_outlined : Icons.key_off_outlined,
              color: live ? tokens.success : theme.colorScheme.outline,
            ),
            const SizedBox(width: AwSpace.x3),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(apiKey.name, style: theme.textTheme.titleSmall),
                  const SizedBox(height: AwSpace.x1),
                  Text(
                    '${apiKey.keyPrefix}…',
                    style: theme.textTheme.bodySmall?.copyWith(
                      fontFamily: 'monospace',
                      fontFamilyFallback: const ['Courier'],
                    ),
                  ),
                  const SizedBox(height: AwSpace.x1),
                  Text(
                    [
                      'apiKeys.created'.tr(
                        args: {'date': date(apiKey.createdAt)},
                      ),
                      if (apiKey.expiresAt != null && !apiKey.isExpired)
                        'apiKeys.expires'.tr(
                          args: {'date': date(apiKey.expiresAt!)},
                        ),
                      status,
                    ].join(' · '),
                    style: theme.textTheme.bodySmall,
                  ),
                ],
              ),
            ),
            if (live)
              TextButton(
                key: Key('api-key-revoke-${apiKey.id}'),
                onPressed: busy ? null : onRevoke,
                child: Text(
                  'apiKeys.revoke'.tr(),
                  style: TextStyle(color: theme.colorScheme.error),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// Name + lifetime. Two questions, because those are the only two the server
/// accepts — no scopes to invent a UI for (ADR-0032 §3).
class _CreateKeySheet extends StatefulWidget {
  const _CreateKeySheet();

  @override
  State<_CreateKeySheet> createState() => _CreateKeySheetState();
}

class _CreateKeySheetState extends State<_CreateKeySheet> {
  final _controller = TextEditingController();
  int? _days = 90;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  String _lifetimeLabel(int? days) => days == null
      ? 'apiKeys.lifetimeNever'.tr()
      : 'apiKeys.lifetimeDays'.tr(args: {'days': '$days'});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(
        AwSpace.x4,
        AwSpace.x2,
        AwSpace.x4,
        AwSpace.x4 + MediaQuery.viewInsetsOf(context).bottom,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'apiKeys.createTitle'.tr(),
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: AwSpace.x3),
          TextField(
            key: const Key('api-key-name-field'),
            controller: _controller,
            autofocus: true,
            decoration: InputDecoration(
              labelText: 'apiKeys.nameLabel'.tr(),
              helperText: 'apiKeys.nameHelp'.tr(),
            ),
            textInputAction: TextInputAction.done,
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: AwSpace.x4),
          Text(
            'apiKeys.lifetimeLabel'.tr(),
            style: Theme.of(context).textTheme.labelLarge,
          ),
          const SizedBox(height: AwSpace.x2),
          Wrap(
            spacing: AwSpace.x2,
            children: [
              for (final days in kApiKeyLifetimes)
                ChoiceChip(
                  key: Key('api-key-lifetime-${days ?? 'never'}'),
                  label: Text(_lifetimeLabel(days)),
                  selected: _days == days,
                  onSelected: (_) => setState(() => _days = days),
                ),
            ],
          ),
          const SizedBox(height: AwSpace.x4),
          FilledButton(
            key: const Key('api-key-create-submit'),
            onPressed: _controller.text.trim().isEmpty
                ? null
                : () => Navigator.of(
                    context,
                  ).pop((name: _controller.text.trim(), days: _days)),
            child: Text('apiKeys.create'.tr()),
          ),
        ],
      ),
    );
  }
}
