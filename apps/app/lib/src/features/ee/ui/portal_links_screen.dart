import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/date_format.dart';
import '../../../core/error_messages.dart';
import '../../../core/persisted_prefs.dart';
import '../../../i18n/i18n.dart';
import '../../../theme/tokens.dart';
import '../../../widgets/fab_clearance.dart';
import '../../../widgets/status_views.dart';
import '../../../widgets/swipe_actions.dart' show awConfirmDelete;
import '../providers.dart' show canProvider;
import '../data/portal_links_models.dart';
import '../data/services_models.dart';
import '../portal_links_providers.dart';
import '../services_providers.dart';
import '../units_providers.dart';
import '../../../widgets/route_leading.dart';

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
      appBar: AppBar(
        leading: awRouteLeading(context),
        title: Text('ee.portal.title'.tr()),
      ),
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
      // OPH-356 (UI-AUDIT #61): a create button exists on a yes only.
      floatingActionButton:
          data.value == null || !ref.watch(canProvider('portal.manage_links'))
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
    // UI-AUDIT #67 — rows that would still read the same (same services,
    // desk and minute of making) carry their short reference too, so the
    // one to pause or revoke can be told apart from its twin.
    final seen = <String>{};
    final twins = <String>{};
    for (final link in data.links) {
      final look = _lookOf(link, nameOf[link.serviceId]);
      if (!seen.add(look)) twins.add(look);
    }

    return ListView(
      padding: EdgeInsets.only(
        bottom: awScrollEndPadding(context, AwSpace.x4, fab: true),
      ),
      children: [
        _QuotaCard(links: data.linkQuota, tickets: data.ticketQuota),
        if (!data.attachmentScanOn) const _ScanOffCard(),
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
          _LinkTile(
            link: link,
            serviceName: nameOf[link.serviceId],
            showRef: twins.contains(_lookOf(link, nameOf[link.serviceId])),
          ),
      ],
    );
  }
}

/// Files through these doors are not virus-scanned — said beside the doors.
///
/// The person opening a public link is the one deciding to take files from
/// strangers, so this is where they learn that nothing checks them. The mark
/// carries the colour and the sentences are body text, for the contrast
/// reason in the header. Nothing here can switch scanning on: it is a server
/// setting, and the card says who holds it.
class _ScanOffCard extends StatelessWidget {
  const _ScanOffCard();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tokens = context.awTokens;
    return Card(
      key: const Key('portal-scan-off'),
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.gpp_maybe_outlined, color: tokens.warning, size: 22),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'ee.portal.scanOffTitle'.tr(),
                    style: theme.textTheme.titleSmall,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'ee.portal.scanOffBody'.tr(),
                    style: theme.textTheme.bodySmall,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
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
          // A phone's width: the label wraps rather than pushing the count
          // off the card.
          Expanded(child: Text(label, style: theme.textTheme.bodyMedium)),
          const SizedBox(width: AwSpace.x2),
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
  const _LinkTile({required this.link, this.serviceName, this.showRef = false});
  final EePortalLink link;
  final String? serviceName;

  /// Another row reads exactly like this one: say the reference as well.
  final bool showRef;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final tokens = context.awTokens;
    final format = ref.watch(dateFormatProvider);

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
      // EE-197 — a catalogue link has no ONE service to name, so it says how
      // many it opens onto. Falling through to "unknown service" would have
      // read as a broken row for a link that is working exactly as minted.
      // UI-AUDIT #67 — a server that names the services (EE-301) is believed
      // first, so two catalogue rows read as their contents, not "2 services".
      title: Text(
        _titleOf(link, serviceName),
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: Text(
        [
          // And the WORD, in body colour.
          'ee.portal.state.${link.state.name}'.tr(),
          if (link.state != EePortalLinkState.revoked)
            'ee.portal.expiresAt'.tr(
              args: {'date': _date(context, link.expiresAt)},
            ),
          // UI-AUDIT #67 — which desk and when it was made: the two facts
          // that tell apart rows minted for the same service.
          if (link.unitName != null && link.unitName!.isNotEmpty)
            link.unitName!,
          // To the minute (UI-AUDIT #67): three links minted for one service
          // on one day differ by the hour they were made.
          if (link.createdAt != null)
            'ee.portal.createdAt'.tr(
              args: {'date': awFormatDateTime(link.createdAt!, format: format)},
            ),
          if (link.hasCustomFields) 'ee.portal.customFields'.tr(),
          if (showRef) 'ee.portal.ref'.tr(args: {'ref': portalLinkRef(link)}),
        ].join(' · '),
        maxLines: 3,
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
        // UI-AUDIT #13 — the length is chosen and the new end is shown
        // before anything is sent. The body stays `{ ttlHours }` (EE-301's
        // contract); a current server adds it to the later of now and the
        // present end, so a long link is never pulled forward.
        final days = await _pickExtension(context, link);
        if (days != null && context.mounted) {
          await _guard(context, () => controller.extend(link.id, days * 24));
        }
      case 'revoke':
        // UI-AUDIT #65 — "Keep it" beside "Revoke link", the irreversible one
        // in the error role, rather than "Cancel" beside "Cancel".
        final confirmed = await awConfirmDelete(
          context,
          title: 'ee.portal.revokeTitle'.tr(),
          // Revocation is the only irreversible act on this screen, so it is
          // the only one that asks — and the question says WHY it is asking.
          body: 'ee.portal.revokeBody'.tr(),
          confirmLabel: 'ee.portal.revokeConfirm'.tr(),
          cancelLabel: 'ee.portal.keep'.tr(),
          confirmKey: const Key('portal-revoke-confirm'),
        );
        // The dialog awaited above may have outlived this element.
        if (confirmed && context.mounted) {
          await _guard(context, () => controller.revoke(link.id));
        }
    }
  }
}

