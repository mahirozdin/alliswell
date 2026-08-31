import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../i18n/i18n.dart';
import '../../../theme/tokens.dart';
import '../data/history_models.dart';
import '../history_providers.dart';

/// The team's whole history, filtered (EE-130).
///
/// ── AN AUDIT SCREEN'S EMPTY STATE IS ITS SHARPEST CLAIM ───────────────────
///
/// "Nothing here" can mean three completely different things, and on a
/// compliance screen they are not interchangeable:
///
///   • nothing has been recorded  → the team is new
///   • nothing MATCHES            → the filters are too narrow
///   • we could not ask           → the server said no, or was unreachable
///
/// A screen that renders all three as a blank list tells an auditor that
/// nothing happened. So each one has its own sentence, and the failure case is
/// an error rather than an empty list — the api_keys lesson, and the reason
/// `teamFeed` deliberately does not swallow a 403.
///
/// ── THE FILTERS ARE A RECORD, AND CLEARING IS ABSENCE ─────────────────────
///
/// A cleared dropdown sends no parameter at all rather than an empty one.
/// `verb=` is a 400 from the server's typed schema and `verb` absent is "no
/// filter"; those are different requests and only the second is what clearing
/// means.
class EeAuditLogScreen extends ConsumerStatefulWidget {
  const EeAuditLogScreen({super.key});

  @override
  ConsumerState<EeAuditLogScreen> createState() => _EeAuditLogScreenState();
}

class _EeAuditLogScreenState extends ConsumerState<EeAuditLogScreen> {
  String? _verb;
  String? _entityType;

  /// The verbs worth offering. Deliberately NOT the whole dictionary: a
  /// dropdown of twenty-odd verbs is a list nobody reads, and these are the
  /// ones somebody actually comes to this screen looking for.
  static const _verbs = <String>[
    'created',
    'updated',
    'deleted',
    'member_added',
    'member_removed',
    'role_changed',
    'revoked',
    'suspended',
    'status_changed',
  ];

  static const _entityTypes = <String>[
    'ee_team',
    'ee_team_member',
    'ee_role',
    'workspace',
    'task',
    'ee_public_form',
    'ee_member_import',
  ];

  bool get _filtered => _verb != null || _entityType != null;

  @override
  Widget build(BuildContext context) {
    final filters = (
      verb: _verb,
      entityType: _entityType,
      from: null as DateTime?,
      to: null as DateTime?,
    );
    final page = ref.watch(eeTeamAuditProvider(filters));

    return Scaffold(
      appBar: AppBar(title: Text('ee.audit.title'.tr())),
      body: Column(
        children: [
          _FilterBar(
            verb: _verb,
            entityType: _entityType,
            verbs: _verbs,
            entityTypes: _entityTypes,
            onVerb: (v) => setState(() => _verb = v),
            onEntityType: (v) => setState(() => _entityType = v),
            onClear: _filtered
                ? () => setState(() {
                    _verb = null;
                    _entityType = null;
                  })
                : null,
          ),
          const Divider(height: 1),
          Expanded(
            child: page.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              // A real error, never an empty list. On this screen a blank page
              // reads as "nothing happened", which is the one thing it must
              // not say when the truth is "we could not ask".
              error: (_, _) => _Message(
                key: const Key('audit-error'),
                title: 'ee.audit.couldNotLoad'.tr(),
              ),
              data: (data) => data.items.isEmpty
                  ? _Message(
                      key: const Key('audit-empty'),
                      // The two empties are different facts and get different
                      // sentences.
                      title: _filtered
                          ? 'ee.audit.emptyFiltered'.tr()
                          : 'ee.audit.empty'.tr(),
                    )
                  : _EventList(page: data),
            ),
          ),
        ],
      ),
    );
  }
}

class _FilterBar extends StatelessWidget {
  const _FilterBar({
    required this.verb,
    required this.entityType,
    required this.verbs,
    required this.entityTypes,
    required this.onVerb,
    required this.onEntityType,
    required this.onClear,
  });

