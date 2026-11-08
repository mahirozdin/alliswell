import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:alliswell/src/features/ee/team_origin.dart';
import 'package:alliswell/src/features/ee/ui/team_chip.dart';
import 'package:alliswell/src/features/workspaces/ui/workspace_switcher.dart';
import 'package:alliswell/src/features/workspaces/workspaces.dart';
import 'package:alliswell/src/i18n/i18n.dart';
import 'package:alliswell/src/theme/theme.dart';

/// R-12 — the workspace label in the section bar says one name, once.
///
/// A member in no unit has one workspace, so there is no switcher, and on a
/// phone the team chip was a bare dot: the bar said nothing about where the
/// person was. A manager on a desktop whose current workspace carries the
/// team's own name saw that name twice, in two chips side by side.
const _team = AwTeamOrigin(slug: 'demir-celik', displayName: 'Demir Çelik');

WorkspaceSummary _ws(String id, String name) => WorkspaceSummary(
  id: id,
  name: name,
  slug: name.toLowerCase(),
  colorRgb: '#2563EB',
  role: 'member',
);

final _root = _ws('01WSROOTAAAAAAAAAAAAAAAAAA', 'Demir Çelik');
final _bakim = _ws('01WSBAKIMAAAAAAAAAAAAAAAAA', 'Bakım');

Future<void> _pump(
  WidgetTester tester, {
  required double width,
  required List<WorkspaceSummary> workspaces,
}) async {
  tester.view.physicalSize = Size(width * 3, 2400);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
  final compact = width < 600;
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        teamIdentityProvider.overrideWithValue(_team),
        currentUserIdProvider.overrideWithValue('01USERAAAAAAAAAAAAAAAAAAAA'),
        workspacesProvider.overrideWith((ref) async => workspaces),
      ],
      child: MaterialApp(
        theme: buildAwTheme(Brightness.light),
        // The shell's two shapes (home_shell.dart buildSectionAppBar): on a
        // phone the identity rides under the title, wider it sits in the
        // action row as two siblings.
        home: Scaffold(
          appBar: AppBar(
            title: compact
                ? const AwWorkspaceSwitcher(
                    title: 'Ana Sayfa',
                    leading: AwTeamChip(),
                  )
                : const Text('Ana Sayfa'),
            actions: compact
                ? const []
                : const [AwWorkspaceSwitcher(), AwTeamChip()],
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    AwI18n.instance.setActiveCached(const Locale('tr'));
  });

  testWidgets('R-12: a phone with one workspace names the team under the '
      'title, not a bare dot', (tester) async {
    await _pump(tester, width: 393, workspaces: [_root]);
    expect(find.byKey(const Key('workspace-switcher')), findsNothing);
    expect(find.text('Demir Çelik'), findsOneWidget);
  });

  testWidgets('R-12: a phone with units keeps the unit’s name beside the dot', (
    tester,
  ) async {
    await _pump(tester, width: 393, workspaces: [_bakim, _root]);
    expect(find.text('Bakım'), findsOneWidget);
    // The team's name stays out: the line has the unit's.
    expect(find.text('Demir Çelik'), findsNothing);
  });

  testWidgets('R-12: on a desktop the team’s name is not said twice when the '
      'open workspace carries it', (tester) async {
    await _pump(tester, width: 1440, workspaces: [_root, _bakim]);
    expect(find.byKey(const Key('workspace-switcher')), findsOneWidget);
    expect(find.text('Demir Çelik'), findsOneWidget);
  });

  testWidgets('R-12: on a desktop in a unit both names stay — they say two '
      'different things', (tester) async {
    await _pump(tester, width: 1440, workspaces: [_bakim, _root]);
    expect(find.text('Bakım'), findsOneWidget);
    expect(find.text('Demir Çelik'), findsOneWidget);
  });
}
