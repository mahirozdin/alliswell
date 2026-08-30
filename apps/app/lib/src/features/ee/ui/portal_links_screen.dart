import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/error_messages.dart';
import '../../../i18n/i18n.dart';
import '../../../theme/tokens.dart';
import '../../../widgets/status_views.dart';
import '../data/portal_links_models.dart';
import '../data/services_models.dart';
import '../portal_links_providers.dart';
import '../services_providers.dart';
import '../units_providers.dart';

/// The public doors, and who may open them (EE-106).
///
/// ── THE URL IS SHOWN ONCE, AND THE SCREEN IS BUILT AROUND THAT ───────────
///
/// The server keeps a keyed digest of the token and nothing else (EE-101), so
/// "show me that link again" is a question with no answer anywhere in the
/// system. This is not a limitation to work around — it is the reason a
/// database dump is not a set of working links — so the screen states it
/// plainly at the moment of creation instead of letting somebody discover it
/// later: one dialog, the URL, a copy button, and a sentence saying it will
/// not be shown again.
///
/// ── COLOUR IS A MARK, MEANING IS A WORD (EE-097's rule) ──────────────────
///
/// A link's state is an icon in a state colour PLUS its own label. Nothing
/// here writes text in a state colour: `AwTokens.warning` measures 3.46 on the
/// light surface, which is enough for a mark and short of what a label needs.
/// `expired` takes the neutral disabled colour rather than amber — a link that
/// ran out did what it was told, and drawing it as a warning would make the
/// ordinary end of a link's life look like a fault.
///
/// ── THE PICKER EXISTS BECAUSE THE STRANGER CANNOT BE ASKED ───────────────
///
/// `resolveTicketDestination` refuses a service two units answer, and E11's
/// whole reason for moving that question to creation time is that the person
/// filling the public form does not know the org chart and must not be shown
/// it (ADR-0013 §3). So the unit picker here is not a convenience: it is where
/// that question is asked, and the server's refusal is what tells us to ask.
class EePortalLinksScreen extends ConsumerWidget {
  const EePortalLinksScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final data = ref.watch(eePortalLinksProvider);

    return Scaffold(
      appBar: AppBar(title: Text('ee.portal.title'.tr())),
      body: data.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => AwErrorState(
          message: localizedError(error),
          onRetry: () => ref.invalidate(eePortalLinksProvider),
        ),
        data: (value) {
          if (value == null) {
            return AwEmptyState(
              icon: Icons.link_off_outlined,
              title: 'ee.portal.unavailable'.tr(),
              message: 'ee.portal.unavailableBody'.tr(),
            );
          }
          return _Body(data: value);
        },
      ),
      floatingActionButton: data.value == null
          ? null
          : FloatingActionButton(
              key: const Key('portal-create'),
              tooltip: 'ee.portal.create'.tr(),
              onPressed: () => _createLink(context, ref),
              child: const Icon(Icons.add_link),
            ),
    );
  }
}

class _Body extends ConsumerWidget {
  const _Body({required this.data});
  final EePortalLinksData data;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final services = ref.watch(eeServicesProvider).value ?? const <EeService>[];
    final nameOf = {for (final s in services) s.id: s.name};

    return ListView(
      padding: const EdgeInsets.only(bottom: 88),
      children: [
        _QuotaCard(links: data.linkQuota, tickets: data.ticketQuota),
        if (data.links.isEmpty)
          Padding(
            padding: const EdgeInsets.all(24),
            child: AwEmptyState(
              icon: Icons.link_outlined,
              title: 'ee.portal.emptyTitle'.tr(),
              message: 'ee.portal.emptyBody'.tr(),
            ),
          ),
        for (final link in data.links)
          _LinkTile(link: link, serviceName: nameOf[link.serviceId]),
      ],
    );
  }
}

/// Both ceilings, beside the list they cap.
///
/// A screen that showed links without showing the room left could only ever
/// report a refusal AFTER the click. `max == null` is "unlimited" and says so
/// in words — rendering it as a number would turn "your plan has no ceiling"
/// into "your ceiling is nothing".
class _QuotaCard extends StatelessWidget {
  const _QuotaCard({required this.links, required this.tickets});
  final EePortalQuota links;
  final EePortalQuota tickets;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      key: const Key('portal-quota'),
      margin: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'ee.portal.quotaTitle'.tr(),
              style: theme.textTheme.titleSmall,
            ),
            const SizedBox(height: 8),
            _QuotaRow(label: 'ee.portal.quotaLinks'.tr(), quota: links),
            _QuotaRow(label: 'ee.portal.quotaTickets'.tr(), quota: tickets),
          ],
        ),
      ),
    );
  }
}

