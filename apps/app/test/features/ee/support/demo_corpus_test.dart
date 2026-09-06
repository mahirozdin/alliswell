// The demo corpus is ONE company, and the numbers on it agree (EE-146).
//
// This file has no `screenshots` dart-define, on purpose: it runs in the
// ordinary `flutter test` CI does. The shot files it protects do not — they
// return from main() immediately without the define, and their only
// `expectLater` is a `matchesGoldenFile` that always passes under
// `--update-goldens`. So the screenshots assert nothing, and this is the only
// thing standing between a marketing page and a set of pictures whose numbers
// contradict each other.
//
// The defect it was written against was live in the repo: three shot fixtures
// described three different companies, two of them disagreed about how many
// people are in Bakım, and both of those pictures are on the same page.
// Meanwhile the two fixtures that DID agree agreed only because a ticket
// subject was a copy-pasted string literal in two files — the failure mode
// this whole design removes.
import 'package:flutter/material.dart' show Locale;
import 'package:flutter_test/flutter_test.dart';

import 'package:alliswell/src/i18n/i18n.dart';

import 'demo_corpus.dart';

/// `GET /ee/team/sla/dashboard` caps the breach list at 20 (routes.js). The
/// screen truncates NOTHING, so a corpus that exceeds the cap would draw a
/// list the server could never send.
const int kServerBreachCap = 20;

