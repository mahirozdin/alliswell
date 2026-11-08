// OPH-400 polish 3 (J-04, DESIGN §46 R3): a silenced alarm's way back is a
// whole action, never "Alarmı geri…".
//
// The row used to squeeze "Alarmı geri aç" / "Turn alarms back on" into the
// width left after the date, so the imperative ended in "…" on a phone
// (`.ceo/shots2/ios` 21, 82) and in "Ala…" at XXL. Now the row shows the short
// complete action ("Sesi aç" / "Unmute"), its accessible name stays the full
// "Alarmı geri aç", its target is ≥ 48 pt, and when it does not fit beside the
// others it takes a line of its own instead of being cut.
//
// Measured with the repo's real Roboto/DejaVu and with the test font, on 360
// and 393 pt, 1.0× to AX3 (3.1×), TR and EN, light and dark.
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:alliswell/src/features/ee/assignments_providers.dart';
import 'package:alliswell/src/features/ee/ticket_work_providers.dart';
import 'package:alliswell/src/features/projects/data/project.dart';
import 'package:alliswell/src/features/projects/providers.dart';
import 'package:alliswell/src/features/tags/tags.dart';
import 'package:alliswell/src/features/tasks/data/task.dart';
import 'package:alliswell/src/features/tasks/ui/task_tile.dart';
import 'package:alliswell/src/features/workspaces/workspaces.dart';
import 'package:alliswell/src/i18n/i18n.dart';
import 'package:alliswell/src/theme/theme.dart';
import 'package:alliswell/src/theme/tokens.dart';

import '../../design_screenshots_test.dart' show loadRealFontsForStore;

const _family = 'ScreenshotSans';

final _now = DateTime.now();
final _future = _now.add(const Duration(days: 3, hours: 2));
final _past = _now.subtract(const Duration(days: 2));

const _projects = {
  'P0': Project(
    id: 'P0',
    workspaceId: 'W1',
    name: 'Launch AllisWell',
    colorRgb: '#16A34A',
    status: 'active',
    sortOrder: 0,
    isFavorite: false,
    revision: 1,
  ),
  'P1': Project(
    id: 'P1',
    workspaceId: 'W1',
    name: 'Ev',
    colorRgb: '#2563EB',
    status: 'active',
    sortOrder: 1,
    isFavorite: false,
    revision: 1,
  ),
};

const _tags = {
  'G1': Tag(id: 'G1', name: 'ev', slug: 'ev', colorRgb: '#2563EB'),
  'G2': Tag(id: 'G2', name: 'acil', slug: 'acil', colorRgb: '#DC2626'),
};

Task _muted(
  String id, {
  DateTime? due,
  String? projectId,
  List<String> tagIds = const [],
  String priority = 'medium',
}) => Task(
  id: id,
  workspaceId: 'W1',
  title: 'Faturayı öde',
  status: 'open',
  priority: priority,
  timezone: 'Europe/Istanbul',
  isUrgent: true,
  requiresAcknowledgement: false,
  sortOrder: 0,
  revision: 1,
  dueAt: due?.toUtc(),
  remindAt: due?.subtract(const Duration(hours: 1)).toUtc(),
  projectId: projectId,
  tagIds: tagIds,
  alarmsMutedAt: _now.toUtc(),
);

/// The judge's rows (a date and a project) plus the crowded ones: overdue,
/// a long project name in the meta line, tags and a priority flag.
List<Task> _rows() => [
  _muted('m0', due: _future, projectId: 'P1'),
  _muted('m1', due: _past, projectId: 'P0'),
  _muted(
    'm2',
    due: _future,
    projectId: 'P0',
    tagIds: const ['G1', 'G2'],
    priority: 'high',
  ),
  _muted('m3'),
];

