// The core product as an enterprise team uses it, for the enterprise page
// (EE-164): Home, the board, projects, notes and files at desktop width, in
// both themes and BOTH languages.
//
// Run locally with (each language writes its own files, EE-145):
//
//   flutter test --update-goldens --dart-define=screenshots=true \
//       --dart-define=shotLocale=tr test/enterprise_workspace_screenshot_test.dart
//   …and again with shotLocale=en, then `npm run shots:ee` at the repo root.
//
// Inert without the dart-define, like every other shot file: goldens are
// generated output, not committed, so a plain CI run must not compare against
// pictures that are not in the repository.
//
// ── WHY NOT THE WEB CAPTURES THE HOMEPAGE USES ────────────────────────────
//
// `screenshots/web/` is a real browser over a real API, seeded by
// scripts/seed-demo.mjs — in English, with a personal workspace ("Evening 5k
// run", "Home renovation"). The enterprise page is read by a plant's IT
// manager, in Turkish more often than not, and the page's own gate insists a
// Turkish page shows a Turkish interface (`check:copy` rule 4). Reproducing
// the browser pipeline per language means Docker, an API, a Flutter web build
// and a headless Chrome for five pictures; this harness needs none of that and
// already pins the real router, theme and fonts (design_screenshots_test.dart).
//
// ── ONE WORKSPACE, TWO LANGUAGES ─────────────────────────────────────────
//
// The seed below is a manufacturing company's week: a maintenance plan, an ERP
// migration, an audit, a new line. Every string is resolved through `_L`, so
// the two language versions are pictures of the SAME workspace — same
// projects, same counts, same dates — with only the words changed. That is
// the rule the EE corpus follows (demo_corpus.json) and for the same reason:
// an English buyer reading Turkish project names concludes the product is not
// translated, and a Turkish buyer reading English ones concludes the same.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:alliswell/src/i18n/i18n.dart';
import 'package:alliswell/src/sections.dart';

import 'design_screenshots_test.dart'
    show
        loadRealFontsForStore,
        openBoard,
        openSection,
        screenshotLocale,
        shootForStore;
import 'features/projects/fake_api.dart';

const bool _enabled = bool.fromEnvironment('screenshots');

/// A string in both languages, resolved against the active locale.
class _L {
  const _L(this.tr, this.en);
  final String tr;
  final String en;

  String get s => AwI18n.instance.locale.languageCode == 'tr' ? tr : en;
}

const _documents = _L('Dokümanlar', 'Documents');