/// What a row says before its reference: services, desk, minute of making.
String _lookOf(EePortalLink link, String? serviceName) {
  final made = link.createdAt;
  final minute = made == null
      ? ''
      : '${made.year}-${made.month}-${made.day} ${made.hour}:${made.minute}';
  return '${_titleOf(link, serviceName)}|${link.unitName ?? ''}|$minute';
}

/// A link's short reference: the tail of its id — the random half of a ULID,
/// so two links made in the same millisecond still differ. Not the secret
/// (the URL's token is shown once and never again).
String portalLinkRef(EePortalLink link) {
  final id = link.id;
  return (id.length <= 6 ? id : id.substring(id.length - 6)).toUpperCase();
}

String _titleOf(EePortalLink link, String? serviceName) {
  if (link.serviceNames.isNotEmpty) return link.serviceNames.join(', ');
  if (link.serviceId == null) {
    return 'ee.portal.catalogueCount'.tr(
      args: {'count': '${link.serviceCount}'},
    );
  }
  return serviceName ?? 'ee.portal.unknownService'.tr();
}

/// The lengths a link can be given, in days — at creation and on extension.
const _ttlDays = [1, 2, 7, 30];

String _daysLabel(int days) => days == 1
    ? 'ee.portal.ttlDayOne'.tr()
    : 'ee.portal.ttlDays'.tr(args: {'days': '$days'});

