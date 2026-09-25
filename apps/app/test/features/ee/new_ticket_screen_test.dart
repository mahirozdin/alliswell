import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:alliswell/src/core/api_exception.dart';
import 'package:alliswell/src/core/reachability.dart';
import 'package:alliswell/src/features/ee/data/kb_api.dart';
import 'package:alliswell/src/features/ee/data/kb_models.dart';
import 'package:alliswell/src/features/ee/data/new_ticket_api.dart';
import 'package:alliswell/src/features/ee/kb_providers.dart';
import 'package:alliswell/src/features/ee/my_tickets_providers.dart';
import 'package:alliswell/src/features/ee/new_ticket_providers.dart';
import 'package:alliswell/src/features/ee/providers.dart';
import 'package:alliswell/src/features/ee/ticket_drafts_providers.dart';
import 'package:alliswell/src/features/ee/ui/my_tickets_screen.dart';
import 'package:alliswell/src/features/ee/ui/new_ticket_screen.dart';
import 'package:alliswell/src/i18n/i18n.dart';
import 'package:alliswell/src/sync/providers.dart';
import 'package:alliswell/src/theme/theme.dart';

/// EE-225 — filing a request from the app.
///
/// The server half (the catalogue offers exactly what the door accepts; a
/// draft only in its author's own space) is tested where it lives. These pin
/// the half the person meets: that what they pick and answer is what is
/// sent, that the form in force asks its own questions and no hidden one,
/// and that with no signal the same form keeps their words as a draft and
/// says what a draft can carry.
const _catalog = EeCatalog(
  categories: [EeCatalogCategory(id: 'C1', name: 'Arızalar')],
  services: [
    EeCatalogService(
      id: 'S-PRES',
      name: 'Pres arızası',
      categoryId: 'C1',
      formVersion: 2,
      units: [EeCatalogUnit(id: 'U1', name: 'Bakım')],
      fields: [
        EeFormField(
          key: 'line',
          label: 'Hat',
          type: 'select',
          required: true,
          options: ['1', '2'],
        ),
        EeFormField(
          key: 'since',
          label: 'Ne zamandan beri',
          type: 'text',
          required: true,
          showIf: EeFormCondition(key: 'line', equals: '2'),
        ),
        EeFormField(key: 'note', label: 'Not', type: 'text', help: 'Kısa'),
      ],
    ),
    EeCatalogService(
      id: 'S-ELEC',
      name: 'Elektrik arızası',
      categoryId: 'C1',
      units: [
        EeCatalogUnit(id: 'U1', name: 'Bakım'),
        EeCatalogUnit(id: 'U2', name: 'Tesis'),
      ],
    ),
    EeCatalogService(
      id: 'S-PRINT',
      name: 'Yazıcı arızası',
      units: [EeCatalogUnit(id: 'U3', name: 'Bilgi işlem')],
      needsApproval: true,
    ),
  ],
);

class _FakeApi extends Fake implements EeNewTicketApi {
  final created = <Map<String, Object?>>[];
  Object? failWith;

  @override
  Future<({String id, int? number})> create({
    required String serviceId,
    required String subject,
    String? body,
    String? unitId,
    Map<String, Object?> fields = const {},
    String? requesterName,
    String? requesterEmail,
    List<String> openedArticleIds = const [],
    String? assetId,
  }) async {
    if (failWith != null) throw failWith!;
    created.add({
      if (openedArticleIds.isNotEmpty) 'openedArticleIds': openedArticleIds,
      'assetId': ?assetId,
      'serviceId': serviceId,
      'subject': subject,
      'body': body,
      'unitId': unitId,
      'fields': fields,
      'requesterName': requesterName,
      'requesterEmail': requesterEmail,
    });
    return (id: 'T-NEW', number: 42);
  }
}

/// The desk's answers (EE-226), as the form meets them: what a subject
/// finds, what opening one reads, and what leaving reports.
class _FakeKb extends Fake implements EeKbApi {
  List<EeKbSuggestion> answers = const [];
  Object? readFails;
  final asked = <String>[];
  final deflected = <List<String>>[];

  @override
  Future<List<EeKbSuggestion>> suggestions(String query) async {
    asked.add(query);
    return answers;
  }

  @override
  Future<EeKbArticle> get(String articleId) async {
    if (readFails != null) throw readFails!;
    final answer = answers.firstWhere((a) => a.id == articleId);
    return EeKbArticle(
      id: answer.id,
      title: answer.title,
      symptom: answer.symptom,
      status: 'published',
      solution: 'Kapağı açın, kağıdı düz çekin.',
    );
  }

