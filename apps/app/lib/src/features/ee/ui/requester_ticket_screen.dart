import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/api_exception.dart';
import '../../../core/date_format.dart';
import '../../../core/error_messages.dart';
import '../../../core/persisted_prefs.dart';
import '../../../core/reachability.dart';
import '../../../i18n/i18n.dart';
import '../../../theme/tokens.dart';
import '../../../widgets/status_views.dart';
import '../../workspaces/workspaces.dart';
import '../data/requester_ticket_api.dart';
import '../requester_ticket_providers.dart';
import '../ticket_write_providers.dart';

/// One request, as the person who ASKED sees it (EE-252, ADR-0017 D17.6).
///
/// Reached at the request's own address (`/tickets/:ticketId`, EE-251) when
/// this device holds no copy of it — which, for somebody outside the unit
/// that answers, is always: the unit's replica is not theirs (ADR-0011 §3).
/// So everything here is read from the server, and the screen says so when
/// there is no connection rather than drawing a stale copy it never had.
///
/// What it offers is exactly what the doors accept (`requester-rules.js`):
/// a visible reply, and — once the desk says it is resolved — "yes, close it"
/// or "no, it is not". Never an internal note: the server would not store
/// one from this person, and the box does not pretend it could.
class EeRequesterTicketScreen extends ConsumerWidget {
  const EeRequesterTicketScreen({super.key, required this.ticketId});

  final String ticketId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ticket = ref.watch(eeRequesterTicketProvider(ticketId));
    return Scaffold(
      appBar: AppBar(title: Text('ee.tickets.detailTitle'.tr())),
      body: ticket.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => AwErrorState(
          message: error is ApiException && error.code == 'NETWORK_ERROR'
              ? 'ee.tickets.requester.needsConnection'.tr()
              : localizedError(error),
          onRetry: () => ref.invalidate(eeRequesterTicketProvider(ticketId)),
        ),
        data: (row) {
          // Not this person's to read (the server's 404 says "not yours" and
          // "does not exist" alike), or a desk request this device does not
          // hold yet. EE-266 teaches this state to read the archive.
          if (row == null || !row.isRequesterView) {
            return AwEmptyState(
              icon: Icons.inventory_2_outlined,
              title: 'ee.tickets.goneTitle'.tr(),
              message: 'ee.tickets.goneBody'.tr(),
            );
          }
          return _RequesterBody(ticket: row);
        },
      ),
    );
  }
}

class _RequesterBody extends ConsumerWidget {
  const _RequesterBody({required this.ticket});

  final EeRequesterTicket ticket;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final format = ref.watch(dateFormatProvider);
    final me = ref.watch(currentUserIdProvider);
    final comments = ref.watch(eeRequesterCommentsProvider(ticket.id));
    final ref0 = ticket.number == null ? null : '#${ticket.number}';

    return ListView(
      key: const Key('ee-requester-ticket'),
      padding: awListPadding(context),
      children: [
        Text(ticket.subject, style: theme.textTheme.titleLarge),
        const SizedBox(height: AwSpace.x1),
        Text(
          [?ref0, ?ticket.serviceName].join(' · '),
          style: theme.textTheme.bodyMedium,
        ),
        const SizedBox(height: AwSpace.x2),
        Wrap(
          spacing: AwSpace.x2,
          runSpacing: AwSpace.x1,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Chip(label: Text('ee.tickets.status.${ticket.status}'.tr())),
            if (ticket.updatedAt != null)
              Text(
                'ee.tickets.requester.updated'.tr(
                  args: {
                    'when': awFormatDateTime(
                      ticket.updatedAt!.toLocal(),
                      format: format,
                    ),
                  },
                ),
                style: theme.textTheme.bodySmall,
              ),
          ],
        ),
        if (ticket.waitsOnRequester)
          Card(
            key: const Key('ee-requester-waiting-on-you'),
            color: scheme.primaryContainer,
            child: ListTile(
              leading: Icon(
                Icons.front_hand_outlined,
                color: scheme.onPrimaryContainer,
              ),
              title: Text(
                'ee.tickets.requester.waitingOnYou'.tr(),
                style: TextStyle(color: scheme.onPrimaryContainer),
              ),
            ),
          )
        else if (ticket.status == 'waiting' && ticket.waitingReason != null)
          Padding(
            padding: const EdgeInsets.only(top: AwSpace.x2),
            child: Text(
              'ee.sla.reason.${ticket.waitingReason}'.tr(),
              style: theme.textTheme.bodyMedium,
            ),
          ),
        const SizedBox(height: AwSpace.x3),
        if ((ticket.body ?? '').trim().isNotEmpty)
          _Line(
            author: 'ee.tickets.requester.yourRequest'.tr(),
            body: ticket.body!,
            mine: true,
          ),
        ...comments.when(
          loading: () => const [
            Padding(
              padding: EdgeInsets.all(AwSpace.x4),
              child: Center(child: CircularProgressIndicator()),
            ),
          ],
          error: (error, _) => [AwInlineError(message: localizedError(error))],
          data: (rows) => [
            for (final c in rows)
              _Line(
                author: c.authorId != null && c.authorId == me
                    ? 'ee.tickets.requester.you'.tr()
                    : 'ee.tickets.requester.desk'.tr(),
                body: c.body,
                mine: c.authorId != null && c.authorId == me,
                when: c.createdAt == null
                    ? null
                    : awFormatDateTime(c.createdAt!.toLocal(), format: format),
              ),
          ],
        ),
        const SizedBox(height: AwSpace.x3),
        if (ticket.isClosed)
          _ClosedFooter(key: const Key('ee-requester-closed'))
        else ...[
          if (ticket.allowedTransitions.isNotEmpty) ...[
            _Outcome(ticket: ticket),
            const SizedBox(height: AwSpace.x2),
          ],
          _RequesterReplyBox(ticketId: ticket.id),
        ],
      ],
    );
  }
}

