// Design-review screenshot harness (docs/DESIGN.md §5): renders the REAL
// signed-in app (real router, theme, seeded replica) in light + dark, phone +
// desktop, with real shadows and a real font, and writes PNGs to
// test/goldens/. Run locally with:
//
//   flutter test --update-goldens --dart-define=screenshots=true \
//       test/design_screenshots_test.dart
//
// Skipped without the dart-define (goldens are generated output, not
// committed, so plain CI runs must not try to compare against them).
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_quill/flutter_quill.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:alliswell/src/core/retry.dart';
import 'package:alliswell/src/features/auth/data/secret_store.dart';
import 'package:alliswell/src/features/auth/data/token_storage.dart';
import 'package:alliswell/src/features/auth/providers.dart';
import 'package:alliswell/src/i18n/i18n.dart';
import 'package:alliswell/src/router.dart';
import 'package:alliswell/src/sections.dart';
import 'package:alliswell/src/theme/theme.dart';
import 'package:alliswell/src/widgets/glass.dart';

import 'features/auth/test_support.dart';
import 'features/projects/fake_api.dart';
import 'support/sync_overrides.dart';

const bool _enabled = bool.fromEnvironment('screenshots');

/// The theme's `fontFamily` is deliberately null (platform system font,
/// DESIGN §3.3) — the test engine maps that to box glyphs, so screenshots
/// pin a real sans under an explicit family instead.
const String _family = 'ScreenshotSans';

Future<void> _loadRealFonts() async {
  final flutterRoot = Platform.environment['FLUTTER_ROOT'];
  if (flutterRoot != null) {
    final icons = File(
      '$flutterRoot/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf',
    );
    if (icons.existsSync()) {
      final bytes = icons.readAsBytesSync();
      await (FontLoader(
        'MaterialIcons',
      )..addFont(Future.value(ByteData.view(bytes.buffer)))).load();
    }
  }
  final loader = FontLoader(_family);
  for (final path in [
    '/System/Library/Fonts/Supplemental/Arial.ttf',
    '/System/Library/Fonts/Supplemental/Arial Bold.ttf',
  ]) {
    final file = File(path);
    if (!file.existsSync()) continue;
    final bytes = file.readAsBytesSync();
    loader.addFont(Future.value(ByteData.view(bytes.buffer)));
  }
  await loader.load();
}

/// The real app (router + aurora + theme), with only the screenshot font
/// pinned — mirrors AllisWellApp in app.dart.
class _ScreenshotApp extends ConsumerWidget {
  const _ScreenshotApp();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final router = ref.watch(routerProvider);
    return MaterialApp.router(
      debugShowCheckedModeBanner: false,
      theme: buildAwTheme(Brightness.light, fontFamilyOverride: _family),
      darkTheme: buildAwTheme(Brightness.dark, fontFamilyOverride: _family),
      themeMode: ThemeMode.system,
      locale: AwI18n.instance.locale,
      supportedLocales: awSupportedLocales,
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
        ...FlutterQuillLocalizations.localizationsDelegates,
      ],
      builder: (context, child) =>
          AuroraBackground(child: child ?? const SizedBox.shrink()),
      routerConfig: router,
    );
  }
}

Future<Widget> _signedInScreenshotApp(FakeApi api) async {
  SharedPreferences.setMockInitialValues({});
  final store = InMemorySecretStore();
  await TokenStorage(store).save(fakeSession());
  return ProviderScope(
    retry: awRetry,
    overrides: [
      ...syncTestOverrides(),
      secretStoreProvider.overrideWithValue(store),
      apiClientProvider.overrideWithValue(
        fakeDio(FakeHttpClientAdapter(api.handle)),
      ),
    ],
    child: const _ScreenshotApp(),
  );
}