class _QuotaRow extends StatelessWidget {
  const _QuotaRow({required this.label, required this.quota});
  final String label;
  final EePortalQuota quota;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: theme.textTheme.bodyMedium),
          Text(
            quota.isUnlimited
                ? 'ee.portal.unlimited'.tr(args: {'used': '${quota.used}'})
                : 'ee.portal.ofMax'.tr(
                    args: {'used': '${quota.used}', 'max': '${quota.max}'},
                  ),
            style: theme.textTheme.bodyMedium?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class _LinkTile extends ConsumerWidget {
  const _LinkTile({required this.link, this.serviceName});
  final EePortalLink link;
  final String? serviceName;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final tokens = context.awTokens;

    // The MARK. `expired` is neutral, not amber: running out is what a link
    // with an expiry is supposed to do.
    final (icon, colour) = switch (link.state) {
      EePortalLinkState.active => (Icons.check_circle_outline, tokens.success),
      EePortalLinkState.disabled => (
        Icons.pause_circle_outline,
        theme.disabledColor,
      ),
      EePortalLinkState.expired => (Icons.schedule, theme.disabledColor),
      EePortalLinkState.revoked => (Icons.block, theme.colorScheme.error),
    };

    return ListTile(
      key: Key('portal-link-${link.id}'),
      // Keyed: the tile also carries a menu icon, so "the state mark" has
      // to be findable as itself rather than as "the first Icon in here".
      leading: Icon(icon, key: Key('portal-mark-${link.id}'), color: colour),
      title: Text(serviceName ?? 'ee.portal.unknownService'.tr()),
      subtitle: Text(
        [
          // And the WORD, in body colour.
          'ee.portal.state.${link.state.name}'.tr(),
          if (link.state != EePortalLinkState.revoked)
            'ee.portal.expiresAt'.tr(
              args: {'date': _date(context, link.expiresAt)},
            ),
          if (link.hasCustomFields) 'ee.portal.customFields'.tr(),
        ].join(' · '),
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: theme.textTheme.bodySmall,
      ),
      trailing: link.state.isEditable
          ? PopupMenuButton<String>(
              key: Key('portal-menu-${link.id}'),
              onSelected: (action) => _act(context, ref, action),
              itemBuilder: (context) => [
                PopupMenuItem(
                  value: 'toggle',
                  child: Text(
                    link.enabled
                        ? 'ee.portal.pause'.tr()
                        : 'ee.portal.resume'.tr(),
                  ),
                ),
                PopupMenuItem(
                  value: 'extend',
                  child: Text('ee.portal.extend'.tr()),
                ),
                PopupMenuItem(
                  value: 'revoke',
                  child: Text('ee.portal.revoke'.tr()),
                ),
              ],
            )
          // Nothing can be done to a revoked link, so it carries no controls
          // at all rather than a menu of things that would all refuse.
          : null,
    );
  }

  Future<void> _act(BuildContext context, WidgetRef ref, String action) async {
    final controller = ref.read(eePortalLinksProvider.notifier);
    switch (action) {
      case 'toggle':
        await _guard(
          context,
          () => controller.setEnabled(link.id, !link.enabled),
        );
      case 'extend':
        await _guard(context, () => controller.extend(link.id, 48));
      case 'revoke':
        final confirmed = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: Text('ee.portal.revokeTitle'.tr()),
            // Revocation is the only irreversible act on this screen, so it is
            // the only one that asks — and the question says WHY it is asking.
            content: Text('ee.portal.revokeBody'.tr()),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: Text('common.cancel'.tr()),
              ),
              FilledButton(
                key: const Key('portal-revoke-confirm'),
                onPressed: () => Navigator.of(context).pop(true),
                child: Text('ee.portal.revoke'.tr()),
              ),
            ],
          ),
        );
        // The dialog awaited above may have outlived this element.
        if ((confirmed ?? false) && context.mounted) {
          await _guard(context, () => controller.revoke(link.id));
        }
    }
  }
}

String _date(BuildContext context, DateTime at) =>
    MaterialLocalizations.of(context).formatShortDate(at);

/// Runs a mutation and puts the SERVER's sentence in front of the person.
///
/// The refusals on this surface are all actionable — "choose which unit",
/// "assign one before publishing", "revoke one or move to a larger plan" — and
/// replacing them with a generic failure would throw away the only useful part.
Future<void> _guard(
  BuildContext context,
  Future<void> Function() action,
) async {
  final messenger = ScaffoldMessenger.maybeOf(context);
  try {
    await action();
  } catch (error) {
    messenger?.showSnackBar(SnackBar(content: Text(localizedError(error))));
  }
}

