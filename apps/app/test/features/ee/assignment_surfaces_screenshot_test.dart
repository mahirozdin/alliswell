// E07's assignment surfaces, shot in both themes (EE-071).
//
//   flutter test --update-goldens --dart-define=screenshots=true \
//       test/features/ee/assignment_surfaces_screenshot_test.dart
//
// Inert without the dart-define, and the images are NOT committed — the house
// rule set at EE-026: shots are generated, looked at, and thrown away. What
// ships to a landing page is a separate, later decision (EE-122).
//
// The avatar chip has its own file (`assignee_avatars_screenshot_test.dart`);
// this one is about the three SURFACES the epic added, where the question is
// composition rather than colour: does an assignee section read as a list of
// people, does "assigned to me" read as work rather than as a report, and does
// a task's history read as a sequence of acts by people.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:alliswell/src/features/ee/assignments_providers.dart';
import 'package:alliswell/src/features/ee/data/history_models.dart';
import 'package:alliswell/src/features/ee/history_providers.dart';
import 'package:alliswell/src/features/ee/ui/assigned_to_me_screen.dart';
import 'package:alliswell/src/features/ee/ui/assignee_avatars.dart';
import 'package:alliswell/src/features/ee/ui/task_history_screen.dart';
import 'package:alliswell/src/features/tasks/data/task.dart';
import 'package:alliswell/src/features/tasks/providers.dart';
import 'package:alliswell/src/i18n/i18n.dart';
import 'package:alliswell/src/theme/theme.dart';
import 'package:alliswell/src/theme/tokens.dart';
import 'package:alliswell/src/widgets/glass.dart';

import '../../design_screenshots_test.dart' show loadRealFontsForStore;

const bool _enabled = bool.fromEnvironment('screenshots');
const String _screenshotFamily = 'ScreenshotSans';
const String _kTask = 'T1';
const String _kWorkspace = 'W1';

Assignee _person(String id, String name, String initials, String colour) =>
    Assignee(
      assignmentId: 'A-$id',
      userId: id,
      displayName: name,
      initials: initials,
      colorRgb: colour,
    );

final _crew = [
  _person('U1', 'Ayla Yönetici', 'AY', '#2563EB'),
  _person('U2', 'Barış Saha', 'BS', '#7C3AED'),
  _person('U3', 'Deniz Koordinatör', 'DK', '#16A34A'),
  // The churn case belongs in the composition shot too: a row of faces with
  // one stranger in it is what a real team looks like a month after a leaver.
  const Assignee(assignmentId: 'A-GONE', userId: 'U-GONE'),
];

Task _task(String id, String title, {DateTime? due, String status = 'open'}) =>
    Task(
      id: id,
      workspaceId: _kWorkspace,
      title: title,
      status: status,
      priority: 'medium',
      timezone: 'Europe/Istanbul',
      isUrgent: false,
      requiresAcknowledgement: false,
      sortOrder: 0,
      revision: 1,
      dueAt: due,
    );

EeHistoryEvent _event(
  String id,
  String verb,
  String who,
  DateTime at, {
  Map<String, dynamic>? diff,
}) => EeHistoryEvent(
  id: id,
  occurredAt: at,
  actor: 'user',
  actorId: 'U1',
  actorName: who,
  actorInitials: who.substring(0, 2).toUpperCase(),
  actorColorRgb: '#2563EB',
  verb: verb,
  entityType: 'task',
  entityId: _kTask,
  diff: diff,
);

void main() {
  if (!_enabled) return;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    AwI18n.instance.setActiveCached(const Locale('tr'));
  });

  Future<void> shoot(
    WidgetTester tester,
    Brightness brightness,
    String name,
    List<Override> overrides,
    Widget screen,
  ) async {
    await loadRealFontsForStore();
    tester.view.physicalSize = const Size(900, 900);
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
    testWidgets('the assignee section — ${brightness.name}', (tester) async {
      await shoot(
        tester,
        brightness,
        'ee-assignee-section',
        [
          taskAssigneesProvider.overrideWith(
            (ref, taskId) => Stream.value(_crew),
          ),
        ],
        Scaffold(
          backgroundColor: Colors.transparent,
          body: Center(
            child: Padding(
              padding: const EdgeInsets.all(AwSpace.x6),
              child: Card(
                child: Padding(
                  padding: const EdgeInsets.all(AwSpace.x4),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text('ee.assign.section'.tr()),
                      const SizedBox(height: AwSpace.x3),
                      const AwAssigneeSection(
                        workspaceId: _kWorkspace,
                        taskId: _kTask,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      );
    });

    testWidgets('assigned to me — ${brightness.name}', (tester) async {
      final tasks = [
        _task('T1', 'Trafo bakımı', due: DateTime(2026, 8, 24, 9)),
        _task('T2', 'Pano montajı — 3. hat', due: DateTime(2026, 8, 26, 14)),
        _task('T3', 'Saha kurulum raporu'),
      ];
      await shoot(tester, brightness, 'ee-assigned-to-me', [
        openTasksProvider.overrideWith((ref) => Stream.value(tasks)),
        myAssignedTaskIdsProvider.overrideWith(
          (ref) => Stream.value({'T1', 'T2', 'T3'}),
        ),
        workspaceAssigneesProvider.overrideWith(
          (ref) => Stream.value({
            'T1': _crew.take(2).toList(),
            'T2': [_crew.first],
            'T3': [_crew.last],
          }),
        ),
      ], const EeAssignedToMeScreen());
    });

    testWidgets('assigned to me, empty — ${brightness.name}', (tester) async {
      await shoot(tester, brightness, 'ee-assigned-to-me-empty', [
        openTasksProvider.overrideWith((ref) => Stream.value(const <Task>[])),
        myAssignedTaskIdsProvider.overrideWith(
          (ref) => Stream.value(const <String>{}),
        ),
      ], const EeAssignedToMeScreen());
    });

    testWidgets('a task’s history — ${brightness.name}', (tester) async {
      await shoot(tester, brightness, 'ee-task-history', [
        eeHistoryProvider.overrideWith(
          (ref, target) async => EeHistoryPage(
            items: [
              _event(
                'E4',
                'released',
                'Barış Saha',
                DateTime(2026, 8, 22, 16, 20),
              ),
              _event(
                'E3',
                'status_changed',
                'Barış Saha',
                DateTime(2026, 8, 22, 15, 05),
                diff: {
                  'subtask': ['Kabloyu çek', 'done'],
                },
              ),
              _event(
                'E2',
                'assigned',
                'Ayla Yönetici',
                DateTime(2026, 8, 22, 11, 40),
              ),
              _event(
                'E1',
                'created',
                'Ayla Yönetici',
                DateTime(2026, 8, 21, 9, 15),
              ),
            ],
          ),
        ),
      ], const EeTaskHistoryScreen(taskId: _kTask));
    });
  }
}
