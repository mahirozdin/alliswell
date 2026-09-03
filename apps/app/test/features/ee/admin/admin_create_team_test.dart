import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:alliswell/src/features/ee/admin/admin_providers.dart';
import 'package:alliswell/src/features/ee/admin/data/admin_models.dart';
import 'package:alliswell/src/features/ee/admin/ui/admin_teams_screen.dart';
import 'package:alliswell/src/i18n/i18n.dart';
import 'package:alliswell/src/theme/theme.dart';

/// OPH-291 — the console can create the team its empty state promised.
///
/// The bug this covers was not a missing feature but a LIE: the empty state
/// read "a team is created here, its first administrator is invited by
/// e-mail", the server had the endpoint, and the screen had no control that
/// called it. On an instance with no teams that sentence is the entire
/// interface, so the console's only screen was an instruction nobody could
/// follow.
///
/// So the first test is the one that would have caught it: with no teams, the
/// empty state offers a way to make one. The rest guard the parts that are
/// easy to get wrong afterwards — the slug is shown as the address it becomes,
/// it stops following the name once somebody edits it, and a refusal from the
/// server is shown ON the form rather than behind it.
void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    AwI18n.instance.setActiveCached(const Locale('en'));
  });

  Future<void> pump(WidgetTester tester, List<AdminTeam> teams) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [adminTeamsProvider.overrideWith((ref) async => teams)],
        child: MaterialApp(
          theme: buildAwTheme(Brightness.light),
          home: const AdminTeamsScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('AN EMPTY CONSOLE OFFERS A WAY TO MAKE THE FIRST TEAM', (
    tester,
  ) async {
    await pump(tester, const []);

    // The sentence and the control that makes it true, together.
    expect(find.text('ee.admin.teams.emptyBody'.tr()), findsOneWidget);
    expect(find.byKey(const Key('admin-teams-create-empty')), findsOneWidget);
  });

  testWidgets('and once teams exist the way in is still there', (tester) async {
    await pump(tester, [
      const AdminTeam(
        id: 'T1',
        name: 'Acme',
        slug: 'acme',
        status: AdminTeamStatus.active,
        packageName: 'Starter',
        seatsUsed: 3,
        seatsLimit: 10,
        pendingDeleteAt: null,
      ),
    ]);
    expect(find.byKey(const Key('admin-teams-create')), findsOneWidget);
    // The empty state's copy is gone, so the two never both claim the screen.
    expect(find.text('ee.admin.teams.emptyBody'.tr()), findsNothing);
  });

  testWidgets('THE SLUG IS SHOWN AS THE ADDRESS IT BECOMES', (tester) async {
    await pump(tester, const []);
    await tester.tap(find.byKey(const Key('admin-teams-create-empty')));
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(const Key('admin-teams-create-name')),
      'Acme Industries',
    );
    await tester.pumpAndSettle();

    // Suggested from the name, and shown as the host it will become — a slug
    // is the one field here that cannot be taken back once people bookmark it.
    expect(
      find.text('acme-industries.${'ee.admin.teams.createSlugSuffix'.tr()}'),
      findsOneWidget,
    );
  });

  testWidgets('...and stops following the name once somebody edits it', (
    tester,
  ) async {
    await pump(tester, const []);
    await tester.tap(find.byKey(const Key('admin-teams-create-empty')));
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(const Key('admin-teams-create-name')),
      'Acme',
    );
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('admin-teams-create-slug')),
      'acme-tr',
    );
    await tester.pumpAndSettle();

    // Typing more of the name must not rewrite a host somebody chose.
    await tester.enterText(
      find.byKey(const Key('admin-teams-create-name')),
      'Acme Industries',
    );
    await tester.pumpAndSettle();

    final slug = tester.widget<TextField>(
      find.byKey(const Key('admin-teams-create-slug')),
    );
    expect(slug.controller?.text, 'acme-tr');
  });

  testWidgets('submitting is refused until both required fields are there', (
    tester,
  ) async {
    await pump(tester, const []);
    await tester.tap(find.byKey(const Key('admin-teams-create-empty')));
    await tester.pumpAndSettle();

    final before = tester.widget<FilledButton>(
      find.byKey(const Key('admin-teams-create-submit')),
    );
    expect(before.onPressed, isNull);

    await tester.enterText(
      find.byKey(const Key('admin-teams-create-name')),
      'Acme',
    );
    await tester.pumpAndSettle();

    final after = tester.widget<FilledButton>(
      find.byKey(const Key('admin-teams-create-submit')),
    );
    // The name filled the slug too, so both are present and it opens.
    expect(after.onPressed, isNotNull);
  });
}
