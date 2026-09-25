import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/date_format.dart';
import '../../../core/error_messages.dart';
import '../../../core/persisted_prefs.dart';
import '../../../i18n/i18n.dart';
import '../../../theme/tokens.dart';
import '../../../widgets/status_views.dart';
import '../data/problems_models.dart';
import '../problems_providers.dart';
import 'problem_labels.dart';
import 'ticket_detail_screen.dart';

/// Opens one problem (EE-270) by its address where a router is there — the
/// list, a request's linked-problem card and a link reach the SAME screen —
/// and by a plain push where the screen is hosted without one.
void awOpenProblem(BuildContext context, String problemId) {
  if (GoRouter.maybeOf(context) != null) {
    context.push('/problems/$problemId');
    return;
  }
  Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (_) => EeProblemDetailScreen(problemId: problemId),
    ),
  );
}

/// One problem (EE-270, AW-E09): "let's open the known-error record".
///
/// ── THE WORKAROUND FIRST ───────────────────────────────────────────────
///
/// It is the sentence this record exists to put in front of somebody: what to
/// do until the fix lands, read out to the person on the phone. So it sits
/// right under the title, in full — a workaround cut in half is a wrong one —
/// and it opens from the device's copy, with no signal. The symptom follows
/// (how to recognise it), then the cause and the permanent action.
///
/// ── THE REQUESTS FROM THE SERVER, AND ONLY THOSE YOU MAY SEE ──────────
///
/// The link lives on the request's side (EE-189); the server answers with the
/// requests in desks this person works in, and the rest as a count, because a
/// unit's subjects do not travel to people outside it (EE-267's rule).
class EeProblemDetailScreen extends ConsumerWidget {
  const EeProblemDetailScreen({super.key, required this.problemId});

  final String problemId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final device = ref.watch(eeProblemOnDeviceProvider(problemId));
    final live = ref.watch(eeProblemLiveProvider(problemId));

    return Scaffold(
      appBar: AppBar(title: Text('ee.problems.detailTitle'.tr())),
      body: device.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => AwErrorState(message: localizedError(error)),
        data: (onDevice) {
          final problem = onDevice ?? live.value?.problem;
          if (problem == null) {
            if (live.isLoading) {
              return const Center(child: CircularProgressIndicator());
            }
            final offline = problemNeedsConnection(live.error);
            return AwEmptyState(
              key: const Key('problem-not-on-device'),
              icon: offline ? Icons.cloud_off_outlined : Icons.search_off,
              title: offline
                  ? 'ee.problems.notOnDevice'.tr()
                  : 'ee.problems.gone'.tr(),
              message: offline
                  ? 'ee.problems.notOnDeviceBody'.tr()
                  : 'ee.problems.goneBody'.tr(),
            );
          }
          return _Body(
            problem: problem,
            fromDevice: onDevice != null,
            live: live,
          );
        },
      ),
    );
  }
}

class _Body extends ConsumerWidget {
  const _Body({
    required this.problem,
    required this.fromDevice,
    required this.live,
  });

  final EeProblem problem;
  final bool fromDevice;
  final AsyncValue<EeProblemLive?> live;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final format = ref.watch(dateFormatProvider);
    final muted = theme.colorScheme.onSurfaceVariant;
    return ListView(
      padding: awListPadding(context, top: AwSpace.x4),
      children: [
        Text(problem.title, style: theme.textTheme.titleLarge),
        const SizedBox(height: AwSpace.x2),
        Wrap(
          spacing: AwSpace.x2,
          runSpacing: AwSpace.x1,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            EeProblemStatusChip(status: problem.status),
            if (problem.resolvedAt != null)
              Chip(
                label: Text(
                  'ee.problems.resolvedOn'.tr(
                    args: {
                      'date': awFormatDate(problem.resolvedAt!, format: format),
                    },
                  ),
                ),
              ),
          ],
        ),
        if (!fromDevice) ...[
          const SizedBox(height: AwSpace.x2),
          Row(
            key: const Key('problem-from-server'),
            children: [
              Icon(Icons.cloud_outlined, size: 18, color: muted),
              const SizedBox(width: AwSpace.x2),
              Expanded(
                child: Text(
                  'ee.problems.fromServer'.tr(),
                  style: theme.textTheme.bodySmall?.copyWith(color: muted),
                ),
              ),
            ],
          ),
        ],
        const SizedBox(height: AwSpace.x4),
        _Workaround(problem: problem),
        _Text(title: 'ee.problems.symptom'.tr(), body: problem.symptom),
        if (problem.rootCause != null && problem.rootCause!.trim().isNotEmpty)
          _Text(title: 'ee.problems.rootCause'.tr(), body: problem.rootCause!),
        if (problem.permanentAction != null &&
            problem.permanentAction!.trim().isNotEmpty)
          _Text(
            title: 'ee.problems.permanentAction'.tr(),
            body: problem.permanentAction!,
          ),
        const SizedBox(height: AwSpace.x2),
        _Requests(live: live),
      ],
    );
  }
}