/// UI-AUDIT #13 — how long to extend by, with the resulting end in the row.
///
/// The end is computed the way the server computes it (EE-301): from the
/// later of now and the present end. Saying it before the tap is what makes
/// "extend" a decision rather than a fixed 48 hours somebody has to trust.
Future<int?> _pickExtension(BuildContext context, EePortalLink link) {
  var days = 2;
  return showDialog<int>(
    context: context,
    builder: (context) => StatefulBuilder(
      builder: (context, setState) {
        final now = DateTime.now();
        final base = link.expiresAt.isAfter(now) ? link.expiresAt : now;
        return AlertDialog(
          key: const Key('portal-extend-dialog'),
          semanticLabel: 'ee.portal.extendTitle'.tr(),
          title: Text('ee.portal.extendTitle'.tr()),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  link.expiresAt.isAfter(now)
                      ? 'ee.portal.extendFrom'.tr(
                          args: {'date': _date(context, link.expiresAt)},
                        )
                      : 'ee.portal.extendFromNow'.tr(),
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
                const SizedBox(height: 8),
                RadioGroup<int>(
                  groupValue: days,
                  onChanged: (value) => setState(() => days = value ?? days),
                  child: Column(
                    children: [
                      for (final option in _ttlDays)
                        RadioListTile<int>(
                          key: Key('portal-extend-$option'),
                          contentPadding: EdgeInsets.zero,
                          value: option,
                          title: Text(_daysLabel(option)),
                          subtitle: Text(
                            'ee.portal.extendUntil'.tr(
                              args: {
                                'date': _date(
                                  context,
                                  base.add(Duration(days: option)),
                                ),
                              },
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text('ee.portal.keep'.tr()),
            ),
            FilledButton(
              key: const Key('portal-extend-confirm'),
              onPressed: () => Navigator.of(context).pop(days),
              child: Text('ee.portal.extendConfirm'.tr()),
            ),
          ],
        );
      },
    ),
  );
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
  // UI-AUDIT #68 — offered in days; the wire stays hours.
  var ttlDays = 2;
  // EE-197 — a catalogue link shows a chosen SET instead of one service. The
  // single-service link stays the default, because the narrowest surface
  // should be the one you get without deciding anything.
  var catalogue = false;
  final chosen = <String>{};

  final created = await showDialog<EePortalLinkCreated>(
    context: context,
    builder: (context) => StatefulBuilder(
      builder: (context, setState) {
        final service = services.where((s) => s.id == serviceId).firstOrNull;
        // The picker appears exactly when the server would refuse without it.
        final needsUnit = !catalogue && (service?.unitIds.length ?? 0) > 1;
        if (!needsUnit) unitId = null;

        return AlertDialog(
          semanticLabel: 'ee.portal.create'.tr(),
          title: Text('ee.portal.create'.tr()),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SwitchListTile(
                  key: const Key('portal-catalogue'),
                  contentPadding: EdgeInsets.zero,
                  value: catalogue,
                  title: Text('ee.portal.catalogue'.tr()),
                  subtitle: Text('ee.portal.catalogueHelp'.tr()),
                  onChanged: (value) => setState(() => catalogue = value),
                ),
                if (!catalogue)
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
                  )
                else
                  // A service answered by TWO desks cannot go in a catalogue,
                  // and the row says so rather than being hidden. The single
                  // link asks which desk at mint time; a catalogue has one
                  // page and many services, so the pick would have to be per
                  // service — which is a screen this round did not build. The
                  // server refuses it either way (TICKET_UNIT_REQUIRED), so
                  // offering it here would be a checkbox that answers 400.
                  for (final s in services)
                    CheckboxListTile(
                      key: Key('portal-catalogue-${s.id}'),
                      contentPadding: EdgeInsets.zero,
                      dense: true,
                      value: chosen.contains(s.id),
                      title: Text(s.name),
                      subtitle: s.unitIds.length > 1
                          ? Text('ee.portal.catalogueAmbiguous'.tr())
                          : null,
                      onChanged: s.unitIds.length > 1
                          ? null
                          : (on) => setState(() {
                              if (on ?? false) {
                                chosen.add(s.id);
                              } else {
                                chosen.remove(s.id);
                              }
                            }),
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
                  initialValue: ttlDays,
                  decoration: InputDecoration(labelText: 'ee.portal.ttl'.tr()),
                  items: [
                    for (final days in _ttlDays)
                      DropdownMenuItem(
                        value: days,
                        child: Text(_daysLabel(days)),
                      ),
                  ],
                  onChanged: (value) => setState(() => ttlDays = value ?? 2),
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
              onPressed:
                  (catalogue ? chosen.isEmpty : serviceId == null) ||
                      (needsUnit && unitId == null)
                  ? null
                  : () async {
                      final messenger = ScaffoldMessenger.maybeOf(context);
                      final navigator = Navigator.of(context);
                      try {
                        final result = await ref
                            .read(eePortalLinksProvider.notifier)
                            .create(
                              serviceId: catalogue ? null : serviceId,
                              serviceIds: catalogue
                                  ? chosen.toList(growable: false)
                                  : null,
                              unitId: unitId,
                              ttlHours: ttlDays * 24,
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
        // UI-AUDIT #64 — read out as what it is, not as a nameless "Alert".
        semanticLabel: 'ee.portal.createdTitle'.tr(),
        title: Text('ee.portal.createdTitle'.tr()),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Semantics(
              label: 'ee.portal.urlLabel'.tr(),
              child: SelectableText(
                created.url,
                key: const Key('portal-url-text'),
                style: Theme.of(context).textTheme.bodySmall,
              ),
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
            onPressed: () => _copyUrl(context, created.url),
            child: Text('ee.portal.copy'.tr()),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text('common.done'.tr()),
          ),
        ],
      ),
    );

/// UI-AUDIT D2 — a clipboard the browser refuses says so.
///
/// This is the only chance to keep the URL, so a silent failure here is the
/// worst kind: the person closes the dialog believing they have it. On a
/// refusal the snackbar tells them to select the address by hand while the
/// dialog is still open.
Future<void> _copyUrl(BuildContext context, String url) async {
  final messenger = ScaffoldMessenger.maybeOf(context);
  try {
    await Clipboard.setData(ClipboardData(text: url));
    messenger?.showSnackBar(SnackBar(content: Text('ee.portal.copied'.tr())));
  } catch (_) {
    messenger?.showSnackBar(
      SnackBar(content: Text('ee.portal.copyFailed'.tr())),
    );
  }
}
