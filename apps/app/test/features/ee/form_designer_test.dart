import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:alliswell/src/core/api_exception.dart';
import 'package:alliswell/src/features/ee/data/new_ticket_api.dart';
import 'package:alliswell/src/features/ee/data/services_api.dart';
import 'package:alliswell/src/features/ee/data/services_models.dart';
import 'package:alliswell/src/features/ee/data/team_admin_api.dart';
import 'package:alliswell/src/features/ee/data/team_admin_models.dart';
import 'package:alliswell/src/features/ee/data/units_api.dart';
import 'package:alliswell/src/features/ee/data/units_models.dart';
import 'package:alliswell/src/features/ee/form_design.dart';
import 'package:alliswell/src/features/ee/providers.dart';
import 'package:alliswell/src/features/ee/services_providers.dart';
import 'package:alliswell/src/features/ee/team_admin_providers.dart';
import 'package:alliswell/src/features/ee/ui/form_designer_screen.dart';
import 'package:alliswell/src/features/ee/ui/team_services_screen.dart';
import 'package:alliswell/src/features/ee/units_providers.dart';
import 'package:alliswell/src/i18n/i18n.dart';
import 'package:alliswell/src/theme/theme.dart';

/// EE-229 — the form designer, and EE-246, the loss it closes.
///
/// The server's half — the version minted on publish, the portal drawing the
/// new version, a forward condition refused whole — is
/// `form-versions.integration.test.js`. These pin what only the screen can
/// get wrong: a publish that carries every property of every question (the
/// old setup page dropped two of seven), the two ways to reorder, the rows
/// that say "this condition broke" the moment a move breaks it, and a
/// preview that is the requester's form rather than a picture of it.
const _kind = EeServiceField(
  key: 'kind',
  label: 'Tür',
  type: 'select',
  options: ['Arıza', 'Talep'],
);
const _machine = EeServiceField(
  key: 'machine',
  label: 'Makine',
  type: 'text',
  help: 'Plakadaki kod',
  showIf: EeFormCondition(key: 'kind', equals: 'Arıza'),
);
const _note = EeServiceField(key: 'note', label: 'Not', type: 'text');

const _service = EeService(
  id: 'S1',
  name: 'Pres arızası',
  unitIds: ['U1'],
  formFields: [_kind, _machine, _note],
  formVersion: 2,
);

/// The server, as far as a publish is concerned: every schema that differs
/// is the next version, and the list says so afterwards.
class _FakeServices extends Fake implements EeServicesApi {
  _FakeServices(EeService service) : _services = [service];

  List<EeService> _services;
  final patched = <(String, Map<String, Object?>)>[];
  Object? patchFails;

  /// The version the server mints, when it is not simply the next one — a
  /// colleague published twice while this admin was designing.
  int? mintAs;

  @override
  Future<List<EeService>?> list() async => _services;

  @override
  Future<List<EeServiceCategory>?> categories() async => const [];

  @override
  Future<void> patch(String serviceId, Map<String, Object?> body) async {
    if (patchFails != null) throw patchFails!;
    patched.add((serviceId, body));
    final schema = body['formSchema'] as Map<String, Object?>?;
    _services = [
      for (final s in _services)
        if (s.id != serviceId)
          s
        else
          EeService.fromJson({
            'id': s.id,
            'name': s.name,
            'unitIds': s.unitIds,
            'formSchema': schema,
            'formVersion': mintAs ?? s.formVersion + 1,
          }),
    ];
  }

  @override
  Future<void> setUnits(String serviceId, List<String> unitIds) async {}
}

class _FakeUnits extends Fake implements EeUnitsApi {
  @override
  Future<List<EeUnit>?> list() async => const [
    EeUnit(id: 'U1', name: 'Bakım', memberCount: 3),
  ];
}

class _FakeAdmin extends Fake implements EeTeamAdminApi {
  @override
  Future<List<EeRole>> roles() async => const [];

  @override
  Future<EeTeamRoster> members() async =>
      const EeTeamRoster(members: [], seats: EeSeats());
}