/// A realistic, screenshot-ready workspace: four colored projects (two
/// favorites), five tags, tasks spread across every Home group AND every
/// default board column (open/in-progress/waiting/completed), two notes, and a
/// small Files tree (folders + workspace uploads + a project attachment). Rich
/// enough to show project badges, tag chips, priority flags and the month
/// calendar without looking staged.
FakeApi _seededApi() {
  final api = FakeApi();
  final now = DateTime.now();
  String iso(DateTime d) => d.toUtc().toIso8601String();
  // A time today at [h]:[m], shifted by [addDays]; late hours keep "today"
  // tasks reading as Today instead of overdue-today whatever the clock says.
  String day(int addDays, int h, int m) => iso(
    DateTime(now.year, now.month, now.day, h, m).add(Duration(days: addDays)),
  );

  final launch =
      api.seedProject(
            name: 'Launch v1',
            colorRgb: '#8E44EC',
            isFavorite: true,
          )['id']
          as String;
  final reno =
      api.seedProject(name: 'Home renovation', colorRgb: '#0C7D6C')['id']
          as String;
  final personal =
      api.seedProject(
            name: 'Personal',
            colorRgb: '#2563EB',
            isFavorite: true,
          )['id']
          as String;
  final reading =
      api.seedProject(name: 'Reading list', colorRgb: '#E8500A')['id']
          as String;

  final design = api.seedTag(name: 'design')['id'] as String;
  final health = api.seedTag(name: 'health')['id'] as String;
  final errand = api.seedTag(name: 'errand')['id'] as String;
  final writing = api.seedTag(name: 'writing')['id'] as String;

  // Overdue — a debt that must never look disabled.
  api.seedTask(
    title: 'Review contrast report',
    priority: 'urgent',
    isUrgent: true,
    dueAt: iso(now.subtract(const Duration(days: 1))),
    projectId: launch,
    tagIds: [design],
  );
  // No date — captured, not yet planned.
  api.seedTask(
    title: 'Sketch onboarding ideas',
    projectId: launch,
    tagIds: [design],
  );
  api.seedTask(
    title: 'Call the plumber about the leak',
    projectId: reno,
    tagIds: [errand],
  );
  // Today.
  api.seedTask(
    title: 'Ship the new Liquid Glass theme',
    description: 'Final QA in light + dark, then tag v0.4.0.',
    priority: 'high',
    dueAt: day(0, 23, 0),
    projectId: launch,
    tagIds: [design],
  );
  api.seedTask(
    title: 'Evening 5k run',
    priority: 'low',
    dueAt: day(0, 23, 30),
    projectId: personal,
    tagIds: [health],
  );
  // This week.
  api.seedTask(
    title: 'Water the plants',
    priority: 'low',
    dueAt: day(2, 9, 0),
    projectId: reno,
  );
  api.seedTask(
    title: 'Book dentist appointment',
    priority: 'medium',
    dueAt: day(3, 10, 0),
    projectId: personal,
    tagIds: [health],
  );
  // Next 30 days.
  api.seedTask(
    title: 'Draft the Q3 planning doc',
    priority: 'medium',
    dueAt: day(8, 12, 0),
    projectId: launch,
    tagIds: [writing],
  );
  api.seedTask(
    title: 'Read “Shape Up”, chapter 4',
    dueAt: day(15, 20, 0),
    projectId: reading,
    tagIds: [writing],
  );

  // Board-only colour: the in-progress / waiting / completed columns.
  api.seedTask(
    title: 'Wire up presigned uploads',
    status: 'in_progress',
    projectId: launch,
    tagIds: [design],
  );
  api.seedTask(
    title: 'Waiting on brand assets',
    status: 'waiting',
    projectId: launch,
    tagIds: [design],
  );
  api.seedTask(
    title: 'Set up the Cloudflare R2 bucket',
    status: 'completed',
    projectId: launch,
  );
  api.seedTask(
    title: 'Pick a launch date',
    status: 'completed',
    projectId: personal,
  );

  // Notes.
  api.seedNote(
    title: 'Launch checklist',
    plainText: 'Store copy, screenshots, press kit, changelog.',
    projectId: launch,
    isPinned: true,
  );
  api.seedNote(
    title: 'Renovation measurements',
    plainText: 'Kitchen 3.2 × 4.1 m · hallway 1.1 m wide.',
    projectId: reno,
  );

  // Files: two folders, workspace uploads inside one, plus a project
  // attachment so the Sources view has cross-target rows.
  final documents = api.seedFolder(name: 'Documents')['id'] as String;
  api.seedFolder(name: 'Invoices');
  api.seedFile(
    name: 'brand-guidelines.pdf',
    targetType: 'workspace',
    targetId: api.workspaceId,
    folderId: documents,
    mime: 'application/pdf',
    sizeBytes: 2400000,
  );
  api.seedFile(
    name: 'floor-plan.png',
    targetType: 'workspace',
    targetId: api.workspaceId,
    folderId: documents,
    mime: 'image/png',
    sizeBytes: 840000,
  );
  api.seedFile(
    name: 'hero-mockup.png',
    targetType: 'project',
    targetId: launch,
    mime: 'image/png',
    sizeBytes: 1200000,
  );

  return api;
}

