import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/error_messages.dart';
import '../../../i18n/i18n.dart';
import '../../../theme/tokens.dart';
import '../../../widgets/status_views.dart';
import '../data/sla_dashboard_models.dart';
import '../sla_dashboard_providers.dart';
import 'report_format.dart';
import 'ticket_detail_screen.dart' show awOpenTicket;
import '../../../widgets/route_leading.dart';
import '../../../widgets/fab_clearance.dart';

/// The SLA dashboard (EE-098) — the screen this epic is sold on.
///
/// Every number here is computed on the server from the pre-aggregated
/// counters and scoped to the workspaces the caller is in, so a unit manager
/// and a team admin open the same screen and see two honest, different worlds.
///
/// ── Three decisions this file exists to keep ─────────────────────────────
///
///   • A DASH IS NOT A ZERO. `compliance == null` means nothing has been
///     judged yet — no promise kept and none broken — and it is drawn as "—".
///     A desk that has not bought an SLA is not at 100 %, and a screen shown
///     to a customer is the worst place to round that up.
///
///   • THE COLOUR IS THE MARK, THE MEANING IS THE WORD (EE-097's rule, and
///     the contrast gate's). `AwTokens.warning` measures 3.46 on the light
///     surface — legal for an icon, illegal for a sentence — so no label here
///     is drawn in it. The compliance figure takes `error` or `success`, both
///     of which pass at text strength, and every state carries its own word
///     so a black-and-white print-out still reads.
///
///   • A BAR IS A BAR AND A NUMBER IS A NUMBER. Each breakdown row shows the
///     count as text beside its bar. A bar alone is a picture of a ratio
///     nobody can quote in a meeting, and this screen exists to be quoted.
class EeSlaDashboardScreen extends ConsumerWidget {
  const EeSlaDashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final dashboard = ref.watch(eeSlaDashboardProvider);

    return Scaffold(
      appBar: AppBar(
        leading: awRouteLeading(context),
        title: Text('ee.slaDash.title'.tr()),
      ),
      body: dashboard.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        // OPH-357 (UI-AUDIT #24): the translated message and a way to ask
        // again — never the exception's own text.
        error: (error, _) => AwErrorState(
          message: localizedError(error),
          onRetry: () => ref.invalidate(eeSlaDashboardProvider),
        ),
        data: (data) {
          if (data == null) {
            return AwEmptyState(
              icon: Icons.query_stats_outlined,
              title: 'ee.slaDash.unavailable'.tr(),
              message: 'ee.slaDash.unavailableBody'.tr(),
            );
          }
          return RefreshIndicator(
            onRefresh: () =>
                ref.read(eeSlaDashboardProvider.notifier).refresh(),
            child: ListView(
              padding: awPagePadding(context, AwSpace.x4),
              children: [
                // UI-AUDIT #22: a team with no default policy measures nothing
                // it opens from now on — said above the figure it undermines.
                if (data.hasDefaultPolicy == false) ...[
                  const _NoDefaultPolicy(),
                  const SizedBox(height: AwSpace.x4),
                ],
                _Compliance(value: data.compliance, judged: data.judged),
                const SizedBox(height: AwSpace.x4),
                _Outcomes(data: data),
                const SizedBox(height: AwSpace.x6),
                _Breakdown(
                  titleKey: 'ee.slaDash.byUnit',
                  buckets: data.byUnit,
                  emptyKey: 'ee.slaDash.noUnits',
                ),
                const SizedBox(height: AwSpace.x6),
                _Breakdown(
                  titleKey: 'ee.slaDash.byService',
                  buckets: data.byService,
                  emptyKey: 'ee.slaDash.noServices',
                  labelFor: (b) => b.label ?? 'ee.slaDash.noService'.tr(),
                ),
                const SizedBox(height: AwSpace.x6),
                _Breaches(breaches: data.breaches),
              ],
            ),
          );
        },
      ),
    );
  }
}

/// The headline: met against broken, as a percentage — or a dash.
class _Compliance extends StatelessWidget {
  const _Compliance({required this.value, required this.judged});

  final double? value;

  /// The denominator `value` was computed over (UI-AUDIT #52).
  final int judged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tokens = context.awTokens;
    // A judged desk speaks in colour, and both of these pass at text strength
    // (measured: error 5.38, success 5.46 on the light surface). Below 90 % is
    // the line an operations manager would call a problem.
    final colour = value == null
        ? theme.textTheme.bodyLarge?.color
        : value! < 90
        ? theme.colorScheme.error
        : tokens.success;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AwSpace.x4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'ee.slaDash.compliance'.tr(),
              style: theme.textTheme.titleSmall,
            ),
            const SizedBox(height: AwSpace.x2),
            Text(
              // "—" and not "0 %" and not "100 %": nothing has been judged.
              //
              // EE-147: the percent sign used to be a hardcoded PREFIX, which
              // is the Turkish convention — so the English capture on the
              // enterprise page has been reading "%78.4" since EE-098. Every
              // other string on this screen goes through .tr(); this one did
              // not, and check:i18n could not see it because its blind spot is
              // exactly this shape (a Text whose argument is an expression,
              // not a literal).
              value == null
                  ? '—'
                  // UI-AUDIT #88: the reader's locale writes it — "%40,3" in
                  // Turkish, "40.3%" in English, not a fixed English point.
                  : eePercentText(value!),
              key: const Key('sla-compliance'),
              style: theme.textTheme.displaySmall?.copyWith(color: colour),
            ),
            const SizedBox(height: AwSpace.x1),
            Text(
              value == null
                  ? 'ee.slaDash.complianceNone'.tr()
                  : 'ee.slaDash.complianceOf'.tr(args: {'total': '$judged'}),
              key: const Key('sla-compliance-of'),
              style: theme.textTheme.bodySmall,
            ),
          ],
        ),
      ),
    );
  }
}

