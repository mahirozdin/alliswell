// The service catalogue, shot in both themes (EE-082 acceptance).
//
// Run locally with:
//
//   flutter test --update-goldens --dart-define=screenshots=true \
//       test/features/ee/services_screenshot_test.dart
//
// Inert without the dart-define, like every other shot file here: goldens are
// generated output, not committed, so a plain CI run must not compare against
// pictures that are not in the repository.
//
// WHY THESE TWO SHOTS. The catalogue's dangerous state is not an error and not
// an empty list — it is a service that looks perfectly fine and silently
// receives nothing, because no unit answers it. That is an ABSENCE, which is
// exactly what a code diff cannot show and a picture can. The list shot puts
// the unrouted service next to a routed one and an archived one, so the three
// have to be tellable apart at a glance; the routing shot is where an admin
// fixes it, with the form's summary and the designer's door underneath.
//
// EE-229 adds the designer twice. Once with the preview's box TICKED, because
// the one thing the preview is for — a question that appears only after an
// answer — is invisible in a picture of the untouched form. And once broken:
// a question dragged above the one it depends on, so the row's warning and
// the blocked publish are judged in both themes, where contrast is decided.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:alliswell/src/features/ee/data/new_ticket_api.dart'
    show EeFormCondition;
import 'package:alliswell/src/features/ee/data/services_api.dart';
import 'package:alliswell/src/features/ee/data/services_models.dart';
import 'package:alliswell/src/features/ee/data/team_admin_api.dart';
import 'package:alliswell/src/features/ee/data/team_admin_models.dart';
import 'package:alliswell/src/features/ee/data/units_api.dart';
import 'package:alliswell/src/features/ee/data/units_models.dart';
import 'package:alliswell/src/features/ee/providers.dart';
import 'package:alliswell/src/features/ee/services_providers.dart';
import 'package:alliswell/src/features/ee/team_admin_providers.dart';
import 'package:alliswell/src/features/ee/ui/form_designer_screen.dart';
import 'package:alliswell/src/features/ee/ui/service_categories_screen.dart';
import 'package:alliswell/src/features/ee/ui/team_services_screen.dart';
import 'package:alliswell/src/features/ee/units_providers.dart';
import 'package:alliswell/src/i18n/i18n.dart';
import 'package:alliswell/src/theme/theme.dart';
import 'package:alliswell/src/widgets/glass.dart';

import '../../design_screenshots_test.dart'
    show loadRealFontsForStore, screenshotLocale;
import 'support/shot.dart';

const bool _enabled = bool.fromEnvironment('screenshots');

/// The theme's own fontFamily is null (platform font, DESIGN §3.3) and the
/// test engine draws that as BOX GLYPHS — every shot file here learned it the
/// same way.
const String _screenshotFamily = 'ScreenshotSans';

final _units = [
  const EeUnit(id: 'U1', name: 'Bakım', memberCount: 9),
  const EeUnit(id: 'U2', name: 'Bilgi İşlem', memberCount: 5),
  const EeUnit(id: 'U3', name: 'İnsan Kaynakları', memberCount: 3),
];

/// One of each state the row must make legible — and the second one is the
/// point of the screen: live, correct-looking, and reaching nobody.
// EE-228: the catalogue on its shelves — a top shelf with a sub-shelf, a
// second top shelf, and one service left unshelved, each with its icon.
const _shelves = [
  EeServiceCategory(id: 'C1', name: 'Arızalar', icon: 'wrench'),
  EeServiceCategory(
    id: 'C2',
    name: 'Bilgi işlem',
    parentId: 'C1',
    icon: 'laptop',
  ),
  EeServiceCategory(id: 'C3', name: 'Personel', icon: 'people', position: 1),
];

