import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'package:alliswell/src/features/ee/assignments_providers.dart';
import 'package:alliswell/src/i18n/i18n.dart';
import 'package:alliswell/src/router.dart';
import 'package:alliswell/src/sync/db/database.dart';

import '../projects/fake_api.dart';
import '../settings/settings_groups_test.dart' show app;

/// EE-290 — a task's team sections follow the TASK's workspace.
///
/// The history button and the "who is on this" card are a team's (EE-068,
/// EE-069): their own comments say a personal workspace never sees them. They
/// asked the roster of the workspace on SCREEN, though, so with a team's
/// workspace selected a personal task — opened from Home, which lists the
/// first workspace, or from a link — wore both.
MemberProfile _profile(String workspaceId) => MemberProfile(
  id: 'MP1',
  workspaceId: workspaceId,
  userId: 'U1',
  displayName: 'Ayşe',
  colorRgb: '#2563EB',
  revision: 1,
);

void main() {
  setUp(() => AwI18n.instance.setActiveCached(const Locale('en')));

  GoRouter routerOf() => GoRouter.of(awRootNavigatorKey.currentContext!);

  Future<void> openTask(
    WidgetTester tester, {
    required bool taskWorkspaceHasTeam,
  }) async {
    // Tall enough that the whole detail list is BUILT: the people card sits
    // below the fold, and a lazy list that never builds it would make the
    // "absent" half of this file pass for the wrong reason.
    tester.view.physicalSize = const Size(1280, 4000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final api = FakeApi();
    final task = api.seedTask(title: 'Kendi işim');
    const teamWorkspace = '01WSTEAMAAAAAAAAAAAAAAAAAA';
    await tester.pumpWidget(
      await app(
        api,
        extra: [
          // The workspace on screen is a team's: its roster is not empty.
          workspaceRosterProvider.overrideWith(
            (ref) => Stream.value([_profile(teamWorkspace)]),
          ),
          workspaceRosterOfProvider.overrideWith(
            (ref, workspaceId) => Stream.value([
              if (workspaceId == teamWorkspace ||
                  (taskWorkspaceHasTeam && workspaceId == api.workspaceId))
                _profile(workspaceId),
            ]),
          ),
        ],
      ),
    );
    await tester.pumpAndSettle();
    routerOf().push('/tasks/${task['id']}');
    await tester.pumpAndSettle();
    expect(find.text('Kendi işim'), findsWidgets);
    // The section right below the people card is built — so an absent card
    // is absent, not merely unbuilt.
    expect(find.text('task.checklist'.tr()), findsOneWidget);
  }

  testWidgets('a personal task shows no team sections, whatever workspace is '
      'on screen', (tester) async {
    await openTask(tester, taskWorkspaceHasTeam: false);
    expect(find.byKey(const Key('task-history')), findsNothing);
    expect(find.text('ee.assign.section'.tr()), findsNothing);
  });

  testWidgets('a team\'s task keeps its history and its people', (
    tester,
  ) async {
    await openTask(tester, taskWorkspaceHasTeam: true);
    expect(find.byKey(const Key('task-history')), findsOneWidget);
    expect(find.text('ee.assign.section'.tr()), findsOneWidget);
  });
}
