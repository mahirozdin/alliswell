import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'dart:convert';
import 'dart:typed_data';

import 'package:alliswell/src/core/date_format.dart';
import 'package:alliswell/src/features/ee/data/csv_export_api.dart';
import 'package:alliswell/src/features/ee/data/history_models.dart';
import 'package:alliswell/src/features/ee/providers.dart';
import 'package:alliswell/src/features/ee/tickets_providers.dart';
import 'package:alliswell/src/features/ee/ui/csv_download.dart';
import 'package:alliswell/src/features/ee/ui/ticket_queue_screen.dart';
import 'package:alliswell/src/features/ee/unit_scope_providers.dart';
import 'package:alliswell/src/features/workspaces/workspaces.dart';
import 'package:dio/dio.dart';
import 'package:go_router/go_router.dart';
import 'package:alliswell/src/features/ee/history_providers.dart';
import 'package:alliswell/src/features/ee/ui/audit_log_screen.dart';
import 'package:alliswell/src/i18n/i18n.dart';
import 'package:alliswell/src/theme/theme.dart';

import '../../support/list_rhythm.dart';

/// EE-130 — the team history screen, asserted where it would MISLEAD.
///
/// The sharpest thing about an audit screen is its empty state, because
/// "nothing here" can mean three different things and a compliance reviewer
/// acts differently on each:
///
///   • nothing has been recorded  → the team is new
///   • nothing MATCHES            → the filters are too narrow
///   • we could not ask           → the server refused, or was unreachable
///
/// Rendering all three as a blank list tells that reviewer nothing happened.
/// Each one is tested separately, and the failure case is tested hardest —
/// an empty list where an error belongs is the most misleading thing this
/// screen could do.
EeHistoryEvent _event({
  String id = 'E1',
  String verb = 'member_added',
  String actor = 'user',
  String? actorName = 'Ada Yönetici',
  String entityType = 'ee_team_member',
  Map<String, dynamic>? diff,
  String? entityLabel,
}) => EeHistoryEvent(
  id: id,
  occurredAt: DateTime(2026, 8, 31, 9, 5),
  actor: actor,
  verb: verb,
  entityType: entityType,
  entityId: 'X1',
  actorName: actorName,
  diff: diff,
  entityLabel: entityLabel,
);

class _FakeCsv extends EeCsvExportApi {
  _FakeCsv() : super(Dio());
  final asked = <String>[];

  @override
  Future<EeCsvFile> audit({String? verb, String? entityType}) async {
    asked.add('audit verb=$verb type=$entityType');
    return EeCsvFile(
      bytes: Uint8List.fromList(utf8.encode('\uFEFFoccurredAt\n')),
      filename: 'acme-audit.csv',
    );
  }

  @override
  Future<EeCsvFile> tickets({
    String? status,
    String? priority,
    String? source,
    String? slaStatus,
    String? serviceId,
    String? unitId,
  }) async {
    asked.add('tickets');
    return EeCsvFile(
      bytes: Uint8List.fromList(utf8.encode('\uFEFFnumber\n')),
      filename: 'acme-requests.csv',
      truncated: true,
    );
  }
}

class _Sink extends EeCsvSink {
  final saved = <String, Uint8List>{};
  @override
  Future<String?> save(Uint8List bytes, String filename) async {
    saved[filename] = bytes;
    return '/tmp/$filename';
  }
}

