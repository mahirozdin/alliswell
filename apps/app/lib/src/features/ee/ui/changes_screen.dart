import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/error_messages.dart';
import '../../../core/persisted_prefs.dart';
import '../../../i18n/i18n.dart';
import '../../../search/search.dart';
import '../../../theme/tokens.dart';
import '../../../widgets/search_field.dart';
import '../../../widgets/status_views.dart';
import '../changes_providers.dart';
import '../data/changes_models.dart';
import '../providers.dart';
import 'change_detail_screen.dart';
import 'change_labels.dart';
import 'new_change_screen.dart';

/// Planned work (EE-269, AW-E09) — the list.
///
/// ── THE DEVICE'S COPY, AND ONLY THIS UNIT'S ───────────────────────────
///
/// EE-186 sends every change to its desk's devices; this is the first screen
/// that reads them. The list is the current unit's copy, for the queue's
/// reason (the engine syncs one workspace at a time): a list spanning units
/// would show the other units as stale as the last visit. A change filed in
/// another unit is in that unit's list — and in THIS change's calendar, which
/// the server computes across every unit.
///
/// ── SPLIT BY THE CLOCK, NOT BY STATUS ─────────────────────────────────
///
/// Coming up first (soonest window on top), then what has no window yet, then
/// the past. A split by status would need the server's type-keyed map to know
/// which statuses end which life, and a copy of that map here would be the
/// second state machine §0.0/6 forbids. Each row says its status anyway.
class EeChangesScreen extends ConsumerWidget {
  const EeChangesScreen({super.key});

  /// Search narrows and orders; `null` hits means the field is closed.
  static List<EeChange> _ranked(List<EeChange> rows, List<SearchHit> hits) {
    final order = {for (var i = 0; i < hits.length; i += 1) hits[i].id: i};
    return rows.where((r) => order.containsKey(r.id)).toList()
      ..sort((a, b) => order[a.id]!.compareTo(order[b.id]!));
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final list = ref.watch(eeChangeListProvider);
    final query = ref.watch(changeSearchQueryProvider).trim();
    final hits = ref.watch(changeSearchResultsProvider).value;
    final canCreate = ref.watch(canProvider('changes.create'));

    return Scaffold(
      appBar: AppBar(
        title: Text('ee.changes.title'.tr()),
        actions: [
          AwSearchAction(
            fieldKey: const Key('change-search'),
            hintText: 'ee.changes.searchHint'.tr(),
            onQuery: (q) => ref.read(changeSearchQueryProvider.notifier).set(q),
          ),
          if (canCreate)
            IconButton(
              key: const Key('change-new'),
              tooltip: 'ee.changes.new'.tr(),
              icon: const Icon(Icons.add),
              onPressed: () => awOpenNewChange(context),
            ),
        ],
      ),
      body: list.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => AwErrorState(
          message: localizedError(error),
          onRetry: () => ref.invalidate(eeChangeListProvider),
        ),
        data: (changes) {
          final searching = hits != null || query.isNotEmpty;
          if (searching) {
            final found = hits == null
                ? const <EeChange>[]
                : _ranked(changes.all, hits);
            if (found.isEmpty) {
              return AwEmptyState(
                key: const Key('change-search-empty'),
                icon: Icons.search_off,
                title: 'ee.changes.searchEmpty'.tr(),
                message: 'ee.changes.searchEmptyBody'.tr(),
              );
            }
            return ListView(
              padding: awListPadding(context),
              children: [for (final c in found) EeChangeRow(change: c)],
            );
          }
          if (changes.isEmpty) {
            return AwEmptyState(
              key: const Key('change-empty'),
              icon: Icons.event_note_outlined,
              title: 'ee.changes.empty'.tr(),
              message: 'ee.changes.emptyBody'.tr(),
            );
          }
          return ListView(
            padding: awListPadding(context),
            children: [
              ..._section(
                context,
                key: 'ahead',
                title: 'ee.changes.section.ahead'.tr(),
                rows: changes.ahead,
              ),
              ..._section(
                context,
                key: 'unscheduled',
                title: 'ee.changes.section.unscheduled'.tr(),
                rows: changes.unscheduled,
              ),
              ..._section(
                context,
                key: 'past',
                title: 'ee.changes.section.past'.tr(),
                rows: changes.past,
              ),
            ],
          );
        },
      ),
    );
  }

  /// A heading and its rows — or nothing, when the section is empty: an empty
  /// "coming up" heading on a quiet week is noise, not information.
  List<Widget> _section(
    BuildContext context, {
    required String key,
    required String title,
    required List<EeChange> rows,
  }) {
    if (rows.isEmpty) return const [];
    return [
      Padding(
        key: Key('change-section-$key'),
        padding: const EdgeInsets.fromLTRB(0, AwSpace.x4, 0, AwSpace.x2),
        child: Text(title, style: Theme.of(context).textTheme.titleSmall),
      ),
      for (final change in rows) EeChangeRow(change: change),
    ];
  }
}

/// One change as a card row: title, the three chips, and the window.
class EeChangeRow extends ConsumerWidget {
  const EeChangeRow({super.key, required this.change});

  final EeChange change;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final format = ref.watch(dateFormatProvider);
    return Card(
      key: Key('change-${change.id}'),
      margin: const EdgeInsets.only(bottom: AwSpace.x2),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => awOpenChange(context, change.id),
        child: Padding(
          padding: const EdgeInsets.all(AwSpace.x3),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(change.title, style: theme.textTheme.titleMedium),
              const SizedBox(height: AwSpace.x2),
              EeChangeChips(change: change, dense: true),
              const SizedBox(height: AwSpace.x2),
              Row(
                children: [
                  Icon(
                    Icons.schedule,
                    size: 18,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                  const SizedBox(width: AwSpace.x2),
                  Expanded(
                    child: Text(
                      change.hasWindow
                          ? changeWindowText(
                              change.windowStart!,
                              change.windowEnd!,
                              format: format,
                            )
                          : 'ee.changes.noWindow'.tr(),
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Opens the form for a new change, from the list (the desk on screen) or
/// from a request ([source], EE-279). A route with the source in `extra`, the
/// way `/tickets/new` carries a follow-up (EE-252): the address carries
/// nothing (OPH-333's rule — a request is not smuggled through a query).
void awOpenNewChange(BuildContext context, {EeChangeSource? source}) {
  if (GoRouter.maybeOf(context) != null) {
    context.push('/changes/new', extra: source);
    return;
  }
  Navigator.of(context).push(
    MaterialPageRoute<void>(builder: (_) => EeNewChangeScreen(source: source)),
  );
}
