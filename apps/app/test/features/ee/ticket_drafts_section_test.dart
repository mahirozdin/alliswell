import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:alliswell/src/core/api_exception.dart';
import 'package:alliswell/src/features/ee/data/new_ticket_api.dart';
import 'package:alliswell/src/features/ee/my_tickets_providers.dart';
import 'package:alliswell/src/features/ee/new_ticket_providers.dart';
import 'package:alliswell/src/features/ee/providers.dart';
import 'package:alliswell/src/features/ee/ticket_drafts_providers.dart';
import 'package:alliswell/src/features/ee/ui/my_tickets_screen.dart';
import 'package:alliswell/src/features/ee/ui/ticket_drafts_section.dart';
import 'package:alliswell/src/i18n/i18n.dart';
import 'package:alliswell/src/theme/theme.dart';

/// EE-225 — the drafts section a requester reads above "my requests".
///
/// Where each draft stands is `draftStatusesProvider`'s job and is pinned in
/// `ticket_draft_statuses_test.dart` against a real database. These pin what
/// the person meets: each state in words, the one fix a row offers (naming a
/// service) going through the store as an ordinary edit, a refusal put away
/// by its person — and the section standing while the list below it cannot.
const _catalog = EeCatalog(
  services: [
    EeCatalogService(
      id: 'S-ONE',
      name: 'Pres arızası',
      units: [EeCatalogUnit(id: 'U1', name: 'Bakım')],
    ),
  ],
);

class _FakeStore extends Fake implements TicketDraftStore {
  final edits = <({String id, String? serviceId})>[];
  final forgotten = <String>[];

  @override
  Future<bool> edit(
    String draftId, {
    String? subject,
    String? body,
    String? serviceId,
  }) async {
    edits.add((id: draftId, serviceId: serviceId));
    return true;
  }

  @override
  Future<void> forgetRejected(String rejectedId) async =>
      forgotten.add(rejectedId);
}

/// The statuses as a test sets them, so a transition can be driven.
class _Statuses extends Notifier<List<EeDraftStatus>> {
  @override
  List<EeDraftStatus> build() => const [];

  void set(List<EeDraftStatus> next) => state = next;
}

final _statuses = NotifierProvider<_Statuses, List<EeDraftStatus>>(
  _Statuses.new,
);

const _onDevice = EeDraftStatus(
  id: 'D-PHONE',
  state: EeDraftState.onDevice,
  subject: 'Hat 2 durdu',
);
const _noService = EeDraftStatus(
  id: 'D-HELD',
  state: EeDraftState.held,
  subject: 'Kompresör sesi',
  hold: EeDraftHold.noService,
);
const _refused = EeDraftStatus(
  id: 'M-REFUSED',
  state: EeDraftState.rejected,
  subject: 'Bir fazla',
  errorCode: 'DRAFT_LIMIT_REACHED',
);

