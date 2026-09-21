import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../i18n/i18n.dart';
import '../../../theme/tokens.dart';
import '../../../widgets/status_views.dart';
import '../data/performance_models.dart';
import '../performance_providers.dart';

/// The performance panel (EE-205) — the same numbers per unit and per person.
///
/// ── THE WARNING IS NOT A FOOTNOTE ────────────────────────────────────────
///
/// "Who closed how many" is the first metric a manager reaches for and the one
/// that punishes whoever takes the hard requests. The task's own acceptance
/// line asks for the sentence, so it is at the TOP of the screen, above the
/// numbers it is about, rather than in small print underneath where it becomes
/// something to scroll past.
///
/// It is also the server's sentence, not the app's: whoever pulls these
/// figures out through the API is exactly the person who needs it, and a
/// warning that lives only in Flutter never reaches them.
///
/// ── THE THREE RULES THIS SCREEN INHERITS ─────────────────────────────────
///
///   • A DASH IS NOT A ZERO. An average with nothing measured is "—". A desk
///     that promised nothing has no mean time to anything, and `0` reads as
///     "instant" — the same rule `sla_dashboard_screen.dart` keeps for
///     compliance.
///   • THE COLOUR IS THE MARK, THE MEANING IS THE WORD. `AwTokens.warning`
///     measures 3.46 on the light surface: legal for an icon, illegal for a
///     sentence. Nothing here is drawn in it, and every state carries its own
///     word so a black-and-white print-out still reads.
///   • A BAR IS A BAR AND A NUMBER IS A NUMBER. Every figure is text. This
///     screen exists to be quoted in a meeting, and nobody quotes a bar.
///
/// ── AND AN AVERAGE NEVER APPEARS WITHOUT ITS DENOMINATOR ─────────────────
///
/// `12 dk (8/20)` rather than `12 dk`. Only requests covered by an SLA policy
/// are timed, so on a desk where half the services promised nothing the bare
/// number is a true statement about a minority and a false one about the desk.
class EePerformanceScreen extends ConsumerWidget {
  const EePerformanceScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final panel = ref.watch(eePerformanceProvider);
    final days = ref.watch(eePerformanceRangeProvider);

    return Scaffold(
      appBar: AppBar(title: Text('ee.perfPanel.title'.tr())),
      body: panel.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => AwErrorState(message: '$error'),
        data: (data) {
          if (data == null) {
            return AwEmptyState(
              icon: Icons.groups_outlined,
              title: 'ee.perfPanel.unavailable'.tr(),
              message: 'ee.perfPanel.unavailableBody'.tr(),
            );
          }
          return RefreshIndicator(
            onRefresh: () => ref.read(eePerformanceProvider.notifier).refresh(),
            child: ListView(
              padding: const EdgeInsets.all(AwSpace.x4),
              children: [
                _Caution(text: data.closedIsNotPerformance),
                const SizedBox(height: AwSpace.x4),
                _RangePicker(
                  days: days,
                  onChanged: (value) {
                    ref.read(eePerformanceRangeProvider.notifier).set(value);
                  },
                ),
                const SizedBox(height: AwSpace.x6),
                _Rows(
                  titleKey: 'ee.perfPanel.byUnit',
                  emptyKey: 'ee.perfPanel.noUnits',
                  rows: data.units,
                ),
                const SizedBox(height: AwSpace.x6),
                _Rows(
                  titleKey: 'ee.perfPanel.byAgent',
                  emptyKey: 'ee.perfPanel.noAgents',
                  rows: data.agents,
                  unnamedKey: 'ee.perfPanel.unattributed',
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

/// The sentence, above the numbers it is about.
class _Caution extends StatelessWidget {
  const _Caution({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      key: const Key('perf-caution'),
      // The surface carries the emphasis; the TEXT is drawn in the ordinary
      // body colour, because a sentence in `warning` would fail contrast at
      // text strength (3.46 measured) — EE-097's rule, and the reason this
      // screen has an icon beside the words rather than coloured words.
      color: theme.colorScheme.surfaceContainerHighest,
      child: Padding(
        padding: const EdgeInsets.all(AwSpace.x4),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.info_outline, color: theme.colorScheme.onSurfaceVariant),
            const SizedBox(width: AwSpace.x3),
            Expanded(child: Text(text, style: theme.textTheme.bodyMedium)),
          ],
        ),
      ),
    );
  }
}

class _RangePicker extends StatelessWidget {
  const _RangePicker({required this.days, required this.onChanged});

  final int days;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: AwSpace.x2,
      children: [7, 30, 90]
          .map(
            (value) => ChoiceChip(
              key: Key('perf-range-$value'),
              label: Text('ee.perfPanel.days'.tr(args: {'days': '$value'})),
              selected: days == value,
              onSelected: (_) => onChanged(value),
            ),
          )
          .toList(growable: false),
    );
  }
}

class _Rows extends StatelessWidget {
  const _Rows({
    required this.titleKey,
    required this.emptyKey,
    required this.rows,
    this.unnamedKey,
  });

  final String titleKey;
  final String emptyKey;
  final List<EePerformanceRow> rows;
  final String? unnamedKey;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(titleKey.tr(), style: theme.textTheme.titleSmall),
        const SizedBox(height: AwSpace.x2),
        if (rows.isEmpty)
          Text(emptyKey.tr(), style: theme.textTheme.bodyMedium)
        else
          ...rows.map(
            (row) => _RowCard(
              row: row,
              // A null key on the people axis is work nobody was there for.
              // Named rather than dropped: the rows have to add up to the
              // desk's totals or somebody spends an afternoon reconciling them.
              fallbackLabel: unnamedKey == null
                  ? 'ee.perfPanel.noUnit'.tr()
                  : unnamedKey!.tr(),
            ),
          ),
      ],
    );
  }
}