/// A manufacturing company's workspace: four projects, four tags, tasks in
/// every Home group and every board column, six notes and a document archive.
FakeApi _seedCompany() {
  final api = FakeApi();
  final now = DateTime.now();
  String iso(DateTime d) => d.toUtc().toIso8601String();
  String day(int addDays, int h, int m) => iso(
    DateTime(now.year, now.month, now.day, h, m).add(Duration(days: addDays)),
  );

  final maintenance =
      api.seedProject(
            name: const _L('Bakım planı 2026', 'Maintenance plan 2026').s,
            colorRgb: '#0C7D6C',
            isFavorite: true,
          )['id']
          as String;
  final erp =
      api.seedProject(
            name: const _L('ERP geçişi', 'ERP migration').s,
            colorRgb: '#2563EB',
            isFavorite: true,
          )['id']
          as String;
  final audit =
      api.seedProject(
            name: const _L('Kalite denetimi', 'Quality audit').s,
            colorRgb: '#8E44EC',
          )['id']
          as String;
  final line =
      api.seedProject(
            name: const _L('Yeni hat kurulumu', 'New line commissioning').s,
            colorRgb: '#E8500A',
          )['id']
          as String;

  final urgent =
      api.seedTag(name: const _L('acil', 'urgent').s)['id'] as String;
  final upkeep =
      api.seedTag(name: const _L('bakım', 'maintenance').s)['id'] as String;
  final purchasing =
      api.seedTag(name: const _L('satın alma', 'purchasing').s)['id'] as String;
  final meeting =
      api.seedTag(name: const _L('toplantı', 'meeting').s)['id'] as String;

  // Overdue.
  api.seedTask(
    title: const _L('Kompresör yıllık bakımı', 'Compressor annual service').s,
    priority: 'urgent',
    dueAt: iso(now.subtract(const Duration(days: 1))),
    projectId: maintenance,
    tagIds: [urgent, upkeep],
  );
  // No date — captured, not yet planned.
  api.seedTask(
    title: const _L(
      'Yedek parça listesini güncelle',
      'Update the spare parts list',
    ).s,
    projectId: maintenance,
    tagIds: [upkeep],
  );
  api.seedTask(
    title: const _L(
      'Tedarikçi tekliflerini karşılaştır',
      'Compare the supplier quotes',
    ).s,
    projectId: line,
    tagIds: [purchasing],
  );
  // Today.
  api.seedTask(
    title: const _L(
      'Vardiya amirleriyle haftalık toplantı',
      'Weekly meeting with the shift supervisors',
    ).s,
    description: const _L(
      'Gündem: hat 3 duruşları, fazla mesai planı.',
      'Agenda: line 3 stoppages, overtime plan.',
    ).s,
    priority: 'high',
    dueAt: day(0, 23, 0),
    projectId: maintenance,
    tagIds: [meeting],
  );
  api.seedTask(
    title: const _L('3. hat sensör değişimi', 'Line 3 sensor replacement').s,
    priority: 'medium',
    dueAt: day(0, 23, 30),
    projectId: line,
    tagIds: [upkeep],
  );
  // This week.
  api.seedTask(
    title: const _L(
      'ISO 9001 iç denetim hazırlığı',
      'ISO 9001 internal audit preparation',
    ).s,
    priority: 'medium',
    dueAt: day(2, 9, 0),
    projectId: audit,
  );
  api.seedTask(
    title: const _L(
      'Forklift ehliyet yenilemeleri',
      'Forklift licence renewals',
    ).s,
    priority: 'low',
    dueAt: day(3, 10, 0),
    projectId: maintenance,
  );
  // Next 30 days.
  api.seedTask(
    title: const _L('Yıl sonu envanter sayımı', 'Year-end inventory count').s,
    priority: 'medium',
    dueAt: day(8, 12, 0),
    projectId: erp,
    tagIds: [purchasing],
  );
  api.seedTask(
    title: const _L('ERP eğitimi — muhasebe', 'ERP training — finance').s,
    dueAt: day(15, 20, 0),
    projectId: erp,
    tagIds: [meeting],
  );

  // Board-only colour: the in-progress / waiting / completed columns.
  api.seedTask(
    title: const _L('CNC tezgâhı kalibrasyonu', 'CNC machine calibration').s,
    status: 'in_progress',
    projectId: maintenance,
    tagIds: [upkeep],
  );
  api.seedTask(
    title: const _L(
      'Elektrik panosu için teklif bekleniyor',
      'Waiting for the switchboard quote',
    ).s,
    status: 'waiting',
    projectId: line,
    tagIds: [purchasing],
  );
  api.seedTask(
    title: const _L(
      'Boyahane havalandırma revizyonu',
      'Paint shop ventilation overhaul',
    ).s,
    status: 'completed',
    projectId: maintenance,
  );
  api.seedTask(
    title: const _L('Yangın tatbikatı raporu', 'Fire drill report').s,
    status: 'completed',
    projectId: audit,
  );

  // Notes: six, so the desktop canvas reads as a workspace in use.
  api.seedNote(
    title: const _L(
      'Haftalık üretim toplantısı — tutanak',
      'Weekly production meeting — minutes',
    ).s,
    plainText: const _L(
      'Hat 3 duruşları, fazla mesai planı, alınan kararlar.',
      'Line 3 stoppages, overtime plan, decisions taken.',
    ).s,
    projectId: maintenance,
    isPinned: true,
  );
  api.seedNote(
    title: const _L(
      'Bakım prosedürü: kompresör',
      'Maintenance procedure: compressor',
    ).s,
    plainText: const _L(
      'Aylık kontrol listesi, yağ değişimi aralıkları, güvenlik notları.',
      'Monthly checklist, oil change intervals, safety notes.',
    ).s,
    projectId: maintenance,
  );
  api.seedNote(
    title: const _L('ERP geçiş takvimi', 'ERP migration schedule').s,
    plainText: const _L(
      'Faz 1 muhasebe, faz 2 satın alma, faz 3 üretim.',
      'Phase 1 finance, phase 2 purchasing, phase 3 production.',
    ).s,
    projectId: erp,
    isPinned: true,
  );
  api.seedNote(
    title: const _L('Tedarikçi görüşme notları', 'Supplier meeting notes').s,
    plainText: const _L(
      'Üç teklif alındı; teslim süresi ve garanti şartları karşılaştırılacak.',
      'Three quotes received; lead time and warranty terms to be compared.',
    ).s,
    projectId: line,
  );
  api.seedNote(
    title: const _L('Kalite denetimi bulguları', 'Quality audit findings').s,
    plainText: const _L(
      'İki küçük uygunsuzluk, düzeltici faaliyet planı ekte.',
      'Two minor non-conformities, corrective action plan attached.',
    ).s,
    projectId: audit,
  );
  api.seedNote(
    title: const _L(
      'Vardiya devir teslim talimatı',
      'Shift handover instructions',
    ).s,
    plainText: const _L(
      'Devir formu, açık arızalar, kritik stok seviyeleri.',
      'Handover form, open faults, critical stock levels.',
    ).s,
  );

  // Files: two folders, documents inside one, plus a project attachment so
  // the Sources view has cross-target rows.
  final documents = api.seedFolder(name: _documents.s)['id'] as String;
  api.seedFolder(name: const _L('Sözleşmeler', 'Contracts').s);
  api.seedFile(
    name: const _L('bakim-plani-2026.xlsx', 'maintenance-plan-2026.xlsx').s,
    targetType: 'workspace',
    targetId: api.workspaceId,
    folderId: documents,
    mime: 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
    sizeBytes: 640000,
  );
  api.seedFile(
    name: const _L('iso-9001-el-kitabi.pdf', 'iso-9001-manual.pdf').s,
    targetType: 'workspace',
    targetId: api.workspaceId,
    folderId: documents,
    mime: 'application/pdf',
    sizeBytes: 2400000,
  );
  api.seedFile(
    name: const _L('yerlesim-plani.png', 'floor-plan.png').s,
    targetType: 'workspace',
    targetId: api.workspaceId,
    folderId: documents,
    mime: 'image/png',
    sizeBytes: 840000,
  );
  api.seedFile(
    name: const _L('tedarikci-sozlesmesi.pdf', 'supplier-agreement.pdf').s,
    targetType: 'workspace',
    targetId: api.workspaceId,
    folderId: documents,
    mime: 'application/pdf',
    sizeBytes: 380000,
  );
  api.seedFile(
    name: const _L('hat-3-teknik-cizim.pdf', 'line-3-drawing.pdf').s,
    targetType: 'project',
    targetId: line,
    mime: 'application/pdf',
    sizeBytes: 1100000,
  );

  return api;
}

