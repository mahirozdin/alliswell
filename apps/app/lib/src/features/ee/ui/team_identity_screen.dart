import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/error_messages.dart';
import '../../../i18n/i18n.dart';
import '../../../theme/tokens.dart';
import '../../../widgets/status_views.dart';
import '../data/identity_api.dart';
import '../data/identity_models.dart';
import '../identity_providers.dart';

/// Where a team connects its own identity source (OPH-287).
///
/// ── THE ORDER OF THE SCREEN IS THE ORDER OF THE RISK ─────────────────────
///
/// Connect, TEST, then switch on — in that order, because a provider that is
/// on is the only authority for the addresses it owns. A form that offered
/// "save and enable" in one press would make a typo in a base DN into an
/// outage for everybody whose account the directory holds. So `enabled` is a
/// separate switch on the tile, and it refuses to move until the server says
/// the provider is complete.
///
/// ── THE CREDENTIAL IS NEVER SHOWN, AND THE SCREEN SAYS SO ────────────────
///
/// `EeTeamAiKeysScreen`'s stance, verbatim, because the situation is
/// identical: the server COULD return the value and deliberately does not, so
/// the honest thing is to say what a stored credential means — "•••• 4417" —
/// rather than imply a hidden field somebody could reveal. Replacing is
/// typing a new one; there is no reading the old one.
///
/// ── A FAILED TEST IS TWO DIFFERENT SENTENCES ─────────────────────────────
///
/// "The directory said no" and "the directory did not answer" call for
/// different actions from the person reading them — correct this form, or go
/// look at the network — so they are never collapsed into one "failed". The
/// server keeps them apart and this screen keeps the server's own words.
///
/// ── COLOUR IS A MARK, MEANING IS A WORD (EE-097's rule) ──────────────────
///
/// A provider's state is an icon in a state colour PLUS its own label, and no
/// label is written in a state colour. Each mark carries its own key, because
/// a tile holds several tappable things.
class EeTeamIdentityScreen extends ConsumerWidget {
  const EeTeamIdentityScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final data = ref.watch(eeIdentityProvidersProvider);

    return Scaffold(
      appBar: AppBar(title: Text('ee.identity.title'.tr())),
      body: data.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => AwErrorState(
          message: localizedError(error),
          onRetry: () => ref.invalidate(eeIdentityProvidersProvider),
        ),
        data: (items) {
          if (items == null) {
            return AwEmptyState(
              icon: Icons.domain_disabled_outlined,
              title: 'ee.identity.unavailable'.tr(),
              message: 'ee.identity.unavailableBody'.tr(),
            );
          }
          if (items.isEmpty) {
            return AwEmptyState(
              icon: Icons.account_tree_outlined,
              title: 'ee.identity.emptyTitle'.tr(),
              message: 'ee.identity.emptyBody'.tr(),
            );
          }
          return ListView(
            padding: const EdgeInsets.only(bottom: 88),
            children: [for (final item in items) _ProviderTile(provider: item)],
          );
        },
      ),
      floatingActionButton: data.value == null
          ? null
          : FloatingActionButton(
              key: const Key('identity-add'),
              tooltip: 'ee.identity.add'.tr(),
              onPressed: () => _openEditor(context, ref, null),
              child: const Icon(Icons.add),
            ),
    );
  }
}

class _ProviderTile extends ConsumerWidget {
  const _ProviderTile({required this.provider});
  final EeIdentityProvider provider;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = context.awTokens;
    final failing = provider.status == 'error';