class _Line extends StatelessWidget {
  const _Line({
    required this.author,
    required this.body,
    required this.mine,
    this.when,
  });

  final String author;
  final String body;
  final bool mine;
  final String? when;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      color: mine ? null : theme.colorScheme.surfaceContainerHighest,
      child: Padding(
        padding: const EdgeInsets.all(AwSpace.x3),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              when == null ? author : '$author · $when',
              style: theme.textTheme.labelMedium,
            ),
            const SizedBox(height: AwSpace.x1),
            SelectableText(body),
          ],
        ),
      ),
    );
  }
}

/// "Yes, that fixed it" / "no, it did not" — offered only when the server
/// lists them (a resolved request), so the screen never shows a move the
/// door refuses.
class _Outcome extends ConsumerStatefulWidget {
  const _Outcome({required this.ticket});

  final EeRequesterTicket ticket;

  @override
  ConsumerState<_Outcome> createState() => _OutcomeState();
}

class _OutcomeState extends ConsumerState<_Outcome> {
  bool _busy = false;

  Future<void> _move(String to) async {
    if (_busy) return;
    if (to == 'closed') {
      final sure = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text('ee.tickets.requester.closeConfirmTitle'.tr()),
          content: Text('ee.tickets.requester.closeConfirmBody'.tr()),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: Text('common.cancel'.tr()),
            ),
            FilledButton(
              key: const Key('ee-requester-close-confirm'),
              onPressed: () => Navigator.of(context).pop(true),
              child: Text('ee.tickets.requester.confirmClose'.tr()),
            ),
          ],
        ),
      );
      if (sure != true || !mounted) return;
    }
    setState(() => _busy = true);
    final messenger = ScaffoldMessenger.maybeOf(context);
    try {
      await ref.read(eeTicketWriteApiProvider).setStatus(widget.ticket.id, to);
      ref.invalidate(eeRequesterTicketProvider(widget.ticket.id));
      ref.invalidate(eeRequesterCommentsProvider(widget.ticket.id));
      messenger?.showSnackBar(
        SnackBar(
          content: Text(
            (to == 'closed'
                    ? 'ee.tickets.requester.closedDone'
                    : 'ee.tickets.requester.disputed')
                .tr(),
          ),
        ),
      );
    } on ApiException catch (error) {
      if (error.code == 'NETWORK_ERROR') {
        ref.read(serverReachabilityProvider.notifier).unreachable();
      }
      messenger?.showSnackBar(SnackBar(content: Text(localizedError(error))));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final offline = ref.watch(serverReachabilityProvider) == false;
    final moves = widget.ticket.allowedTransitions;
    final enabled = !offline && !_busy;
    return Card(
      key: const Key('ee-requester-outcome'),
      child: Padding(
        padding: const EdgeInsets.all(AwSpace.x3),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('ee.tickets.requester.resolvedPrompt'.tr()),
            const SizedBox(height: AwSpace.x2),
            Wrap(
              spacing: AwSpace.x2,
              runSpacing: AwSpace.x2,
              children: [
                if (moves.contains('closed'))
                  FilledButton(
                    key: const Key('ee-requester-close'),
                    onPressed: enabled ? () => _move('closed') : null,
                    child: Text('ee.tickets.requester.confirmClose'.tr()),
                  ),
                if (moves.contains('in_progress'))
                  OutlinedButton(
                    key: const Key('ee-requester-dispute'),
                    onPressed: enabled ? () => _move('in_progress') : null,
                    child: Text('ee.tickets.requester.dispute'.tr()),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// A visible reply, and nothing else — the requester's box has no internal
/// note to choose. Online only (a request is server-canonical, E19's rule),
/// greyed out with the reason before anybody types; what was typed survives
/// leaving the screen for the session (EE-223's draft store).
class _RequesterReplyBox extends ConsumerStatefulWidget {
  const _RequesterReplyBox({required this.ticketId});

  final String ticketId;

  @override
  ConsumerState<_RequesterReplyBox> createState() => _RequesterReplyBoxState();
}

class _RequesterReplyBoxState extends ConsumerState<_RequesterReplyBox> {
  late final TextEditingController _text;
  bool _sending = false;

  @override
  void initState() {
    super.initState();
    final draft = ref
        .read(eeCommentDraftsProvider.notifier)
        .of(widget.ticketId);
    _text = TextEditingController(text: draft.text);
    _text.addListener(_remember);
  }

  @override
  void dispose() {
    _text.removeListener(_remember);
    _text.dispose();
    super.dispose();
  }

  void _remember() {
    ref
        .read(eeCommentDraftsProvider.notifier)
        .keep(
          widget.ticketId,
          EeCommentDraft(text: _text.text, internal: false),
        );
    setState(() {});
  }

  Future<void> _send() async {
    final body = _text.text.trim();
    if (body.isEmpty || _sending) return;
    setState(() => _sending = true);
    final messenger = ScaffoldMessenger.maybeOf(context);
    try {
      await ref
          .read(eeTicketWriteApiProvider)
          .comment(widget.ticketId, body: body, internal: false);
      _text.clear();
      ref.invalidate(eeRequesterCommentsProvider(widget.ticketId));
      // The request may have moved (EE-253: an answer to "waiting for you"
      // hands it back to the desk), so its header is read again too.
      ref.invalidate(eeRequesterTicketProvider(widget.ticketId));
      messenger?.showSnackBar(
        SnackBar(content: Text('ee.tickets.composer.replySent'.tr())),
      );
    } on ApiException catch (error) {
      if (error.code == 'NETWORK_ERROR') {
        ref.read(serverReachabilityProvider.notifier).unreachable();
      }
      messenger?.showSnackBar(SnackBar(content: Text(localizedError(error))));
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final offline = ref.watch(serverReachabilityProvider) == false;
    final canSend = !offline && !_sending && _text.text.trim().isNotEmpty;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          key: const Key('ee-requester-reply'),
          controller: _text,
          enabled: !offline,
          minLines: 2,
          maxLines: 6,
          decoration: InputDecoration(
            hintText: 'ee.tickets.requester.replyHint'.tr(),
          ),
        ),
        if (offline)
          Padding(
            padding: const EdgeInsets.only(top: AwSpace.x1),
            child: Text(
              'ee.tickets.composer.offline'.tr(),
              key: const Key('ee-requester-offline'),
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
        const SizedBox(height: AwSpace.x2),
        Align(
          alignment: Alignment.centerRight,
          child: FilledButton.icon(
            key: const Key('ee-requester-send'),
            onPressed: canSend ? _send : null,
            icon: const Icon(Icons.send),
            label: Text('ee.tickets.requester.send'.tr()),
          ),
        ),
      ],
    );
  }
}

class _ClosedFooter extends StatelessWidget {
  const _ClosedFooter({super.key});

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AwSpace.x3),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('ee.tickets.composer.closed'.tr()),
            const SizedBox(height: AwSpace.x2),
            FilledButton.tonal(
              key: const Key('ee-requester-new'),
              onPressed: () => context.push('/tickets/new'),
              child: Text('ee.tickets.requester.newRequest'.tr()),
            ),
          ],
        ),
      ),
    );
  }
}