Future<void> _pump(
  WidgetTester tester, {
  required double width,
  required double scale,
  Brightness brightness = Brightness.light,
  String? family,
}) async {
  SharedPreferences.setMockInitialValues({});
  tester.view.physicalSize = Size(width, 4000);
  tester.view.devicePixelRatio = 1.0;
  tester.platformDispatcher.textScaleFactorTestValue = scale;
  addTearDown(() {
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
    tester.platformDispatcher.clearTextScaleFactorTestValue();
  });
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        projectsByIdProvider.overrideWithValue(_projects),
        tagsByIdProvider.overrideWithValue(_tags),
        unitLabelsProvider.overrideWithValue(const {}),
        workspaceAssigneesProvider.overrideWith((ref) => Stream.value({})),
        workTicketsByTaskProvider.overrideWith((ref) => Stream.value({})),
      ],
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: buildAwTheme(brightness, fontFamilyOverride: family),
        home: Scaffold(
          body: ListView(
            padding: const EdgeInsets.symmetric(horizontal: AwSpace.x4),
            children: [
              for (final task in _rows())
                TaskTile(key: ValueKey('row-${task.id}'), task: task),
            ],
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Finder _in(String id, Finder f) =>
    find.descendant(of: find.byKey(ValueKey('row-$id')), matching: f);

void _expectWholeAction(WidgetTester tester, String label) {
  final short = 'task.unmuteShort'.tr();
  final full = 'task.unmuteAlarms'.tr();
  expect(short, isNot('task.unmuteShort'), reason: '$label: key exists');
  for (final task in _rows()) {
    final id = task.id;
    final why = '$label $id';
    final button = find.byKey(Key('unmute-$id'));
    expect(
      button.hitTestable(),
      findsOneWidget,
      reason: '$why: shown, tappable',
    );
    expect(_in(id, find.textContaining('…')), findsNothing, reason: why);

    // The action is the short complete imperative, drawn whole.
    final paragraphs = find
        .descendant(of: button, matching: find.byType(RichText))
        .evaluate()
        .map((e) => e.renderObject! as RenderParagraph)
        .toList();
    expect(paragraphs, hasLength(1), reason: why);
    final p = paragraphs.single;
    expect(
      p.text.toPlainText(includeSemanticsLabels: false).trim(),
      short,
      reason: why,
    );
    expect(p.didExceedMaxLines, isFalse, reason: '$why: not cut');
    final wordsFit = short
        .split(' ')
        .every(
          (w) =>
              (TextPainter(
                text: TextSpan(text: w, style: p.text.style),
                textDirection: p.textDirection,
                textScaler: p.textScaler,
              )..layout()).width <=
              p.size.width + 0.5,
        );
    expect(wordsFit, isTrue, reason: '$why: no word broken');

    // ≥ 48 pt target, inside the card.
    final rect = tester.getRect(button);
    expect(rect.height, greaterThanOrEqualTo(48 - 0.01), reason: why);
    expect(rect.width, greaterThanOrEqualTo(48 - 0.01), reason: why);
    final card = tester.getRect(_in(id, find.byType(Card)));
    expect(rect.left, greaterThanOrEqualTo(card.left - 0.5), reason: why);
    expect(rect.right, lessThanOrEqualTo(card.right + 0.5), reason: why);
    expect(rect.bottom, lessThanOrEqualTo(card.bottom + 0.5), reason: why);

    // The silenced glyph is never dropped beside it.
    expect(
      _in(id, find.byIcon(Icons.notifications_off)).hitTestable(),
      findsOneWidget,
      reason: why,
    );

    // A reader hears the full action.
    expect(
      tester.getSemantics(button),
      matchesSemantics(
        label: full,
        isButton: true,
        hasTapAction: true,
        isEnabled: true,
        hasEnabledState: true,
        isFocusable: true,
        hasFocusAction: true,
      ),
      reason: why,
    );
  }
}

void main() {
  setUp(() => AwI18n.instance.setActiveCached(const Locale('tr')));
  tearDown(() => AwI18n.instance.setActiveCached(const Locale('en')));

  testWidgets('test font: the way back is whole and ≥ 48 pt at 1.0×–3.1×', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    for (final language in ['tr', 'en']) {
      AwI18n.instance.setActiveCached(Locale(language));
      for (final width in [360.0, 393.0]) {
        for (final scale in [1.0, 1.3, 2.0, 3.1]) {
          await _pump(tester, width: width, scale: scale);
          final label = '$language $width × $scale';
          expect(tester.takeException(), isNull, reason: label);
          _expectWholeAction(tester, label);
        }
      }
    }
    handle.dispose();
  });

  group('real glyphs', () {
    setUpAll(loadRealFontsForStore);

    testWidgets('360/393 × 1.0/1.3/AX3 × TR/EN × light/dark: "Sesi aç" whole, '
        'never "Alarmı geri…"', (tester) async {
      final handle = tester.ensureSemantics();
      for (final language in ['tr', 'en']) {
        AwI18n.instance.setActiveCached(Locale(language));
        for (final brightness in Brightness.values) {
          for (final width in [360.0, 393.0]) {
            for (final scale in [1.0, 1.3, 3.1]) {
              await _pump(
                tester,
                width: width,
                scale: scale,
                brightness: brightness,
                family: _family,
              );
              final label = '$language ${brightness.name} $width × $scale';
              expect(tester.takeException(), isNull, reason: label);
              _expectWholeAction(tester, label);
            }
          }
        }
      }
      handle.dispose();
    });
  });
}
