import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/error_messages.dart';
import '../../../i18n/i18n.dart';
import '../../../sync/db/database.dart';
import '../../../widgets/search_field.dart';
import '../../../widgets/status_views.dart';
import '../data/kb_models.dart';
import '../kb_providers.dart';
import '../providers.dart';
import 'kb_article_screen.dart';
import 'kb_editor_sheet.dart';

/// The knowledge base (EE-196).
///
/// ── THE LIST READS THE DEVICE, AND THAT IS THE FEATURE ─────────────────
///
/// EE-195's task asked for one thing in one sentence: the agent has to be
/// able to look a solution up IN THE FIELD. So both the list and the search
/// come off the replica, and the screen works with no signal — which is also
/// why the search field here is the house `AwSearchAction` over folded shadow
/// columns rather than a `?q=` to the server (`check:no-server-search`).
///
/// ── WIP IS SHOWN FIRST, ON PURPOSE ─────────────────────────────────────
///
/// A `wip` article is a captured QUESTION with no answer yet. The task calls
/// a pile of them "list pollution" and asks the screen to show it — so they
/// sort first rather than being tucked behind a filter. A desk that can see
/// what it has not answered is a desk that can answer it.
class EeKbScreen extends ConsumerWidget {
  const EeKbScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final articles = ref.watch(eeKbArticlesProvider);
    final hits = ref.watch(eeKbSearchResultsProvider).value;
    final status = ref.watch(eeKbStatusFilterProvider);
    final canWrite = ref.watch(canProvider('kb.write'));

    return Scaffold(
      appBar: AppBar(
        title: Text('ee.kb.title'.tr()),
        actions: [
          AwSearchAction(
            fieldKey: const Key('kb-search'),
            hintText: 'ee.kb.searchHint'.tr(),
            onQuery: (q) => ref.read(eeKbSearchQueryProvider.notifier).set(q),
          ),
          if (canWrite)
            IconButton(
              key: const Key('kb-new'),
              tooltip: 'ee.kb.new'.tr(),
              icon: const Icon(Icons.post_add_outlined),
              onPressed: () => showKbEditorSheet(context, ref),
            ),
        ],
      ),
      body: Column(
        children: [
          _StatusFilter(status: status),
          Expanded(
            child: articles.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (error, _) => AwErrorState(
                message: localizedError(error),
                onRetry: () => ref.invalidate(eeKbArticlesProvider),
              ),
              data: (rows) {
                final shown = _ranked(rows, hits);
                if (shown.isEmpty) {
                  return AwEmptyState(
                    icon: Icons.menu_book_outlined,
                    title: hits == null
                        ? 'ee.kb.empty'.tr()
                        : 'ee.kb.noMatches'.tr(),
                    message: hits == null
                        ? 'ee.kb.emptyBody'.tr()
                        : 'ee.kb.noMatchesBody'.tr(),
                  );
                }
                return ListView.builder(
                  itemCount: shown.length,
                  itemBuilder: (context, i) => _Row(article: shown[i]),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  /// Search narrows and REORDERS: the registry ranks by tier (title before
  /// symptom), and a list that kept its own order would throw that away.
  static List<KbArticleRecord> _ranked(
    List<KbArticleRecord> rows,
    List<dynamic>? hits,
  ) {
    if (hits == null) return rows;
    final order = {
      for (var i = 0; i < hits.length; i += 1) hits[i].id as String: i,
    };
    final matched = rows.where((r) => order.containsKey(r.id)).toList()
      ..sort((a, b) => order[a.id]!.compareTo(order[b.id]!));
    return matched;
  }
}

class _StatusFilter extends ConsumerWidget {
  const _StatusFilter({required this.status});

  final String? status;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Row(
        children: [
          _Chip(
            label: 'ee.kb.filterAll'.tr(),
            selected: status == null,
            onSelected: () =>
                ref.read(eeKbStatusFilterProvider.notifier).clear(),
          ),
          for (final s in kEeKbStatuses)
            Padding(
              padding: const EdgeInsets.only(left: 8),
              child: _Chip(
                key: Key('kb-filter-$s'),
                label: 'ee.kb.status.$s'.tr(),
                selected: status == s,
                onSelected: () =>
                    ref.read(eeKbStatusFilterProvider.notifier).toggle(s),
              ),
            ),
        ],
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({
    super.key,
    required this.label,
    required this.selected,
    required this.onSelected,
  });

  final String label;
  final bool selected;
  final VoidCallback onSelected;

  @override
  Widget build(BuildContext context) => FilterChip(
    label: Text(label),
    selected: selected,
    onSelected: (_) => onSelected(),
  );
}

class _Row extends StatelessWidget {
  const _Row({required this.article});

  final KbArticleRecord article;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final retired = article.status == 'retired';
    return ListTile(
      key: Key('kb-row-${article.id}'),
      leading: const Icon(Icons.menu_book_outlined),
      title: Text(
        article.title,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        // Retired reads as retired: muted, never struck through or coloured
        // like an error (the services screen settled this first).
        style: retired
            ? theme.textTheme.bodyLarge?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              )
            : null,
      ),
      subtitle: Text(
        article.symptom,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
      ),
      trailing: KbStatusChip(status: article.status),
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => EeKbArticleScreen(articleId: article.id),
        ),
      ),
    );
  }
}