void main() {
  late _FakeServices api;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    AwI18n.instance.setActiveCached(const Locale('tr'));
    api = _FakeServices(_service);
  });

  Finder key(String value) => find.byKey(Key(value));

  List<Override> overrides() => [
    eeServicesApiProvider.overrideWithValue(api),
    eeUnitsApiProvider.overrideWithValue(_FakeUnits()),
    eeTeamAdminApiProvider.overrideWithValue(_FakeAdmin()),
    eeFeatureProvider.overrideWith((ref, feature) => true),
    canProvider.overrideWith((ref, id) => true),
  ];

  /// Opens [screen] as a PUSHED route over a page that holds the catalogue,
  /// the way the app reaches it — so "back" has somewhere to go and the list
  /// the screen publishes into is alive, as it is behind the real designer.
  Future<void> open(WidgetTester tester, Widget screen) async {
    // Tall: a list builds only what is on screen, and the preview sits under
    // the questions on a phone.
    tester.view.physicalSize = const Size(1170, 7200);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        overrides: overrides(),
        child: MaterialApp(
          theme: buildAwTheme(Brightness.light),
          home: Consumer(
            builder: (context, ref, _) {
              ref.watch(eeServicesProvider);
              return Scaffold(
                body: Center(
                  child: IconButton(
                    key: const Key('open'),
                    icon: const Icon(Icons.open_in_new),
                    onPressed: () => Navigator.of(
                      context,
                    ).push(MaterialPageRoute<void>(builder: (_) => screen)),
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(key('open'));
    await tester.pumpAndSettle();
  }

  Future<void> openDesigner(WidgetTester tester, [EeService? service]) =>
      open(tester, EeFormDesignerScreen(service: service ?? _service));

  Future<void> tap(WidgetTester tester, String k) async {
    await tester.ensureVisible(key(k));
    await tester.pumpAndSettle();
    await tester.tap(key(k));
    await tester.pumpAndSettle();
  }

  /// Picks the item reading [label] from the dropdown [field].
  ///
  /// By its TEXT, and the last match: the button keeps every item in an
  /// IndexedStack for sizing, and a finder by the item's key found only that
  /// hidden copy — the tap then landed on whichever menu row happened to lie
  /// over it, which picked the right one by luck of the layout.
  Future<void> pick(WidgetTester tester, String field, String label) async {
    await tap(tester, field);
    await tester.tap(find.text(label).last);
    await tester.pumpAndSettle();
  }

  List<String> order(WidgetTester tester) {
    final rows = [
      for (final k in ['kind', 'machine', 'note', 'acil_mi', 'neden_acil'])
        if (key('form-field-$k').evaluate().isNotEmpty)
          (k, tester.getTopLeft(key('form-field-$k')).dy),
    ]..sort((a, b) => a.$2.compareTo(b.$2));
    return [for (final row in rows) row.$1];
  }

  bool publishable(WidgetTester tester) =>
      tester.widget<TextButton>(key('form-publish')).onPressed != null;

  Map<String, Object?> publishedSchema() =>
      api.patched.single.$2['formSchema']! as Map<String, Object?>;

  group('the rules a designer can break by clicking', () {
    test('a condition looking forward, at nothing, or at a gone value', () {
      expect(formDesignProblems([_kind, _machine, _note]), isEmpty);
      expect(formDesignProblems([_machine, _kind]), {
        'machine': FormDesignProblem.conditionLooksForward,
      });
      expect(formDesignProblems([_machine, _note]), {
        'machine': FormDesignProblem.conditionTargetMissing,
      });
      // The picker lost the option the condition waits for.
      expect(
        formDesignProblems([
          _kind.copyWith(options: ['Talep']),
          _machine,
        ]),
        {'machine': FormDesignProblem.conditionValueGone},
      );
      // …or stopped being a picker: a checkbox can only be ticked (EE-247).
      expect(
        formDesignProblems([
          _kind.copyWith(type: 'checkbox', options: const []),
          _machine,
        ]),
        {'machine': FormDesignProblem.conditionValueGone},
      );
    });

    test('a checkbox condition means ticked, spelled `true` (EE-247)', () {
      const box = EeServiceField(key: 'b', label: 'B', type: 'checkbox');
      expect(conditionValueAccepted(box, 'true'), isTrue);
      expect(conditionValueAccepted(box, 'on'), isFalse);
      expect(conditionValueAccepted(box, 'false'), isFalse);
      expect(conditionValueAccepted(_note, 'anything'), isTrue);
      expect(conditionValueAccepted(_note, ''), isFalse);
      expect(conditionValueAccepted(_note, 'x' * 81), isFalse);
    });

    test('a change is seen in help, condition and order — the old compare '
        'saw none of the first two', () {
      expect(sameFormDesign([_kind, _machine], [_kind, _machine]), isTrue);
      expect(sameFormDesign([_machine, _kind], [_kind, _machine]), isFalse);
      expect(
        sameFormDesign(
          [_kind, _machine.copyWith(help: 'Başka')],
          [_kind, _machine],
        ),
        isFalse,
      );
      expect(
        sameFormDesign(
          [
            _kind,
            _machine.copyWith(
              showIf: const EeFormCondition(key: 'kind', equals: 'Talep'),
            ),
          ],
          [_kind, _machine],
        ),
        isFalse,
      );
    });

    test('a key comes from the label, in the server\'s alphabet', () {
      expect(fieldKeyFromLabel('Hat numarası'), 'hat_numarasi');
      expect(fieldKeyFromLabel('Şube / İl'), 'sube_il');
      expect(fieldKeyFromLabel('3. vardiya'), 'f_3_vardiya');
      expect(kFieldKeyPattern.hasMatch(fieldKeyFromLabel('Çok' * 20)), isTrue);
    });

    test('EE-246: help and the condition survive a round trip', () {
      final back = EeServiceField.fromJson(_machine.toJson());
      expect(back.help, 'Plakadaki kod');
      expect(back.showIf?.key, 'kind');
      expect(back.showIf?.equals, 'Arıza');
      // A blank help is not sent: the server stores what it is given, and an
      // empty sentence under a question is not a sentence.
      expect(_note.copyWith(help: '   ').toJson().containsKey('help'), isFalse);
    });
  });

  group('the setup page', () {
    testWidgets('summarises the form and opens the designer', (tester) async {
      await open(tester, const EeServiceRoutingScreen(service: _service));
      expect(
        tester.widget<Text>(key('service-form-summary')).data,
        '3 soru · yayında sürüm 2',
      );
      // The old inline editor is gone: a form is published, not saved with
      // the icon — one button doing both would mint a version per icon.
      expect(key('service-field-add'), findsNothing);
      await tap(tester, 'service-form-design');
      expect(find.byType(EeFormDesignerScreen), findsOneWidget);
      expect(key('form-field-machine'), findsOneWidget);

      // Published there, true here: the page it returns to reads the list,
      // not the snapshot it was opened with.
      await tap(tester, 'form-field-remove-note');
      await tap(tester, 'form-publish');
      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(
        tester.widget<Text>(key('service-form-summary')).data,
        '2 soru · yayında sürüm 3',
      );
      // And its own Save has nothing to send: the form is not its business.
      expect(
        tester.widget<FilledButton>(key('service-routing-save')).onPressed,
        isNull,
      );
    });
  });

  group('a form from before versions', () {
    // EE-214's migration left such a service at version 0 until its next
    // edit rather than invent a number. Both screens must say "live, not
    // numbered" — "not published" and "version 0" are each false about it.
    const legacy = EeService(
      id: 'S1',
      name: 'Eski servis',
      unitIds: ['U1'],
      formFields: [_kind, _note],
    );

    testWidgets('the setup page does not call it version 0', (tester) async {
      // The summary reads the LIST, not the snapshot the page opened with —
      // so the list is what holds the legacy service here.
      api = _FakeServices(legacy);
      await open(tester, const EeServiceRoutingScreen(service: legacy));
      expect(
        tester.widget<Text>(key('service-form-summary')).data,
        '2 soru · yayında, sürüm numarası yok',
      );
    });

    testWidgets('the designer does not call it unpublished, and its next '
        'publish is version 1', (tester) async {
      api = _FakeServices(legacy);
      await openDesigner(tester, legacy);
      expect(
        tester.widget<Text>(key('form-status')).data,
        startsWith('Yayında, numarasız'),
      );
      await tap(tester, 'form-field-remove-note');
      await tap(tester, 'form-publish');
      expect(find.text('Sürüm 1 yayında.'), findsOneWidget);
    });

    testWidgets('a service that never had a form is "not published yet"', (
      tester,
    ) async {
      await openDesigner(tester, const EeService(id: 'S1', name: 'Yeni'));
      expect(
        tester.widget<Text>(key('form-status')).data,
        'Henüz yayınlanmadı · her şey yayında',
      );
    });
  });

  group('the designer', () {
    testWidgets('EE-246: one question moved, every other one published '
        'whole — help and condition included', (tester) async {
      await openDesigner(tester);
      expect(publishable(tester), isFalse, reason: 'nothing changed yet');
      await tap(tester, 'form-field-up-note');
      expect(order(tester), ['kind', 'note', 'machine']);
      expect(publishable(tester), isTrue);

      await tap(tester, 'form-publish');
      expect(api.patched.single.$1, 'S1');
      expect(publishedSchema(), {
        'fields': [
          {
            'key': 'kind',
            'label': 'Tür',
            'type': 'select',
            'options': ['Arıza', 'Talep'],
          },
          {'key': 'note', 'label': 'Not', 'type': 'text'},
          {
            'key': 'machine',
            'label': 'Makine',
            'type': 'text',
            'help': 'Plakadaki kod',
            'showIf': {'key': 'kind', 'equals': 'Arıza'},
          },
        ],
      });
      // ONE key: a publish is the form and nothing else.
      expect(api.patched.single.$2.keys, ['formSchema']);
    });

    testWidgets('the buttons and the drag handle make the same move', (
      tester,
    ) async {
      await openDesigner(tester);
      // The first cannot go up and the last cannot go down.
      expect(
        tester.widget<IconButton>(key('form-field-up-kind')).onPressed,
        isNull,
      );
      expect(
        tester.widget<IconButton>(key('form-field-down-note')).onPressed,
        isNull,
      );

      await tap(tester, 'form-field-up-note');
      expect(order(tester), ['kind', 'note', 'machine']);
      await tap(tester, 'form-field-down-note');
      expect(order(tester), ['kind', 'machine', 'note']);

      // The same move by hand: `note` dragged to the top.
      final gesture = await tester.startGesture(
        tester.getCenter(key('form-field-drag-note')),
      );
      await tester.pump(const Duration(milliseconds: 100));
      for (var i = 0; i < 20; i++) {
        await gesture.moveBy(const Offset(0, -20));
        await tester.pump(const Duration(milliseconds: 16));
      }
      await gesture.up();
      await tester.pumpAndSettle();
      expect(order(tester), ['note', 'kind', 'machine']);
    });

    testWidgets('a move above the question it depends on is said on the row '
        'and stops the publish; moving back clears it', (tester) async {
      await openDesigner(tester);
      await tap(tester, 'form-field-up-machine');
      expect(order(tester), ['machine', 'kind', 'note']);
      expect(
        tester.widget<Text>(key('form-field-problem-machine')).data,
        'ee.team.services.designer.problemForward'.tr(),
      );
      expect(key('form-blocked'), findsOneWidget);
      expect(publishable(tester), isFalse);

      await tap(tester, 'form-field-down-machine');
      expect(key('form-field-problem-machine'), findsNothing);
      expect(key('form-blocked'), findsNothing);
      // Back where it was: nothing to publish either.
      expect(publishable(tester), isFalse);
    });

    testWidgets('removing a question another depends on flags the dependent', (
      tester,
    ) async {
      await openDesigner(tester);
      await tap(tester, 'form-field-remove-kind');
      expect(key('form-field-kind'), findsNothing);
      expect(
        tester.widget<Text>(key('form-field-problem-machine')).data,
        'ee.team.services.designer.problemMissing'.tr(),
      );
      expect(publishable(tester), isFalse);
    });

    testWidgets('a question on a ticked box: the preview asks it only once '
        'the box is ticked, and it is published as `true`', (tester) async {
      await openDesigner(tester);
      await tap(tester, 'form-field-add');
      await tester.enterText(key('field-label'), 'Acil mi');
      await pick(
        tester,
        'field-type',
        'ee.team.services.fieldType.checkbox'.tr(),
      );
      await tap(tester, 'field-save');
      expect(key('form-field-acil_mi'), findsOneWidget);

      await tap(tester, 'form-field-add');
      await tester.enterText(key('field-label'), 'Neden acil');
      await tester.enterText(key('field-help'), 'Bir cümle yeter');
      await tap(tester, 'field-required');
      await tap(tester, 'field-conditional');
      await pick(tester, 'field-condition-key', 'Acil mi');
      // A box has one answer a condition can wait for, so no value is asked.
      expect(key('field-condition-ticked'), findsOneWidget);
      await tap(tester, 'field-save');

      // The preview is the requester's form: hidden until ticked.
      expect(key('form-preview-neden_acil'), findsNothing);
      await tap(tester, 'form-preview-acil_mi');
      expect(key('form-preview-neden_acil'), findsOneWidget);
      expect(find.text('Bir cümle yeter'), findsOneWidget);

      await tap(tester, 'form-publish');
      final fields = publishedSchema()['fields']! as List<Object?>;
      expect(fields.last, {
        'key': 'neden_acil',
        'label': 'Neden acil',
        'type': 'text',
        'required': true,
        'help': 'Bir cümle yeter',
        'showIf': {'key': 'acil_mi', 'equals': 'true'},
      });
    });

    testWidgets('the first question cannot have a condition — there is '
        'nothing above it to look at', (tester) async {
      await openDesigner(tester, const EeService(id: 'S1', name: 'Boş'));
      expect(key('form-empty'), findsOneWidget);
      await tap(tester, 'form-field-add');
      expect(
        tester.widget<SwitchListTile>(key('field-conditional')).onChanged,
        isNull,
      );
    });

    testWidgets('the editor says what is wrong instead of doing nothing', (
      tester,
    ) async {
      await openDesigner(tester);
      await tap(tester, 'form-field-add');
      await tap(tester, 'field-save');
      expect(
        find.text('ee.team.services.designer.errorLabel'.tr()),
        findsOneWidget,
      );

      await tester.enterText(key('field-label'), 'Vardiya');
      await pick(
        tester,
        'field-type',
        'ee.team.services.fieldType.select'.tr(),
      );
      await tap(tester, 'field-save');
      expect(
        find.text('ee.team.services.designer.errorOptions'.tr()),
        findsOneWidget,
      );

      await tester.enterText(key('field-options'), 'Gece\nGece');
      await tap(tester, 'field-save');
      expect(
        find.text('ee.team.services.designer.errorOptionTwice'.tr()),
        findsOneWidget,
      );

      // A key another question already holds: two answers, one slot.
      await tester.enterText(key('field-options'), 'Gündüz\nGece');
      await tester.enterText(key('field-key'), 'kind');
      await tap(tester, 'field-save');
      expect(find.text('ee.team.services.fieldDuplicate'.tr()), findsOneWidget);
      expect(key('form-field-vardiya'), findsNothing);
    });

    testWidgets('an existing question shows its key and does not offer it', (
      tester,
    ) async {
      await openDesigner(tester);
      await tap(tester, 'form-field-machine');
      expect(key('field-key'), findsNothing);
      expect(key('field-key-locked'), findsOneWidget);
      // Its condition comes back as it was, not blank.
      expect(
        tester
            .widget<DropdownButtonFormField<String>>(key('field-condition-key'))
            .initialValue,
        'kind',
      );
    });

    testWidgets('publishing reports the version the server minted', (
      tester,
    ) async {
      // Somebody else published 3 and 4 meanwhile: the screen says 5, the
      // number read back, not the 3 it would have guessed.
      api.mintAs = 5;
      await openDesigner(tester);
      expect(
        tester.widget<Text>(key('form-status')).data,
        'Yayında: sürüm 2 · her şey yayında',
      );
      await tap(tester, 'form-field-remove-note');
      expect(
        tester.widget<Text>(key('form-status')).data,
        'Yayında: sürüm 2 · yayınlanmamış değişiklikler var',
      );
      await tap(tester, 'form-publish');
      expect(find.text('Sürüm 5 yayında.'), findsOneWidget);
      expect(
        tester.widget<Text>(key('form-status')).data,
        'Yayında: sürüm 5 · her şey yayında',
      );
      expect(publishable(tester), isFalse);
    });

    testWidgets('a refused publish keeps the draft and says why', (
      tester,
    ) async {
      api.patchFails = const ApiException(
        'BAD_REQUEST',
        'field "machine": showIf must name a field above it',
      );
      await openDesigner(tester);
      await tap(tester, 'form-field-remove-note');
      await tap(tester, 'form-publish');
      expect(
        tester.widget<Text>(key('form-publish-error')).data,
        'field "machine": showIf must name a field above it',
      );
      expect(key('form-field-note'), findsNothing);
      expect(publishable(tester), isTrue, reason: 'the draft is still there');
    });

    testWidgets('leaving with unpublished changes asks first', (tester) async {
      await openDesigner(tester);
      await tap(tester, 'form-field-remove-note');

      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(key('form-discard-confirm'), findsOneWidget);
      await tap(tester, 'form-discard-keep');
      expect(find.byType(EeFormDesignerScreen), findsOneWidget);

      await tester.pageBack();
      await tester.pumpAndSettle();
      await tap(tester, 'form-discard-confirm');
      expect(find.byType(EeFormDesignerScreen), findsNothing);
      expect(api.patched, isEmpty);
    });

    testWidgets('an untouched designer leaves without asking', (tester) async {
      await openDesigner(tester);
      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(key('form-discard-confirm'), findsNothing);
      expect(find.byType(EeFormDesignerScreen), findsNothing);
    });
  });
}
