import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:alliswell/src/core/date_format.dart';
import 'package:alliswell/src/features/ee/assignments_providers.dart';
import 'package:alliswell/src/features/ee/data/services_models.dart';
import 'package:alliswell/src/features/ee/data/ticket_links_models.dart';
import 'package:alliswell/src/features/ee/data/ticket_write_api.dart';
import 'package:alliswell/src/features/ee/kb_providers.dart';
import 'package:alliswell/src/features/ee/providers.dart';
import 'package:alliswell/src/features/ee/services_providers.dart';
import 'package:alliswell/src/features/ee/ticket_links_providers.dart';
import 'package:alliswell/src/features/ee/ticket_write_providers.dart';
import 'package:alliswell/src/features/ee/tickets_providers.dart';
import 'package:alliswell/src/features/ee/ui/ticket_detail_screen.dart';
import 'package:alliswell/src/features/ee/worklog_providers.dart';
import 'package:alliswell/src/features/files/providers.dart';
import 'package:alliswell/src/i18n/i18n.dart';
import 'package:alliswell/src/sync/db/database.dart';
import 'package:alliswell/src/theme/theme.dart';

/// EE-278 — the desk reads what a request was filed with.
///
/// The service form's answers (EE-213) live on the server, and the detail
/// endpoint has returned them since EE-242 — which wrote that the app "will
/// read" them. No screen did: the demo's purchase opened with its amount
/// nowhere on it. They come with the detail's server read, which is asked
/// only for a request whose service HAS a form (EE-224's rule).
const _ticketId = '01TKBBBBBBBBBBBBBBBBBBBBBB';
const _serviceId = '01SVAAAAAAAAAAAAAAAAAAAAAA';

TicketRecord _ticket() => TicketRecord(
  id: _ticketId,
  workspaceId: 'W1',
  serviceId: _serviceId,
  subject: 'Hat 3 sunucusu için yedek disk ve RAID kartı',
  status: 'new',
  priority: 'high',
  source: 'internal',
  revision: 1,
  createdAt: DateTime.utc(2026, 9, 25),
);

const _answers = [
  EeTicketAnswer(label: 'Tahmini tutar (TL)', type: 'number', value: '48500'),
  EeTicketAnswer(label: 'Gerekçe', type: 'select', value: 'Arıza'),
  EeTicketAnswer(
    label: 'İstenen teslim tarihi',
    type: 'date',
    value: '2026-09-29',
  ),
  EeTicketAnswer(label: 'Bütçede var mı', type: 'checkbox', value: 'true'),
];

EeService _service({required bool withForm}) => EeService(
  id: _serviceId,
  name: 'Yatırım ve demirbaş alımı',
  formFields: withForm
      ? const [
          EeServiceField(
            key: 'tutar',
            label: 'Tahmini tutar (TL)',
            type: 'number',
          ),
        ]
      : const [],
);

class _Catalogue extends EeServicesController {
  _Catalogue(this.services);

  final List<EeService>? services;

