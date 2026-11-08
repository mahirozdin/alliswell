import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/error_messages.dart';
import '../../../i18n/i18n.dart';
import '../../../theme/tokens.dart';
import '../../../theme/typography.dart';
import '../../../widgets/status_views.dart';
import '../data/performance_models.dart';
import '../data/unit_tickets_api.dart' show EeFigureScope;
import '../performance_providers.dart';
import '../../../core/format.dart';
import '../../../widgets/route_leading.dart';
import 'figure_scope.dart';
import '../../../widgets/fab_clearance.dart';

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
  const EePerformanceScreen({super.key, this.embedded = false});

  /// OPH-409: drawn as a tab of the requests header, under its bar.
  final bool embedded;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final panel = ref.watch(eePerformanceProvider);
    final days = ref.watch(eePerformanceRangeProvider);

    final body = panel.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      // OPH-357 (UI-AUDIT #24): the translated message and a way to ask
      // again — never the exception's own text.
      error: (error, _) => AwErrorState(
        message: localizedError(error),
        onRetry: () => ref.invalidate(eePerformanceProvider),
      ),
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
            padding: awPagePadding(context, AwSpace.x4),
            children: [
              _Caution(text: data.closedIsNotPerformance),
              const SizedBox(height: AwSpace.x4),
              _RangePicker(
                days: days,
                onChanged: (value) {
                  ref.read(eePerformanceRangeProvider.notifier).set(value);
                },
              ),
              const SizedBox(height: AwSpace.x2),
              // U-20: what every figure below counts, and whose.
              // P-14 (EE-310): flow and compliance count different things;
              // named apart where the server says which, today's line when
              // it does not, nothing for a basis the app does not know.
              if (_perfScopeKey(data.scope) case final key?)
                Text(
                  key.tr(),
                  key: const Key('perf-scope'),
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              EeFigureScopeLine(scope: data.scope),
              const SizedBox(height: AwSpace.x6),
              // EE-268 (AW-E21): "how long do repairs take, apart from
              // access requests?" — first, because it is the question
              // this panel is opened to answer.
              _Rows(
                titleKey: 'ee.perfPanel.byProcessType',
                emptyKey: 'ee.perfPanel.noProcessTypes',
                rows: data.processTypes,
                showCsat: false,
                labelOf: (row) => row.key == null
                    ? 'ee.perfPanel.processTypeNone'.tr()
                    : 'ee.perfPanel.processType.${row.key}'.tr(),
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
                // A person has no SLA of their own: no compliance figure.
                showCompliance: false,
              ),
            ],
          ),
        );
      },
    );
    if (embedded) return body;
    return Scaffold(
      appBar: AppBar(
        leading: awRouteLeading(context),
        title: Text('ee.perfPanel.title'.tr()),
      ),
      body: body,
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
    this.labelOf,
    this.showCsat = true,
    this.showCompliance = true,
  });

  final String titleKey;
  final String emptyKey;
  final List<EePerformanceRow> rows;
  final String? unnamedKey;

  /// A row's name when the server does not send one (EE-268: a kind of
  /// work is named HERE, in this device's language).
  final String Function(EePerformanceRow row)? labelOf;

  /// Satisfaction is asked per unit and per person, never per kind of work.
  final bool showCsat;

  /// Units and kinds of work have an SLA figure; people do not.
  final bool showCompliance;

  String _fallback() =>
      unnamedKey == null ? 'ee.perfPanel.noUnit'.tr() : unnamedKey!.tr();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // OPH-410 (U-23): on a desktop the rows are one table — a unit beside a
    // unit, columns aligned, sortable by any of them. The phone keeps a
    // card per row.
    final table =
        rows.isNotEmpty &&
        MediaQuery.sizeOf(context).width >= kAwPaneBreakpoint;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(titleKey.tr(), style: theme.textTheme.titleSmall),
        const SizedBox(height: AwSpace.x2),
        if (rows.isEmpty)
          Text(emptyKey.tr(), style: theme.textTheme.bodyMedium)
        else if (table)
          _Table(
            key: Key('perf-table-$titleKey'),
            section: titleKey.split('.').last,
            rows: rows,
            labelOf: (row) => labelOf?.call(row) ?? row.label ?? _fallback(),
            showCsat: showCsat,
            showCompliance: showCompliance,
          )
        else
          ...rows.map(
            (row) => _RowCard(
              row: row,
              label: labelOf?.call(row),
              showCsat: showCsat,
              showCompliance: showCompliance,
              // A null key on the people axis is work nobody was there for.
              // Named rather than dropped: the rows have to add up to the
              // desk's totals or somebody spends an afternoon reconciling them.
              fallbackLabel: _fallback(),
            ),
          ),
      ],
    );
  }
}

