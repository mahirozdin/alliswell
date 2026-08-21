import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:alliswell/src/features/workspaces/ui/workspace_switcher.dart';
import 'package:alliswell/src/features/workspaces/workspaces.dart';
import 'package:alliswell/src/theme/theme.dart';

/// EE-061 — the switch that lifted the "first workspace" v1 constraint.
///
/// Under ADR-0008 a unit IS a workspace, so this is the unit switcher. What is
/// pinned here is mostly what it does NOT do: it stays invisible for the
/// one-workspace case (every community build), and a selection that has gone
/// away resolves to something rather than to nothing.
///
/// That last one is not hypothetical. Losing a unit removes a workspace from
/// this list (EE-058), and a person whose selected unit was revoked must land
/// somewhere — an app that resolves to null there is an app with no data in it.
WorkspaceSummary ws(String id, String name) => WorkspaceSummary(
  id: id,
  name: name,
  slug: name.toLowerCase(),
  colorRgb: '#2563EB',
  icon: null,
  role: 'member',
);

final muhasebe = ws('01WSAAAAAAAAAAAAAAAAAAAAAA', 'Muhasebe');
final saha = ws('01WSBBBBBBBBBBBBBBBBBBBBBB', 'Saha Servis');

class _FixedSelection extends SelectedWorkspace {
  _FixedSelection(this._value);
  final String _value;
  @override
  String? build() => _value;
}

Widget harness(
  List<WorkspaceSummary> list, {
  String? selected,
}) => ProviderScope(
  overrides: [
    // The selection is PER USER, so the switcher reaches for the signed-in id
    // — which would otherwise mount the auth controller and its refresh timer.
    // Saying who is signed in is cheaper and more honest than silencing it.
    currentUserIdProvider.overrideWithValue('01USERAAAAAAAAAAAAAAAAAAAA'),
    workspacesProvider.overrideWith((ref) async => list),
    if (selected != null)
      selectedWorkspaceIdProvider.overrideWith(() => _FixedSelection(selected)),
  ],
  child: MaterialApp(
    theme: buildAwTheme(Brightness.light),
    home: const Scaffold(body: Center(child: AwWorkspaceSwitcher())),
  ),
);

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('one workspace draws NOTHING — a choice of one is furniture', (
    tester,
  ) async {
    await tester.pumpWidget(harness([muhasebe]));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('workspace-switcher')), findsNothing);
  });

  testWidgets('two workspaces: the switcher appears, naming the current one', (
    tester,
  ) async {
    await tester.pumpWidget(harness([muhasebe, saha]));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('workspace-switcher')), findsOneWidget);
    expect(find.text('Muhasebe'), findsOneWidget);
  });

  testWidgets('THE ACCEPTANCE: a two-unit person switches, and it sticks', (
    tester,
  ) async {
    late WidgetRef captured;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          currentUserIdProvider.overrideWithValue('01USERAAAAAAAAAAAAAAAAAAAA'),
          workspacesProvider.overrideWith((ref) async => [muhasebe, saha]),
        ],
        child: MaterialApp(
          theme: buildAwTheme(Brightness.light),
          home: Consumer(
            builder: (context, ref, _) {
              captured = ref;
              ref.watch(currentWorkspaceProvider);
              return const Scaffold(body: Center(child: AwWorkspaceSwitcher()));
            },
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(captured.read(currentWorkspaceProvider).value?.name, 'Muhasebe');

    await tester.tap(find.byKey(const Key('workspace-switcher')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(Key('workspace-option-${saha.id}')));
    await tester.pumpAndSettle();

    // Everything downstream reads this one provider — 16 call sites, and the
    // sync engine among them — so this assertion IS the switch.
    expect(captured.read(currentWorkspaceProvider).value?.name, 'Saha Servis');
  });

  testWidgets('a selection that no longer exists falls back, never to null', (
    tester,
  ) async {
    late WidgetRef captured;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          currentUserIdProvider.overrideWithValue('01USERAAAAAAAAAAAAAAAAAAAA'),
          workspacesProvider.overrideWith((ref) async => [muhasebe]),
          // The selected unit was revoked (EE-058) and its workspace is gone.
          selectedWorkspaceIdProvider.overrideWith(
            () => _FixedSelection(saha.id),
          ),
        ],
        child: MaterialApp(
          home: Consumer(
            builder: (context, ref, _) {
              captured = ref;
              // Watched, not read: an unwatched FutureProvider is never
              // subscribed to and its future never resolves in a test.
              ref.watch(currentWorkspaceProvider);
              return const SizedBox.shrink();
            },
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(captured.read(currentWorkspaceProvider).value?.id, muhasebe.id);
  });
}
