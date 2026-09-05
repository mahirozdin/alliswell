// One company, in the app's own model types (EE-146).
//
// Read demo_corpus.json's `_readme` first — it carries the WHY. This file is
// the seam: it turns that document into the records each screen's providers
// expect, resolves every string to the active language, and DERIVES every
// figure that another figure implies.
//
// The derivation is the point. `compliance` is not in the JSON: it is
// met / (met + breached), computed here exactly as counters.js computes it
// server-side, so the number on the dashboard cannot drift from the buckets
// that produce it. Unit member counts are the length of the unit's roster
// rather than a typed integer. A breach row is the corpus's own ticket, so its
// subject cannot be a second copy of a string.
//
// ORDERING HAZARD: `active()` reads the language from AwI18n, so it must be
// called AFTER setActiveCached. It asserts rather than defaulting — a silent
// fallback would write an English screenshot under a Turkish filename, which
// is the same class of failure as the missing-font bug the harness already
// guards (design_screenshots_test.dart).
import 'dart:convert';
import 'dart:io';

import 'package:alliswell/src/features/ee/assignments_providers.dart'
    show Assignee;
import 'package:alliswell/src/features/ee/data/portal_links_models.dart';
import 'package:alliswell/src/features/ee/data/services_models.dart';
import 'package:alliswell/src/features/ee/data/sla_dashboard_models.dart';
import 'package:alliswell/src/features/ee/data/units_models.dart';
import 'package:alliswell/src/sync/db/database.dart';
import 'package:alliswell/src/i18n/i18n.dart';

/// Which period the SLA dashboard is showing.
enum DemoPeriod {
  /// Below the line, with a breach list a manager would act on.
  struggling,

  /// Nothing missed — the shot a customer sees on a day the product works.
  healthy,
}

class DemoCorpus {
  DemoCorpus._(this._raw, this.lang);

  final Map<String, dynamic> _raw;

  /// `tr` or `en`. Structure never varies with it; only strings do.
  final String lang;

  static final Map<String, DemoCorpus> _cache = {};
  static Map<String, dynamic>? _json;

  /// The corpus in whatever language `AwI18n` is currently set to.
  static DemoCorpus active() {
    final code = AwI18n.instance.locale.languageCode;
    assert(
      code == 'tr' || code == 'en',
      'DemoCorpus.active() before a locale was chosen (got "$code"). Call '
      'AwI18n.instance.setActiveCached(...) in setUp FIRST — a corpus that '
      'quietly falls back writes one language under the other one\'s filename.',
    );
    return forLanguage(code);
  }

  static DemoCorpus forLanguage(String code) => _cache.putIfAbsent(code, () {
    // Relative to the working directory, the same way the screenshot harness
    // finds its fonts — so every run starts with `cd apps/app`.
    _json ??=
        jsonDecode(
              File(
                'test/features/ee/support/demo_corpus.json',
              ).readAsStringSync(),
            )
            as Map<String, dynamic>;
    return DemoCorpus._(_json!, code);
  });

  String _s(Map<String, dynamic> node) => node[lang] as String;

  List<Map<String, dynamic>> _list(String key) =>
      (_raw[key] as List).cast<Map<String, dynamic>>();

  // ── The organisation ─────────────────────────────────────────────────────

  Map<String, dynamic> get _company => _raw['company'] as Map<String, dynamic>;

  String get companyName => _s(_company['name'] as Map<String, dynamic>);
  String get brandRgb => _company['brandRgb'] as String;
  String get subdomain => _company['subdomain'] as String;

  /// Units with `memberCount` DERIVED from the roster, never typed twice.
  List<EeUnit> get units => _list('units')
      .map(
        (u) => EeUnit(
          id: u['id'] as String,
          name: _s(u['name'] as Map<String, dynamic>),
          archived: (u['archived'] as bool?) ?? false,
          manages: (u['manages'] as bool?) ?? false,
          memberCount: roster(u['id'] as String).length,
          workspaceIds: [u['id'] as String],
        ),
      )
      .toList();

  /// What an admin sees. A delegated manager sees only what they run — the
  /// server hands them that list, so the shot must not show them the team.
  List<EeUnit> unitsAsSeenBy({required bool admin}) =>
      admin ? units : units.where((u) => u.manages).toList();

  List<EeUnitMember> roster(String unitId) => _list('people')
      .where((p) => p['unitId'] == unitId)
      .map(
        (p) => EeUnitMember(
          userId: p['id'] as String,
          role: p['role'] as String,
          displayName: p['displayName'] as String?,
          email: p['email'] as String?,
        ),
      )
      .toList();

  // ── The catalogue ────────────────────────────────────────────────────────

  List<EeService> get services => _list('services')
      .map(
        (s) => EeService(
          id: s['id'] as String,
          name: _s(s['name'] as Map<String, dynamic>),
          unitIds: ((s['unitIds'] as List?) ?? const []).cast<String>(),
          formFields: ((s['fields'] as List?) ?? const [])
              .cast<Map<String, dynamic>>()
              .map(
                (f) => EeServiceField(
                  key: f['key'] as String,
                  label: _s(f['label'] as Map<String, dynamic>),
                  type: f['type'] as String,
                  required: (f['required'] as bool?) ?? false,
                  options: ((f['options'] as List?) ?? const []).cast<String>(),
                ),
              )
              .toList(),
        ),
      )
      .toList();

  /// The catalogue entry routed to nobody. `tickets/db.js` refuses a request
  /// for one, so it must appear in no count anywhere.
  EeService get unroutedService =>
      services.firstWhere((s) => s.unitIds.isEmpty);

  // ── The work ─────────────────────────────────────────────────────────────

  List<Map<String, dynamic>> get _tickets => _list('tickets');

