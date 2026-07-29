import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:alliswell/src/core/retry.dart';
import 'package:alliswell/src/app.dart';
import 'package:alliswell/src/features/auth/data/secret_store.dart';
import 'package:alliswell/src/features/auth/data/token_storage.dart';
import 'package:alliswell/src/features/auth/providers.dart';

import '../auth/test_support.dart';
import 'fake_api.dart';
import '../../support/sync_overrides.dart';

Future<Widget> signedInAppWith(FakeApi api) async {
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
    child: const AllisWellApp(),
  );
}

Future<void> openProjects(WidgetTester tester) async {
  await tester.tap(find.text('Projects').last);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('projects list renders items and favorites, never a raw status', (
    tester,
  ) async {
    final api = FakeApi()
      ..seedProject(name: 'Website', isFavorite: true)
      ..seedProject(name: 'Ev İşleri', status: 'paused');

    await tester.pumpWidget(await signedInAppWith(api));
    await tester.pumpAndSettle();
    await openProjects(tester);

    expect(find.text('Website'), findsOneWidget);
    expect(find.text('Ev İşleri'), findsOneWidget);
    // OPH-184/193: the row used to print `project.status` verbatim, so a user
    // read the English enum "paused" in a Turkish app. The only state a person
    // recognises is archived, and that has its own localized label.
    expect(find.text('paused'), findsNothing);
    expect(find.byIcon(Icons.star), findsOneWidget); // favorite filled
    expect(find.byIcon(Icons.star_border), findsOneWidget);
  });

  testWidgets('the edit sheet has no status picker, and never sends one', (
    tester,
  ) async {
    final api = FakeApi()..seedProject(name: 'Düzenlenecek', status: 'paused');

    await tester.pumpWidget(await signedInAppWith(api));
    await tester.pumpAndSettle();
    await openProjects(tester);

    await tester.tap(
      find.byKey(Key('project-menu-${api.projects.first['id']}')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Edit'));
    await tester.pumpAndSettle();

    // OPH-193: the picker existed ONLY in edit mode — the same object had two
    // different forms — and it printed the raw server enum at the user.
    expect(find.byType(DropdownButtonFormField<String>), findsNothing);
    expect(find.text('paused'), findsNothing);

    await tester.enterText(find.byType(TextFormField).first, 'Yeni ad');
    await tester.tap(find.text('Save changes'));
    await tester.pumpAndSettle();

    final pushed = api.pushedMutations.where(
      (m) => m['entityType'] == 'project',
    );
    expect(pushed, isNotEmpty);
    for (final mutation in pushed) {
      expect(
        (mutation['patch'] as Map).containsKey('status'),
        isFalse,
        reason: 'a project changes state through the archive flow only',
      );
    }
    // The status the row already had is untouched — no migration, nothing lost.
    expect(api.projects.first['status'], 'paused');
    expect(api.projects.first['name'], 'Yeni ad');
  });

  testWidgets('FAB create flow syncs to the API and refreshes the list', (
    tester,
  ) async {
    final api = FakeApi();
    await tester.pumpWidget(await signedInAppWith(api));
    await tester.pumpAndSettle();
    await openProjects(tester);

    expect(find.text('No projects yet'), findsOneWidget);

    await tester.tap(find.byType(FloatingActionButton));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Name'),
      'Yeni Proje',
    );
    await tester.tap(find.text('Create project'));
    await tester.pumpAndSettle();

    expect(find.text('Yeni Proje'), findsOneWidget);
    // Local-first: the create reaches the server through one sync push.
    expect(api.projects.single['name'], 'Yeni Proje');
    expect(api.requests.where((r) => r.contains('/sync/push')), hasLength(1));
  });

  testWidgets('favorite star toggles through the outbox', (tester) async {
    final api = FakeApi()..seedProject(name: 'Yıldızsız');
    await tester.pumpWidget(await signedInAppWith(api));
    await tester.pumpAndSettle();
    await openProjects(tester);

    await tester.tap(find.byIcon(Icons.star_border));
    await tester.pumpAndSettle();

    expect(find.byIcon(Icons.star), findsOneWidget);
    expect(api.projects.single['isFavorite'], isTrue);
    expect(api.requests.any((r) => r.contains('/sync/push')), isTrue);
  });

  testWidgets('project detail: README placeholder, live Tasks with quick add', (
    tester,
  ) async {
    final api = FakeApi()..seedProject(name: 'Detaylı');
    await tester.pumpWidget(await signedInAppWith(api));
    await tester.pumpAndSettle();
    await openProjects(tester);

    await tester.tap(find.text('Detaylı'));
    await tester.pumpAndSettle();

    // 'Notes' also exists as a nav label — scope tab assertions to the TabBar.
    Finder inTabBar(String label) =>
        find.descendant(of: find.byType(TabBar), matching: find.text(label));
    expect(inTabBar('Overview'), findsOneWidget);
    expect(inTabBar('Tasks'), findsOneWidget);
    expect(inTabBar('Notes'), findsOneWidget);
    // Overview opens on the README section (no README yet → create button).
    expect(find.byKey(const Key('create-readme')), findsOneWidget);

    // Tasks tab is a real list now — quick-add creates a task IN this project.
    await tester.tap(inTabBar('Tasks'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('project-quick-add')),
      'Proje görevi',
    );
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();

    expect(find.text('Proje görevi'), findsOneWidget);
    expect(api.tasks.single['projectId'], api.projects.single['id']);
  });

  testWidgets('Create README spawns a linked note and opens its editor', (
    tester,
  ) async {
    final api = FakeApi()..seedProject(name: 'Dokümanlı');
    await tester.pumpWidget(await signedInAppWith(api));
    await tester.pumpAndSettle();
    await openProjects(tester);
    await tester.tap(find.text('Dokümanlı'));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('create-readme')));
    await tester.pumpAndSettle();

    // A note titled after the project was created, attached to it, and the
    // project now references it as its README.
    expect(api.notes.single['projectId'], api.projects.single['id']);
    expect(api.notes.single['title'], 'Dokümanlı');
    expect(api.projects.single['readmeNoteId'], api.notes.single['id']);
    // We landed in the note editor.
    expect(find.byKey(const Key('note-title')), findsOneWidget);
  });

  testWidgets('project Notes tab captures a new note in the project', (
    tester,
  ) async {
    final api = FakeApi()..seedProject(name: 'Notlu');
    await tester.pumpWidget(await signedInAppWith(api));
    await tester.pumpAndSettle();
    await openProjects(tester);
    await tester.tap(find.text('Notlu'));
    await tester.pumpAndSettle();

    await tester.tap(
      find.descendant(of: find.byType(TabBar), matching: find.text('Notes')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('project-add-note')));
    await tester.pumpAndSettle();

    expect(api.notes.single['projectId'], api.projects.single['id']);
    expect(find.byKey(const Key('note-title')), findsOneWidget);
  });

  testWidgets('returning to a tab shows its root, not the last detail (OPH-108)', (
    tester,
  ) async {
    final api = FakeApi()..seedProject(name: 'Deneme');
    await tester.pumpWidget(await signedInAppWith(api));
    await tester.pumpAndSettle();
    await openProjects(tester);

    // Open the project detail (its Overview/Tasks/Notes TabBar marks "detail").
    await tester.tap(find.text('Deneme'));
    await tester.pumpAndSettle();
    expect(find.byType(TabBar), findsOneWidget);

    // Switch away (Inbox has no name clash) and back to Projects.
    await tester.tap(find.text('Inbox').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Projects').last);
    await tester.pumpAndSettle();

    // We land on the projects LIST (no detail tabs), not the reopened project.
    expect(find.byType(TabBar), findsNothing);
    expect(find.text('Deneme'), findsOneWidget); // the list row
  });

  testWidgets(
    'a README is hidden from the notes list, shown under READMEs (OPH-109)',
    (tester) async {
      final api = FakeApi()..seedProject(name: 'Dokümanlı');
      await tester.pumpWidget(await signedInAppWith(api));
      await tester.pumpAndSettle();
      await openProjects(tester);
      await tester.tap(find.text('Dokümanlı'));
      await tester.pumpAndSettle();

      // Create the README (its title defaults to the project name) — the editor
      // is pushed on top of the project (OPH-109), so pop back to the project.
      await tester.tap(find.byKey(const Key('create-readme')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('note-title')), findsOneWidget);
      Navigator.of(tester.element(find.byKey(const Key('note-title')))).pop();
      await tester.pumpAndSettle();

      // Leave the project (Inbox has no name clash) and open the Notes section.
      await tester.tap(find.text('Inbox').last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Notes').last);
      await tester.pumpAndSettle();

      // Default (All) hides the README; the READMEs chip surfaces it.
      expect(find.text('Dokümanlı'), findsNothing);
      await tester.tap(find.text('READMEs'));
      await tester.pumpAndSettle();
      expect(find.text('Dokümanlı'), findsOneWidget);
    },
  );

  testWidgets(
    'archiving a project moves it behind the Archived chip (OPH-110)',
    (tester) async {
      final api = FakeApi()..seedProject(name: 'Arşivlenecek');
      await tester.pumpWidget(await signedInAppWith(api));
      await tester.pumpAndSettle();
      await openProjects(tester);
      expect(find.text('Arşivlenecek'), findsOneWidget);

      // Row menu → Archive… → confirm (no cascade → optimistic status flip).
      await tester.tap(find.byType(PopupMenuButton<String>).first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Archive…'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('archive-confirm')));
      await tester.pumpAndSettle();

      // Gone from the default (Active) view, moved to archived on the server.
      expect(find.text('Arşivlenecek'), findsNothing);
      expect(api.projects.single['status'], 'archived');

      // The Archived chip surfaces it, with an Unarchive… action.
      await tester.tap(find.text('Archived'));
      await tester.pumpAndSettle();
      expect(find.text('Arşivlenecek'), findsOneWidget);
      await tester.tap(find.byType(PopupMenuButton<String>).first);
      await tester.pumpAndSettle();
      expect(find.text('Unarchive…'), findsOneWidget);
    },
  );

  testWidgets(
    'archiving is the ONLY way to change a project\'s state (OPH-110/193)',
    (tester) async {
      final api = FakeApi()..seedProject(name: 'Düzenlenecek');
      await tester.pumpWidget(await signedInAppWith(api));
      await tester.pumpAndSettle();
      await openProjects(tester);

      await tester.tap(find.byType(PopupMenuButton<String>).first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Edit'));
      await tester.pumpAndSettle();

      // OPH-110 kept 'archived' out of the dropdown so its cascade question
      // could never be skipped. OPH-193 finished the thought: there is no
      // dropdown at all, so no status is reachable except through the flow.
      expect(find.text('active'), findsNothing);
      expect(find.text('paused'), findsNothing);
      expect(find.text('archived'), findsNothing);
      expect(find.byType(DropdownButtonFormField<String>), findsNothing);
    },
  );

  testWidgets(
    'the edit sheet opens IN FRONT of the shell, and can be typed into (OPH-212)',
    (tester) async {
      // Round 12 #4: the sheet appeared UNDER the popup menu — really, under
      // the shell's own glass bar and FAB, because `showModalBottomSheet`
      // defaults to the nearest navigator and every project surface lives
      // inside a StatefulShellBranch. `findsOneWidget` would have passed the
      // whole time it was broken, so this test TOUCHES the sheet: `tap` throws
      // if the target is covered or off-screen, and `enterText` needs a real
      // focus. That is the difference between "it is in the tree" and "the
      // user can use it".
      tester.view.physicalSize = const Size(390, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      final api = FakeApi()..seedProject(name: 'Düzenlenecek');
      await tester.pumpWidget(await signedInAppWith(api));
      await tester.pumpAndSettle();
      await openProjects(tester);

      await tester.tap(find.byType(PopupMenuButton<String>).first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Edit'));
      await tester.pumpAndSettle();

      final nameField = find.byType(TextFormField).first;
      await tester.tap(nameField); // would throw if something covered it
      await tester.enterText(nameField, 'Yeni ad');
      await tester.pumpAndSettle();
      expect(find.text('Yeni ad'), findsOneWidget);

      final save = find.widgetWithText(FilledButton, 'Save changes');
      await tester.ensureVisible(save);
      await tester.tap(save);
      await tester.pumpAndSettle();
      expect(api.projects.first['name'], 'Yeni ad');
    },
  );
}
