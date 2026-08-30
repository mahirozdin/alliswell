import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/error_messages.dart';
import '../../../i18n/i18n.dart';
import '../../../theme/tokens.dart';
import '../../../widgets/status_views.dart';
import '../data/team_ai_models.dart';
import '../team_ai_providers.dart';

/// The team's AI keys, and who else may bring one (EE-111, madde 13).
///
/// ── THE KEY IS NEVER SHOWN, AND THE SCREEN NEVER PRETENDS OTHERWISE ──────
///
/// The portal screen shows a URL once because the server cannot recover it.
/// This screen shows a key NEVER, and the difference matters: the server COULD
/// return it and deliberately does not, so the honest thing is to say what a
/// key row means rather than imply a hidden field. A configured provider reads
/// "•••• 9911" — four characters is the whole of what anybody can learn here —
/// and replacing a key is an act of typing a new one, not of revealing the old.
///
/// ── THE POLICY SITS ABOVE THE LIST, NOT IN A MENU ────────────────────────
///
/// "May members use their own keys" decides whether everything below it is the
/// team's only option or one of several. Hiding that behind an overflow menu
/// would let somebody store a company key and never notice that half the team
/// is still spending their own — which is exactly the arrangement madde 13
/// exists to end. So it is a switch at the top, with a sentence under it that
/// changes with its state.
///
/// ── COLOUR IS A MARK, MEANING IS A WORD (EE-097's rule) ──────────────────
///
/// A connection's state is an icon in a state colour PLUS its own label, and
/// no text is written in a state colour: `AwTokens.warning` measures 3.46 on
/// the light surface, which is enough for a mark and short of what a label
/// needs. Each mark carries its OWN key, because the tile also holds a delete
/// button — E11 lost three CI runs to finders that matched more than they
/// meant.
class EeTeamAiKeysScreen extends ConsumerWidget {
  const EeTeamAiKeysScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final data = ref.watch(eeTeamAiProvider);

    return Scaffold(
      appBar: AppBar(title: Text('ee.teamAi.title'.tr())),
      body: data.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => AwErrorState(
          message: localizedError(error),
          onRetry: () => ref.invalidate(eeTeamAiProvider),
        ),
        data: (value) {
          if (value == null) {
            return AwEmptyState(
              icon: Icons.key_off_outlined,
              title: 'ee.teamAi.unavailable'.tr(),
              message: 'ee.teamAi.unavailableBody'.tr(),
            );
          }
          return _Body(data: value);
        },
      ),
      floatingActionButton: data.value == null
          ? null
          : FloatingActionButton(
              key: const Key('team-ai-add'),
              tooltip: 'ee.teamAi.add'.tr(),
              onPressed: () => _edit(context, ref, data.value!),
              child: const Icon(Icons.key),
            ),
    );
  }
}

class _Body extends ConsumerWidget {
  const _Body({required this.data});
  final EeTeamAiData data;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ListView(
      padding: const EdgeInsets.only(bottom: 88),
      children: [
        _PolicyCard(
          allowed: data.personalKeysAllowed,
          hasKey: data.items.isNotEmpty,
        ),
        if (data.items.isEmpty)
          Padding(
            padding: const EdgeInsets.all(24),
            child: AwEmptyState(
              icon: Icons.vpn_key_outlined,
              title: 'ee.teamAi.emptyTitle'.tr(),
              message: 'ee.teamAi.emptyBody'.tr(),
            ),
          ),
        for (final item in data.items)
          _ConnectionTile(connection: item, data: data),
      ],
    );
  }
}

/// The policy, above the list it governs.
///
/// The sentence under the switch changes with BOTH the policy and whether a
/// team key exists, because the dangerous combination is a specific one:
/// personal keys forbidden and no team key configured means nobody in the team
/// can use AI at all. A screen that let an admin arrive there without saying so
/// would be handing them an outage disguised as a setting.
class _PolicyCard extends ConsumerWidget {
  const _PolicyCard({required this.allowed, required this.hasKey});
  final bool allowed;
  final bool hasKey;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final tokens = context.awTokens;
    final stranded = !allowed && !hasKey;