/// UI-AUDIT #52 — what the percentage is made of: broken, close, kept.
///
/// The counts were on the wire all along (`bySla`) and never drawn, so a
/// board at 40 % could not say whether that was 114 broken promises or 2.
class _Outcomes extends StatelessWidget {
  const _Outcomes({required this.data});

  final EeSlaDashboard data;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tokens = context.awTokens;
    Widget figure(
      String key,
      String labelKey,
      IconData icon,
      Color mark,
    ) => Expanded(
      child: Semantics(
        container: true,
        excludeSemantics: true,
        label: '${labelKey.tr()}: ${data.slaCount(key)}',
        child: Column(
          key: Key('sla-outcome-$key'),
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // The colour is the mark; the word and the number are body
            // text (EE-097's rule — warning is 3.46, a mark only).
            Row(
              children: [
                Icon(icon, size: 16, color: mark),
                const SizedBox(width: AwSpace.x1),
                Flexible(
                  child: Text(
                    labelKey.tr(),
                    style: theme.textTheme.labelMedium,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            const SizedBox(height: AwSpace.x1),
            Text('${data.slaCount(key)}', style: theme.textTheme.headlineSmall),
          ],
        ),
      ),
    );
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AwSpace.x4),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            figure(
              'breached',
              'ee.slaDash.outcomeBreached',
              Icons.error_outline,
              theme.colorScheme.error,
            ),
            figure(
              'warned',
              'ee.slaDash.outcomeWarned',
              Icons.schedule,
              tokens.warning,
            ),
            figure(
              'met',
              'ee.slaDash.outcomeMet',
              Icons.verified_outlined,
              tokens.success,
            ),
          ],
        ),
      ),
    );
  }
}

/// UI-AUDIT #22 — no default policy: new requests are measured by nothing.
class _NoDefaultPolicy extends StatelessWidget {
  const _NoDefaultPolicy();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      key: const Key('sla-no-default-policy'),
      child: Padding(
        padding: const EdgeInsets.all(AwSpace.x4),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.warning_amber_outlined, color: context.awTokens.warning),
            const SizedBox(width: AwSpace.x3),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'ee.slaDash.noDefaultTitle'.tr(),
                    style: theme.textTheme.titleSmall,
                  ),
                  const SizedBox(height: AwSpace.x1),
                  Text(
                    'ee.slaDash.noDefaultBody'.tr(),
                    style: theme.textTheme.bodySmall,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// One axis, as rows of "name — bar — number".
class _Breakdown extends StatelessWidget {
  const _Breakdown({
    required this.titleKey,
    required this.buckets,
    required this.emptyKey,
    this.labelFor,
  });

  final String titleKey;
  final List<EeSlaBucket> buckets;
  final String emptyKey;
  final String Function(EeSlaBucket)? labelFor;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (buckets.isEmpty) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(titleKey.tr(), style: theme.textTheme.titleSmall),
          const SizedBox(height: AwSpace.x2),
          Text(emptyKey.tr(), style: theme.textTheme.bodySmall),
        ],
      );
    }
    final most = buckets.fold<int>(1, (n, b) => b.count > n ? b.count : n);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(titleKey.tr(), style: theme.textTheme.titleSmall),
        const SizedBox(height: AwSpace.x2),
        for (final b in buckets)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: AwSpace.x1),
            child: Row(
              children: [
                SizedBox(
                  width: 120,
                  child: Text(
                    labelFor?.call(b) ?? b.label ?? '—',
                    style: theme.textTheme.bodyMedium,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                Expanded(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(
                      value: b.count / most,
                      minHeight: 8,
                      // A bar is decoration here — the number beside it is the
                      // fact — so it takes the container tint rather than an
                      // accent that would have to pass at text strength.
                      backgroundColor:
                          theme.colorScheme.surfaceContainerHighest,
                    ),
                  ),
                ),
                const SizedBox(width: AwSpace.x2),
                // The quotable half. A bar alone is a picture of a ratio.
                Text('${b.count}', style: theme.textTheme.bodyMedium),
              ],
            ),
          ),
      ],
    );
  }
}

/// The broken promises, named. Bounded on the server at twenty.
class _Breaches extends StatelessWidget {
  const _Breaches({required this.breaches});

  final List<EeSlaBreach> breaches;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('ee.slaDash.breaches'.tr(), style: theme.textTheme.titleSmall),
        const SizedBox(height: AwSpace.x2),
        if (breaches.isEmpty)
          // Good news needs its own sentence. An empty list drawn as an empty
          // list reads as a screen that failed to load.
          Text(
            'ee.slaDash.noBreaches'.tr(),
            key: const Key('sla-no-breaches'),
            style: theme.textTheme.bodySmall,
          )
        else
          for (final b in breaches)
            ListTile(
              key: Key('sla-breach-${b.id}'),
              contentPadding: EdgeInsets.zero,
              leading: Icon(
                Icons.error_outline,
                color: theme.colorScheme.error,
              ),
              // UI-AUDIT #53: the number tells two rows with one subject
              // apart, and the row opens the request it names.
              title: Text(
                b.number == null ? b.subject : '#${b.number} · ${b.subject}',
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              subtitle: Text(
                [
                  'ee.tickets.status.${b.status}'.tr(),
                  'ee.tickets.priority.${b.priority}'.tr(),
                ].join(' · '),
                style: theme.textTheme.bodySmall,
              ),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => awOpenTicket(context, b.id),
            ),
      ],
    );
  }
}