  TicketRecord _ticket(Map<String, dynamic> t) => TicketRecord(
    id: t['id'] as String,
    workspaceId: t['unitId'] as String,
    serviceId: t['serviceId'] as String?,
    requesterId: 'P01',
    subject: _s(t['subject'] as Map<String, dynamic>),
    body: null,
    status: t['status'] as String,
    priority: t['priority'] as String,
    source: 'internal',
    terminalAt: t['terminalAt'] == null
        ? null
        : DateTime.parse(t['terminalAt'] as String),
    slaStatus: t['slaStatus'] as String?,
    slaDueAt: t['slaDueAt'] == null
        ? null
        : DateTime.parse(t['slaDueAt'] as String),
    createdAt: DateTime.utc(2026, 8, 20, 9),
    revision: 1,
    updatedAt: DateTime.utc(2026, 8, 20, 9),
  );

  /// The rows the queue screenshot shows, in the order the screen sorts them.
  List<TicketRecord> get queue =>
      _tickets.where((t) => t['onQueue'] == true).map(_ticket).toList();

  /// Avatars on two of the four rows: an assigned ticket and an unassigned one
  /// have to be tellable apart, and "nobody is on it" is the commonest state
  /// of a live queue rather than an edge case.
  Map<String, List<Assignee>> get assignees {
    final people = {for (final p in _list('people')) p['id'] as String: p};
    final out = <String, List<Assignee>>{};
    for (final t in _tickets) {
      final ids = ((t['assignees'] as List?) ?? const []).cast<String>();
      if (ids.isEmpty) continue;
      out[t['id'] as String] = [
        for (var i = 0; i < ids.length; i++)
          Assignee(
            assignmentId: 'A${t['id']}$i',
            userId: ids[i],
            displayName: people[ids[i]]!['displayName'] as String,
            initials: people[ids[i]]!['initials'] as String,
            colorRgb: people[ids[i]]!['colorRgb'] as String,
          ),
      ];
    }
    return out;
  }

  // ── The dashboard, entirely folded ───────────────────────────────────────

  Map<String, dynamic> _period(DemoPeriod p) =>
      (_raw['periods'] as Map<String, dynamic>)[p.name] as Map<String, dynamic>;

  /// met / (met + breached), rounded to one decimal — `counters.js`'s
  /// `complianceOf`. Null when nothing has been judged: a desk where no
  /// promise has come due yet is at NO percentage, not at 100 %.
  static double? complianceOf(Map<String, int> bySla) {
    final met = bySla['met'] ?? 0;
    final breached = bySla['breached'] ?? 0;
    if (met + breached == 0) return null;
    return (met * 1000 / (met + breached)).round() / 10;
  }

  Map<String, int> slaCounts(DemoPeriod p) =>
      (_period(p)['bySla'] as Map<String, dynamic>).cast<String, int>();

  List<EeSlaBucket> _axis(
    DemoPeriod p,
    String key,
    String Function(String id)? label,
  ) {
    final raw = (_period(p)[key] as Map<String, dynamic>).cast<String, int>();
    return [
      for (final e in raw.entries)
        // The empty key is the retired-catalogue-entry bucket: the count is
        // still true, so the row stays and the screen says so in words rather
        // than dropping a number nobody can account for.
        EeSlaBucket(
          key: e.key.isEmpty ? null : e.key,
          label: e.key.isEmpty ? null : (label?.call(e.key) ?? e.key),
          count: e.value,
        ),
    ];
  }

  EeSlaDashboard dashboard(DemoPeriod p) {
    final byId = {for (final t in _tickets) t['id'] as String: t};
    final unitName = {for (final u in units) u.id: u.name};
    final serviceName = {for (final s in services) s.id: s.name};
    return EeSlaDashboard(
      compliance: complianceOf(slaCounts(p)),
      byStatus: _axis(p, 'byStatus', null),
      byUnit: _axis(p, 'byUnit', (id) => unitName[id]!),
      byService: _axis(p, 'byService', (id) => serviceName[id]!),
      bySla: _axis(p, 'bySla', null),
      breaches: [
        for (final id in (_period(p)['breachIds'] as List).cast<String>())
          EeSlaBreach(
            id: id,
            subject: _s(byId[id]!['subject'] as Map<String, dynamic>),
            priority: byId[id]!['priority'] as String,
            status: byId[id]!['status'] as String,
          ),
      ],
    );
  }

  // ── The public portal ────────────────────────────────────────────────────

  Map<String, dynamic> get _portal => _raw['portal'] as Map<String, dynamic>;

  EePortalQuota _quota(String key) {
    final q = (_portal[key] as Map<String, dynamic>).cast<String, int>();
    return EePortalQuota(
      used: q['used']!,
      max: q['max'],
      // Derived, so the two halves of "2 of 5 used, 3 left" cannot disagree.
      remaining: q['max'] == null ? null : q['max']! - q['used']!,
    );
  }

  EePortalLinksData get portalLinks => EePortalLinksData(
    links: [
      for (final l in (_portal['links'] as List).cast<Map<String, dynamic>>())
        EePortalLink(
          id: l['id'] as String,
          serviceId: l['serviceId'] as String,
          unitId: l['unitId'] as String?,
          state: EePortalLinkState.parse(l['state'] as String?),
          enabled: l['enabled'] as bool,
          expiresAt: DateTime.parse(l['expiresAt'] as String),
          revokedAt: l['revokedAt'] == null
              ? null
              : DateTime.parse(l['revokedAt'] as String),
          hasCustomFields: (l['hasCustomFields'] as bool?) ?? false,
        ),
    ],
    linkQuota: _quota('linkQuota'),
    ticketQuota: _quota('ticketQuota'),
  );
}