void main() {
  DemoCorpus corpusFor(String code) {
    AwI18n.instance.setActiveCached(Locale(code));
    return DemoCorpus.active();
  }

  for (final code in ['tr', 'en']) {
    group('the demo corpus in $code', () {
      late DemoCorpus c;
      setUp(() => c = corpusFor(code));

      test('a unit says how many people it has by counting them', () {
        for (final u in c.units) {
          expect(
            u.memberCount,
            c.roster(u.id).length,
            reason: 'unit ${u.id} (${u.name}) counts its own roster',
          );
        }
        // A team with no roster at all would pass the loop above vacuously.
        expect(c.units, isNotEmpty);
        expect(
          c.units.map((u) => u.memberCount).reduce((a, b) => a + b),
          greaterThan(0),
        );
      });

      test('exactly one unit is the one the viewer runs', () {
        expect(c.units.where((u) => u.manages), hasLength(1));
        expect(c.unitsAsSeenBy(admin: false), hasLength(1));
        expect(
          c.unitsAsSeenBy(admin: true).length,
          greaterThan(c.unitsAsSeenBy(admin: false).length),
        );
      });

      test('one catalogue entry is routed to nobody, and names no work', () {
        final unrouted = c.unroutedService;
        for (final p in DemoPeriod.values) {
          final keys = c.dashboard(p).byService.map((b) => b.key);
          expect(
            keys,
            isNot(contains(unrouted.id)),
            reason:
                '${unrouted.id} is routed to no unit, so tickets/db.js would '
                'refuse every request for it — it cannot have a count',
          );
        }
      });

      for (final period in DemoPeriod.values) {
        group('the ${period.name} period', () {
          test('every axis counts the same requests', () {
            final d = c.dashboard(period);
            final total = d.total;
            expect(total, greaterThan(0));
            for (final axis in {
              'byStatus': d.byStatus,
              'byUnit': d.byUnit,
              'byService': d.byService,
              'bySla': d.bySla,
            }.entries) {
              expect(
                axis.value.fold<int>(0, (n, b) => n + b.count),
                total,
                reason: '${axis.key} must add up to the same $total',
              );
            }
          });

          test('the compliance figure is what its buckets say', () {
            final d = c.dashboard(period);
            expect(d.compliance, DemoCorpus.complianceOf(c.slaCounts(period)));
          });

          test('the breach list is complete and not a second copy', () {
            final d = c.dashboard(period);
            final breached = c.slaCounts(period)['breached'] ?? 0;

            expect(
              d.breaches,
              hasLength(breached),
              reason:
                  'the screen draws every breach it is given, so a list '
                  'shorter than the bucket is a number nobody can account for',
            );
            expect(
              breached,
              lessThanOrEqualTo(kServerBreachCap),
              reason: 'the endpoint would have truncated at $kServerBreachCap',
            );

            // Each row IS the corpus's ticket, not a retyped copy of it.
            for (final b in d.breaches) {
              final t = c.queue.where((q) => q.id == b.id);
              if (t.isNotEmpty) {
                expect(t.single.subject, b.subject);
                expect(t.single.priority, b.priority);
                expect(t.single.status, b.status);
              }
              expect(b.subject, isNotEmpty);
            }
          });
        });
      }

      test('a breached row in the queue appears in the breach list', () {
        final listed = c
            .dashboard(DemoPeriod.struggling)
            .breaches
            .map((b) => b.id)
            .toSet();
        final onQueue = c.queue
            .where((t) => t.slaStatus == 'breached')
            .map((t) => t.id);
        expect(onQueue, isNotEmpty, reason: 'the queue shot needs a breach');
        for (final id in onQueue) {
          expect(listed, contains(id));
        }
      });

      test('a healthy desk has nothing to list, and says so with a number', () {
        final d = c.dashboard(DemoPeriod.healthy);
        expect(d.breaches, isEmpty);
        expect(d.compliance, 100.0);
      });

      test('the portal quotas cannot disagree with themselves', () {
        final p = c.portalLinks;
        for (final q in [p.linkQuota, p.ticketQuota]) {
          if (q.max != null) expect(q.remaining, q.max! - q.used);
        }
        // Every link points at a service that exists.
        final serviceIds = c.services.map((s) => s.id).toSet();
        for (final l in p.links) {
          expect(serviceIds, contains(l.serviceId));
        }
      });

      test('a running clock is in the future, a missed one is not', () {
        // An absolute date in a fixture becomes false the day after the shot.
        // The queue's warned row read "16 d over" on the day this was written,
        // which is a state the server cannot produce: warned means the clock
        // is past 80% and still RUNNING.
        for (final t in c.queue) {
          if (t.slaDueAt == null) continue;
          if (t.slaStatus == 'warned' || t.slaStatus == 'ok') {
            expect(
              t.slaDueAt!.isAfter(DateTime.now()),
              isTrue,
              reason: '${t.id} is ${t.slaStatus} but its target has passed',
            );
          }
        }
      });

      test('a request with a conversation on it has been picked up', () {
        // The thread was first hung on the queue's top row, which is `new`.
        // Three messages on an untouched request is a picture that argues with
        // itself, and this page is read by people who look twice.
        for (final id in c.threadedTicketIds) {
          expect(
            c.ticket(id).status,
            isNot('new'),
            reason: '$id carries a thread but nobody has picked it up',
          );
        }
      });

      test('every audit verb is one the product actually has', () {
        // ee.verb.* mirrors the server's CLOSED dictionary
        // (ee/server/modules/audit/verbs.js). The first draft of the history
        // fixture used `sla_breached` and `commented`; neither exists — a
        // comment is not an audited event — and the only thing that said so
        // was an [i18n] missing key line scrolling past in a golden run.
        for (final e in c.historyFor('T5').items) {
          final key = 'ee.verb.${e.verb}';
          expect(
            key.tr(),
            isNot(key),
            reason: '${e.verb} is not in the audit verb dictionary',
          );
        }
      });

      test('every reference resolves', () {
        final unitIds = c.units.map((u) => u.id).toSet();
        final serviceIds = c.services.map((s) => s.id).toSet();
        for (final t in c.queue) {
          expect(unitIds, contains(t.workspaceId));
          if (t.serviceId != null) expect(serviceIds, contains(t.serviceId));
        }
        for (final s in c.services) {
          for (final u in s.unitIds) {
            expect(unitIds, contains(u));
          }
        }
      });

      test('the strings are in the language that was asked for', () {
        // A locale that fell back would produce the other language's words
        // under this language's filename — the failure eeGolden exists to
        // make impossible, checked here from the other end.
        expect(c.lang, code);
        final maintenance = c.units.first.name;
        expect(maintenance, code == 'tr' ? 'Bakım' : 'Maintenance');
      });
    });
  }

  // ── The two versions of the page must quote the same figures ─────────────
  test('English and Turkish are the same company, structurally', () {
    final tr = corpusFor('tr');
    final en = corpusFor('en');

    expect(en.subdomain, tr.subdomain);
    expect(en.brandRgb, tr.brandRgb);
    expect(en.units.map((u) => u.id), tr.units.map((u) => u.id));
    expect(
      en.units.map((u) => u.memberCount),
      tr.units.map((u) => u.memberCount),
    );
    expect(en.services.map((s) => s.id), tr.services.map((s) => s.id));
    expect(en.queue.map((t) => t.id), tr.queue.map((t) => t.id));

    for (final p in DemoPeriod.values) {
      final a = en.dashboard(p);
      final b = tr.dashboard(p);
      expect(a.compliance, b.compliance);
      expect(a.total, b.total);
      expect(a.breaches.map((x) => x.id), b.breaches.map((x) => x.id));
      expect(
        a.byUnit.map((x) => x.count),
        b.byUnit.map((x) => x.count),
        reason: 'the two language versions must not quote different numbers',
      );
    }

    // And the words really did change, or nothing was translated at all.
    expect(en.companyName, isNot(tr.companyName));
    expect(en.units.first.name, isNot(tr.units.first.name));
    expect(en.queue.first.subject, isNot(tr.queue.first.subject));

    // People are deliberately NOT translated: initials and colours are drawn
    // onto the queue rows, so a translated name would change the avatar and
    // the two versions would stop being pictures of the same screen.
    expect(
      en.roster('U1').map((m) => m.displayName),
      tr.roster('U1').map((m) => m.displayName),
    );
  });
}
