import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/date_format.dart';
import '../../../core/error_messages.dart';
import '../../../i18n/i18n.dart';
import '../../../sync/providers.dart';
import '../../../theme/tokens.dart';
import '../../../widgets/status_views.dart';
import '../../workspaces/workspaces.dart';
import '../data/meeting_models.dart';
import '../meetings_providers.dart';
import 'meeting_screen.dart';

/// The unit's meetings (EE-271, AW-E26) — the door EE-115's screen never had.
///
/// `/meetings/:meetingId` shipped with a route, a guide paragraph and nothing
/// that led to it: a meeting could be read only by somebody who already had
/// its address. This list is that door, for the unit on screen, newest first.
///
/// Each row says the one thing somebody opens this list to learn — is it
/// ready, and what did it decide — so a meeting still being transcribed reads
/// as WAITING, never as done (the detail's rule, EE-115), and the decision
/// count is shown only once there is a note to count them in.
///
/// Server-only and said so: the list is asked for every time it opens and,
/// with no signal, the screen says a connection is needed rather than
/// drawing an old list as the current one.
class EeMeetingsScreen extends ConsumerWidget {
  const EeMeetingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final workspace = ref.watch(currentWorkspaceProvider).value;
    return Scaffold(
      appBar: AppBar(title: Text('ee.meetings.title'.tr())),
      body: workspace == null
          ? const Center(child: CircularProgressIndicator())
          : _List(workspaceId: workspace.id),
    );
  }
}

class _List extends ConsumerWidget {
  const _List({required this.workspaceId});
  final String workspaceId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final list = ref.watch(eeMeetingListProvider(workspaceId));
    void retry() {
      ref.invalidate(eeMeetingListProvider(workspaceId));
      // The read does not ask while the app knows it is offline; the sync
      // engine's pull is the probe that can flip that (the asset card's
      // retry, for the same reason).
      unawaited(ref.read(syncEngineProvider)?.syncNow());
    }

    return list.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (error, _) => meetingsNeedConnection(error)
          ? AwEmptyState(
              key: const Key('meetings-offline'),
              icon: Icons.cloud_off_outlined,
              title: 'ee.meetings.offline'.tr(),
              message: 'ee.meetings.offlineBody'.tr(),
              action: OutlinedButton.icon(
                onPressed: retry,
                icon: const Icon(Icons.refresh),
                label: Text('common.retry'.tr()),
              ),
            )
          : AwErrorState(message: localizedError(error), onRetry: retry),
      data: (meetings) {
        if (meetings == null) {
          return AwEmptyState(
            key: const Key('meetings-unavailable'),
            icon: Icons.mic_off_outlined,
            title: 'ee.meeting.unavailable'.tr(),
            message: 'ee.meeting.unavailableBody'.tr(),
          );
        }
        if (meetings.isEmpty) {
          return AwEmptyState(
            key: const Key('meetings-empty'),
            icon: Icons.groups_outlined,
            title: 'ee.meetings.empty'.tr(),
            message: 'ee.meetings.emptyBody'.tr(),
          );
        }
        return RefreshIndicator(
          onRefresh: () async => retry(),
          child: ListView(
            padding: awListPadding(context),
            children: [for (final m in meetings) EeMeetingRow(meeting: m)],
          ),
        );
      },
    );
  }
}

/// One meeting as a card row: its title, its state in a word, when it was,
/// and — once there is a note — what it decided.
class EeMeetingRow extends StatelessWidget {
  const EeMeetingRow({super.key, required this.meeting});

  final EeMeetingSummary meeting;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tokens = context.awTokens;
    final muted = theme.colorScheme.onSurfaceVariant;
    final status = meeting.status;
    // The detail's marks (EE-115), so the two screens cannot disagree about
    // what a state looks like.
    final (icon, colour) = switch (status) {
      EeMeetingStatus.ready => (Icons.check_circle_outline, tokens.success),
      EeMeetingStatus.failed => (Icons.error_outline, theme.colorScheme.error),
      EeMeetingStatus.transcribed => (Icons.hourglass_bottom, tokens.warning),
      _ => (Icons.autorenew, muted),
    };
    final when = awRelativePast(meeting.createdAt, DateTime.now());
    return Card(
      key: Key('meeting-${meeting.id}'),
      margin: const EdgeInsets.only(bottom: AwSpace.x2),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => awOpenMeeting(context, meeting.id),
        child: Padding(
          padding: const EdgeInsets.all(AwSpace.x3),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icon, color: colour, size: 22),
              const SizedBox(width: AwSpace.x3),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      meeting.title ?? 'ee.meeting.untitled'.tr(),
                      style: theme.textTheme.titleMedium,
                    ),
                    const SizedBox(height: AwSpace.x1),
                    // The WORD, in body colour — the mark beside it is a mark.
                    Text(
                      '${'ee.meeting.status.${status.name}'.tr()} · $when',
                      style: theme.textTheme.bodySmall,
                    ),
                    if (status == EeMeetingStatus.ready) ...[
                      const SizedBox(height: AwSpace.x1),
                      Text(
                        'ee.meetings.counts'.tr(
                          args: {
                            'decisions': '${meeting.decisionCount}',
                            'ideas': '${meeting.ideaCount}',
                          },
                        ),
                        key: Key('meeting-counts-${meeting.id}'),
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: muted,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Opens one meeting — by its address when there is a router, so the list and
/// a pasted link reach the same screen.
void awOpenMeeting(BuildContext context, String meetingId) {
  if (GoRouter.maybeOf(context) != null) {
    context.push('/meetings/$meetingId');
    return;
  }
  Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (_) => EeMeetingScreen(meetingId: meetingId),
    ),
  );
}