  @override
  Future<void> reportDeflected(List<String> articleIds) async =>
      deflected.add(articleIds);
}

class _FakeDrafts extends Fake implements TicketDraftStore {
  final written = <Map<String, Object?>>[];

  @override
  Future<String> write({
    required String workspaceId,
    required String subject,
    String? body,
    String? serviceId,
    String? assetId,
  }) async {
    written.add({
      'workspaceId': workspaceId,
      'subject': subject,
      'body': body,
      'serviceId': serviceId,
      'assetId': ?assetId,
    });
    return 'D-1';
  }
}

void main() {
  late _FakeApi api;
  late _FakeDrafts drafts;
  late _FakeKb kb;
  late ProviderContainer container;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    AwI18n.instance.setActiveCached(const Locale('tr'));
    api = _FakeApi();
    drafts = _FakeDrafts();
    kb = _FakeKb();
  });

  Future<void> pumpForm(
    WidgetTester tester, {
    bool mayActForOthers = false,
    String? home = 'W-OWN',
    bool offline = false,
    EeTicketAsset? asset,
  }) async {
    container = ProviderContainer(
      overrides: <Override>[
        eeNewTicketApiProvider.overrideWithValue(api),
        eeKbApiProvider.overrideWithValue(kb),
        eeFeatureProvider.overrideWith((ref, feature) => true),
        eeCatalogProvider.overrideWith((ref) async => _catalog),
        ticketDraftStoreProvider.overrideWithValue(drafts),
        draftWorkspaceIdProvider.overrideWithValue(home),
        syncEngineProvider.overrideWithValue(null),
        canProvider.overrideWith(
          (ref, permission) =>
              permission == 'tickets.create' ||
              (mayActForOthers && permission == 'tickets.create_on_behalf'),
        ),
      ],
    );
    addTearDown(container.dispose);
    if (offline) {
      container.read(serverReachabilityProvider.notifier).unreachable();
    }
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: buildAwTheme(Brightness.light),
          home: Builder(
            builder: (context) => Scaffold(
              body: Center(
                child: TextButton(
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => EeNewTicketScreen(asset: asset),
                    ),
                  ),
                  child: const Text('open'),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    tester.view.physicalSize = const Size(1170, 2532);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
  }

  Finder key(String k) => find.byKey(Key(k));

  Future<void> pick(WidgetTester tester, String serviceId) async {
    await tester.tap(key('new-ticket-service'));
    await tester.pumpAndSettle();
    await tester.tap(key('catalog-service-$serviceId'));
    await tester.pumpAndSettle();
  }

  Future<void> send(WidgetTester tester) async {
    await tester.ensureVisible(key('new-ticket-submit'));
    await tester.tap(key('new-ticket-submit'));
    await tester.pumpAndSettle();
  }

  String? errorText(WidgetTester tester) {
    final finder = key('new-ticket-error');
    return finder.evaluate().isEmpty ? null : tester.widget<Text>(finder).data;
  }

  testWidgets(
    'the catalogue is what can be picked, shelved, and searched folded',
    (tester) async {
      await pumpForm(tester);
      await tester.tap(key('new-ticket-service'));
      await tester.pumpAndSettle();
      expect(find.text('Arızalar'), findsOneWidget);
      expect(find.text('Diğer'), findsOneWidget, reason: 'the unshelved one');
      for (final id in ['S-PRES', 'S-ELEC', 'S-PRINT']) {
        expect(key('catalog-service-$id'), findsOneWidget);
      }
      // The device's fold (EE-212): the Turkish spelling (`yazıcı`, dotless ı)
      // and the ASCII one (`yazici`) both find `Yazıcı`. A plain lower-casing
      // passes `yazici` and `YAZICI` — Dart maps I to i whatever the language —
      // and fails the dotless one. Measured: the first two drafts of this test
      // used only those two, and a fold-less search went green both times.
      for (final typed in ['yazıcı', 'YAZICI', 'yazici']) {
        await tester.enterText(key('new-ticket-service-search'), typed);
        await tester.pumpAndSettle();
        expect(key('catalog-service-S-PRINT'), findsOneWidget, reason: typed);
        expect(key('catalog-service-S-PRES'), findsNothing, reason: typed);
      }
    },
  );

  testWidgets(
    'the form in force: its questions, its condition, and only what shows is sent',
    (tester) async {
      await pumpForm(tester);
      await pick(tester, 'S-PRES');
      expect(key('new-ticket-field-line'), findsOneWidget);
      expect(key('new-ticket-field-note'), findsOneWidget);
      expect(
        key('new-ticket-field-since'),
        findsNothing,
        reason: 'hidden until line=2',
      );

      // Nothing filled: the sentence says what stops the send, in its words.
      await send(tester);
      expect(errorText(tester), contains('Konu'));
      expect(errorText(tester), contains('Hat'));
      expect(api.created, isEmpty);

      await tester.enterText(key('new-ticket-subject'), 'Pres 2 durdu');
      await tester.tap(key('new-ticket-field-line'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('2').last);
      await tester.pumpAndSettle();
      // The answer revealed its question — and it is required.
      expect(key('new-ticket-field-since'), findsOneWidget);
      await send(tester);
      expect(errorText(tester), contains('Ne zamandan beri'));
      await tester.enterText(key('new-ticket-field-since'), 'Dünden beri');
      await tester.pumpAndSettle();

      // Back to line 1: the revealed question hides again, and the answer it
      // was given does NOT travel — it is not something the person now means.
      await tester.tap(key('new-ticket-field-line'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('1').last);
      await tester.pumpAndSettle();
      await tester.enterText(key('new-ticket-field-note'), 'Yağ sızıyor');
      await tester.pumpAndSettle();
      await send(tester);

      expect(api.created, hasLength(1));
      expect(api.created.single, {
        'serviceId': 'S-PRES',
        'subject': 'Pres 2 durdu',
        'body': null,
        'unitId': null,
        'fields': {'line': '1', 'note': 'Yağ sızıyor'},
        'requesterName': null,
        'requesterEmail': null,
      });
      expect(find.text('Talep açıldı — #42'), findsOneWidget);
      expect(find.text('open'), findsOneWidget, reason: 'the form closed');
    },
  );

  testWidgets('several units answer: the form asks which, and sends it', (
    tester,
  ) async {
    await pumpForm(tester);
    await pick(tester, 'S-ELEC');
    await tester.enterText(key('new-ticket-subject'), 'Sigorta attı');
    await send(tester);
    expect(errorText(tester), contains('Hangi birim baksın?'));

    await tester.tap(key('new-ticket-unit-U2'));
    await tester.pumpAndSettle();
    await send(tester);
    expect(api.created.single['unitId'], 'U2');
  });

  testWidgets('a service that asks for approval says so before the send', (
    tester,
  ) async {
    await pumpForm(tester);
    await pick(tester, 'S-PRINT');
    expect(key('new-ticket-approval'), findsOneWidget);
  });

  testWidgets(
    'on behalf of somebody: only with the verb; the name is then required',
    (tester) async {
      await pumpForm(tester);
      expect(key('new-ticket-on-behalf'), findsNothing);
    },
  );

  testWidgets('…and with it, the name and address travel', (tester) async {
    await pumpForm(tester, mayActForOthers: true);
    await pick(tester, 'S-PRINT');
    await tester.enterText(key('new-ticket-subject'), 'Kağıt sıkıştı');
    await tester.ensureVisible(key('new-ticket-on-behalf'));
    await tester.tap(key('new-ticket-on-behalf'));
    await tester.pumpAndSettle();
    await send(tester);
    expect(errorText(tester), contains('Kimin adına'));

    await tester.enterText(key('new-ticket-requester-name'), 'Kerem Usta');
    await tester.enterText(
      key('new-ticket-requester-email'),
      'kerem@ornek.com',
    );
    await tester.pumpAndSettle();
    await send(tester);
    expect(api.created.single, containsPair('requesterName', 'Kerem Usta'));
    expect(
      api.created.single,
      containsPair('requesterEmail', 'kerem@ornek.com'),
    );
  });

  testWidgets(
    'offline: the same form keeps a draft in the own space, and says what it carries',
    (tester) async {
      await pumpForm(tester, offline: true, mayActForOthers: true);
      expect(key('new-ticket-offline'), findsOneWidget);
      expect(key('new-ticket-draft-note'), findsOneWidget);
      await pick(tester, 'S-PRES');
      // What a draft cannot carry is not offered.
      expect(key('new-ticket-field-line'), findsNothing);
      expect(key('new-ticket-on-behalf'), findsNothing);
      expect(find.text('Taslak olarak kaydet'), findsOneWidget);

      await tester.enterText(key('new-ticket-subject'), 'Kompresör gece durdu');
      await tester.enterText(key('new-ticket-body'), 'Alarm çalıyor');
      await tester.pumpAndSettle();
      await send(tester);
      expect(api.created, isEmpty);
      expect(drafts.written, [
        {
          'workspaceId': 'W-OWN',
          'subject': 'Kompresör gece durdu',
          'body': 'Alarm çalıyor',
          'serviceId': 'S-PRES',
        },
      ]);
      expect(
        find.text('Taslak kaydedildi — bağlantı gelince gönderilecek'),
        findsOneWidget,
      );
    },
  );

  testWidgets(
    'offline, a service with several units: the note says the draft will wait',
    (tester) async {
      await pumpForm(tester, offline: true);
      await pick(tester, 'S-ELEC');
      expect(key('new-ticket-draft-multi-unit'), findsOneWidget);
      expect(key('new-ticket-unit-U1'), findsNothing);
    },
  );

  testWidgets(
    'offline with no own space on the device: nothing written, and why',
    (tester) async {
      await pumpForm(tester, offline: true, home: null);
      await tester.enterText(key('new-ticket-subject'), 'Durdu');
      await tester.pumpAndSettle();
      await send(tester);
      expect(drafts.written, isEmpty);
      expect(errorText(tester), contains('kişisel bir alan yok'));
    },
  );

  testWidgets(
    'a send that finds no server keeps every word and turns into the draft form',
    (tester) async {
      api.failWith = const ApiException('NETWORK_ERROR', 'no route');
      await pumpForm(tester);
      await pick(tester, 'S-PRINT');
      await tester.enterText(key('new-ticket-subject'), 'Kağıt sıkıştı');
      await tester.pumpAndSettle();
      await send(tester);

      expect(container.read(serverReachabilityProvider), isFalse);
      expect(key('new-ticket-offline'), findsOneWidget);
      expect(
        tester.widget<TextField>(key('new-ticket-subject')).controller!.text,
        'Kağıt sıkıştı',
      );
      expect(find.text('Taslak olarak kaydet'), findsOneWidget);
    },
  );

  group('the doors in', () {
    Future<void> pumpMine(
      WidgetTester tester, {
      required bool mayCreate,
    }) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: <Override>[
            eeMyTicketsProvider.overrideWith((ref) async => const []),
            // The drafts section above the list reads the device's database;
            // these tests are about the button, not the drafts.
            draftStatusesProvider.overrideWithValue(const []),
            canProvider.overrideWith(
              (ref, permission) => mayCreate && permission == 'tickets.create',
            ),
          ],
          child: MaterialApp(
            theme: buildAwTheme(Brightness.light),
            home: const EeMyTicketsScreen(),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('"my requests" offers a new one to whoever may file', (
      tester,
    ) async {
      await pumpMine(tester, mayCreate: true);
      expect(key('my-tickets-new'), findsOneWidget);
    });

    testWidgets('…and no button at all to whoever may not', (tester) async {
      await pumpMine(tester, mayCreate: false);
      expect(key('my-tickets-new'), findsNothing);
    });
  });

  group('the answer may already be written (EE-226)', () {
    const jam = EeKbSuggestion(
      id: 'KB-JAM',
      title: 'Yazıcı kağıt sıkıştırıyor',
      symptom: 'Kağıt yolda sıkışıyor',
    );

    Future<void> typeSubject(WidgetTester tester, String text) async {
      await tester.enterText(key('new-ticket-subject'), text);
      await tester.pump(const Duration(milliseconds: 450));
      await tester.pumpAndSettle();
    }

    Future<void> read(WidgetTester tester) async {
      await tester.tap(key('new-ticket-answer-KB-JAM'));
      await tester.pumpAndSettle();
    }

    Future<void> backToForm(WidgetTester tester) async {
      await tester.tap(key('kb-answer-back'));
      await tester.pumpAndSettle();
    }

    testWidgets(
      'offered after a pause in typing, and never for under three letters',
      (tester) async {
        kb.answers = const [jam];
        await pumpForm(tester);
        await typeSubject(tester, 'Ya');
        expect(key('new-ticket-answers'), findsNothing);
        expect(kb.asked, isEmpty);

        await tester.enterText(key('new-ticket-subject'), 'Yazıcı sıkıştı');
        await tester.pump(const Duration(milliseconds: 200));
        expect(kb.asked, isEmpty, reason: 'still typing: nobody is asked yet');
        await tester.pump(const Duration(milliseconds: 250));
        await tester.pumpAndSettle();
        expect(kb.asked, ['Yazıcı sıkıştı']);
        expect(key('new-ticket-answer-KB-JAM'), findsOneWidget);
        expect(find.text('Belki cevabı zaten yazılmıştır'), findsOneWidget);
      },
    );

    testWidgets('no signal: no answers, and nobody is asked', (tester) async {
      kb.answers = const [jam];
      await pumpForm(tester, offline: true);
      await typeSubject(tester, 'Yazıcı kağıt');
      expect(key('new-ticket-answers'), findsNothing);
      expect(kb.asked, isEmpty);
    });

    testWidgets(
      'read and sent anyway: it rides with the request, and nothing else is said',
      (tester) async {
        kb.answers = const [jam];
        await pumpForm(tester);
        await pick(tester, 'S-PRINT');
        await typeSubject(tester, 'Yazıcı kağıt');
        await read(tester);
        expect(find.text('Kapağı açın, kağıdı düz çekin.'), findsOneWidget);
        await backToForm(tester);
        await send(tester);
        expect(api.created.single['openedArticleIds'], ['KB-JAM']);
        expect(kb.deflected, isEmpty);
      },
    );

    testWidgets(
      'read and left without asking: that is the deflection, said once',
      (tester) async {
        kb.answers = const [jam];
        await pumpForm(tester);
        await typeSubject(tester, 'Yazıcı kağıt');
        await read(tester);
        await backToForm(tester);
        await tester.pageBack();
        await tester.pumpAndSettle();
        expect(kb.deflected, [
          ['KB-JAM'],
        ]);
        expect(api.created, isEmpty);
      },
    );

    testWidgets('"this solved it" closes the form, and that is counted', (
      tester,
    ) async {
      kb.answers = const [jam];
      await pumpForm(tester);
      await typeSubject(tester, 'Yazıcı kağıt');
      await read(tester);
      await tester.tap(key('kb-answer-solved'));
      await tester.pumpAndSettle();
      expect(key('new-ticket-subject'), findsNothing);
      expect(find.text('open'), findsOneWidget);
      expect(kb.deflected, [
        ['KB-JAM'],
      ]);
    });

    testWidgets('shown and never opened: leaving counts nothing', (
      tester,
    ) async {
      kb.answers = const [jam];
      await pumpForm(tester);
      await typeSubject(tester, 'Yazıcı kağıt');
      expect(key('new-ticket-answer-KB-JAM'), findsOneWidget);
      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(kb.deflected, isEmpty);
    });

    testWidgets('an answer that did not load was not read', (tester) async {
      kb.answers = const [jam];
      kb.readFails = const ApiException('SERVER_ERROR', 'boom');
      await pumpForm(tester);
      await typeSubject(tester, 'Yazıcı kağıt');
      await read(tester);
      expect(key('kb-answer-solved'), findsNothing);
      await backToForm(tester);
      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(kb.deflected, isEmpty);
    });

    testWidgets(
      'a draft after reading is a request on its way, not a deflection',
      (tester) async {
        kb.answers = const [jam];
        await pumpForm(tester);
        await typeSubject(tester, 'Yazıcı kağıt');
        await read(tester);
        await backToForm(tester);
        container.read(serverReachabilityProvider.notifier).unreachable();
        await tester.pumpAndSettle();
        await send(tester);
        expect(drafts.written, hasLength(1));
        expect(kb.deflected, isEmpty);
      },
    );
  });

  testWidgets('AW-E26: opened from a machine card, the request names the '
      'machine, and the server is asked to link it', (tester) async {
    await pumpForm(
      tester,
      asset: const EeTicketAsset(
        id: 'A-PRESS',
        tag: 'PRS-250',
        name: 'Hidrolik pres',
      ),
    );
    // The machine is on the form before anything is typed — the field a
    // card fills, shown even to somebody the register is not offered to.
    expect(
      find.descendant(
        of: key('new-ticket-asset'),
        matching: find.text('PRS-250 · Hidrolik pres'),
      ),
      findsOneWidget,
    );
    await pick(tester, 'S-PRINT');
    await tester.enterText(key('new-ticket-subject'), 'Pres yağ kaçırıyor');
    await send(tester);
    expect(api.created.single['assetId'], 'A-PRESS');
    expect(api.created.single['serviceId'], 'S-PRINT');
  });
}
