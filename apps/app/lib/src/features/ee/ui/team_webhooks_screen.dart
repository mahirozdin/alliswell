import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/error_messages.dart';
import '../../../i18n/i18n.dart';
import '../../../theme/tokens.dart';
import '../../../widgets/status_views.dart';
import '../data/team_webhooks_models.dart';
import '../team_webhooks_providers.dart';

/// The team's outgoing endpoints (EE-175/EE-176).
///
/// ── THE SECRET IS SHOWN ONCE, AND THE SCREEN SAYS SO WHILE SHOWING IT ────
///
/// The AI key screen shows a key NEVER, because nothing needs to leave. This
/// one shows a secret ONCE, because somebody has to paste it into the system
/// at the other end — and a value that cannot be retrieved has to be presented
/// as a value that cannot be retrieved, at the moment it is on screen, or the
/// person closes the dialog and learns the rule the expensive way. After that
/// a row reads "•••• 9f2c", which is the whole of what anybody can learn here.
///
/// ── THE EVENT LIST COMES FROM THE SERVER ─────────────────────────────────
///
/// Checkboxes, not a text field, and the boxes are built from what the server
/// says it fires. A free text box would let somebody subscribe to an event
/// this product never sends, and the symptom — a call that never arrives — is
/// indistinguishable from a broken integration.
///
/// ── THE TEST BUTTON POINTS AT A ROW, NOT AT A TICK ───────────────────────
///
/// It queues a real delivery through the real queue, so the honest report is
/// the delivery list below refreshing with a new row. A green tick would be
/// this screen claiming something it cannot see: whether the far end answered.
class EeTeamWebhooksScreen extends ConsumerWidget {
  const EeTeamWebhooksScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final data = ref.watch(eeTeamWebhooksProvider);

    return Scaffold(
      appBar: AppBar(title: Text('ee.webhooks.title'.tr())),
      body: data.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => AwErrorState(
          message: localizedError(error),
          onRetry: () => ref.invalidate(eeTeamWebhooksProvider),
        ),
        data: (value) {
          if (value == null) {
            return AwEmptyState(
              icon: Icons.link_off_outlined,
              title: 'ee.webhooks.unavailable'.tr(),
              message: 'ee.webhooks.unavailableBody'.tr(),
            );
          }
          if (value.items.isEmpty) {
            return Padding(
              padding: const EdgeInsets.all(AwSpace.x6),
              child: AwEmptyState(
                icon: Icons.webhook_outlined,
                title: 'ee.webhooks.emptyTitle'.tr(),
                message: 'ee.webhooks.emptyBody'.tr(),
              ),
            );
          }
          return ListView(
            padding: const EdgeInsets.only(bottom: 88),
            children: [
              for (final hook in value.items)
                _EndpointCard(hook: hook, vocabulary: value.eventClasses),
            ],
          );
        },
      ),
      floatingActionButton: data.value == null
          ? null
          : FloatingActionButton(
              key: const Key('team-webhooks-add'),
              tooltip: 'ee.webhooks.add'.tr(),
              onPressed: () => _add(context, ref, data.value!.eventClasses),
              child: const Icon(Icons.add),
            ),
    );
  }
}

Future<void> _add(
  BuildContext context,
  WidgetRef ref,
  List<String> vocabulary,
) async {
  final result = await showDialog<_EndpointDraft>(
    context: context,
    builder: (_) => _EndpointDialog(vocabulary: vocabulary),
  );
  if (result == null || !context.mounted) return;
  try {
    final secret = await ref
        .read(eeTeamWebhooksProvider.notifier)
        .create(url: result.url, eventClasses: result.eventClasses);
    if (context.mounted) await _showSecret(context, secret);
  } catch (error) {
    if (context.mounted) _say(context, localizedError(error));
  }
}

/// The one moment the secret exists outside the server. Not a snackbar: a
/// snackbar is a thing that disappears while you are reaching for a pen.
Future<void> _showSecret(BuildContext context, String? secret) async {
  if (secret == null) return;
  await showDialog<void>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      key: const Key('team-webhooks-secret'),
      title: Text('ee.webhooks.secretTitle'.tr()),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('ee.webhooks.secretBody'.tr()),
          const SizedBox(height: AwSpace.x4),
          SelectableText(
            secret,
            style: Theme.of(
              dialogContext,
            ).textTheme.bodyMedium?.copyWith(fontFamily: 'monospace'),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () async {
            await Clipboard.setData(ClipboardData(text: secret));
            if (dialogContext.mounted) Navigator.of(dialogContext).pop();
          },
          child: Text('common.copy'.tr()),
        ),
        FilledButton(
          onPressed: () => Navigator.of(dialogContext).pop(),
          child: Text('common.done'.tr()),
        ),
      ],
    ),
  );
}

void _say(BuildContext context, String message) {
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
}

class _EndpointCard extends ConsumerWidget {
  const _EndpointCard({required this.hook, required this.vocabulary});

  final EeWebhook hook;
  final List<String> vocabulary;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final tokens = context.awTokens;

