import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/date_format.dart';
import '../../../core/persisted_prefs.dart';
import '../../../i18n/i18n.dart';
import '../../../theme/tokens.dart';
import '../../../widgets/status_views.dart';
import '../data/history_models.dart';
import '../history_providers.dart';
import 'assignee_avatars.dart';

/// The reusable history tab (EE-026). E07's units and E09's tickets attach it
/// with two strings and get the same tab — one implementation, so "who did
/// what, when" reads identically wherever it appears.
///
/// Server-only by construction (ADR-0005): there is no replica behind this,
/// so an unreachable server must SAY so. An empty list would read as "nothing
/// ever happened here", which is a claim about the past we cannot make when
/// we have not heard from the server (the api_keys lesson, applied).
class EeHistoryTab extends ConsumerWidget {
  const EeHistoryTab({
    super.key,
    required this.entityType,
    required this.entityId,
  });

  final String entityType;
  final String entityId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final target = (entityType: entityType, entityId: entityId);
    final history = ref.watch(eeHistoryProvider(target));

    return history.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (_, _) => AwErrorState(
        message: 'ee.history.couldNotLoad'.tr(),
        onRetry: () => ref.invalidate(eeHistoryProvider(target)),
      ),
      data: (page) => page.items.isEmpty
          ? AwEmptyState(
              icon: Icons.history_toggle_off_outlined,
              title: 'ee.history.emptyTitle'.tr(),
              message: 'ee.history.emptyBody'.tr(),
            )
          : ListView.separated(
              padding: const EdgeInsets.symmetric(vertical: AwSpace.x2),
              itemCount: page.items.length + (page.hasMore ? 1 : 0),
              separatorBuilder: (_, _) => const SizedBox(height: AwSpace.x1),
              itemBuilder: (context, index) {
                if (index == page.items.length) {
                  // The server said there is more. Saying so beats a list that
                  // silently stops at fifty and looks complete.
                  return Padding(
                    padding: const EdgeInsets.all(AwSpace.x4),
                    child: Text(
                      'ee.history.moreOnServer'.tr(),
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                  );
                }
                return _HistoryRow(event: page.items[index]);
              },
            ),
    );
  }
}

class _HistoryRow extends ConsumerWidget {
  const _HistoryRow({required this.event});

  final EeHistoryEvent event;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final actorName = event.isSystem
        ? 'ee.history.actorSystem'.tr()
        : (event.actorName ?? 'ee.history.actorUnknown'.tr());

    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AwSpace.x4,
        vertical: AwSpace.x2,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _Avatar(event: event),
          const SizedBox(width: AwSpace.x3),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text.rich(
                  TextSpan(
                    children: [
                      TextSpan(
                        text: actorName,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const TextSpan(text: ' '),
                      TextSpan(
                        // The verb dictionary is closed server-side precisely
                        // so every verb has a sentence here (EE-023 rule 2).
                        text: 'ee.verb.${event.verb}'.tr(),
                        style: theme.textTheme.bodyMedium,
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 2),
                // The ONE diff key this tab reads, and it earns the exception:
                // item 10 names "alt işi tamamladı" as an act of its own, and
                // a row saying only "changed the status" cannot tell a
                // finished subtask from a finished task. Everything else in a
                // diff stays the entity's private business.
                if (event.diff?['subtask'] case final List<dynamic> subtask
                    when subtask.isNotEmpty && subtask.first is String)
                  Text(
                    subtask.first as String,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: scheme.onSurface,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                Text(
                  // The user's own date preference — history is not the place
                  // to invent a second format.
                  awFormatShort(
                    event.occurredAt,
                    format: ref.watch(dateFormatProvider),
                  ),
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Avatar extends StatelessWidget {
  const _Avatar({required this.event});

  final EeHistoryEvent event;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    if (event.isSystem) {
      // A repair is not a person. Drawing initials for it would put a name on
      // something nobody did.
      return CircleAvatar(
        radius: 16,
        backgroundColor: scheme.surfaceContainerHighest,
        child: Icon(
          Icons.settings_suggest_outlined,
          size: 18,
          color: scheme.onSurfaceVariant,
        ),
      );
    }
    // EE-071: the shared primitive. This used to fill the circle with the
    // roster colour and draw WHITE initials, on the claim that all ten of the
    // server's colours were dark enough. Measured, five of them are not (worst
    // #CA8A04 at 2.94:1), so half a roster read its own history through
    // initials it could not see. Same circle as a task's assignees now, same
    // measured guarantee (DESIGN §36 W2).
    return AwPersonAvatar(
      label: event.actorName ?? event.actorInitials ?? '',
      initials: event.actorInitials,
      colorRgb: event.actorColorRgb,
      size: 32,
    );
  }
}