  final String? verb;
  final String? entityType;
  final List<String> verbs;
  final List<String> entityTypes;
  final ValueChanged<String?> onVerb;
  final ValueChanged<String?> onEntityType;
  final VoidCallback? onClear;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(AwSpace.x3),
      child: Wrap(
        spacing: AwSpace.x2,
        runSpacing: AwSpace.x2,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          DropdownButton<String?>(
            key: const Key('audit-filter-verb'),
            value: verb,
            hint: Text('ee.audit.anyAction'.tr()),
            onChanged: onVerb,
            items: [
              DropdownMenuItem(
                value: null,
                child: Text('ee.audit.anyAction'.tr()),
              ),
              for (final v in verbs)
                DropdownMenuItem(value: v, child: Text('ee.verb.$v'.tr())),
            ],
          ),
          DropdownButton<String?>(
            key: const Key('audit-filter-entity'),
            value: entityType,
            hint: Text('ee.audit.anything'.tr()),
            onChanged: onEntityType,
            items: [
              DropdownMenuItem(
                value: null,
                child: Text('ee.audit.anything'.tr()),
              ),
              for (final t in entityTypes)
                DropdownMenuItem(value: t, child: Text(t)),
            ],
          ),
          if (onClear != null)
            TextButton(
              key: const Key('audit-clear'),
              onPressed: onClear,
              child: Text('ee.audit.clear'.tr()),
            ),
        ],
      ),
    );
  }
}

class _EventList extends StatelessWidget {
  const _EventList({required this.page});

  final EeHistoryPage page;

  @override
  Widget build(BuildContext context) {
    return ListView.separated(
      itemCount: page.items.length + (page.hasMore ? 1 : 0),
      separatorBuilder: (_, _) => const Divider(height: 1),
      itemBuilder: (context, index) {
        if (index >= page.items.length) {
          // The server has more. Said plainly rather than with an infinite
          // scroll that would let somebody believe they had reached the end of
          // the record when they had reached the end of a page.
          return Padding(
            key: const Key('audit-more'),
            padding: const EdgeInsets.all(AwSpace.x4),
            child: Text(
              'ee.audit.moreOnServer'.tr(),
              style: Theme.of(context).textTheme.bodySmall,
            ),
          );
        }
        return _AuditRow(event: page.items[index]);
      },
    );
  }
}

class _AuditRow extends StatelessWidget {
  const _AuditRow({required this.event});

  final EeHistoryEvent event;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final actorName = event.isSystem
        ? 'ee.history.actorSystem'.tr()
        : (event.actorName ?? 'ee.history.actorUnknown'.tr());

    return ListTile(
      key: Key('audit-row-${event.id}'),
      dense: true,
      title: Text.rich(
        TextSpan(
          children: [
            TextSpan(
              text: actorName,
              style: theme.textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            const TextSpan(text: ' '),
            // The verb dictionary is closed server-side precisely so every
            // verb has a sentence here (EE-023 rule 2).
            TextSpan(text: 'ee.verb.${event.verb}'.tr()),
          ],
        ),
      ),
      subtitle: Text(
        '${event.entityType} · ${_stamp(event.occurredAt)}',
        style: theme.textTheme.bodySmall,
      ),
    );
  }

  /// Local time, to the minute. Seconds on an audit list are noise; the exact
  /// instant is in the export, which is where somebody goes when it matters.
  static String _stamp(DateTime at) {
    String two(int n) => n.toString().padLeft(2, '0');
    return '${at.year}-${two(at.month)}-${two(at.day)} ${two(at.hour)}:${two(at.minute)}';
  }
}

class _Message extends StatelessWidget {
  const _Message({required this.title, super.key});

  final String title;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AwSpace.x6),
        child: Text(
          title,
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.bodyMedium,
        ),
      ),
    );
  }
}