    return Card(
      margin: const EdgeInsets.fromLTRB(
        AwSpace.x4,
        AwSpace.x2,
        AwSpace.x4,
        AwSpace.x2,
      ),
      child: ExpansionTile(
        key: Key('webhook-${hook.id}'),
        leading: Icon(
          hook.enabled ? Icons.webhook : Icons.pause_circle_outline,
          // A mark in a state colour, and the word beside it in ordinary ink
          // (EE-097's rule): `warning` is short of what a label needs.
          color: hook.enabled ? tokens.success : tokens.warning,
        ),
        title: Text(hook.url, maxLines: 2, overflow: TextOverflow.ellipsis),
        subtitle: Text(
          hook.enabled ? 'ee.webhooks.active'.tr() : 'ee.webhooks.paused'.tr(),
          style: theme.textTheme.bodySmall,
        ),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AwSpace.x4,
              0,
              AwSpace.x4,
              AwSpace.x4,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
                  spacing: AwSpace.x2,
                  runSpacing: AwSpace.x2,
                  children: [
                    for (final name in hook.eventClasses)
                      Chip(label: Text(name)),
                  ],
                ),
                const SizedBox(height: AwSpace.x3),
                Text(
                  hook.secretLast4 == null
                      ? 'ee.webhooks.noSecret'.tr()
                      : 'ee.webhooks.secretTail'.tr(
                          args: {'last4': hook.secretLast4!},
                        ),
                  style: theme.textTheme.bodySmall,
                ),
                const SizedBox(height: AwSpace.x3),
                Wrap(
                  spacing: AwSpace.x2,
                  children: [
                    TextButton.icon(
                      key: Key('webhook-test-${hook.id}'),
                      onPressed: () => _test(context, ref),
                      icon: const Icon(Icons.send_outlined),
                      label: Text('ee.webhooks.test'.tr()),
                    ),
                    TextButton.icon(
                      key: Key('webhook-events-${hook.id}'),
                      onPressed: () => _editEvents(context, ref),
                      icon: const Icon(Icons.checklist_outlined),
                      label: Text('ee.webhooks.events'.tr()),
                    ),
                    TextButton.icon(
                      key: Key('webhook-toggle-${hook.id}'),
                      onPressed: () => _toggle(context, ref),
                      icon: Icon(
                        hook.enabled
                            ? Icons.pause_outlined
                            : Icons.play_arrow_outlined,
                      ),
                      label: Text(
                        hook.enabled
                            ? 'ee.webhooks.pause'.tr()
                            : 'ee.webhooks.resume'.tr(),
                      ),
                    ),
                    TextButton.icon(
                      key: Key('webhook-rotate-${hook.id}'),
                      onPressed: () => _rotate(context, ref),
                      icon: const Icon(Icons.autorenew),
                      label: Text('ee.webhooks.rotate'.tr()),
                    ),
                    TextButton.icon(
                      key: Key('webhook-delete-${hook.id}'),
                      onPressed: () => _remove(context, ref),
                      icon: const Icon(Icons.delete_outline),
                      label: Text('common.delete'.tr()),
                    ),
                  ],
                ),
                const Divider(height: AwSpace.x8),
                Text(
                  'ee.webhooks.deliveries'.tr(),
                  style: theme.textTheme.titleSmall,
                ),
                _Deliveries(endpointId: hook.id),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _test(BuildContext context, WidgetRef ref) async {
    try {
      await ref.read(eeTeamWebhooksProvider.notifier).sendTest(hook.id);
      ref.invalidate(eeWebhookDeliveriesProvider(hook.id));
      if (context.mounted) _say(context, 'ee.webhooks.testQueued'.tr());
    } catch (error) {
      if (context.mounted) _say(context, localizedError(error));
    }
  }

  Future<void> _toggle(BuildContext context, WidgetRef ref) async {
    try {
      await ref
          .read(eeTeamWebhooksProvider.notifier)
          .setEnabled(hook.id, enabled: !hook.enabled);
    } catch (error) {
      if (context.mounted) _say(context, localizedError(error));
    }
  }

  Future<void> _rotate(BuildContext context, WidgetRef ref) async {
    try {
      final secret = await ref
          .read(eeTeamWebhooksProvider.notifier)
          .rotateSecret(hook.id);
      if (context.mounted) await _showSecret(context, secret);
    } catch (error) {
      if (context.mounted) _say(context, localizedError(error));
    }
  }

  Future<void> _editEvents(BuildContext context, WidgetRef ref) async {
    final picked = await showDialog<List<String>>(
      context: context,
      builder: (_) =>
          _EventsDialog(vocabulary: vocabulary, selected: hook.eventClasses),
    );
    if (picked == null || !context.mounted) return;
    try {
      await ref
          .read(eeTeamWebhooksProvider.notifier)
          .setEvents(hook.id, picked);
    } catch (error) {
      if (context.mounted) _say(context, localizedError(error));
    }
  }

  Future<void> _remove(BuildContext context, WidgetRef ref) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('ee.webhooks.deleteTitle'.tr()),
        content: Text('ee.webhooks.deleteBody'.tr()),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text('common.cancel'.tr()),
          ),
          FilledButton(
            key: const Key('webhook-delete-confirm'),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text('common.delete'.tr()),
          ),
        ],
      ),
    );
    if (ok != true || !context.mounted) return;
    try {
      await ref.read(eeTeamWebhooksProvider.notifier).remove(hook.id);
    } catch (error) {
      if (context.mounted) _say(context, localizedError(error));
    }
  }
}

