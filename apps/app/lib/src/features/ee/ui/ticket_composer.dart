import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api_exception.dart';
import '../../../core/error_messages.dart';
import '../../../core/reachability.dart';
import '../../../i18n/i18n.dart';
import '../../../sync/providers.dart';
import '../../../theme/tokens.dart';
import '../../../widgets/status_views.dart';
import '../data/ticket_write_api.dart';
import '../ticket_write_providers.dart';

/// EE-223 — writing on a request: a reply its requester reads, or a note only
/// the unit does.
///
/// ── THE SAME THREE SIGNALS AS THE THREAD (EE-084) ──────────────────────
///
/// An internal note is WRITTEN on the surface it will be SHOWN on — the tint,
/// the lock, the word — so the difference is visible before the send, which
/// is the only moment it can still be changed. And the button names its
/// audience: "Send to the requester" is a sentence nobody presses by accident
/// while thinking they are talking to a colleague. The kind can be switched
/// until then; afterwards the comment is the server's, and a note that was
/// read by a customer cannot be un-read.
///
/// ── ONLINE, AND HONEST ABOUT IT (E19) ──────────────────────────────────
///
/// A request is server-canonical: the reply goes straight to the server, and
/// with no connection the box greys out BEFORE anybody types into it and says
/// why (`serverReachabilityProvider`, OPH-342). What was typed stays — in the
/// box, and in the session's draft if the person backs out.
class EeTicketComposer extends ConsumerStatefulWidget {
  const EeTicketComposer({super.key, required this.ticketId});

  final String ticketId;

  @override
  ConsumerState<EeTicketComposer> createState() => _EeTicketComposerState();
}

class _EeTicketComposerState extends ConsumerState<EeTicketComposer> {
  late final TextEditingController _text;
  late bool _internal;
  bool _sending = false;