    return Card(
      margin: const EdgeInsets.fromLTRB(12, 8, 12, 0),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  key: Key('identity-mark-${provider.id}'),
                  failing ? Icons.error_outline : Icons.check_circle_outline,
                  color: failing ? tokens.warning : tokens.success,
                  size: 20,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    provider.displayName,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                Text('ee.identity.type.${provider.type}'.tr()),
              ],
            ),
            const SizedBox(height: 4),
            // The state as a WORD, never only as a colour.
            Text(
              failing
                  ? 'ee.identity.status.error'.tr()
                  : 'ee.identity.status.active'.tr(),
              style: Theme.of(context).textTheme.bodySmall,
            ),
            if (failing && provider.lastError != null)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  provider.lastError!,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
            if (provider.secretSet)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  'ee.identity.secretMask'.tr(
                    args: {'last4': provider.secretLast4 ?? ''},
                  ),
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
            if (!provider.ready)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  'ee.identity.incomplete'.tr(
                    args: {'fields': _missingLabel(provider)},
                  ),
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
            const SizedBox(height: 8),
            Row(
              children: [
                // The switch is what turns a configuration into an authority,
                // so it is the control that refuses to move while the server
                // says the provider is incomplete.
                Switch(
                  key: Key('identity-enable-${provider.id}'),
                  value: provider.enabled,
                  onChanged: provider.ready
                      ? (value) => _run(
                          context,
                          () => ref
                              .read(eeIdentityProvidersProvider.notifier)
                              .patch(provider.id, enabled: value),
                        )
                      : null,
                ),
                Text(
                  provider.enabled
                      ? 'ee.identity.on'.tr()
                      : 'ee.identity.off'.tr(),
                ),
                const Spacer(),
                TextButton(
                  key: Key('identity-test-${provider.id}'),
                  onPressed: () => _test(context, ref, provider),
                  child: Text('ee.identity.test'.tr()),
                ),
                TextButton(
                  key: Key('identity-edit-${provider.id}'),
                  onPressed: () => _openEditor(context, ref, provider),
                  child: Text('ee.identity.edit'.tr()),
                ),
                IconButton(
                  key: Key('identity-delete-${provider.id}'),
                  tooltip: 'ee.identity.remove'.tr(),
                  icon: const Icon(Icons.delete_outline),
                  onPressed: () => _confirmRemove(context, ref, provider),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

String _missingLabel(EeIdentityProvider provider) {
  final missing = [...provider.missingRequired];
  if (provider.secretField != null && !provider.secretSet) {
    missing.add(provider.secretField!);
  }
  return missing.join(', ');
}

Future<void> _run(BuildContext context, Future<void> Function() action) async {
  final messenger = ScaffoldMessenger.of(context);
  try {
    await action();
  } catch (error) {
    // The server's sentence, not a generic failure: "this provider still
    // needs: baseDn" is the only actionable thing in a refusal.
    messenger.showSnackBar(SnackBar(content: Text(localizedError(error))));
  }
}

Future<void> _test(
  BuildContext context,
  WidgetRef ref,
  EeIdentityProvider provider,
) async {
  final messenger = ScaffoldMessenger.of(context);
  try {
    final result = await ref
        .read(eeIdentityProvidersProvider.notifier)
        .test(provider.id);
    final message = result.ok
        ? 'ee.identity.testOk'.tr()
        // Two different sentences, deliberately — see the class header.
        : result.error != null
        ? 'ee.identity.testUnreachable'.tr(args: {'error': result.error!})
        : 'ee.identity.testRefused'.tr(args: {'reason': result.reason ?? ''});
    messenger.showSnackBar(SnackBar(content: Text(message)));
  } catch (error) {
    messenger.showSnackBar(SnackBar(content: Text(localizedError(error))));
  }
}

Future<void> _confirmRemove(
  BuildContext context,
  WidgetRef ref,
  EeIdentityProvider provider,
) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text('ee.identity.removeTitle'.tr()),
      content: Text('ee.identity.removeBody'.tr()),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: Text('common.cancel'.tr()),
        ),
        TextButton(
          key: const Key('identity-remove-confirm'),
          onPressed: () => Navigator.of(context).pop(true),
          child: Text('ee.identity.remove'.tr()),
        ),
      ],
    ),
  );
  if (ok != true || !context.mounted) return;
  await _run(
    context,
    () => ref.read(eeIdentityProvidersProvider.notifier).remove(provider.id),
  );
}

/// The editor. `null` creates; a provider edits.
Future<void> _openEditor(
  BuildContext context,
  WidgetRef ref,
  EeIdentityProvider? provider,
) => showModalBottomSheet<void>(
  context: context,
  isScrollControlled: true,
  builder: (context) => Padding(
    padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
    child: _Editor(provider: provider),
  ),
);

class _Editor extends ConsumerStatefulWidget {
  const _Editor({required this.provider});
  final EeIdentityProvider? provider;

  @override
  ConsumerState<_Editor> createState() => _EditorState();
}

class _EditorState extends ConsumerState<_Editor> {
  late String _type = widget.provider?.type ?? 'ldap';
  late final _name = TextEditingController(
    text: widget.provider?.displayName ?? '',
  );
  late final _url = TextEditingController(
    text: widget.provider?.config['url'] as String? ?? '',
  );
  late final _baseDn = TextEditingController(
    text: widget.provider?.config['baseDn'] as String? ?? '',
  );
  late final _bindDn = TextEditingController(
    text: widget.provider?.config['bindDn'] as String? ?? '',
  );
  late final _issuer = TextEditingController(
    text: widget.provider?.config['issuer'] as String? ?? '',
  );
  late final _clientId = TextEditingController(
    text: widget.provider?.config['clientId'] as String? ?? '',
  );
  final _secret = TextEditingController();
  bool _busy = false;