/// An average with its denominator, or a dash. Never a bare number and never
/// a zero standing in for "nothing measured".
String _avg(EeTimedAverage a) {
  if (a.minutes == null) return '—';
  // UI-AUDIT #88 / OPH-408: "3 gün 21 saat", not "5587.5 dk".
  final value = awFormatDuration(a.minutes!.round());
  return a.isPartial ? '$value (${a.measured}/${a.total})' : value;
}

String _csat(EeCsatFigure c) {
  if (c.average == null) return '—';
  return '${awFormatNumber(c.average!, decimals: 1)} (${c.answered}/${c.sent})';
}

/// U-20: a share of nothing is "—", never a percentage borrowed from
/// elsewhere.
bool _complianceShown(EePerformanceRow row) =>
    row.compliance != null && row.judged != 0;

String _complianceValue(EePerformanceRow row) =>
    _complianceShown(row) ? awFormatPercent(row.compliance) : kAwNoValue;

String? _complianceCaption(EePerformanceRow row) =>
    !_complianceShown(row) || row.judged == null
    ? null
    : 'ee.perfPanel.complianceOf'.tr(
        args: {'judged': awFormatNumber(row.judged!)},
      );

class _RowCard extends StatelessWidget {
  const _RowCard({
    required this.row,
    required this.fallbackLabel,
    this.label,
    this.showCsat = true,
    this.showCompliance = true,
  });