/// The workaround, or the honest absence of one.
class _Workaround extends StatelessWidget {
  const _Workaround({required this.problem});

  final EeProblem problem;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    if (!problem.hasWorkaround) {
      return Text(
        'ee.problems.noWorkaround'.tr(),
        key: const Key('problem-no-workaround'),
        style: theme.textTheme.bodyMedium?.copyWith(
          color: scheme.onSurfaceVariant,
        ),
      );
    }
    return Card(
      key: const Key('problem-workaround'),
      margin: EdgeInsets.zero,
      color: scheme.primaryContainer,
      child: Padding(
        padding: const EdgeInsets.all(AwSpace.x4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.handyman_outlined,
                  size: 20,
                  color: scheme.onPrimaryContainer,
                ),
                const SizedBox(width: AwSpace.x2),
                Expanded(
                  child: Text(
                    'ee.problems.workaround'.tr(),
                    style: theme.textTheme.titleSmall?.copyWith(
                      color: scheme.onPrimaryContainer,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: AwSpace.x2),
            // Full text, never truncated: a workaround cut in half is a
            // wrong one.
            Text(
              problem.workaround!,
              style: theme.textTheme.bodyLarge?.copyWith(
                color: scheme.onPrimaryContainer,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Text extends StatelessWidget {
  const _Text({required this.title, required this.body});

  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: AwSpace.x4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: theme.textTheme.titleSmall),
          const SizedBox(height: AwSpace.x1),
          Text(body, style: theme.textTheme.bodyMedium),
        ],
      ),
    );
  }
}

/// The requests this problem explains — the server's half.
class _Requests extends StatelessWidget {
  const _Requests({required this.live});

  final AsyncValue<EeProblemLive?> live;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurfaceVariant;
    Widget heading() => Padding(
      padding: const EdgeInsets.only(top: AwSpace.x6, bottom: AwSpace.x2),
      child: Text(
        'ee.problems.requests'.tr(),
        style: theme.textTheme.titleSmall,
      ),
    );
    return live.when(
      loading: () => const Padding(
        padding: EdgeInsets.symmetric(vertical: AwSpace.x4),
        child: Center(child: CircularProgressIndicator()),
      ),
      error: (error, _) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          heading(),
          if (problemNeedsConnection(error))
            Row(
              key: const Key('problem-live-offline'),
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.cloud_off_outlined, size: 18, color: muted),
                const SizedBox(width: AwSpace.x2),
                Expanded(
                  child: Text(
                    'ee.problems.live.offline'.tr(),
                    style: theme.textTheme.bodySmall?.copyWith(color: muted),
                  ),
                ),
              ],
            )
          else
            AwInlineError(message: localizedError(error)),
        ],
      ),
      data: (data) {
        // No entitlement: nothing was asked, and there is nothing to say.
        if (data == null) return const SizedBox.shrink();
        final list = data.tickets;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            heading(),
            if (list.tickets.isEmpty && list.elsewhere == 0)
              Text(
                'ee.problems.requestsNone'.tr(),
                key: const Key('problem-requests-none'),
                style: theme.textTheme.bodySmall,
              ),
            for (final ticket in list.tickets)
              Card(
                key: Key('problem-request-${ticket.id}'),
                margin: const EdgeInsets.only(bottom: AwSpace.x2),
                clipBehavior: Clip.antiAlias,
                child: ListTile(
                  leading: const Icon(Icons.support_agent),
                  title: Text(
                    [
                      if (ticket.number != null) '#${ticket.number}',
                      ticket.subject,
                    ].join(' · '),
                  ),
                  subtitle: Text(
                    AwI18n.instance.maybeTranslate(
                          'ee.tickets.status.${ticket.status}',
                        ) ??
                        ticket.status,
                  ),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => awOpenTicket(context, ticket.id),
                ),
              ),
            if (list.count > list.tickets.length)
              Text(
                'ee.problems.requestsMore'.tr(
                  args: {'count': '${list.count - list.tickets.length}'},
                ),
                style: theme.textTheme.bodySmall,
              ),
            if (list.elsewhere > 0)
              Padding(
                padding: const EdgeInsets.only(top: AwSpace.x1),
                child: Text(
                  'ee.problems.requestsElsewhere'.tr(
                    args: {'count': '${list.elsewhere}'},
                  ),
                  key: const Key('problem-requests-elsewhere'),
                  style: theme.textTheme.bodySmall?.copyWith(color: muted),
                ),
              ),
          ],
        );
      },
    );
  }
}
