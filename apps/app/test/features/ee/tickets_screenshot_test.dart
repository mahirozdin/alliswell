// The service desk's screens, shot in both themes (EE-084 acceptance).
//
// Run locally with:
//
//   flutter test --update-goldens --dart-define=screenshots=true \
//       test/features/ee/tickets_screenshot_test.dart
//
// Inert without the dart-define, like every other shot file here: goldens are
// generated output, not committed, so a plain CI run must not compare against
// pictures that are not in the repository.
//
// WHY FIVE SHOTS. The acceptance names three queue states, and each fails in a
// way the other two cannot show:
//
//   • FULL is where priority has to read at a glance, finished work has to sit
//     apart without disappearing, and an urgent row has to be findable in a
//     photograph of a screen taken in a plant.
//   • EMPTY and FILTERED-EMPTY are the same absence with opposite meanings —
//     "nothing came in" is good news, "your filters exclude everything" is a
//     mistake somebody is one tap from fixing — and a screen that drew one
//     message for both would be wrong exactly when it matters.
//   • The DETAIL shot exists for the internal note. An agent who mistakes it
//     for a reply to the customer has said the wrong thing to the wrong
//     person, so the three signals (tint, lock, word) have to be legible
//     together, in both themes.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:alliswell/src/features/ee/assignments_providers.dart'
    show Assignee;
import 'package:alliswell/src/features/ee/tickets_providers.dart';
import 'package:alliswell/src/features/ee/ui/ticket_queue_screen.dart';
import 'package:alliswell/src/i18n/i18n.dart';
import 'package:alliswell/src/sync/db/database.dart';
import 'package:alliswell/src/theme/theme.dart';
import 'package:alliswell/src/widgets/glass.dart';

import '../../design_screenshots_test.dart'
    show loadRealFontsForStore, screenshotLocale;

const bool _enabled = bool.fromEnvironment('screenshots');

/// The theme's own fontFamily is null (platform font, DESIGN §3.3) and the
/// test engine draws that as BOX GLYPHS — every shot file here learned it the
/// same way.
const String _screenshotFamily = 'ScreenshotSans';

TicketRecord _ticket({
  required String id,
  required String subject,
  required String status,
  required String priority,
  DateTime? terminalAt,
  String? serviceId,
  String? slaStatus,
  DateTime? slaDueAt,
}) => TicketRecord(
  id: id,
  workspaceId: 'W1',
  serviceId: serviceId,
  requesterId: 'U1',
  subject: subject,
  body: null,
  status: status,
  priority: priority,
  source: 'internal',
  terminalAt: terminalAt,
  slaStatus: slaStatus,
  slaDueAt: slaDueAt,
  createdAt: DateTime.utc(2026, 8, 20, 9),
  revision: 1,
  updatedAt: DateTime.utc(2026, 8, 20, 9),
);

/// One of each state the row has to make legible, in the order the screen
/// sorts them: live work first, finished work last.
final _queue = [
  _ticket(
    id: 'T1',
    subject: '3. hat dolum bandı sensörü çift sayıyor, vardiya durdu',
    status: 'new',
    priority: 'urgent',
    serviceId: 'S1',
    // EE-097: one shot, all four badge states — a breach has to be findable in
    // a photograph of a screen taken across a plant floor, and the amber row
    // below has to be legible in the same picture without taking the accent
    // into its text.
    slaStatus: 'breached',
  ),
  _ticket(
    id: 'T2',
    subject: 'Kaynak robotu kalibrasyonu sapıyor',
    status: 'in_progress',
    priority: 'high',
    serviceId: 'S1',
    slaStatus: 'warned',
    slaDueAt: DateTime.utc(2026, 8, 20, 11),
  ),
  _ticket(
    id: 'T3',
    subject: 'Yedek parça talebi — rulman 6204',
    status: 'waiting',
    priority: 'normal',
    serviceId: 'S2',
    // Paused: a promise with no countdown, which is a state of its own.
    slaStatus: 'ok',
  ),
  _ticket(
    id: 'T4',
    subject: 'Ofis yazıcısı kağıt sıkıştırıyor',
    status: 'closed',
    priority: 'low',
    terminalAt: DateTime.utc(2026, 8, 19, 16),
    serviceId: 'S2',
    slaStatus: 'met',
  ),
];

/// EE-086's avatars, on two of the four rows: an assigned ticket and an
/// unassigned one have to be tellable apart at a glance, and "nobody is on it"
/// is the commonest state of a live queue rather than an edge case.
const _assignees = {
  'T1': [
    Assignee(
      assignmentId: 'A1',
      userId: 'U1',
      displayName: 'Barış Servis',
      initials: 'BS',
      colorRgb: '#0A5CFF',
    ),
    Assignee(
      assignmentId: 'A2',
      userId: 'U2',
      displayName: 'Deniz Koordinatör',
      initials: 'DK',
      colorRgb: '#7C3AED',
    ),
  ],
  'T2': [
    Assignee(
      assignmentId: 'A3',
      userId: 'U1',
      displayName: 'Barış Servis',
      initials: 'BS',
      colorRgb: '#0A5CFF',
    ),
  ],
};

List<Override> _overrides(List<TicketRecord> rows, {TicketFilter? filter}) => [
  ticketQueueProvider.overrideWith((ref) => Stream.value(rows)),
  ticketAssigneesProvider.overrideWith((ref) => Stream.value(_assignees)),
  if (filter != null)
    ticketFilterProvider.overrideWith(() => _FixedFilter(filter)),
];

class _FixedFilter extends TicketFilterController {
  _FixedFilter(this._value);
  final TicketFilter _value;

  @override
  TicketFilter build() => _value;
}

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
    List<Override> overrides,
    Widget screen,
  ) async {
    await loadRealFontsForStore();
    tester.view.physicalSize = const Size(900, 1000);
    tester.view.devicePixelRatio = 2.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    debugDisableShadows = false;
    try {
      await tester.pumpWidget(
        ProviderScope(
          overrides: overrides,
          child: MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: buildAwTheme(
              brightness,
              fontFamilyOverride: _screenshotFamily,
            ),
            home: AwPageBackground(child: screen),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('../../goldens/$name-${brightness.name}.png'),
      );
    } finally {
      debugDisableShadows = true;
    }
  }

  for (final brightness in Brightness.values) {
    testWidgets('the unit queue, with work in it — ${brightness.name}', (
      tester,
    ) async {
      await shoot(
        tester,
        brightness,
        'ee-ticket-queue',
        _overrides(_queue),
        const EeTicketQueueScreen(),
      );
    });

    testWidgets('nothing came in — ${brightness.name}', (tester) async {
      await shoot(
        tester,
        brightness,
        'ee-ticket-queue-empty',
        _overrides(const []),
        const EeTicketQueueScreen(),
      );
    });

    // The SAME emptiness, the opposite meaning. Two shots because one message
    // for both states would be wrong exactly when somebody is stuck.
    testWidgets('the filter excludes everything — ${brightness.name}', (
      tester,
    ) async {
      await shoot(
        tester,
        brightness,
        'ee-ticket-queue-filtered',
        _overrides(const [], filter: const TicketFilter(statuses: {'waiting'})),
        const EeTicketQueueScreen(),
      );
    });
  }
}