  @override
  Future<List<EeService>?> build() async => services;
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    AwI18n.instance.setActiveCached(const Locale('tr'));
  });

  /// Returns how many times the screen asked the server.
  Future<int Function()> pump(
    WidgetTester tester, {
    required List<EeService>? services,
    required EeTicketActions? actions,
  }) async {
    var asked = 0;
    await tester.pumpWidget(
      ProviderScope(
        overrides: <Override>[
          ticketProvider(
            _ticketId,
          ).overrideWith((ref) => Stream.value(_ticket())),
          ticketCommentsProvider(
            _ticketId,
          ).overrideWith((ref) => Stream.value(const [])),
          eeServicesProvider.overrideWith(() => _Catalogue(services)),
          eeTicketActionsProvider(_ticketId).overrideWith((ref) async {
            asked += 1;
            return actions;
          }),
          // Everything else the screen watches, quiet (the attachments
          // test's list, for the same reasons).
          targetFilesProvider((
            targetType: 'ticket',
            targetId: _ticketId,
          )).overrideWith((ref) => Stream.value(const [])),
          eeTicketExternalFilesProvider(
            _ticketId,
          ).overrideWith((ref) async => EeExternalFiles.none),
          eeTicketRelationsProvider(
            _ticketId,
          ).overrideWith((ref) async => const EeTicketRelations()),
          eeKbSuggestionsProvider(
            'Hat 3 sunucusu için yedek disk ve RAID kartı',
          ).overrideWith((ref) async => const []),
          eeKbOfTicketProvider(_ticketId).overrideWith((ref) async => const []),
          canProvider('kb.write').overrideWith((ref) => false),
          canProvider('tickets.convert').overrideWith((ref) => false),
          canProvider('tickets.create').overrideWith((ref) => false),
          canProvider('tickets.comment').overrideWith((ref) => false),
          eeWorklogProvider(_ticketId).overrideWith((ref) async => null),
          ticketAssigneesForProvider(
            _ticketId,
          ).overrideWith((ref) => Stream.value(const [])),
          workspaceRosterOfProvider.overrideWith(
            (ref, workspaceId) => Stream.value(const []),
          ),
        ],
        child: MaterialApp(
          theme: buildAwTheme(Brightness.light),
          home: const EeTicketDetailScreen(ticketId: _ticketId),
        ),
      ),
    );
    tester.view.physicalSize = const Size(1170, 2532);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    // Fixed pumps: the history tab never settles in a test with no server.
    for (var i = 0; i < 3; i += 1) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    return () => asked;
  }

  testWidgets('AW-E14: the purchase opens with what it asked for — its form '
      'answers, in the form’s order, under the request', (tester) async {
    await pump(
      tester,
      services: [_service(withForm: true)],
      actions: const EeTicketActions(
        status: 'new',
        priority: 'high',
        answers: _answers,
      ),
    );

    expect(find.byKey(const Key('ticket-answers')), findsOneWidget);
    expect(find.text('Form cevapları'), findsOneWidget);
    for (final label in _answers.map((a) => a.label)) {
      expect(find.text(label), findsOneWidget);
    }
    expect(find.text('48500'), findsOneWidget);
    expect(find.text('Arıza'), findsOneWidget);
    // A date reads the way every other date in the app does, and a ticked
    // box reads as a word rather than as `true`.
    expect(
      find.text(
        awFormatDate(DateTime.parse('2026-09-29'), format: kAwSystemDateFormat),
      ),
      findsOneWidget,
    );
    expect(find.text('Evet'), findsOneWidget);
    expect(find.text('true'), findsNothing);

    // The form's order is kept: the amount is read first.
    final amount = tester.getTopLeft(find.text('Tahmini tutar (TL)'));
    final reason = tester.getTopLeft(find.text('Gerekçe'));
    expect(amount.dy, lessThan(reason.dy));
  });

  testWidgets('a request whose service has no form does not ask the server '
      'anything — EE-224’s rule holds', (tester) async {
    final asked = await pump(
      tester,
      services: [_service(withForm: false)],
      actions: const EeTicketActions(
        status: 'new',
        priority: 'high',
        answers: _answers,
      ),
    );

    expect(asked(), 0);
    expect(find.byKey(const Key('ticket-answers')), findsNothing);
  });

  testWidgets('a server that says nothing draws nothing', (tester) async {
    final asked = await pump(
      tester,
      services: [_service(withForm: true)],
      actions: null,
    );

    expect(asked(), greaterThan(0));
    expect(find.byKey(const Key('ticket-answers')), findsNothing);
  });

  test('the answers are read from the detail endpoint’s `fields`, in its '
      'order — the shape EE-242 fixed', () {
    final actions = EeTicketActions.fromJson({
      'status': 'new',
      'priority': 'high',
      'fields': [
        {
          'key': 'tutar',
          'label': 'Tahmini tutar (TL)',
          'type': 'number',
          'value': '48500',
          'number': 48500,
          'formVersion': 1,
          'date': null,
        },
        {
          'key': 'gerekce',
          'label': 'Gerekçe',
          'type': 'select',
          'value': 'Arıza',
          'number': null,
          'formVersion': 1,
          'date': null,
        },
      ],
    });
    expect(actions.answers.map((a) => a.label), [
      'Tahmini tutar (TL)',
      'Gerekçe',
    ]);
    expect(actions.answers.first.value, '48500');
    // A request with no form answers `fields: []`, and an older server
    // answers nothing at all: both are "no answers", not an error.
    expect(
      EeTicketActions.fromJson({'status': 'new', 'priority': 'low'}).answers,
      isEmpty,
    );
  });
}