Future<void> _createLink(BuildContext context, WidgetRef ref) async {
  final services = (ref.read(eeServicesProvider).value ?? const <EeService>[])
      .where((s) => !s.archived)
      .toList();
  final units = ref.read(eeUnitsProvider).value ?? const [];
  final unitName = {for (final u in units) u.id: u.name};

  String? serviceId = services.isEmpty ? null : services.first.id;
  String? unitId;
  int ttlHours = 48;

  final created = await showDialog<EePortalLinkCreated>(
    context: context,
    builder: (context) => StatefulBuilder(
      builder: (context, setState) {
        final service = services.where((s) => s.id == serviceId).firstOrNull;
        // The picker appears exactly when the server would refuse without it.
        final needsUnit = (service?.unitIds.length ?? 0) > 1;
        if (!needsUnit) unitId = null;

        return AlertDialog(
          title: Text('ee.portal.create'.tr()),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                DropdownButtonFormField<String>(
                  key: const Key('portal-service'),
                  initialValue: serviceId,
                  decoration: InputDecoration(
                    labelText: 'ee.portal.service'.tr(),
                  ),
                  items: [
                    for (final s in services)
                      DropdownMenuItem(value: s.id, child: Text(s.name)),
                  ],
                  onChanged: (value) => setState(() => serviceId = value),
                ),
                if (needsUnit) ...[
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    key: const Key('portal-unit'),
                    initialValue: unitId,
                    decoration: InputDecoration(
                      labelText: 'ee.portal.unit'.tr(),
                      helperText: 'ee.portal.unitHelp'.tr(),
                      helperMaxLines: 3,
                    ),
                    items: [
                      for (final id in service!.unitIds)
                        DropdownMenuItem(
                          value: id,
                          child: Text(unitName[id] ?? id),
                        ),
                    ],
                    onChanged: (value) => setState(() => unitId = value),
                  ),
                ],
                const SizedBox(height: 12),
                DropdownButtonFormField<int>(
                  key: const Key('portal-ttl'),
                  initialValue: ttlHours,
                  decoration: InputDecoration(labelText: 'ee.portal.ttl'.tr()),
                  items: [
                    for (final hours in [24, 48, 168, 720])
                      DropdownMenuItem(
                        value: hours,
                        child: Text(
                          'ee.portal.ttlHours'.tr(args: {'hours': '$hours'}),
                        ),
                      ),
                  ],
                  onChanged: (value) => setState(() => ttlHours = value ?? 48),
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
              key: const Key('portal-create-confirm'),
              onPressed: serviceId == null || (needsUnit && unitId == null)
                  ? null
                  : () async {
                      final messenger = ScaffoldMessenger.maybeOf(context);
                      final navigator = Navigator.of(context);
                      try {
                        final result = await ref
                            .read(eePortalLinksProvider.notifier)
                            .create(
                              serviceId: serviceId!,
                              unitId: unitId,
                              ttlHours: ttlHours,
                            );
                        navigator.pop(result);
                      } catch (error) {
                        messenger?.showSnackBar(
                          SnackBar(content: Text(localizedError(error))),
                        );
                      }
                    },
              child: Text('ee.portal.create'.tr()),
            ),
          ],
        );
      },
    ),
  );

  if (created != null && context.mounted) await _showUrlOnce(context, created);
}

/// The one moment the URL exists (EE-101).
///
/// A separate dialog rather than a snackbar: a snackbar disappears on its own,
/// and this is the only chance anybody has to keep this string. The sentence
/// under it is not decoration — it is the difference between "I closed it too
/// early" and "I have to make a new link now".
Future<void> _showUrlOnce(BuildContext context, EePortalLinkCreated created) =>
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        key: const Key('portal-url-once'),
        title: Text('ee.portal.createdTitle'.tr()),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SelectableText(
              created.url,
              key: const Key('portal-url-text'),
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 12),
            Text(
              'ee.portal.createdOnce'.tr(),
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
        actions: [
          TextButton(
            key: const Key('portal-url-copy'),
            onPressed: () async {
              await Clipboard.setData(ClipboardData(text: created.url));
              if (context.mounted) {
                ScaffoldMessenger.maybeOf(context)?.showSnackBar(
                  SnackBar(content: Text('ee.portal.copied'.tr())),
                );
              }
            },
            child: Text('ee.portal.copy'.tr()),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text('common.done'.tr()),
          ),
        ],
      ),
    );