void main() {
  late _FakeStore store;
  late int listBuilds;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    AwI18n.instance.setActiveCached(const Locale('tr'));
    store = _FakeStore();
    listBuilds = 0;
  });

  Future<ProviderContainer> pump(
    WidgetTester tester,
    List<EeDraftStatus> drafts, {
    EeCatalog? catalog = _catalog,
    Object? listFails,
    Widget? screen,
  }) async {
    final container = ProviderContainer(
      overrides: <Override>[
        draftStatusesProvider.overrideWith((ref) => ref.watch(_statuses)),
        eeCatalogProvider.overrideWith((ref) async => catalog),
        ticketDraftStoreProvider.overrideWithValue(store),
        eeMyTicketsProvider.overrideWith((ref) async {
          listBuilds += 1;
          if (listFails != null) throw listFails;
          return const [];
        }),
        canProvider.overrideWith((ref, permission) => false),
      ],
    );
    addTearDown(container.dispose);
    container.read(_statuses.notifier).set(drafts);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: buildAwTheme(Brightness.light),
          home:
              screen ??
              Scaffold(
                body: ListView(children: const [EeTicketDraftsSection()]),
              ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return container;
  }

  Finder key(String value) => find.byKey(Key(value));
  String status(WidgetTester tester, String id) =>
      tester.widget<Text>(key('ticket-draft-$id-status')).data!;

  testWidgets('nothing to say: no section, not an empty heading', (
    tester,
  ) async {
    await pump(tester, const []);
    expect(key('ticket-drafts'), findsNothing);
    expect(find.text('Taslaklar'), findsNothing);
  });

  testWidgets('every state says where the draft is, in words', (tester) async {
    await pump(tester, const [
      _refused,
      _onDevice,
      _noService,
      EeDraftStatus(
        id: 'D-GONE',
        state: EeDraftState.sent,
        subject: 'Boyahane basınç',
      ),
    ]);
    expect(find.text('Taslaklar'), findsOneWidget);
    expect(
      status(tester, 'D-PHONE'),
      'Telefonda — bağlantı gelince gönderilecek',
    );
    expect(status(tester, 'D-HELD'), 'Masada bekliyor — servis seçilmedi');
    expect(
      status(tester, 'M-REFUSED'),
      'Reddedildi — kişisel alanında en fazla 200 gönderilmemiş taslak '
      'tutulabilir',
    );
    expect(status(tester, 'D-GONE'), 'İletildi — talebin aşağıda');
    // The one row that can be helped from here is the one with the button.
    expect(key('ticket-draft-D-HELD-service'), findsOneWidget);
    expect(key('ticket-draft-D-PHONE-service'), findsNothing);
    expect(key('ticket-draft-D-GONE-service'), findsNothing);
  });

  testWidgets('a code this screen does not know is shown as the code', (
    tester,
  ) async {
    await pump(tester, const [
      EeDraftStatus(
        id: 'M-ODD',
        state: EeDraftState.rejected,
        subject: 'Garip',
        errorCode: 'SOMETHING_NEW',
      ),
    ]);
    expect(
      status(tester, 'M-ODD'),
      'Reddedildi — masa kabul etmedi (SOMETHING_NEW)',
    );
  });

  testWidgets(
    'naming the service is an ordinary edit through the draft store',
    (tester) async {
      await pump(tester, const [_noService]);
      await tester.tap(key('ticket-draft-D-HELD-service'));
      await tester.pumpAndSettle();
      await tester.tap(key('catalog-service-S-ONE'));
      await tester.pumpAndSettle();
      expect(store.edits, [(id: 'D-HELD', serviceId: 'S-ONE')]);
    },
  );

  testWidgets('closing the picker names nothing', (tester) async {
    await pump(tester, const [_noService]);
    await tester.tap(key('ticket-draft-D-HELD-service'));
    await tester.pumpAndSettle();
    await tester.tapAt(const Offset(10, 10));
    await tester.pumpAndSettle();
    expect(store.edits, isEmpty);
  });

  testWidgets('without the catalogue: the reason stays, the button does not', (
    tester,
  ) async {
    await pump(tester, const [_noService], catalog: null);
    expect(status(tester, 'D-HELD'), 'Masada bekliyor — servis seçilmedi');
    expect(key('ticket-draft-D-HELD-service'), findsNothing);
  });

  testWidgets('a refusal is put away by its person — by the parked row id', (
    tester,
  ) async {
    await pump(tester, const [_refused]);
    await tester.tap(key('ticket-draft-M-REFUSED-forget'));
    await tester.pumpAndSettle();
    expect(store.forgotten, ['M-REFUSED']);
  });

  testWidgets('a draft that became a request asks the list below again', (
    tester,
  ) async {
    final container = await pump(tester, const [
      _onDevice,
    ], screen: const EeMyTicketsScreen());
    expect(listBuilds, 1);
    container.read(_statuses.notifier).set(const [
      EeDraftStatus(
        id: 'D-PHONE',
        state: EeDraftState.sent,
        subject: 'Hat 2 durdu',
      ),
    ]);
    await tester.pumpAndSettle();
    expect(listBuilds, 2);
  });

  testWidgets(
    'no signal: the list below says so, and the drafts above still stand',
    (tester) async {
      await pump(
        tester,
        const [_onDevice],
        listFails: const ApiException('NETWORK_ERROR', 'no route'),
        screen: const EeMyTicketsScreen(),
      );
      expect(key('ticket-draft-D-PHONE'), findsOneWidget);
      expect(
        status(tester, 'D-PHONE'),
        'Telefonda — bağlantı gelince gönderilecek',
      );
      expect(find.byType(Card), findsOneWidget);
      expect(find.textContaining('Tekrar'), findsWidgets);
    },
  );
}
