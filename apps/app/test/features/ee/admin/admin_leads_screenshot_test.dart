// The sales inbox, shot in both themes (EE-160 acceptance).
//
// Run locally with:
//
//   flutter test --update-goldens --dart-define=screenshots=true \
//       test/features/ee/admin/admin_leads_screenshot_test.dart
//
// Inert without the dart-define, like every other shot file here: goldens are
// generated output, not committed, so a plain CI run must not compare against
// pictures that are not in the repository.
//
// The picture worth looking at is the SECOND one. A lead whose personal columns
// were emptied still occupies a row, and the notice is the only thing standing
// between "we discharged a legal obligation" and "this record is broken". That
// distinction is a visual one, so a person has to look at it.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:alliswell/src/features/ee/admin/admin_providers.dart';
import 'package:alliswell/src/features/ee/admin/data/admin_models.dart';
import 'package:alliswell/src/features/ee/admin/ui/admin_leads_screen.dart';
import 'package:alliswell/src/features/ee/admin/ui/admin_shell.dart';
import 'package:alliswell/src/i18n/i18n.dart';
import 'package:alliswell/src/theme/theme.dart';
import 'package:alliswell/src/widgets/glass.dart';

import '../../../design_screenshots_test.dart' show loadRealFontsForStore;

const bool _enabled = bool.fromEnvironment('screenshots');

/// The theme's own fontFamily is null (platform font, DESIGN §3.3) and the
/// test engine draws that as BOX GLYPHS.
const String _screenshotFamily = 'ScreenshotSans';

AdminLead _lead({
  required String id,
  required String status,
  String? company,
  int? seats,
  bool erased = false,
}) => AdminLead.fromJson({
  'id': id,
  'status': status,
  'locale': 'tr',
  'erased': erased,
  'fullName': erased ? null : 'Aydın Yılmaz',
  'companyName': erased ? null : company,
  'workEmail': erased ? null : 'satinalma@aydinmetal.example',
  'phone': erased ? null : '+90 212 555 00 00',
  'seatCount': seats,
  'unitCount': 12,
  'packageInterest': 'Enterprise',
  'message': erased
      ? null
      : 'Üç fabrikamız için bakım taleplerini tek yerde toplamak istiyoruz.',
  'notes': null,
  'consentVersion': '2026-09',
  'consentAt': '2026-09-08T10:00:00.000Z',
  'sourceIp': erased ? null : '198.51.100.44',
  'userAgent': erased ? null : 'Mozilla/5.0',
  'referrer': erased ? null : 'https://alliswell.space/enterprise/tr',
  'statusChangedAt': null,
  'erasedAt': erased ? '2026-09-09T08:00:00.000Z' : null,
  'createdAt': '2026-09-08T10:00:00.000Z',
});

/// A list with every state an operator has to tell apart at a glance —
/// including the erased one, which is the whole reason this file exists.
final _page = AdminLeadPage(
  items: [
    _lead(
      id: '01JLEAD0000000000000000001',
      status: 'new',
      company: 'Aydın Metal A.Ş.',
      seats: 250,
    ),
    _lead(
      id: '01JLEAD0000000000000000002',
      status: 'contacted',
      company: 'Kuzey Lojistik',
      seats: 80,
    ),
    _lead(
      id: '01JLEAD0000000000000000003',
      status: 'qualified',
      company: 'Ege Üniversitesi',
      seats: 1200,
    ),
    // Counts and package intact: the notice says they survive an erasure,
    // and a picture showing "Not stated" beside that sentence would argue
    // against it.
    _lead(
      id: '01JLEAD0000000000000000004',
      status: 'won',
      seats: 300,
      erased: true,
    ),
    _lead(
      id: '01JLEAD0000000000000000005',
      status: 'lost',
      company: 'Batı Tekstil',
      seats: 40,
    ),
  ],
  nextCursor: '01JLEAD0000000000000000005',
);

class _StubLeads extends AdminLeadsController {
  @override
  Future<AdminLeadPage> build() async => _page;
}

final _erased = _lead(
  id: '01JLEAD0000000000000000004',
  status: 'won',
  seats: 300,
  erased: true,
);

void main() {
  if (!_enabled) {
    test(
      'screenshots disabled',
      () {},
      skip: 'pass --dart-define=screenshots=true',
    );
    return;
  }

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    AwI18n.instance.setActiveCached(const Locale('en'));
  });

  for (final brightness in Brightness.values) {
    testWidgets('sales inbox — ${brightness.name}', (tester) async {
      await loadRealFontsForStore();
      tester.view.physicalSize = const Size(1100, 800);
      tester.view.devicePixelRatio = 2.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      debugDisableShadows = false;
      try {
        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              adminLeadsProvider.overrideWith(_StubLeads.new),
              adminSessionProvider.overrideWith(AdminSessionController.new),
            ],
            child: MaterialApp(
              debugShowCheckedModeBanner: false,
              theme: buildAwTheme(
                brightness,
                fontFamilyOverride: _screenshotFamily,
              ),
              home: AwPageBackground(
                child: AdminShell(
                  location: '/admin/leads',
                  child: const AdminLeadsScreen(),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        await expectLater(
          find.byType(AdminShell),
          matchesGoldenFile(
            '../../../goldens/ee-admin-leads-${brightness.name}.png',
          ),
        );
      } finally {
        debugDisableShadows = true;
      }
    });

    testWidgets('an erased enquiry — ${brightness.name}', (tester) async {
      await loadRealFontsForStore();
      tester.view.physicalSize = const Size(1100, 1000);
      tester.view.devicePixelRatio = 2.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      debugDisableShadows = false;
      try {
        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              adminLeadProvider(
                _erased.id,
              ).overrideWith((ref) async => _erased),
              adminSessionProvider.overrideWith(AdminSessionController.new),
            ],
            child: MaterialApp(
              debugShowCheckedModeBanner: false,
              theme: buildAwTheme(
                brightness,
                fontFamilyOverride: _screenshotFamily,
              ),
              home: AwPageBackground(
                child: AdminShell(
                  location: '/admin/leads',
                  child: AdminLeadDetailScreen(leadId: _erased.id),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        await expectLater(
          find.byType(AdminShell),
          matchesGoldenFile(
            '../../../goldens/ee-admin-lead-erased-${brightness.name}.png',
          ),
        );
      } finally {
        debugDisableShadows = true;
      }
    });
  }
}