  @override
  void dispose() {
    for (final c in [
      _name,
      _url,
      _baseDn,
      _bindDn,
      _issuer,
      _clientId,
      _secret,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final editing = widget.provider != null;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              editing
                  ? 'ee.identity.editTitle'.tr()
                  : 'ee.identity.addTitle'.tr(),
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 12),
            if (!editing)
              DropdownButtonFormField<String>(
                key: const Key('identity-type'),
                initialValue: _type,
                decoration: InputDecoration(
                  labelText: 'ee.identity.typeLabel'.tr(),
                ),
                items: [
                  for (final type in ['ldap', 'saml', 'oidc'])
                    DropdownMenuItem(
                      value: type,
                      child: Text('ee.identity.type.$type'.tr()),
                    ),
                ],
                onChanged: (value) => setState(() => _type = value ?? 'ldap'),
              ),
            TextField(
              key: const Key('identity-name'),
              controller: _name,
              decoration: InputDecoration(
                labelText: 'ee.identity.nameLabel'.tr(),
                helperText: 'ee.identity.nameHelp'.tr(),
              ),
            ),
            if (_type == 'ldap') ...[
              TextField(
                key: const Key('identity-url'),
                controller: _url,
                decoration: InputDecoration(
                  labelText: 'ee.identity.urlLabel'.tr(),
                  helperText: 'ee.identity.urlHelp'.tr(),
                ),
              ),
              TextField(
                key: const Key('identity-basedn'),
                controller: _baseDn,
                decoration: InputDecoration(
                  labelText: 'ee.identity.baseDnLabel'.tr(),
                ),
              ),
              TextField(
                key: const Key('identity-binddn'),
                controller: _bindDn,
                decoration: InputDecoration(
                  labelText: 'ee.identity.bindDnLabel'.tr(),
                  helperText: 'ee.identity.bindDnHelp'.tr(),
                ),
              ),
            ] else ...[
              TextField(
                key: const Key('identity-issuer'),
                controller: _issuer,
                decoration: InputDecoration(
                  labelText: 'ee.identity.issuerLabel'.tr(),
                ),
              ),
              TextField(
                key: const Key('identity-clientid'),
                controller: _clientId,
                decoration: InputDecoration(
                  labelText: 'ee.identity.clientIdLabel'.tr(),
                ),
              ),
            ],
            if (_type != 'saml')
              TextField(
                key: const Key('identity-secret'),
                controller: _secret,
                obscureText: true,
                decoration: InputDecoration(
                  labelText: 'ee.identity.secretLabel'.tr(),
                  helperText: editing
                      ? 'ee.identity.secretReplaceHelp'.tr()
                      : 'ee.identity.secretHelp'.tr(),
                ),
              ),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: _busy ? null : () => Navigator.of(context).pop(),
                  child: Text('common.cancel'.tr()),
                ),
                FilledButton(
                  key: const Key('identity-save'),
                  onPressed: _busy ? null : _save,
                  child: Text('common.save'.tr()),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Map<String, dynamic> _config() => _type == 'ldap'
      ? {
          'url': _url.text.trim(),
          'baseDn': _baseDn.text.trim(),
          if (_bindDn.text.trim().isNotEmpty) 'bindDn': _bindDn.text.trim(),
        }
      : {'issuer': _issuer.text.trim(), 'clientId': _clientId.text.trim()};

  Future<void> _save() async {
    setState(() => _busy = true);
    final navigator = Navigator.of(context);
    final controller = ref.read(eeIdentityProvidersProvider.notifier);
    final secret = _secret.text.isEmpty ? null : _secret.text;
    try {
      if (widget.provider == null) {
        await controller.create(
          type: _type,
          displayName: _name.text.trim(),
          config: _config(),
          secret: secret,
        );
      } else {
        await controller.patch(
          widget.provider!.id,
          displayName: _name.text.trim(),
          config: _config(),
          // Absent, not null: an empty box means "leave the stored one",
          // which is different from removing it.
          secret: secret ?? eeKeepSecret,
        );
      }
      navigator.pop();
    } catch (error) {
      if (!mounted) return;
      setState(() => _busy = false);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(localizedError(error))));
    }
  }
}