  @override
  void initState() {
    super.initState();
    final draft = ref
        .read(eeCommentDraftsProvider.notifier)
        .of(widget.ticketId);
    _text = TextEditingController(text: draft.text);
    _internal = draft.internal;
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
          EeCommentDraft(text: _text.text, internal: _internal),
        );
    setState(() {}); // the send button follows the text
  }

  void _setKind(bool internal) {
    setState(() => _internal = internal);
    _remember();
  }

  Future<void> _send() async {
    final body = _text.text.trim();
    if (body.isEmpty || _sending) return;
    final internal = _internal;
    setState(() => _sending = true);
    final messenger = ScaffoldMessenger.maybeOf(context);
    try {
      await ref
          .read(eeTicketWriteApiProvider)
          .comment(widget.ticketId, body: body, internal: internal);
      _text.clear();
      // The thread reads the device's copy; ask for the new row now rather
      // than at the next scheduled pull (the cascade-archive precedent).
      unawaited(ref.read(syncEngineProvider)?.syncNow());
      messenger?.showSnackBar(
        SnackBar(
          content: Text(
            (internal
                    ? 'ee.tickets.composer.noteAdded'
                    : 'ee.tickets.composer.replySent')
                .tr(),
          ),
        ),
      );
    } on ApiException catch (error) {
      // No answer at all: say so where the box is, not only in a toast that
      // is gone before anybody reads it. The text stays either way.
      if (error.code == 'NETWORK_ERROR') {
        ref.read(serverReachabilityProvider.notifier).unreachable();
      }
      messenger?.showSnackBar(SnackBar(content: Text(localizedError(error))));
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _insertCanned() async {
    final picked = await showModalBottomSheet<EeCannedReply>(
      context: context,
      showDragHandle: true,
      builder: (_) => _CannedRepliesSheet(ticketId: widget.ticketId),
    );
    if (picked == null) return;
    // Added, never substituted: what the person already wrote is theirs, and
    // the saved wording is a start, not the reply. Sending is still theirs.
    final current = _text.text.trimRight();
    final joined = current.isEmpty ? picked.text : '$current\n\n${picked.text}';
    _text.value = TextEditingValue(
      text: joined,
      selection: TextSelection.collapsed(offset: joined.length),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final offline = ref.watch(serverReachabilityProvider) == false;
    final busy = offline || _sending;
    final canSend = !busy && _text.text.trim().isNotEmpty;
    final quiet = theme.textTheme.bodySmall?.copyWith(
      color: scheme.onSurfaceVariant,
    );

    return Card(
      key: const Key('ticket-composer'),
      margin: const EdgeInsets.only(top: AwSpace.x3),
      // Signal one: the thread's own "set apart" surface (EE-084 chose it
      // because the contrast gate has measured it; a mixed amber would not).
      color: _internal ? scheme.surfaceContainerHighest : null,
      child: Padding(
        padding: const EdgeInsets.all(AwSpace.x4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SegmentedButton<bool>(
              key: const Key('ticket-composer-kind'),
              showSelectedIcon: false,
              segments: [
                ButtonSegment(
                  value: false,
                  icon: const Icon(Icons.reply_outlined),
                  label: Text('ee.tickets.composer.reply'.tr()),
                ),
                ButtonSegment(
                  value: true,
                  icon: const Icon(Icons.lock_outline),
                  label: Text('ee.tickets.composer.internal'.tr()),
                ),
              ],
              selected: {_internal},
              onSelectionChanged: _sending
                  ? null
                  : (selection) => _setKind(selection.first),
            ),
            const SizedBox(height: AwSpace.x2),
            // Signals two and three: the lock, and the words saying who reads
            // this — the sentence nobody can mistake.
            Row(
              children: [
                Icon(
                  _internal ? Icons.lock_outline : Icons.person_outline,
                  size: 16,
                  color: scheme.onSurfaceVariant,
                ),
                const SizedBox(width: AwSpace.x1),
                Expanded(
                  child: Text(
                    key: const Key('ticket-composer-audience'),
                    (_internal
                            ? 'ee.tickets.composer.internalAudience'
                            : 'ee.tickets.composer.replyAudience')
                        .tr(),
                    style: quiet,
                  ),
                ),
              ],
            ),
            const SizedBox(height: AwSpace.x2),
            TextField(
              key: const Key('ticket-composer-text'),
              controller: _text,
              enabled: !busy,
              minLines: 3,
              maxLines: 8,
              keyboardType: TextInputType.multiline,
              textCapitalization: TextCapitalization.sentences,
              decoration: InputDecoration(
                hintText:
                    (_internal
                            ? 'ee.tickets.composer.noteHint'
                            : 'ee.tickets.composer.replyHint')
                        .tr(),
              ),
            ),
            if (offline) ...[
              const SizedBox(height: AwSpace.x2),
              Row(
                key: const Key('ticket-composer-offline'),
                children: [
                  Icon(
                    Icons.cloud_off_outlined,
                    size: 16,
                    color: scheme.onSurfaceVariant,
                  ),
                  const SizedBox(width: AwSpace.x1),
                  Expanded(
                    child: Text(
                      'ee.tickets.composer.offline'.tr(),
                      style: quiet,
                    ),
                  ),
                ],
              ),
            ],
            const SizedBox(height: AwSpace.x2),
            Wrap(
              alignment: WrapAlignment.spaceBetween,
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: AwSpace.x2,
              runSpacing: AwSpace.x2,
              children: [
                TextButton.icon(
                  key: const Key('ticket-composer-canned'),
                  onPressed: busy ? null : _insertCanned,
                  icon: const Icon(Icons.quickreply_outlined),
                  label: Text('ee.tickets.composer.canned'.tr()),
                ),
                FilledButton.icon(
                  key: const Key('ticket-composer-send'),
                  onPressed: canSend ? _send : null,
                  icon: _sending
                      ? const SizedBox.square(
                          dimension: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : Icon(
                          _internal ? Icons.lock_outline : Icons.send_outlined,
                        ),
                  label: Text(
                    (_internal
                            ? 'ee.tickets.composer.addNote'
                            : 'ee.tickets.composer.sendReply')
                        .tr(),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// The desk's saved replies, rendered against this request (EE-201).
class _CannedRepliesSheet extends ConsumerWidget {
  const _CannedRepliesSheet({required this.ticketId});

  final String ticketId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final replies = ref.watch(eeCannedRepliesProvider(ticketId));
    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * 0.7,
        ),
        child: replies.when(
          loading: () => const Padding(
            padding: EdgeInsets.all(AwSpace.x6),
            child: Center(child: CircularProgressIndicator()),
          ),
          error: (error, _) => AwErrorState(message: localizedError(error)),
          data: (rows) => rows.isEmpty
              ? AwEmptyState(
                  icon: Icons.quickreply_outlined,
                  title: 'ee.tickets.composer.cannedEmptyTitle'.tr(),
                  message: 'ee.tickets.composer.cannedEmptyBody'.tr(),
                )
              : ListView(
                  shrinkWrap: true,
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(
                        AwSpace.x4,
                        0,
                        AwSpace.x4,
                        AwSpace.x2,
                      ),
                      child: Text(
                        'ee.tickets.composer.cannedTitle'.tr(),
                        style: Theme.of(context).textTheme.titleSmall,
                      ),
                    ),
                    for (final reply in rows)
                      ListTile(
                        key: Key('canned-${reply.id}'),
                        leading: const Icon(Icons.short_text),
                        title: Text(reply.name),
                        subtitle: Text(
                          reply.text,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        onTap: () => Navigator.of(context).pop(reply),
                      ),
                  ],
                ),
        ),
      ),
    );
  }
}