    return Card(
      margin: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SwitchListTile(
              key: const Key('team-ai-policy'),
              contentPadding: EdgeInsets.zero,
              value: allowed,
              title: Text('ee.teamAi.policyTitle'.tr()),
              onChanged: (next) => ref
                  .read(eeTeamAiProvider.notifier)
                  .setPersonalKeysAllowed(next),
            ),
            Text(
              allowed ? 'ee.teamAi.policyOn'.tr() : 'ee.teamAi.policyOff'.tr(),
              style: theme.textTheme.bodySmall,
            ),
            if (stranded) ...[
              const SizedBox(height: 12),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // The mark carries the colour; the sentence beside it is
                  // body text, for the contrast reason in the header.
                  Icon(
                    Icons.warning_amber_outlined,
                    key: const Key('team-ai-stranded'),
                    color: tokens.warning,
                    size: 20,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'ee.teamAi.strandedBody'.tr(),
                      style: theme.textTheme.bodySmall,
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _ConnectionTile extends ConsumerWidget {
  const _ConnectionTile({required this.connection, required this.data});
  final EeTeamAiConnection connection;
  final EeTeamAiData data;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final tokens = context.awTokens;

    final (icon, colour) = switch (connection.status) {
      EeTeamAiStatus.active => (Icons.check_circle_outline, tokens.success),
      EeTeamAiStatus.error => (Icons.error_outline, theme.colorScheme.error),
    };

    return ListTile(
      key: Key('team-ai-${connection.id}'),
      // Keyed: the tile also carries a delete button, so "the state mark" has
      // to be findable as itself rather than as "the first Icon in here".
      leading: Icon(
        icon,
        key: Key('team-ai-mark-${connection.id}'),
        color: colour,
      ),
      title: Text('ee.teamAi.provider.${connection.provider}'.tr()),
      subtitle: Text(
        [
          // And the WORD, in body colour.
          'ee.teamAi.status.${connection.status.name}'.tr(),
          if (connection.keyLast4 != null)
            'ee.teamAi.keyMask'.tr(args: {'last4': connection.keyLast4!}),
          if (connection.baseUrl != null) connection.baseUrl!,
        ].join(' · '),
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: theme.textTheme.bodySmall,
      ),
      onTap: () => _edit(context, ref, data, existing: connection),
      trailing: IconButton(
        key: Key('team-ai-remove-${connection.id}'),
        tooltip: 'ee.teamAi.remove'.tr(),
        icon: const Icon(Icons.delete_outline),
        onPressed: () => _remove(context, ref, connection),
      ),
    );
  }

  Future<void> _remove(
    BuildContext context,
    WidgetRef ref,
    EeTeamAiConnection connection,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('ee.teamAi.removeTitle'.tr()),
        content: Text('ee.teamAi.removeBody'.tr()),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text('common.cancel'.tr()),
          ),
          FilledButton(
            key: const Key('team-ai-remove-confirm'),
            onPressed: () => Navigator.of(context).pop(true),
            child: Text('ee.teamAi.remove'.tr()),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;
    await ref.read(eeTeamAiProvider.notifier).remove(connection.id);
  }
}

/// Add or replace. One dialog for both, because they are the same act: the
/// server keys a connection by provider and a second save overwrites the
/// first. A separate "edit" that could not change the key would be a form
/// where the most important field is missing.
Future<void> _edit(
  BuildContext context,
  WidgetRef ref,
  EeTeamAiData data, {
  EeTeamAiConnection? existing,
}) async {
  final providers = data.providers;
  if (providers.isEmpty) return;

  var provider = existing?.provider ?? providers.first;
  final key = TextEditingController();
  final baseUrl = TextEditingController(text: existing?.baseUrl ?? '');

  final saved = await showDialog<bool>(
    context: context,
    builder: (context) => StatefulBuilder(
      builder: (context, setState) => AlertDialog(
        title: Text(
          existing == null ? 'ee.teamAi.add'.tr() : 'ee.teamAi.replace'.tr(),
        ),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              DropdownButtonFormField<String>(
                key: const Key('team-ai-provider'),
                initialValue: provider,
                decoration: InputDecoration(
                  labelText: 'ee.teamAi.providerLabel'.tr(),
                ),
                // Only providers the SERVER can talk to: the list comes from
                // its adapter registry, so this dropdown cannot offer a name
                // that would be stored and then fail at the first request.
                items: [
                  for (final p in providers)
                    DropdownMenuItem(
                      value: p,
                      child: Text('ee.teamAi.provider.$p'.tr()),
                    ),
                ],
                // A provider is what a connection IS keyed by, so changing it
                // in a replace would silently create a second one.
                onChanged: existing != null
                    ? null
                    : (next) => setState(() => provider = next ?? provider),
              ),
              const SizedBox(height: 12),
              TextField(
                key: const Key('team-ai-key'),
                controller: key,
                obscureText: true,
                autocorrect: false,
                enableSuggestions: false,
                decoration: InputDecoration(
                  labelText: 'ee.teamAi.keyLabel'.tr(),
                  helperText: existing == null
                      ? 'ee.teamAi.keyHelp'.tr()
                      : 'ee.teamAi.keyReplaceHelp'.tr(),
                  helperMaxLines: 3,
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                key: const Key('team-ai-base-url'),
                controller: baseUrl,
                autocorrect: false,
                keyboardType: TextInputType.url,
                decoration: InputDecoration(
                  labelText: 'ee.teamAi.baseUrlLabel'.tr(),
                  helperText: 'ee.teamAi.baseUrlHelp'.tr(),
                  helperMaxLines: 3,
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text('common.cancel'.tr()),
          ),
          FilledButton(
            key: const Key('team-ai-save'),
            onPressed: () => Navigator.of(context).pop(true),
            child: Text('common.save'.tr()),
          ),
        ],
      ),
    ),
  );

  final apiKey = key.text.trim();
  final url = baseUrl.text.trim();
  key.dispose();
  baseUrl.dispose();
  if (saved != true) return;

  await ref
      .read(eeTeamAiProvider.notifier)
      .save(
        provider: provider,
        // Empty means "leave what is stored alone" on a replace, and the
        // server's own refusal answers an empty key on a first save — this
        // screen does not duplicate that rule, it lets the sentence through.
        apiKey: apiKey.isEmpty ? null : apiKey,
        baseUrl: url.isEmpty ? null : url,
      );
}