Future<void> _pump(
  WidgetTester tester, {
  EeHistoryPage? page,
  Object? error,
  Brightness brightness = Brightness.light,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        eeTeamAuditProvider.overrideWith((ref, filters) async {
          if (error != null) throw error;
          return page ?? const EeHistoryPage(items: []);
        }),
        eeCsvExportApiProvider.overrideWithValue(_csv),
        eeCsvSinkProvider.overrideWithValue(_sink),
      ],
      child: MaterialApp(
        theme: buildAwTheme(brightness),
        home: const EeAuditLogScreen(),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

late _FakeCsv _csv;
late _Sink _sink;

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    AwI18n.instance.setActiveCached(const Locale('en'));
    _csv = _FakeCsv();
    _sink = _Sink();
  });

  group('the three empty states are three different sentences', () {
    testWidgets('AN UNREACHABLE SERVER IS AN ERROR, NOT AN EMPTY LIST', (
      tester,
    ) async {
      // The one that matters most: a blank audit screen reads as "nothing
      // happened", and that is exactly what must never be said on this screen
      // when the truth is "we could not ask".
      await _pump(tester, error: Exception('boom'));
      expect(find.byKey(const Key('audit-error')), findsOneWidget);
      expect(find.byKey(const Key('audit-empty')), findsNothing);
      expect(find.textContaining('could not be loaded'), findsOneWidget);
    });

    testWidgets('a new team is told nothing has been recorded YET', (
      tester,
    ) async {
      await _pump(tester, page: const EeHistoryPage(items: []));
      expect(find.byKey(const Key('audit-empty')), findsOneWidget);
      expect(find.textContaining('Nothing has been recorded'), findsOneWidget);
    });

    testWidgets('narrow filters are told the FILTERS matched nothing', (
      tester,
    ) async {
      await _pump(tester, page: const EeHistoryPage(items: []));
      // Pick a verb — now the empty list is a statement about the filters.
      await tester.tap(find.byKey(const Key('audit-filter-verb')));
      await tester.pumpAndSettle();
      // The dropdown shows the verb's SENTENCE, not its key.
      await tester.tap(find.text('deleted this').last);
      await tester.pumpAndSettle();

      expect(find.textContaining('No events match'), findsOneWidget);
      expect(find.textContaining('Nothing has been recorded'), findsNothing);
    });
  });

  group('the list', () {
    testWidgets('events are card rows in the list rhythm, with no dividers '
        '(OPH-353)', (tester) async {
      await _pump(
        tester,
        page: EeHistoryPage(
          items: [
            _event(),
            _event(id: 'E2'),
          ],
        ),
      );
      // A divider between two rows would make the gap 7 px, so the rhythm
      // itself proves they are gone (the filter bar keeps its own).
      expectCardRhythm(tester, [
        cardAround(const Key('audit-row-E1')),
        cardAround(const Key('audit-row-E2')),
      ]);
    });

    testWidgets('an event reads as a sentence: who, then what', (tester) async {
      await _pump(tester, page: EeHistoryPage(items: [_event()]));
      expect(find.byKey(const Key('audit-row-E1')), findsOneWidget);
      // `findRichText` because the row is a Text.rich — the actor is bold and
      // the verb is not, so the sentence is spans rather than a string.
      expect(
        find.text('Ada Yönetici added a member', findRichText: true),
        findsOneWidget,
      );
      // The verb dictionary is closed server-side precisely so every verb has
      // a sentence here; a raw key on screen means one slipped through.
      expect(find.textContaining('ee.verb.', findRichText: true), findsNothing);
    });

    testWidgets('a system actor is not blamed on the last human', (
      tester,
    ) async {
      await _pump(
        tester,
        page: EeHistoryPage(items: [_event(actor: 'system', actorName: null)]),
      );
      // Not "System": the product names itself, because a sweep is the
      // PRODUCT acting and "System" is a word every app uses for something
      // different.
      expect(
        find.text('AllisWell added a member', findRichText: true),
        findsOneWidget,
      );
    });

    testWidgets('MORE ON THE SERVER IS SAID, not hidden behind a scroll', (
      tester,
    ) async {
      // An infinite scroll would let somebody believe they had reached the end
      // of the record when they had reached the end of a page.
      await _pump(
        tester,
        page: EeHistoryPage(items: [_event()], nextCursor: 'CURSOR'),
      );
      expect(find.byKey(const Key('audit-more')), findsOneWidget);
    });

    testWidgets('a complete page says nothing about more', (tester) async {
      await _pump(tester, page: EeHistoryPage(items: [_event()]));
      expect(find.byKey(const Key('audit-more')), findsNothing);
    });
  });

  group('the filters', () {
    testWidgets('clear appears only once something is filtered', (
      tester,
    ) async {
      await _pump(tester, page: EeHistoryPage(items: [_event()]));
      expect(find.byKey(const Key('audit-clear')), findsNothing);

      await tester.tap(find.byKey(const Key('audit-filter-verb')));
      await tester.pumpAndSettle();
      // The dropdown shows the verb's SENTENCE, not its key.
      await tester.tap(find.text('deleted this').last);
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('audit-clear')), findsOneWidget);
    });

    testWidgets('clearing puts the screen back to no filters at all', (
      tester,
    ) async {
      // Clearing means ABSENCE, not an empty value: the family key returns to
      // the all-null record, which is a different request from `verb=''`.
      await _pump(tester, page: EeHistoryPage(items: [_event()]));
      await tester.tap(find.byKey(const Key('audit-filter-verb')));
      await tester.pumpAndSettle();
      // The dropdown shows the verb's SENTENCE, not its key.
      await tester.tap(find.text('deleted this').last);
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('audit-clear')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('audit-clear')), findsNothing);
      expect(find.byKey(const Key('audit-row-E1')), findsOneWidget);
    });
  });

  group('UI-AUDIT OPH-360', () {
    testWidgets('UI-AUDIT #89: the screen is called what Settings calls it', (
      tester,
    ) async {
      AwI18n.instance.setActiveCached(const Locale('tr'));
      await _pump(tester);
      expect(find.text('Denetim günlüğü'), findsOneWidget);
      expect(find.text('Takım geçmişi'), findsNothing);
      expect('settings.group.teamAudit'.tr(), 'ee.audit.title'.tr());
    });

    testWidgets(
      'UI-AUDIT #44: the type filter offers every kind the server writes, by name',
      (tester) async {
        await _pump(tester, page: EeHistoryPage(items: [_event()]));
        await tester.tap(find.byKey(const Key('audit-filter-entity')));
        await tester.pumpAndSettle();
        for (final name in ['Absence', 'Alert source', 'Approval', 'Asset']) {
          expect(find.text(name), findsWidgets);
        }
        expect(find.textContaining('ee_'), findsNothing);
      },
    );

    test('UI-AUDIT #44: every offered kind has a name in both languages', () {
      for (final locale in const [Locale('en'), Locale('tr')]) {
        AwI18n.instance.setActiveCached(locale);
        for (final type in kEeAuditEntityTypes) {
          expect(
            AwI18n.instance.maybeTranslate('ee.audit.entity.$type'),
            isNotNull,
            reason: '$type in ${locale.languageCode}',
          );
        }
      }
    });

    testWidgets('UI-AUDIT #44: a row names the record and opens it', (
      tester,
    ) async {
      final router = GoRouter(
        routes: [
          GoRoute(
            path: '/',
            builder: (context, state) => const EeAuditLogScreen(),
          ),
          GoRoute(
            path: '/tickets/:id',
            builder: (context, state) =>
                Text('ticket ${state.pathParameters['id']}'),
          ),
        ],
      );
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            eeTeamAuditProvider.overrideWith(
              (ref, filters) async => EeHistoryPage(
                items: [
                  _event(
                    verb: 'status_changed',
                    entityType: 'ee_ticket',
                    diff: {
                      'number': 223,
                      'subject': 'Yazıcı arızası',
                      'status': ['new', 'open'],
                    },
                  ),
                ],
              ),
            ),
          ],
          child: MaterialApp.router(
            theme: buildAwTheme(Brightness.light),
            routerConfig: router,
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        find.textContaining('Request · #223 Yazıcı arızası'),
        findsOneWidget,
      );
      expect(find.textContaining('ee_ticket'), findsNothing);
      await tester.tap(find.byKey(const Key('audit-row-E1')));
      await tester.pumpAndSettle();
      expect(find.text('ticket X1'), findsOneWidget);
    });

    testWidgets(
      'UI-AUDIT #44: a status change with no subject in its diff is named by '
      'the server, and dated in the reader\'s format — never ISO',
      (tester) async {
        await _pump(
          tester,
          page: EeHistoryPage(
            items: [
              _event(
                verb: 'status_changed',
                entityType: 'ee_ticket',
                diff: {
                  'status': ['open', 'resolved'],
                },
                entityLabel: '#201 Yazıcı arızası',
              ),
            ],
          ),
        );
        final stamp = awFormatDateTime(
          DateTime(2026, 8, 31, 9, 5),
          format: kAwSystemDateFormat,
        );
        expect(
          find.textContaining('Request · #201 Yazıcı arızası · $stamp'),
          findsOneWidget,
        );
        expect(find.textContaining('2026-08-31'), findsNothing);
      },
    );

    test('UI-AUDIT #44: a renamed record reads by its new name', () {
      final label = eeAuditRecordLabel(
        _event(
          verb: 'updated',
          entityType: 'ee_unit',
          diff: {
            'name': ['Bakım', 'Bakım ve Onarım'],
          },
        ),
      );
      expect(label, 'Bakım ve Onarım');
      expect(
        eeAuditRecordPath(_event(verb: 'deleted', entityType: 'ee_ticket')),
        isNull,
      );
    });

    testWidgets(
      'UI-AUDIT #56: the audit log downloads as CSV with the filters on screen',
      (tester) async {
        await _pump(tester, page: EeHistoryPage(items: [_event()]));
        await tester.tap(find.byKey(const Key('audit-filter-verb')));
        await tester.pumpAndSettle();
        await tester.tap(find.text('deleted this').last);
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('audit-csv')));
        await tester.pumpAndSettle();
        expect(_csv.asked, ['audit verb=deleted type=null']);
        // The bytes go out as the server wrote them — BOM included.
        expect(_sink.saved['acme-audit.csv']!.sublist(0, 3), [
          0xEF,
          0xBB,
          0xBF,
        ]);
        expect(find.textContaining('Saved: acme-audit.csv'), findsOneWidget);
      },
    );

    Future<void> pumpQueue(
      WidgetTester tester, {
      required bool mayExport,
    }) async {
      tester.view.physicalSize = const Size(1170, 2532);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            workspacesProvider.overrideWith((ref) async => const []),
            eeMyUnitsScopeProvider.overrideWith((ref) async => null),
            ticketQueueProvider.overrideWith((ref) => Stream.value(const [])),
            ticketAssigneesProvider.overrideWith(
              (ref) => Stream.value(const {}),
            ),
            currentUserIdProvider.overrideWithValue('U1'),
            canProvider.overrideWith(
              (ref, permission) => mayExport && permission == 'tickets.export',
            ),
            eeCsvExportApiProvider.overrideWithValue(_csv),
            eeCsvSinkProvider.overrideWithValue(_sink),
          ],
          child: MaterialApp(
            theme: buildAwTheme(Brightness.light),
            home: const EeTicketQueueScreen(),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('UI-AUDIT #56: the queue menu downloads the requests as CSV', (
      tester,
    ) async {
      await pumpQueue(tester, mayExport: true);
      await tester.tap(find.byKey(const Key('ticket-more')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('ticket-csv')));
      await tester.pumpAndSettle();
      expect(_csv.asked, ['tickets']);
      expect(_sink.saved.keys, ['acme-requests.csv']);
      // A file cut at the ceiling says so.
      expect(find.textContaining('row limit'), findsOneWidget);
    });

    testWidgets('UI-AUDIT #56: without tickets.export there is no entry', (
      tester,
    ) async {
      await pumpQueue(tester, mayExport: false);
      await tester.tap(find.byKey(const Key('ticket-more')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('ticket-csv')), findsNothing);
    });

    test('the server-suggested file name is taken only when it is plain', () {
      expect(
        filenameFromDisposition(
          'attachment; filename="acme-requests-2026-10-07.csv"',
        ),
        'acme-requests-2026-10-07.csv',
      );
      expect(
        filenameFromDisposition('attachment; filename="../x.csv"'),
        isNull,
      );
      expect(filenameFromDisposition(null), isNull);
    });
  });
}