  final EePerformanceRow row;
  final String fallbackLabel;
  final String? label;
  final bool showCsat;
  final bool showCompliance;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final label = this.label ?? row.label ?? fallbackLabel;
    return Padding(
      padding: kAwListRowPadding,
      child: Card(
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
                  if (showCsat)
                    _Figure(
                      labelKey: 'ee.perfPanel.csat',
                      value: _csat(row.csat),
                    ),
                  // U-20: the share with its denominator, and "—" when
                  // nothing was judged — a row that opened nothing is at no
                  // percentage, not at one borrowed from elsewhere.
                  if (showCompliance &&
                      (row.compliance != null || row.judged != null))
                    _Figure(
                      key: Key('perf-compliance-${row.key ?? 'none'}'),
                      labelKey: 'ee.perfPanel.compliance',
                      value: _complianceValue(row),
                      caption: _complianceCaption(row),
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

/// One figure: a word above a number, both readable in black and white.
class _Figure extends StatelessWidget {
  const _Figure({
    super.key,
    required this.labelKey,
    required this.value,
    this.caption,
  });

  final String labelKey;
  final String value;

  /// What the number is out of (U-20), under it.
  final String? caption;

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
        if (caption != null)
          Text(
            caption!,
            style: theme.textTheme.labelSmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
      ],
    );
  }
}

/// A column of the desktop table (OPH-410, U-23): its header, how a row
/// reads in it, and what it sorts by.
class _Column {
  const _Column({
    required this.id,
    required this.labelKey,
    required this.value,
    required this.sortKey,
    this.caption,
  });

  final String id;
  final String labelKey;
  final String Function(EePerformanceRow row) value;

  /// Null sorts last whichever way the column is sorted: "nothing measured"
  /// is neither the best nor the worst.
  final num? Function(EePerformanceRow row) sortKey;
  final String? Function(EePerformanceRow row)? caption;
}

/// The rows as one table: a name column, then the figures right-aligned in
/// tabular digits so a unit's number sits under the one above it. A header
/// sorts by its column — first tap the highest first (the name A→Z), the
/// second tap the other way.
class _Table extends StatefulWidget {
  const _Table({
    super.key,
    required this.section,
    required this.rows,
    required this.labelOf,
    required this.showCsat,
    required this.showCompliance,
  });

  final String section;
  final List<EePerformanceRow> rows;
  final String Function(EePerformanceRow row) labelOf;
  final bool showCsat;
  final bool showCompliance;

  @override
  State<_Table> createState() => _TableState();
}

class _TableState extends State<_Table> {
  /// Null: the server's order.
  String? _sortBy;
  bool _descending = true;

  static const double _figureWidth = 152;
  static const double _rowHeight = 48;

  List<_Column> get _columns => [
    _Column(
      id: 'opened',
      labelKey: 'ee.perfPanel.opened',
      value: (r) => awFormatNumber(r.opened),
      sortKey: (r) => r.opened,
    ),
    _Column(
      id: 'resolved',
      labelKey: 'ee.perfPanel.resolved',
      value: (r) => awFormatNumber(r.resolved),
      sortKey: (r) => r.resolved,
    ),
    _Column(
      id: 'mtta',
      labelKey: 'ee.perfPanel.mtta',
      value: (r) => _avg(r.mtta),
      sortKey: (r) => r.mtta.minutes,
    ),
    _Column(
      id: 'mttr',
      labelKey: 'ee.perfPanel.mttr',
      value: (r) => _avg(r.mttr),
      sortKey: (r) => r.mttr.minutes,
    ),
    if (widget.showCsat)
      _Column(
        id: 'csat',
        labelKey: 'ee.perfPanel.csat',
        value: (r) => _csat(r.csat),
        sortKey: (r) => r.csat.average,
      ),
    if (widget.showCompliance &&
        widget.rows.any((r) => r.compliance != null || r.judged != null))
      _Column(
        id: 'compliance',
        labelKey: 'ee.perfPanel.compliance',
        value: _complianceValue,
        caption: _complianceCaption,
        sortKey: (r) => _complianceShown(r) ? r.compliance : null,
      ),
  ];

  List<EePerformanceRow> _sorted(List<_Column> columns) {
    final by = _sortBy;
    if (by == null) return widget.rows;
    final rows = [...widget.rows];
    if (by == 'name') {
      rows.sort((a, b) {
        final c = widget
            .labelOf(a)
            .toLowerCase()
            .compareTo(widget.labelOf(b).toLowerCase());
        return _descending ? -c : c;
      });
      return rows;
    }
    final column = columns.firstWhere((c) => c.id == by);
    rows.sort((a, b) {
      final x = column.sortKey(a);
      final y = column.sortKey(b);
      if (x == null && y == null) return 0;
      if (x == null) return 1;
      if (y == null) return -1;
      final c = x.compareTo(y);
      return _descending ? -c : c;
    });
    return rows;
  }

  void _sort(String id) {
    setState(() {
      if (_sortBy == id) {
        _descending = !_descending;
      } else {
        _sortBy = id;
        // A name reads A→Z first; a figure, the largest first.
        _descending = id != 'name';
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final columns = _columns;
    final rows = _sorted(columns);
    final figure = awTabular(theme.textTheme.bodyMedium!);
    final caption = awTabular(
      theme.textTheme.labelSmall!.copyWith(color: scheme.onSurfaceVariant),
    );

    Widget header(String id, String labelKey, {required bool end}) {
      final active = _sortBy == id;
      final label = labelKey.tr();
      return Semantics(
        button: true,
        label: active
            ? 'ee.perfPanel.sortedBy'.tr(
                args: {
                  'column': label,
                  'direction':
                      (_descending
                              ? 'ee.perfPanel.sortDescending'
                              : 'ee.perfPanel.sortAscending')
                          .tr(),
                },
              )
            : 'ee.perfPanel.sortBy'.tr(args: {'column': label}),
        excludeSemantics: true,
        child: InkWell(
          key: Key('perf-sort-${widget.section}-$id'),
          onTap: () => _sort(id),
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: _rowHeight),
            child: Row(
              mainAxisAlignment: end
                  ? MainAxisAlignment.end
                  : MainAxisAlignment.start,
              children: [
                Flexible(
                  child: Text(
                    label,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    textAlign: end ? TextAlign.end : TextAlign.start,
                    style: theme.textTheme.labelMedium?.copyWith(
                      color: active
                          ? scheme.onSurface
                          : scheme.onSurfaceVariant,
                      fontWeight: active ? FontWeight.w700 : null,
                    ),
                  ),
                ),
                const SizedBox(width: AwSpace.x1),
                // The arrow is where the sort is, and only there.
                SizedBox(
                  width: 16,
                  child: active
                      ? Icon(
                          _descending
                              ? Icons.arrow_downward
                              : Icons.arrow_upward,
                          size: 14,
                          color: scheme.onSurface,
                        )
                      : null,
                ),
              ],
            ),
          ),
        ),
      );
    }

    Widget line(List<Widget> cells, {Key? key, bool divider = true}) =>
        Container(
          key: key,
          constraints: const BoxConstraints(minHeight: _rowHeight),
          padding: const EdgeInsets.symmetric(horizontal: AwSpace.x4),
          decoration: divider
              ? BoxDecoration(
                  border: Border(top: BorderSide(color: scheme.outlineVariant)),
                )
              : null,
          child: Row(children: cells),
        );

    return Card(
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          line(divider: false, [
            Expanded(
              child: header(
                'name',
                widget.section == 'byAgent'
                    ? 'ee.perfPanel.columnPerson'
                    : widget.section == 'byUnit'
                    ? 'ee.perfPanel.columnUnit'
                    : 'ee.perfPanel.columnKind',
                end: false,
              ),
            ),
            for (final c in columns)
              SizedBox(
                width: _figureWidth,
                child: header(c.id, c.labelKey, end: true),
              ),
          ]),
          for (final row in rows)
            line(key: Key('perf-row-${row.key ?? 'none'}'), [
              Expanded(
                child: Text(
                  widget.labelOf(row),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.titleSmall,
                ),
              ),
              for (final c in columns)
                SizedBox(
                  width: _figureWidth,
                  child: Padding(
                    padding: const EdgeInsetsDirectional.only(end: AwSpace.x5),
                    child: Column(
                      key: c.id == 'compliance'
                          ? Key('perf-compliance-${row.key ?? 'none'}')
                          : null,
                      crossAxisAlignment: CrossAxisAlignment.end,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          c.value(row),
                          textAlign: TextAlign.end,
                          style: figure,
                        ),
                        if (c.caption?.call(row) case final String text)
                          Text(text, textAlign: TextAlign.end, style: caption),
                      ],
                    ),
                  ),
                ),
            ]),
        ],
      ),
    );
  }
}

/// The workload panel's basis line (P-14, EE-310), or null when the server
/// names a basis this build cannot describe.
String? _perfScopeKey(EeFigureScope? scope) {
  final flow = scope?.flow;
  final compliance = scope?.compliance;
  if (flow == null && compliance == null) return 'ee.perfPanel.scope';
  if (flow == 'events_in_window' && compliance == 'opened_in_window') {
    return 'ee.perfPanel.scopeWindow';
  }
  return null;
}
