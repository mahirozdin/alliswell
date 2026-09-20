import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/error_messages.dart';
import '../../../i18n/i18n.dart';
import '../../../sync/db/database.dart';
import '../../../widgets/status_views.dart';
import '../data/kb_models.dart';
import '../kb_providers.dart';
import '../providers.dart';
import 'kb_editor_sheet.dart';

/// One article (EE-196).
///
/// ── THE CARD READS THE REPLICA, THE BUTTONS WRITE TO THE SERVER ────────
///
/// Reading is the half that must work in a machine hall with no signal, so
/// the body comes off the device. Moving an article through its life is the
/// half that must NOT work offline: `kb.publish` exists so a sentence reaches
/// customers only after somebody decided it should, and an offline queue
/// would walk around that decision.
///
/// ── THE FLOW OFFERS WHAT THE SERVER ALLOWS, AND NOTHING ELSE ───────────
///
/// `kEeKbTransitions` mirrors the server's map. Offering every status and
/// letting the server refuse four of them would make four buttons that answer
/// 409 — which is the thing this repo tests for by name ("no dead buttons").
/// The server is still the gate; this only decides what to show.
class EeKbArticleScreen extends ConsumerWidget {
  const EeKbArticleScreen({super.key, required this.articleId});

  final String articleId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final article = ref.watch(eeKbArticleProvider(articleId));
    final canWrite = ref.watch(canProvider('kb.write'));
    final canPublish = ref.watch(canProvider('kb.publish'));

    return Scaffold(
      appBar: AppBar(
        title: Text('ee.kb.articleTitle'.tr()),
        actions: [
          if (canWrite &&
              article.value != null &&
              article.value!.status != 'retired')
            IconButton(
              key: const Key('kb-edit'),
              tooltip: 'ee.kb.edit'.tr(),
              icon: const Icon(Icons.edit_outlined),
              onPressed: () =>
                  showKbEditorSheet(context, ref, existing: article.value),
            ),
        ],
      ),
      body: article.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => AwErrorState(
          message: localizedError(error),
          onRetry: () => ref.invalidate(eeKbArticleProvider(articleId)),
        ),
        data: (row) {
          if (row == null) {
            return AwEmptyState(
              icon: Icons.menu_book_outlined,
              title: 'ee.kb.gone'.tr(),
              message: 'ee.kb.goneBody'.tr(),
            );
          }
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      row.title,
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                  ),
                  const SizedBox(width: 8),
                  KbStatusChip(status: row.status),
                ],
              ),
              const SizedBox(height: 16),
              _Section(label: 'ee.kb.symptom'.tr(), body: row.symptom),
              if (row.environment != null && row.environment!.isNotEmpty)
                _Section(
                  label: 'ee.kb.environment'.tr(),
                  body: row.environment!,
                ),
              // A `wip` article has no solution BY DEFINITION — that is what
              // the status means. Saying so is more useful than an empty box,
              // because the reader's next question is "is it missing or is
              // nobody working on it".
              _Section(
                key: const Key('kb-solution'),
                label: 'ee.kb.solution'.tr(),
                body: (row.solution?.trim().isNotEmpty ?? false)
                    ? row.solution!
                    : 'ee.kb.noSolutionYet'.tr(),
                muted: !(row.solution?.trim().isNotEmpty ?? false),
              ),
              const SizedBox(height: 24),
              if (canWrite)
                _Flow(
                  article: row,
                  canPublish: canPublish,
                  articleId: articleId,
                ),
            ],
          );
        },
      ),
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({
    super.key,
    required this.label,
    required this.body,
    this.muted = false,
  });

  final String label;
  final String body;
  final bool muted;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: theme.textTheme.labelLarge?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            body,
            style: muted
                ? theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                    fontStyle: FontStyle.italic,
                  )
                : theme.textTheme.bodyMedium,
          ),
        ],
      ),
    );
  }
}

class _Flow extends ConsumerStatefulWidget {
  const _Flow({
    required this.article,
    required this.canPublish,
    required this.articleId,
  });

  final KbArticleRecord article;
  final bool canPublish;
  final String articleId;

  @override
  ConsumerState<_Flow> createState() => _FlowState();
}

class _FlowState extends ConsumerState<_Flow> {
  bool _busy = false;

  Future<void> _move(String to) async {
    setState(() => _busy = true);
    try {
      await ref.read(eeKbApiProvider).setStatus(widget.articleId, to);
      ref.invalidate(eeKbArticleProvider(widget.articleId));
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(localizedError(error))));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final next = kEeKbTransitions[widget.article.status] ?? const <String>[];
    if (next.isEmpty) {
      return Text(
        'ee.kb.terminal'.tr(),
        style: Theme.of(context).textTheme.bodySmall?.copyWith(
          color: Theme.of(context).colorScheme.onSurfaceVariant,
        ),
      );
    }
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final to in next)
          // The publish gate is drawn, not hidden: a writer who cannot
          // publish sees the button disabled with a reason rather than a flow
          // that silently ends. Hiding it would leave them wondering whether
          // the article is finished or they are.
          Tooltip(
            message:
                eeKbNeedsPublish(widget.article.status, to) &&
                    !widget.canPublish
                ? 'ee.kb.needsPublish'.tr()
                : '',
            child: FilledButton(
              key: Key('kb-move-$to'),
              onPressed:
                  _busy ||
                      (eeKbNeedsPublish(widget.article.status, to) &&
                          !widget.canPublish)
                  ? null
                  : () => _move(to),
              child: Text('ee.kb.moveTo.$to'.tr()),
            ),
          ),
      ],
    );
  }
}

/// The status, everywhere it is shown.
///
/// Text AND shape rather than colour alone: the queue screen settled this
/// (roughly 8% of men cannot separate red from green, and a factory prints
/// screenshots in black and white).
class KbStatusChip extends StatelessWidget {
  const KbStatusChip({super.key, required this.status});

  final String status;

  @override
  Widget build(BuildContext context) => Chip(
    key: Key('kb-status-$status'),
    label: Text('ee.kb.status.$status'.tr()),
    visualDensity: VisualDensity.compact,
    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
  );
}
