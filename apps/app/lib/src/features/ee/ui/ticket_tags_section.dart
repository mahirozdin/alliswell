import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/error_messages.dart';
import '../../../core/reachability.dart';
import '../../../i18n/i18n.dart';
import '../../../sync/db/database.dart';
import '../../../sync/providers.dart';
import '../../../theme/tokens.dart';
import '../providers.dart';
import '../ticket_tags_providers.dart';

/// The desk's words on one request (EE-235).
///
/// READ from the device: the chips are the row's `tag_names` (OPH-350), so a
/// request opened in a basement still says it is a warranty case. WRITTEN over
/// REST, like every other write onto a request (EE-223): with no signal the
/// chips stay and the two doors go grey with the reason under them.
///
/// Between a write and the pull that brings the row down, the chips show the
/// list the server answered with — a word that vanished for a second after
/// being added would look like it had not been. The moment the row changes,
/// the row wins again.
///
/// Hidden — not disabled — for somebody who may not tag and sees no tags:
/// an empty heading with nothing under it is a question with no answer.
class EeTicketTagsSection extends ConsumerStatefulWidget {
  const EeTicketTagsSection({required this.ticket, super.key});

  final TicketRecord ticket;

  @override
  ConsumerState<EeTicketTagsSection> createState() => _State();
}

class _State extends ConsumerState<EeTicketTagsSection> {
  /// The server's answer after a write, until the replica agrees.
  List<String>? _answered;
  bool _busy = false;

  @override
  void didUpdateWidget(covariant EeTicketTagsSection old) {
    super.didUpdateWidget(old);
    if (old.ticket.tagNames != widget.ticket.tagNames) _answered = null;
  }

  List<String> get _shown =>
      _answered ?? decodeTagNames(widget.ticket.tagNames);

  Future<void> _write(Future<List<String>> Function() action) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final names = await action();
      if (!mounted) return;
      setState(() => _answered = names);
      // The row comes down with the new list on the next pull.
      unawaited(ref.read(syncEngineProvider)?.syncNow());
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(localizedError(error))));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _add() async {
    final name = await showDialog<String>(
      context: context,
      builder: (_) => const _AddTagDialog(),
    );
    if (name == null || name.trim().isEmpty) return;
    final api = ref.read(eeTicketTagsApiProvider);
    await _write(() async {
      final words = await api.tag(widget.ticket.id, name.trim());
      return [for (final word in words) word.name];
    });
  }

  Future<void> _remove(String name) async {
    final api = ref.read(eeTicketTagsApiProvider);
    await _write(() async {
      // The chip carries a word; the server removes by id. The vocabulary is
      // the team's and small, and this is online anyway.
      final words = await api.vocabulary();
      final key = foldTag(name);
      for (final word in words) {
        if (foldTag(word.name) == key) {
          await api.untag(widget.ticket.id, word.id);
          break;
        }
      }
      return [
        for (final shown in _shown)
          if (foldTag(shown) != key) shown,
      ];
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurfaceVariant;
    final tags = _shown;
    final may = ref.watch(canProvider('tickets.comment'));
    if (tags.isEmpty && !may) return const SizedBox.shrink();
    final offline = ref.watch(
      serverReachabilityProvider.select((up) => up == false),
    );
    final canWrite = may && !offline && !_busy;

    return Padding(
      key: const Key('ticket-tags'),
      padding: const EdgeInsets.only(top: AwSpace.x3),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('ee.tickets.tags.title'.tr(), style: theme.textTheme.titleSmall),
          const SizedBox(height: AwSpace.x1),
          Wrap(
            spacing: AwSpace.x2,
            runSpacing: AwSpace.x1,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              for (final name in tags)
                may
                    ? InputChip(
                        key: Key('ticket-tag-$name'),
                        avatar: const Icon(Icons.sell_outlined, size: 18),
                        label: Text(name),
                        deleteButtonTooltipMessage: 'ee.tickets.tags.remove'
                            .tr(),
                        onDeleted: canWrite ? () => _remove(name) : null,
                      )
                    : Chip(
                        key: Key('ticket-tag-$name'),
                        avatar: const Icon(Icons.sell_outlined, size: 18),
                        label: Text(name),
                      ),
              if (may)
                ActionChip(
                  key: const Key('ticket-tag-add'),
                  avatar: const Icon(Icons.add, size: 18),
                  label: Text('ee.tickets.tags.add'.tr()),
                  onPressed: canWrite ? _add : null,
                ),
            ],
          ),
          if (may && offline)
            Padding(
              padding: const EdgeInsets.only(top: AwSpace.x1),
              child: Text(
                'ee.tickets.tags.offline'.tr(),
                key: const Key('ticket-tags-offline'),
                style: theme.textTheme.bodySmall?.copyWith(color: muted),
              ),
            ),
        ],
      ),
    );
  }
}

/// A word to put on the request — typed, or picked from the team's
/// vocabulary as it narrows.
class _AddTagDialog extends ConsumerStatefulWidget {
  const _AddTagDialog();

  @override
  ConsumerState<_AddTagDialog> createState() => _AddTagDialogState();
}

class _AddTagDialogState extends ConsumerState<_AddTagDialog> {
  final _field = TextEditingController();

  @override
  void dispose() {
    _field.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final typed = foldTag(_field.text);
    final words = ref.watch(eeTagVocabularyProvider).value ?? const [];
    final suggestions = [
      for (final word in words)
        if (typed.isEmpty || foldTag(word.name).contains(typed)) word,
    ].take(6).toList();
    return AlertDialog(
      title: Text('ee.tickets.tags.addTitle'.tr()),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextField(
            key: const Key('ticket-tag-field'),
            controller: _field,
            autofocus: true,
            maxLength: 40,
            decoration: InputDecoration(
              labelText: 'ee.tickets.tags.field'.tr(),
              helperText: 'ee.tickets.tags.hint'.tr(),
            ),
            onChanged: (_) => setState(() {}),
            onSubmitted: (value) => Navigator.of(context).pop(value),
          ),
          if (suggestions.isNotEmpty)
            Wrap(
              spacing: AwSpace.x2,
              runSpacing: AwSpace.x1,
              children: [
                for (final word in suggestions)
                  ActionChip(
                    key: Key('ticket-tag-suggestion-${word.name}'),
                    label: Text(word.name),
                    onPressed: () => Navigator.of(context).pop(word.name),
                  ),
              ],
            ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text('common.cancel'.tr()),
        ),
        FilledButton(
          key: const Key('ticket-tag-save'),
          onPressed: _field.text.trim().isEmpty
              ? null
              : () => Navigator.of(context).pop(_field.text),
          child: Text('ee.tickets.tags.save'.tr()),
        ),
      ],
    );
  }
}