class _RowCard extends StatelessWidget {
  const _RowCard({required this.row, required this.fallbackLabel});

  final EePerformanceRow row;
  final String fallbackLabel;

  /// An average with its denominator, or a dash. Never a bare number and never
  /// a zero standing in for "nothing measured".
  String _avg(EeTimedAverage a) {
    if (a.minutes == null) return '—';
    final value = 'ee.perfPanel.minutes'.tr(
      args: {'minutes': a.minutes!.toStringAsFixed(1)},
    );
    return a.isPartial ? '$value (${a.measured}/${a.total})' : value;
  }

  String _csat(EeCsatFigure c) {
    if (c.average == null) return '—';
    return '${c.average!.toStringAsFixed(1)} (${c.answered}/${c.sent})';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final label = row.label ?? fallbackLabel;
    return Card(
      key: Key('perf-row-${row.key ?? 'none'}'),
      child: Padding(
        padding: const EdgeInsets.all(AwSpace.x4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: theme.textTheme.titleSmall),
            const SizedBox(height: AwSpace.x2),
            Wrap(
              spacing: AwSpace.x4,
              runSpacing: AwSpace.x2,
              children: [
                _Figure(
                  labelKey: 'ee.perfPanel.opened',
                  value: '${row.opened}',
                ),
                _Figure(
                  labelKey: 'ee.perfPanel.resolved',
                  value: '${row.resolved}',
                ),
                _Figure(labelKey: 'ee.perfPanel.mtta', value: _avg(row.mtta)),
                _Figure(labelKey: 'ee.perfPanel.mttr', value: _avg(row.mttr)),
                _Figure(labelKey: 'ee.perfPanel.csat', value: _csat(row.csat)),
                if (row.compliance != null)
                  _Figure(
                    labelKey: 'ee.perfPanel.compliance',
                    value: 'ee.perfPanel.percent'.tr(
                      args: {'value': row.compliance!.toStringAsFixed(1)},
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

/// One figure: a word above a number, both readable in black and white.
class _Figure extends StatelessWidget {
  const _Figure({required this.labelKey, required this.value});

  final String labelKey;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          labelKey.tr(),
          style: theme.textTheme.labelSmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        Text(value, style: theme.textTheme.titleMedium),
      ],
    );
  }
}
