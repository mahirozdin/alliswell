import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../i18n/i18n.dart';
import '../../../theme/tokens.dart';
import '../my_tickets_providers.dart';
import '../new_ticket_providers.dart';
import '../ticket_drafts_providers.dart';
import 'new_ticket_screen.dart';

/// EE-225 — the requests still on their way, above the ones that arrived.
///
/// "My requests" is a REST list and says so when there is no signal; the
/// drafts are the device's own and are right with none. So they sit ABOVE
/// the list, in their own section, and each says where it stands in words:
///
///   • on the phone — its last write has not left yet;
///   • waiting at the desk — the server keeps a draft it cannot convert rather
///     than refusing it (EE-216), and the row says WHICH reason it is, with
///     the one fix a person can make here: naming the service;
///   • refused — in the server's words, and put away by its person;
///   • sent — this session's conversions, pointing down at the request.
///
/// The section draws nothing at all when there is nothing to say: an empty
/// "drafts" heading above every requester's list would be noise.
class EeTicketDraftsSection extends ConsumerWidget {
  const EeTicketDraftsSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final drafts = ref.watch(draftStatusesProvider);
    // A draft that just went through is a request now: ask the list again,
    // so the two halves of this screen agree.
    ref.listen(
      draftStatusesProvider.select(
        (all) => all.where((d) => d.state == EeDraftState.sent).length,
      ),
      (previous, next) {
        if (next > (previous ?? 0)) ref.invalidate(eeMyTicketsProvider);
      },
    );
    if (drafts.isEmpty) return const SizedBox.shrink();
    final theme = Theme.of(context);
    return Padding(
      key: const Key('ticket-drafts'),
      padding: const EdgeInsets.only(bottom: AwSpace.x4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'ee.tickets.drafts.title'.tr(),
            style: theme.textTheme.titleSmall,
          ),
          const SizedBox(height: AwSpace.x2),
          for (final draft in drafts) _DraftCard(draft: draft),
        ],
      ),
    );
  }
}

class _DraftCard extends ConsumerWidget {
  const _DraftCard({required this.draft});

  final EeDraftStatus draft;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final catalog = ref.watch(eeCatalogProvider).value;
    final serviceName = draft.serviceId == null
        ? null
        : catalog?.services
              .where((service) => service.id == draft.serviceId)
              .firstOrNull
              ?.name;
    final (icon, status) = switch (draft.state) {
      EeDraftState.onDevice => (
        Icons.phone_android_outlined,
        'ee.tickets.drafts.onDevice'.tr(),
      ),
      EeDraftState.held => (
        Icons.hourglass_top_outlined,
        'ee.tickets.drafts.held.${draft.hold?.name ?? 'waiting'}'.tr(),
      ),
      EeDraftState.rejected => (
        Icons.block_outlined,
        'ee.tickets.drafts.rejected'.tr(
          args: {'reason': _refusal(draft.errorCode)},
        ),
      ),
      EeDraftState.sent => (
        Icons.task_alt_outlined,
        'ee.tickets.drafts.sent'.tr(),
      ),
    };
    // The one fix a person can make from here: naming the service a held
    // draft is waiting on. It needs the catalogue, so without one there is no
    // button to press (DESIGN §22) — the reason is still on the row.
    final canName =
        draft.state == EeDraftState.held &&
        draft.hold != EeDraftHold.waiting &&
        catalog != null;
    return Card(
      key: Key('ticket-draft-${draft.id}'),
      margin: const EdgeInsets.only(bottom: AwSpace.x2),
      child: Padding(
        padding: const EdgeInsets.all(AwSpace.x3),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, size: 20, color: theme.colorScheme.onSurfaceVariant),
            const SizedBox(width: AwSpace.x3),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(draft.subject, style: theme.textTheme.bodyLarge),
                  if (serviceName != null)
                    Text(serviceName, style: theme.textTheme.bodySmall),
                  const SizedBox(height: AwSpace.x1),
                  Text(
                    status,
                    key: Key('ticket-draft-${draft.id}-status'),
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  if (canName || draft.state == EeDraftState.rejected)
                    Align(
                      alignment: AlignmentDirectional.centerEnd,
                      child: canName
                          ? TextButton.icon(
                              key: Key('ticket-draft-${draft.id}-service'),
                              onPressed: () => _name(context, ref),
                              icon: const Icon(Icons.category_outlined),
                              label: Text('ee.tickets.drafts.pickService'.tr()),
                            )
                          : TextButton(
                              key: Key('ticket-draft-${draft.id}-forget'),
                              onPressed: () => ref
                                  .read(ticketDraftStoreProvider)
                                  .forgetRejected(draft.id),
                              child: Text('ee.tickets.drafts.forget'.tr()),
                            ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _name(BuildContext context, WidgetRef ref) async {
    final picked = await showEeCatalogPicker(context);
    if (picked == null) return;
    // An edit like any other: local first, queued, and the server converts
    // the draft the moment it can (EE-216's `afterUpdate`).
    await ref
        .read(ticketDraftStoreProvider)
        .edit(draft.id, serviceId: picked.id);
  }
}

/// A refusal in words: the ones this door is known to give, and the code
/// itself for anything else rather than a sentence that pretends to know.
String _refusal(String? code) => switch (code) {
  'DRAFT_LIMIT_REACHED' => 'ee.tickets.drafts.reason.limit'.tr(),
  'DRAFT_WORKSPACE_NOT_OWN' => 'ee.tickets.drafts.reason.notOwn'.tr(),
  'SYNC_ENTITY_NOT_FOUND' => 'ee.tickets.drafts.reason.noDesk'.tr(),
  _ => 'ee.tickets.drafts.reason.other'.tr(args: {'code': code ?? '—'}),
};
