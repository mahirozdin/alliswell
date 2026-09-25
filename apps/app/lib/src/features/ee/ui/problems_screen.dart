import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/error_messages.dart';
import '../../../i18n/i18n.dart';
import '../../../search/search.dart';
import '../../../theme/tokens.dart';
import '../../../widgets/search_field.dart';
import '../../../widgets/status_views.dart';
import '../data/problems_models.dart';
import '../problems_providers.dart';
import '../providers.dart';
import 'new_problem_screen.dart';
import 'problem_detail_screen.dart';
import 'problem_labels.dart';

/// Known faults (EE-270, AW-E09's problem half) — the list.
///
/// The current unit's copy, readable and searchable with no signal, grouped
/// by the server's own status word with known errors first: a known error is
/// the one kind of problem that comes with something to do about it. Each row
/// says whether a workaround is written down, because that is the question an
/// agent opens this screen with.
class EeProblemsScreen extends ConsumerWidget {
  const EeProblemsScreen({super.key});

  static List<EeProblem> _ranked(List<EeProblem> rows, List<SearchHit> hits) {
    final order = {for (var i = 0; i < hits.length; i += 1) hits[i].id: i};
    return rows.where((r) => order.containsKey(r.id)).toList()
      ..sort((a, b) => order[a.id]!.compareTo(order[b.id]!));
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final list = ref.watch(eeProblemListProvider);
    final query = ref.watch(problemSearchQueryProvider).trim();
    final hits = ref.watch(problemSearchResultsProvider).value;
    final canManage = ref.watch(canProvider('problems.manage'));

    return Scaffold(
      appBar: AppBar(
        title: Text('ee.problems.title'.tr()),
        actions: [
          AwSearchAction(
            fieldKey: const Key('problem-search'),
            hintText: 'ee.problems.searchHint'.tr(),
            onQuery: (q) =>
                ref.read(problemSearchQueryProvider.notifier).set(q),
          ),
          if (canManage)
            IconButton(
              key: const Key('problem-new'),
              tooltip: 'ee.problems.new'.tr(),
              icon: const Icon(Icons.add),
              onPressed: () => awOpenNewProblem(context),
            ),
        ],
      ),
      body: list.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => AwErrorState(
          message: localizedError(error),
          onRetry: () => ref.invalidate(eeProblemListProvider),
        ),
        data: (problems) {
          final searching = hits != null || query.isNotEmpty;
          if (searching) {
            final found = hits == null
                ? const <EeProblem>[]
                : _ranked(problems, hits);
            if (found.isEmpty) {
              return AwEmptyState(
                key: const Key('problem-search-empty'),
                icon: Icons.search_off,
                title: 'ee.problems.searchEmpty'.tr(),
                message: 'ee.problems.searchEmptyBody'.tr(),
              );
            }
            return ListView(
              padding: awListPadding(context),
              children: [for (final p in found) EeProblemRow(problem: p)],
            );
          }
          if (problems.isEmpty) {
            return AwEmptyState(
              key: const Key('problem-empty'),
              icon: Icons.bug_report_outlined,
              title: 'ee.problems.empty'.tr(),
              message: 'ee.problems.emptyBody'.tr(),
            );
          }
          final children = <Widget>[];
          String? group;
          for (final problem in problems) {
            if (problem.status != group) {
              group = problem.status;
              children.add(
                Padding(
                  key: Key('problem-section-${problem.status}'),
                  padding: const EdgeInsets.fromLTRB(
                    0,
                    AwSpace.x4,
                    0,
                    AwSpace.x2,
                  ),
                  child: Text(
                    AwI18n.instance.maybeTranslate(
                          'ee.problems.section.${problem.status}',
                        ) ??
                        problem.status,
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                ),
              );
            }
            children.add(EeProblemRow(problem: problem));
          }
          return ListView(padding: awListPadding(context), children: children);
        },
      ),
    );
  }
}

/// One problem as a card row: its title, its status, what people see, and
/// whether there is a workaround to read out.
class EeProblemRow extends StatelessWidget {
  const EeProblemRow({super.key, required this.problem});

  final EeProblem problem;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurfaceVariant;
    return Card(
      key: Key('problem-${problem.id}'),
      margin: const EdgeInsets.only(bottom: AwSpace.x2),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => awOpenProblem(context, problem.id),
        child: Padding(
          padding: const EdgeInsets.all(AwSpace.x3),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(problem.title, style: theme.textTheme.titleMedium),
              const SizedBox(height: AwSpace.x2),
              EeProblemStatusChip(status: problem.status, dense: true),
              const SizedBox(height: AwSpace.x2),
              Text(
                problem.symptom,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodySmall?.copyWith(color: muted),
              ),
              if (problem.hasWorkaround) ...[
                const SizedBox(height: AwSpace.x2),
                Row(
                  key: Key('problem-has-workaround-${problem.id}'),
                  children: [
                    Icon(
                      Icons.handyman_outlined,
                      size: 18,
                      color: theme.colorScheme.primary,
                    ),
                    const SizedBox(width: AwSpace.x2),
                    Expanded(
                      child: Text(
                        'ee.problems.hasWorkaround'.tr(),
                        style: theme.textTheme.bodySmall,
                      ),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// Opens the form for a new problem record — from the list (the desk on
/// screen) or from a request ([source], EE-280), which the route carries in
/// `extra` rather than in its address.
void awOpenNewProblem(BuildContext context, {EeProblemSource? source}) {
  if (GoRouter.maybeOf(context) != null) {
    context.push('/problems/new', extra: source);
    return;
  }
  Navigator.of(context).push(
    MaterialPageRoute<void>(builder: (_) => EeNewProblemScreen(source: source)),
  );
}
