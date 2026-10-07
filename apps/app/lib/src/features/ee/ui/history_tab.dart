import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/date_format.dart';
import '../../../core/persisted_prefs.dart';
import '../../../i18n/i18n.dart';
import '../../../theme/tokens.dart';
import '../../../widgets/status_views.dart';
import '../data/history_models.dart';
import '../data/labour_models.dart';
import '../data/ticket_write_api.dart';
import '../history_providers.dart';
import '../ticket_write_providers.dart';
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
                        text: eeAuditVerb(event.entityType, event.verb),
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
                // OPH-358 (UI-AUDIT #6): a request's row says WHAT moved —
                // the status it left and the one it took, the questions an
                // approver corrected — because "updated this" on twenty rows
                // reads as nothing happening twenty times.
                if (event.entityType == 'ee_ticket')
                  if (_TicketChange.of(event) case final change?)
                    _TicketChangeLine(event: event, change: change),
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

/// What one request row's diff says, in words (OPH-358, UI-AUDIT #6). Only
/// the keys the request's writers are known to send (`tickets/db.js`); any
/// other diff stays the entity's private business, as before.
class _TicketChange {
  const _TicketChange({this.line, this.answerKeys = const []});

  final String? line;

  /// `answersChanged`: the form questions a correction moved — named by the
  /// row widget, which can ask for the labels.
  final List<String> answerKeys;

  static String? _pair(Object? value, String Function(String) word) {
    if (value is! List || value.length != 2) return null;
    final from = value[0];
    final to = value[1];
    if (to is! String) return null;
    return from is String ? '${word(from)} → ${word(to)}' : word(to);
  }

  static String _status(String v) =>
      AwI18n.instance.maybeTranslate('ee.tickets.status.$v') ??
      'ee.history.ticket.unknownValue'.tr();

  static String _priority(String v) =>
      AwI18n.instance.maybeTranslate('ee.tickets.priority.$v') ??
      'ee.history.ticket.unknownValue'.tr();

  static _TicketChange? of(EeHistoryEvent event) {
    final diff = event.diff;
    if (diff == null) return null;
    final answers = diff['answersChanged'];
    if (answers is List && answers.isNotEmpty) {
      return _TicketChange(answerKeys: answers.whereType<String>().toList());
    }
    final reason = diff['reason'];
    if (reason is List &&
        reason.length == 2 &&
        reason[1] == 'requester_replied') {
      final status = _pair(diff['status'], _status);
      return _TicketChange(
        line: ['ee.history.ticket.requesterReplied'.tr(), ?status].join(' · '),
      );
    }
    if (_pair(diff['status'], _status) case final status?) {
      return _TicketChange(
        line: 'ee.history.ticket.status'.tr(args: {'change': status}),
      );
    }
    if (_pair(diff['priority'], _priority) case final priority?) {
      return _TicketChange(
        line: 'ee.history.ticket.priority'.tr(args: {'change': priority}),
      );
    }
    final tag = diff['tag'];
    if (tag is List && tag.length == 2) {
      if (tag[1] is String) {
        return _TicketChange(
          line: 'ee.history.ticket.tagAdded'.tr(
            args: {'tag': tag[1] as String},
          ),
        );
      }
      if (tag[0] is String) {
        return _TicketChange(
          line: 'ee.history.ticket.tagRemoved'.tr(
            args: {'tag': tag[0] as String},
          ),
        );
      }
    }
    if (diff.containsKey('customer')) {
      return _TicketChange(line: 'ee.history.ticket.customer'.tr());
    }
    final internal = diff['internal'];
    if (diff.containsKey('comment') &&
        internal is List &&
        internal.length == 2) {
      return _TicketChange(
        line:
            (internal[1] == true
                    ? 'ee.history.ticket.note'
                    : 'ee.history.ticket.reply')
                .tr(),
      );
    }
    if (diff['minutes'] case final num minutes when minutes > 0) {
      return _TicketChange(
        line: 'ee.history.ticket.worklog'.tr(
          args: {'duration': eeDurationText(minutes.toInt())},
        ),
      );
    }
    return null;
  }
}

class _TicketChangeLine extends ConsumerWidget {
  const _TicketChangeLine({required this.event, required this.change});

  final EeHistoryEvent event;
  final _TicketChange change;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    var line = change.line;
    if (change.answerKeys.isNotEmpty) {
      // The questions as the form asks them. Read only for a row that needs
      // them (the request's own read, EE-278), and the key stands in until —
      // or unless — it answers.
      final labels = {
        for (final answer
            in ref
                    .watch(eeTicketActionsProvider(event.entityId))
                    .value
                    ?.answers ??
                const <EeTicketAnswer>[])
          if (answer.key != null) answer.key!: answer.label,
      };
      line = 'ee.history.ticket.formCorrected'.tr(
        args: {
          'fields': [
            for (final key in change.answerKeys) labels[key] ?? key,
          ].join(', '),
        },
      );
    }
    if (line == null) return const SizedBox.shrink();
    return Text(
      line,
      key: Key('history-change-${event.id}'),
      style: theme.textTheme.bodySmall?.copyWith(
        color: theme.colorScheme.onSurface,
      ),
    );
  }
}

/// The verb as a sentence about WHAT it was done to (OPH-362, UI-AUDIT R2-2).
///
/// One server verb covers several acts: `revoked` is an administrator ending
/// somebody's sessions, an invitation withdrawn, a webhook, a public link, a
/// share, a chat channel or a mailbox cut off. A single sentence for all of
/// them ("ended a session") put a revoked invitation in the log as a session
/// that ended. So a kind may have its own sentence (`ee.verbFor.<type>.<verb>`)
/// and the verb's own (`ee.verb.<verb>`) is the neutral fallback for every
/// kind that has none — never the wire name. `check:i18n` holds both
/// dictionaries to the server's kinds and verbs (`ee-vocabulary.mjs`).
String eeAuditVerb(String entityType, String verb) =>
    AwI18n.instance.maybeTranslate('ee.verbFor.$entityType.$verb') ??
    'ee.verb.$verb'.tr();
