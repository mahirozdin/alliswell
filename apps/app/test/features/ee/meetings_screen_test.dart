import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:alliswell/src/core/reachability.dart';
import 'package:alliswell/src/features/ee/data/meeting_models.dart';
import 'package:alliswell/src/features/ee/data/meetings_api.dart';
import 'package:alliswell/src/features/ee/meetings_providers.dart';
import 'package:alliswell/src/features/ee/providers.dart';
import 'package:alliswell/src/features/ee/ui/meetings_screen.dart';
import 'package:alliswell/src/features/workspaces/workspaces.dart';
import 'package:alliswell/src/i18n/i18n.dart';
import 'package:alliswell/src/sync/providers.dart';
import 'package:alliswell/src/theme/theme.dart';

/// AW-E26 / EE-271 — the meetings list, asserted where it could mislead.
///
/// A list of meetings answers one question per row: is it ready, and what did
/// it decide. So a meeting still waiting for its note must read as WAITING
/// (the detail's rule, EE-115) and must not show a decision count it does not
/// have yet; and a list that needs the server must say so with no signal
/// rather than draw an old answer — or ask a network the app already knows is
/// gone.
class _FakeMeetings extends Fake implements EeMeetingsApi {
  List<EeMeetingSummary>? rows = const [];
  int listed = 0;

  @override
  Future<List<EeMeetingSummary>?> list(String workspaceId) async {
    listed += 1;
    return rows;
  }
}

EeMeetingSummary _meeting(
  String id,
  String title,
  EeMeetingStatus status, {
  int decisions = 0,
  int ideas = 0,
}) => EeMeetingSummary(
  id: id,
  workspaceId: 'W1',
  status: status,
  attempts: 1,
  decisionCount: decisions,
  ideaCount: ideas,
  createdAt: DateTime.now().subtract(const Duration(hours: 3)),
  title: title,
);

void main() {
  late _FakeMeetings api;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    AwI18n.instance.setActiveCached(const Locale('tr'));
    api = _FakeMeetings();
  });

  Future<ProviderContainer> pump(
    WidgetTester tester, {
    bool entitled = true,
    bool offline = false,
  }) async {
    final container = ProviderContainer(
      overrides: [
        eeMeetingsApiProvider.overrideWithValue(api),
        eeFeatureProvider.overrideWith((ref, name) => entitled),
        syncEngineProvider.overrideWithValue(null),
        currentWorkspaceProvider.overrideWithValue(
          const AsyncValue.data(
            WorkspaceSummary(
              id: 'W1',
              name: 'Bakım',
              slug: 'bakim',
              colorRgb: '#2563EB',
              role: 'member',
            ),
          ),
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
          home: const EeMeetingsScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return container;
  }

  Finder key(String k) => find.byKey(Key(k));

  testWidgets('AW-E26: a ready meeting says what it decided; a waiting one '
      'reads as waiting and claims no decisions', (tester) async {
    api.rows = [
      _meeting(
        'M1',
        'Vardiya devri',
        EeMeetingStatus.ready,
        decisions: 3,
        ideas: 2,
      ),
      _meeting('M2', 'Kalite gözden geçirme', EeMeetingStatus.transcribed),
    ];
    await pump(tester);

    expect(key('meeting-M1'), findsOneWidget);
    expect(
      find.text(
        'ee.meetings.counts'.tr(args: {'decisions': '3', 'ideas': '2'}),
      ),
      findsOneWidget,
    );
    // `transcribed` is WAITING: the word says the note is still being
    // written, and there is no count to show until it is.
    expect(
      find.descendant(
        of: key('meeting-M2'),
        matching: find.textContaining('ee.meeting.status.transcribed'.tr()),
      ),
      findsOneWidget,
    );
    expect(key('meeting-counts-M2'), findsNothing);
  });

  testWidgets('AW-E26: with no signal the list says it needs a connection — '
      'and asks nothing', (tester) async {
    api.rows = [_meeting('M1', 'Vardiya devri', EeMeetingStatus.ready)];
    await pump(tester, offline: true);
    expect(key('meetings-offline'), findsOneWidget);
    expect(key('meeting-M1'), findsNothing);
    expect(api.listed, 0);
  });

  testWidgets('without the entitlement the list says meetings are not here', (
    tester,
  ) async {
    await pump(tester, entitled: false);
    expect(key('meetings-unavailable'), findsOneWidget);
    expect(api.listed, 0);
  });

  testWidgets('a unit with no meetings says so', (tester) async {
    api.rows = const [];
    await pump(tester);
    expect(key('meetings-empty'), findsOneWidget);
  });
}
