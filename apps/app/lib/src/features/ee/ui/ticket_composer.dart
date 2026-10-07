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
import '../../files/providers.dart';
import '../../files/ui/attach_menu.dart';
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
  const EeTicketComposer({
    super.key,
    required this.ticketId,
    this.workspaceId,
    this.asksHere = false,
    this.byEmail = false,
    this.customerName,
  });

  final String ticketId;

  /// The request's unit, where a file sent with a reply is stored (core's
  /// upload walk, EE-168). Null: no file can be sent from here.
  final String? workspaceId;

  /// OPH-358 (UI-AUDIT #21): the person writing is the one who asked. Their
  /// "reply" goes to the desk, and the words say so — "send to the
  /// requester" was telling them to write to themselves.
  final bool asksHere;

  /// The request came by mail, so a reply leaves as one (UI-AUDIT #21).
  final bool byEmail;

  /// The company whose portal shows this request (UI-AUDIT #48).
  final String? customerName;

  @override
  ConsumerState<EeTicketComposer> createState() => _EeTicketComposerState();
}

class _EeTicketComposerState extends ConsumerState<EeTicketComposer> {
  late final TextEditingController _text;
  late bool _internal;
  bool _sending = false;

  /// OPH-358 (UI-AUDIT #34): files picked for the next reply or note. Sent
  /// after it, onto IT (`ticket_comment`) — never onto the request, where a
  /// note's file would reach the person the note is hidden from.
  final _files = <PickedUpload>[];

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
      final commentId = await ref
          .read(eeTicketWriteApiProvider)
          .comment(widget.ticketId, body: body, internal: internal);
      _text.clear();
      final files = List.of(_files);
      if (mounted) setState(_files.clear);
      var failed = 0;
      final home = widget.workspaceId;
      if (files.isNotEmpty && commentId != null && home != null) {
        final uploads = ref.read(uploadsProvider.notifier);
        for (final file in files) {
          final id = await uploads.start(
            workspaceId: home,
            targetType: 'ticket_comment',
            targetId: commentId,
            source: file,
          );
          if (id == null) failed += 1;
        }
      }
      // The thread reads the device's copy; ask for the new row now rather
      // than at the next scheduled pull (the cascade-archive precedent).
      unawaited(ref.read(syncEngineProvider)?.syncNow());
      messenger?.showSnackBar(
        SnackBar(
          content: Text(
            failed > 0
                ? 'ee.tickets.composer.filesFailed'.tr(
                    args: {'count': '$failed'},
                  )
                : (internal
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
                  label: Text(
                    (widget.asksHere
                            ? 'ee.tickets.composer.replyOwn'
                            : 'ee.tickets.composer.reply')
                        .tr(),
                  ),
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
                            : widget.asksHere
                            ? 'ee.tickets.composer.replyOwnAudience'
                            : 'ee.tickets.composer.replyAudience')
                        .tr(),
                    style: quiet,
                  ),
                ),
              ],
            ),
            // UI-AUDIT #21 / #48: where a reply actually goes, before it goes.
            if (!_internal && !widget.asksHere && widget.byEmail)
              _Hint(
                key: const Key('ticket-composer-by-email'),
                icon: Icons.mail_outline,
                text: 'ee.tickets.composer.byEmail'.tr(),
              ),
            if (!_internal && widget.customerName != null)
              _Hint(
                key: const Key('ticket-composer-customer'),
                icon: Icons.apartment_outlined,
                text: 'ee.tickets.composer.customerPortal'.tr(
                  args: {'name': widget.customerName!},
                ),
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
            if (_files.isNotEmpty) ...[
              const SizedBox(height: AwSpace.x2),
              Wrap(
                spacing: AwSpace.x2,
                runSpacing: AwSpace.x1,
                children: [
                  for (final (i, file) in _files.indexed)
                    InputChip(
                      key: Key('ticket-composer-file-$i'),
                      avatar: const Icon(Icons.attach_file, size: 16),
                      label: Text(
                        file.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      onDeleted: busy
                          ? null
                          : () => setState(() => _files.removeAt(i)),
                    ),
                ],
              ),
              if (_internal)
                _Hint(
                  icon: Icons.lock_outline,
                  text: 'ee.tickets.composer.filesInternal'.tr(),
                ),
            ],
            const SizedBox(height: AwSpace.x2),
            // The tools on one line, the send under them at the end — a send
            // that wraps on its own to the start reads as one more tool.
            Wrap(
              spacing: AwSpace.x2,
              runSpacing: AwSpace.x1,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                TextButton.icon(
                  key: const Key('ticket-composer-canned'),
                  onPressed: busy ? null : _insertCanned,
                  icon: const Icon(Icons.quickreply_outlined),
                  label: Text('ee.tickets.composer.canned'.tr()),
                ),
                if (widget.workspaceId != null)
                  AttachButton(
                    buttonKey: const Key('ticket-composer-attach'),
                    style: AttachButtonStyle.text,
                    enabled: !busy,
                    onPicked: (picks) async {
                      if (mounted) setState(() => _files.addAll(picks));
                    },
                  ),
              ],
            ),
            const SizedBox(height: AwSpace.x2),
            Align(
              alignment: AlignmentDirectional.centerEnd,
              child: FilledButton.icon(
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
            ),
          ],
        ),
      ),
    );
  }
}

/// One quiet line under the audience: an icon and the words.
class _Hint extends StatelessWidget {
  const _Hint({super.key, required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurfaceVariant;
    return Padding(
      padding: const EdgeInsets.only(top: AwSpace.x1),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 16, color: muted),
          const SizedBox(width: AwSpace.x1),
          Expanded(
            child: Text(
              text,
              style: theme.textTheme.bodySmall?.copyWith(color: muted),
            ),
          ),
        ],
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
