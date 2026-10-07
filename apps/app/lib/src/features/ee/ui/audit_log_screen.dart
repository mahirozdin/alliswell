import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:go_router/go_router.dart';

import '../../../core/date_format.dart';
import '../../../core/persisted_prefs.dart';
import '../../../i18n/i18n.dart';
import '../../../theme/tokens.dart';
import '../data/history_models.dart';
import '../history_providers.dart';
import 'csv_download.dart';
import 'history_tab.dart' show eeAuditVerb;
import '../../../widgets/status_views.dart';
import '../../../widgets/route_leading.dart';

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
/// UI-AUDIT #44: every type a team's history is written against — the
/// server's `HISTORY_ENTITY_TYPES` (EE-302 keeps that list equal to the
/// emit sites by test). The old seven-entry list could not filter to a
/// request, a unit, a service, an invitation or a webhook, and drew the
/// keys raw. Each has a name under `ee.audit.entity.<type>`.
const kEeAuditEntityTypes = <String>[
  'ee_alert_source',
  'ee_announcement',
  'ee_approval',
  'ee_asset',
  'ee_asset_import',
  'ee_automation_rule',
  'ee_business_calendar',
  'ee_canned_reply',
  'ee_catalog_import',
  'ee_change',
  'ee_change_freeze',
  'ee_chat_channel',
  'ee_classification_rule',
  'ee_customer',
  'ee_customer_user',
  'ee_health_check',
  'ee_identity_provider',
  'ee_invite',
  'ee_item_share',
  'ee_kb_article',
  'ee_mail_inbox',
  'ee_meeting',
  'ee_member_absence',
  'ee_member_import',
  'ee_notification_outbox',
  'ee_oncall_schedule',
  'ee_problem',
  'ee_public_form',
  'ee_role',
  'ee_saved_view',
  'ee_service',
  'ee_service_category',
  'ee_sla_policy',
  'ee_supplier',
  'ee_team',
  'ee_team_ai_connection',
  'ee_team_mail_settings',
  'ee_team_member',
  'ee_ticket',
  'ee_ticket_export',
  'ee_ticket_import',
  'ee_ticket_rating',
  'ee_ticket_template',
  'ee_unit',
  'ee_webhook',
  'ee_whatsapp_config',
  'task',
  'workspace',
];

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
      appBar: AppBar(
        leading: awRouteLeading(context),
        // UI-AUDIT #89: the same name as the Settings row that opens it.
        title: Text('ee.audit.title'.tr()),
        actions: [
          // UI-AUDIT #56: the record as a file, with the filters on screen —
          // the screen itself already stands behind `team.view_audit`.
          IconButton(
            key: const Key('audit-csv'),
            tooltip: 'ee.csv.download'.tr(),
            icon: const Icon(Icons.download_outlined),
            onPressed: () => eeDownloadCsv(
              context,
              ref,
              (api) => api.audit(verb: _verb, entityType: _entityType),
            ),
          ),
        ],
      ),
      body: Column(
        children: [
          _FilterBar(
            verb: _verb,
            entityType: _entityType,
            verbs: _verbs,
            entityTypes: kEeAuditEntityTypes,
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
              // Sorted by what a person reads, not by the key.
              for (final t
                  in [...entityTypes]..sort(
                    (a, b) =>
                        eeAuditEntityName(a).compareTo(eeAuditEntityName(b)),
                  ))
                DropdownMenuItem(value: t, child: Text(eeAuditEntityName(t))),
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
    return ListView.builder(
      padding: awListPadding(context),
      itemCount: page.items.length + (page.hasMore ? 1 : 0),
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

class _AuditRow extends ConsumerWidget {
  const _AuditRow({required this.event});

  final EeHistoryEvent event;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final format = ref.watch(dateFormatProvider);
    final actorName = event.isSystem
        ? 'ee.history.actorSystem'.tr()
        : (event.actorName ?? 'ee.history.actorUnknown'.tr());

    final record = eeAuditRecordLabel(event);
    final path = eeAuditRecordPath(event);

    return Padding(
      padding: kAwListRowPadding,
      child: Card(
        child: ListTile(
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
                // verb has a sentence here (EE-023 rule 2) — and the sentence
                // depends on what it was done to (UI-AUDIT R2-2).
                TextSpan(text: eeAuditVerb(event.entityType, event.verb)),
              ],
            ),
          ),
          // UI-AUDIT #44: WHICH record — its kind in words, and its name or
          // number when the event carries one — rather than "ee_ticket".
          subtitle: Text(
            [
              eeAuditEntityName(event.entityType),
              ?record,
              // The person's own date format (DESIGN §17), never ISO.
              awFormatDateTime(event.occurredAt, format: format),
            ].join(' · '),
            style: theme.textTheme.bodySmall,
          ),
          // …and a way to it, for the kinds that have a screen of their own.
          trailing: path == null ? null : const Icon(Icons.chevron_right),
          onTap: path == null || GoRouter.maybeOf(context) == null
              ? null
              : () => context.push(path),
        ),
      ),
    );
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

/// The kind of record, in words (UI-AUDIT #44). A type this build has no
/// name for — a newer server's — falls back to the key rather than nothing.
String eeAuditEntityName(String type) =>
    AwI18n.instance.maybeTranslate('ee.audit.entity.$type') ?? type;

/// The record's own name or number: the server's [EeHistoryEvent.entityLabel]
/// when it sent one, else read from the event's diff — the fields
/// the server's emit sites write (`number`, `subject`, `title`, `name`,
/// `email`, `filename`). A diff field is either a value or an `[old, new]`
/// pair; the newer side wins, so a renamed record reads by its current name
/// and a deleted one by the name it had.
String? eeAuditRecordLabel(EeHistoryEvent event) {
  final named = event.entityLabel?.trim();
  if (named != null && named.isNotEmpty) return named;
  final diff = event.diff;
  if (diff == null) return null;
  Object? valueOf(String key) {
    final raw = diff[key];
    if (raw is List) {
      if (raw.length == 2) return raw[1] ?? raw[0];
      return null;
    }
    return raw;
  }

  final number = valueOf('number');
  final name = [
    'subject',
    'title',
    'name',
    'email',
    'filename',
  ].map(valueOf).whereType<String>().where((v) => v.isNotEmpty).firstOrNull;
  if (number is num) {
    return name == null ? '#${number.toInt()}' : '#${number.toInt()} $name';
  }
  return name;
}

/// Where a row leads, for the kinds of record that have a screen with an
/// address. A deleted record has none to open.
String? eeAuditRecordPath(EeHistoryEvent event) {
  if (event.verb == 'deleted' || event.entityId.isEmpty) return null;
  final id = event.entityId;
  return switch (event.entityType) {
    'ee_ticket' => '/tickets/$id',
    'task' => '/tasks/$id',
    'ee_change' => '/changes/$id',
    'ee_problem' => '/problems/$id',
    'ee_asset' => '/assets/$id',
    'ee_kb_article' => '/kb/$id',
    'ee_meeting' => '/meetings/$id',
    'ee_approval' => '/approvals/$id',
    _ => null,
  };
}