final _services = [
  const EeService(
    id: 'S1',
    name: 'Elektrik arızası',
    description: 'Hat duruşları, pano ve sensör arızaları',
    categoryId: 'C1',
    icon: 'wrench',
    approvalMode: 'manager',
    approverRoleKey: 'admin',
    unitIds: ['U1'],
    formVersion: 2,
    formFields: [
      EeServiceField(
        key: 'line_no',
        label: 'Hat numarası',
        type: 'text',
        required: true,
      ),
      EeServiceField(
        key: 'shift',
        label: 'Vardiya',
        type: 'select',
        options: ['1', '2', '3'],
      ),
    ],
  ),
  const EeService(
    id: 'S2',
    name: 'Yeni personel kartı',
    description: 'Giriş kartı ve yetkilendirme',
    categoryId: 'C3',
    icon: 'key',
  ),
  const EeService(
    id: 'S3',
    name: 'Bilgisayar arızası',
    categoryId: 'C2',
    icon: 'laptop',
    unitIds: ['U2', 'U3'],
  ),
  const EeService(
    id: 'S4',
    name: 'Eski servis talebi',
    archived: true,
    unitIds: ['U1'],
  ),
];

/// EE-229: a form worth designing — a picker, a question behind one of its
/// answers, a box, and a question behind the box.
const _designed = EeService(
  id: 'S9',
  name: 'Hat duruşu',
  unitIds: ['U1'],
  formVersion: 3,
  formFields: [
    EeServiceField(
      key: 'kind',
      label: 'Talep türü',
      type: 'select',
      required: true,
      options: ['Arıza', 'Bakım talebi'],
      help: 'Hat durduysa Arıza seçin.',
    ),
    EeServiceField(
      key: 'machine',
      label: 'Makine kodu',
      type: 'text',
      help: 'Makinenin plakasındaki kod.',
      showIf: EeFormCondition(key: 'kind', equals: 'Arıza'),
    ),
    EeServiceField(key: 'stopped', label: 'Hat durdu mu?', type: 'checkbox'),
    EeServiceField(
      key: 'since',
      label: 'Ne zamandan beri?',
      type: 'text',
      required: true,
      showIf: EeFormCondition(key: 'stopped', equals: 'true'),
    ),
  ],
);

class _ShotServicesApi implements EeServicesApi {
  const _ShotServicesApi();

  @override
  Future<List<EeService>?> list() async => _services;
  @override
  Future<void> create({
    required String name,
    String? description,
    Map<String, dynamic>? formSchema,
  }) async {}
  @override
  Future<void> update(
    String serviceId, {
    String? name,
    String? description,
    Map<String, dynamic>? formSchema,
    Set<String> clear = const {},
  }) async {}
  @override
  Future<void> setArchived(String serviceId, {required bool archived}) async {}
  @override
  Future<void> setUnits(String serviceId, List<String> unitIds) async {}
  @override
  Future<void> patch(String serviceId, Map<String, Object?> body) async {}
  @override
  Future<void> setCategory(String serviceId, String? categoryId) async {}
  @override
  Future<List<EeServiceCategory>?> categories() async => _shelves;
  @override
  Future<void> createCategory({
    required String name,
    String? parentId,
    String? icon,
  }) async {}
  @override
  Future<void> updateCategory(
    String categoryId,
    Map<String, Object?> body,
  ) async {}
  @override
  Future<void> deleteCategory(String categoryId) async {}
}

class _ShotAdminApi extends Fake implements EeTeamAdminApi {
  @override
  Future<List<EeRole>> roles() async => const [
    EeRole(
      key: 'admin',
      name: 'Yönetici',
      base: true,
      anchor: 'admin',
      editable: true,
    ),
    EeRole(
      key: 'member',
      name: 'Üye',
      base: true,
      anchor: 'member',
      editable: true,
    ),
  ];

  @override
  Future<EeTeamRoster> members() async =>
      const EeTeamRoster(members: [], seats: EeSeats());
}

class _ShotUnitsApi implements EeUnitsApi {
  const _ShotUnitsApi();