/// The golden's name carries theme AND language, like `eeGolden` does, so the
/// two language runs cannot overwrite each other (EE-145). `npm run shots:ee`
/// drops the `ee-` prefix into `screenshots/ee/`.
String _name(String screen, Brightness brightness) =>
    'ee-work-$screen-${brightness.name}-'
    '${AwI18n.instance.locale.languageCode}';

void main() {
  if (!_enabled) return;

  setUpAll(loadRealFontsForStore);

  setUp(() {
    // Before the seed: every `_L` reads the active language.
    AwI18n.instance.setActiveCached(screenshotLocale('tr'));
  });

  const size = Size(1280, 800);

  for (final brightness in Brightness.values) {
    testWidgets('home — ${brightness.name}', (tester) async {
      await shootForStore(
        tester,
        size: size,
        brightness: brightness,
        name: _name('home', brightness),
        seed: _seedCompany,
      );
    });

    testWidgets('board — ${brightness.name}', (tester) async {
      await shootForStore(
        tester,
        size: size,
        brightness: brightness,
        name: _name('board', brightness),
        seed: _seedCompany,
        navigate: openBoard,
      );
    });

    testWidgets('projects — ${brightness.name}', (tester) async {
      await shootForStore(
        tester,
        size: size,
        brightness: brightness,
        name: _name('projects', brightness),
        seed: _seedCompany,
        navigate: (t) => openSection(t, AppSection.projects),
      );
    });

    testWidgets('notes — ${brightness.name}', (tester) async {
      await shootForStore(
        tester,
        size: size,
        brightness: brightness,
        name: _name('notes', brightness),
        seed: _seedCompany,
        navigate: (t) => openSection(t, AppSection.notes),
      );
    });

    testWidgets('files — ${brightness.name}', (tester) async {
      await shootForStore(
        tester,
        size: size,
        brightness: brightness,
        name: _name('files', brightness),
        seed: _seedCompany,
        navigate: (t) async {
          await openSection(t, AppSection.files);
          await t.pumpAndSettle();
          await t.tap(find.text(_documents.s)); // open the folder → file rows
        },
      );
    });
  }
}