/// Pump the seeded app and write `test/goldens/<name>.png` — with REAL
/// shadows (the binding otherwise paints elevations as black outlines).
/// The flag is restored inside the test body: the binding's invariant check
/// runs before addTearDown callbacks would. [size] is LOGICAL pixels; the
/// PNG is written at 2× for crispness.
Future<void> _shoot(
  WidgetTester tester, {
  required Size size,
  required Brightness brightness,
  required String name,
  Future<void> Function(WidgetTester tester)? navigate,
}) async {
  tester.view.physicalSize = size * 2;
  tester.view.devicePixelRatio = 2.0;
  tester.platformDispatcher.platformBrightnessTestValue = brightness;
  addTearDown(() {
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
    tester.platformDispatcher.clearPlatformBrightnessTestValue();
  });
  debugDisableShadows = false;
  try {
    await tester.pumpWidget(await _signedInScreenshotApp(_seededApi()));
    await tester.pumpAndSettle();
    if (navigate != null) {
      await navigate(tester);
      await tester.pumpAndSettle();
    }
    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('goldens/$name.png'),
    );
  } finally {
    debugDisableShadows = true;
  }
}

/// Tap a top-level nav destination by its label (NavigationRail on desktop).
Future<void> _openSection(WidgetTester tester, String label) async {
  await tester.tap(find.text(label).first);
}

void main() {
  setUpAll(_loadRealFonts);

  testWidgets('phone home — light', skip: !_enabled, (tester) async {
    await _shoot(
      tester,
      size: const Size(390, 844),
      brightness: Brightness.light,
      name: 'phone_home_light',
    );
  });

  testWidgets('phone home — dark', skip: !_enabled, (tester) async {
    await _shoot(
      tester,
      size: const Size(390, 844),
      brightness: Brightness.dark,
      name: 'phone_home_dark',
    );
  });

  testWidgets('phone create sheet — light', skip: !_enabled, (tester) async {
    await _shoot(
      tester,
      size: const Size(390, 844),
      brightness: Brightness.light,
      name: 'phone_sheet_light',
      navigate: (t) => t.tap(find.byType(FloatingActionButton)),
    );
  });

  testWidgets('phone create sheet — dark', skip: !_enabled, (tester) async {
    await _shoot(
      tester,
      size: const Size(390, 844),
      brightness: Brightness.dark,
      name: 'phone_sheet_dark',
      navigate: (t) => t.tap(find.byType(FloatingActionButton)),
    );
  });

  testWidgets('desktop home — light', skip: !_enabled, (tester) async {
    await _shoot(
      tester,
      size: const Size(1280, 800),
      brightness: Brightness.light,
      name: 'desktop_home_light',
    );
  });

  testWidgets('desktop home — dark', skip: !_enabled, (tester) async {
    await _shoot(
      tester,
      size: const Size(1280, 800),
      brightness: Brightness.dark,
      name: 'desktop_home_dark',
    );
  });

  testWidgets('desktop board — light', skip: !_enabled, (tester) async {
    await _shoot(
      tester,
      size: const Size(1280, 800),
      brightness: Brightness.light,
      name: 'desktop_board_light',
      navigate: (t) => t.tap(find.text('board.viewBoard'.tr())),
    );
  });

  testWidgets('desktop files — light', skip: !_enabled, (tester) async {
    await _shoot(
      tester,
      size: const Size(1280, 800),
      brightness: Brightness.light,
      name: 'desktop_files_light',
      navigate: (t) async {
        await _openSection(t, AppSection.files.title);
        await t.pumpAndSettle();
        await t.tap(find.text('Documents')); // open the folder → file rows
      },
    );
  });

  testWidgets('desktop projects — light', skip: !_enabled, (tester) async {
    await _shoot(
      tester,
      size: const Size(1280, 800),
      brightness: Brightness.light,
      name: 'desktop_projects_light',
      navigate: (t) => _openSection(t, AppSection.projects.title),
    );
  });
}