  @override
  Future<List<EeUnit>?> list() async => _units;
  @override
  Future<List<EeUnitMember>> members(String unitId) async => const [];
  @override
  Future<List<EeUnitMember>> candidates(String unitId) async => const [];
  @override
  Future<void> create(String name) async {}
  @override
  Future<void> rename(String unitId, String name) async {}
  @override
  Future<void> setArchived(String unitId, {required bool archived}) async {}
  @override
  Future<void> addMember(String unitId, String userId) async {}
  @override
  Future<void> removeMember(String unitId, String userId) async {}
  @override
  Future<void> setMemberRole(String unitId, String userId, String role) async {}
}

List<Override> _overrides() => [
  eeServicesApiProvider.overrideWithValue(const _ShotServicesApi()),
  eeTeamAdminApiProvider.overrideWithValue(_ShotAdminApi()),
  eeUnitsApiProvider.overrideWithValue(const _ShotUnitsApi()),
  canProvider.overrideWith((ref, id) => true),
  eeFeatureProvider.overrideWith((ref, feature) => true),
];

void main() {
  if (!_enabled) return;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    AwI18n.instance.setActiveCached(screenshotLocale('tr'));
  });

  Future<void> shoot(
    WidgetTester tester,
    Brightness brightness,
    String name,
    Widget screen, {
    Size size = const Size(900, 1100),
    Future<void> Function(WidgetTester tester)? afterPump,
  }) async {
    await loadRealFontsForStore();
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 2.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    debugDisableShadows = false;
    try {
      await tester.pumpWidget(
        ProviderScope(
          overrides: _overrides(),
          child: MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: buildAwTheme(
              brightness,
              fontFamilyOverride: _screenshotFamily,
            ),
            // Every route is wrapped in the page background; a bare Scaffold
            // renders the veil against nothing — a flat grey that exists
            // nowhere in the product.
            home: AwPageBackground(child: screen),
          ),
        ),
      );
      await tester.pumpAndSettle();
      if (afterPump != null) {
        await afterPump(tester);
        await tester.pumpAndSettle();
      }

      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile(eeGolden(name, brightness)),
      );
    } finally {
      debugDisableShadows = true;
    }
  }

  for (final brightness in Brightness.values) {
    testWidgets('the catalogue, with one service reaching nobody — '
        '${brightness.name}', (tester) async {
      await shoot(
        tester,
        brightness,
        'ee-services-admin',
        const EeTeamServicesScreen(),
      );
    });

    testWidgets('one service: who answers it and what it asks — '
        '${brightness.name}', (tester) async {
      await shoot(
        tester,
        brightness,
        'ee-service-routing',
        EeServiceRoutingScreen(service: _services.first),
        // EE-228 made the setup one long page — shelf, icon, units, the
        // approval rule, the form — and the picture shows all of it.
        size: const Size(900, 3000),
      );
    });

    // EE-229: the designer, with the question behind the box revealed.
    testWidgets('the form designer, its preview answering — '
        '${brightness.name}', (tester) async {
      await shoot(
        tester,
        brightness,
        'ee-form-designer',
        const EeFormDesignerScreen(service: _designed),
        size: const Size(900, 3000),
        afterPump: (tester) async {
          await tester.ensureVisible(
            find.byKey(const Key('form-preview-stopped')),
          );
          await tester.pumpAndSettle();
          await tester.tap(find.byKey(const Key('form-preview-stopped')));
        },
      );
    });

    // EE-229: and broken — a question moved above the one it waits for.
    testWidgets('the form designer, a condition broken by a move — '
        '${brightness.name}', (tester) async {
      await shoot(
        tester,
        brightness,
        'ee-form-designer-problem',
        const EeFormDesignerScreen(service: _designed),
        size: const Size(900, 1800),
        afterPump: (tester) async {
          await tester.tap(find.byKey(const Key('form-field-up-machine')));
        },
      );
    });

    // EE-228: the shelves themselves, two levels deep.
    testWidgets('the shelves — ${brightness.name}', (tester) async {
      await shoot(
        tester,
        brightness,
        'ee-service-shelves',
        const EeServiceCategoriesScreen(),
      );
    });
  }
}