class _Deliveries extends ConsumerWidget {
  const _Deliveries({required this.endpointId});
  final String endpointId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final tokens = context.awTokens;
    final deliveries = ref.watch(eeWebhookDeliveriesProvider(endpointId));

    return deliveries.when(
      loading: () => const Padding(
        padding: EdgeInsets.all(AwSpace.x4),
        child: LinearProgressIndicator(),
      ),
      error: (error, _) => AwInlineError(message: localizedError(error)),
      data: (items) {
        if (items.isEmpty) {
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: AwSpace.x3),
            child: Text(
              'ee.webhooks.noDeliveries'.tr(),
              style: theme.textTheme.bodySmall,
            ),
          );
        }
        return Column(
          children: [
            for (final row in items)
              ListTile(
                key: Key('delivery-${row.id}'),
                dense: true,
                contentPadding: EdgeInsets.zero,
                leading: Icon(
                  row.failed
                      ? Icons.error_outline
                      : row.sentAt != null
                      ? Icons.check_circle_outline
                      : Icons.schedule,
                  color: row.failed ? theme.colorScheme.error : tokens.success,
                ),
                title: Text(row.eventClass),
                subtitle: Text(
                  row.lastError ??
                      'ee.webhooks.attempts'.tr(args: {'n': '${row.attempts}'}),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
          ],
        );
      },
    );
  }
}

class _EndpointDraft {
  const _EndpointDraft({required this.url, required this.eventClasses});
  final String url;
  final List<String> eventClasses;
}

class _EndpointDialog extends StatefulWidget {
  const _EndpointDialog({required this.vocabulary});
  final List<String> vocabulary;

  @override
  State<_EndpointDialog> createState() => _EndpointDialogState();
}

class _EndpointDialogState extends State<_EndpointDialog> {
  final _url = TextEditingController();
  final _selected = <String>{};

  @override
  void dispose() {
    _url.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('ee.webhooks.add'.tr()),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              key: const Key('webhook-url-field'),
              controller: _url,
              keyboardType: TextInputType.url,
              // Rebuild on every keystroke, because Save is disabled until
              // this field has something in it. Without this the button stays
              // grey after somebody has typed a perfectly good address and
              // only wakes when they touch something else — a control that
              // lies about its own state (DESIGN §22).
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(
                labelText: 'ee.webhooks.url'.tr(),
                hintText:
                    'https://', // i18n-ignore: a URL scheme, the same in every language.
              ),
            ),
            const SizedBox(height: AwSpace.x4),
            Text('ee.webhooks.events'.tr()),
            for (final name in widget.vocabulary)
              CheckboxListTile(
                key: Key('webhook-event-$name'),
                dense: true,
                contentPadding: EdgeInsets.zero,
                value: _selected.contains(name),
                title: Text(name),
                onChanged: (on) => setState(() {
                  if (on ?? false) {
                    _selected.add(name);
                  } else {
                    _selected.remove(name);
                  }
                }),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text('common.cancel'.tr()),
        ),
        FilledButton(
          key: const Key('webhook-create-confirm'),
          // No dead controls (DESIGN §22): nothing can be saved until there is
          // an address AND at least one event, because an endpoint subscribed
          // to nothing is a row that will never do anything.
          onPressed: _url.text.trim().isEmpty || _selected.isEmpty
              ? null
              : () => Navigator.of(context).pop(
                  _EndpointDraft(
                    url: _url.text.trim(),
                    eventClasses: _selected.toList(growable: false),
                  ),
                ),
          child: Text('common.save'.tr()),
        ),
      ],
    );
  }
}

class _EventsDialog extends StatefulWidget {
  const _EventsDialog({required this.vocabulary, required this.selected});
  final List<String> vocabulary;
  final List<String> selected;

  @override
  State<_EventsDialog> createState() => _EventsDialogState();
}

class _EventsDialogState extends State<_EventsDialog> {
  late final Set<String> _selected = {...widget.selected};

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('ee.webhooks.events'.tr()),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final name in widget.vocabulary)
              CheckboxListTile(
                key: Key('webhook-edit-event-$name'),
                dense: true,
                contentPadding: EdgeInsets.zero,
                value: _selected.contains(name),
                title: Text(name),
                onChanged: (on) => setState(() {
                  if (on ?? false) {
                    _selected.add(name);
                  } else {
                    _selected.remove(name);
                  }
                }),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text('common.cancel'.tr()),
        ),
        FilledButton(
          onPressed: _selected.isEmpty
              ? null
              : () => Navigator.of(
                  context,
                ).pop(_selected.toList(growable: false)),
          child: Text('common.save'.tr()),
        ),
      ],
    );
  }
}
