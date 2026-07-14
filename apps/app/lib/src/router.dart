import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'features/auth/providers.dart';
import 'features/auth/ui/login_screen.dart';
import 'features/auth/ui/register_screen.dart';
import 'features/notes/ui/note_editor_screen.dart';
import 'features/notes/ui/notes_screen.dart';
import 'features/projects/ui/project_detail_screen.dart';
import 'features/projects/ui/projects_screen.dart';
import 'features/tasks/providers.dart';
import 'features/tasks/ui/task_detail_screen.dart';
import 'features/tasks/ui/task_list_screen.dart';
import 'screens/home_shell.dart';
import 'screens/settings_screen.dart';
import 'screens/splash_screen.dart';
import 'sections.dart';

const _authLocations = {'/login', '/register'};

/// Pure redirect policy (unit-tested in test/router_redirect_test.dart):
/// restoring → splash; signed out → login/register only; signed in → keep
/// auth/splash pages unreachable.
String? computeAuthRedirect({
  required bool isRestoring,
  required bool isLoggedIn,
  required String location,
}) {
  if (isRestoring) return location == '/splash' ? null : '/splash';
  if (!isLoggedIn) {
    return _authLocations.contains(location) ? null : '/login';
  }
  if (location == '/splash' || _authLocations.contains(location)) {
    return AppSection.today.path;
  }
  return null;
}

/// App navigation. The five main sections live in an indexed-stack shell so
/// each keeps its own navigation state; Settings is pushed on top. Everything
/// outside /login, /register and /splash requires a session (OPH-024).
final routerProvider = Provider<GoRouter>((ref) {
  // go_router re-evaluates `redirect` whenever this notifier fires.
  final authChanged = ValueNotifier(0);
  ref.listen(authControllerProvider, (_, _) => authChanged.value++);
  ref.onDispose(authChanged.dispose);

  final router = GoRouter(
    initialLocation: '/splash',
    refreshListenable: authChanged,
    redirect: (context, state) {
      final auth = ref.read(authControllerProvider);
      return computeAuthRedirect(
        isRestoring: auth.isLoading,
        isLoggedIn: auth.value != null,
        location: state.matchedLocation,
      );
    },
    routes: [
      GoRoute(
        path: '/splash',
        builder: (context, state) => const SplashScreen(),
      ),
      GoRoute(path: '/login', builder: (context, state) => const LoginScreen()),
      GoRoute(
        path: '/register',
        builder: (context, state) => const RegisterScreen(),
      ),
      StatefulShellRoute.indexedStack(
        builder: (context, state, navigationShell) =>
            HomeShell(navigationShell: navigationShell),
        branches: [
          for (final section in AppSection.values)
            StatefulShellBranch(
              routes: [
                GoRoute(
                  path: section.path,
                  builder: (context, state) => switch (section) {
                    AppSection.inbox => const TaskListScreen(
                      kind: TaskListKind.inbox,
                    ),
                    AppSection.today => const TaskListScreen(
                      kind: TaskListKind.today,
                    ),
                    AppSection.upcoming => const TaskListScreen(
                      kind: TaskListKind.upcoming,
                    ),
                    AppSection.projects => const ProjectsScreen(),
                    AppSection.notes => const NotesScreen(),
                  },
                  routes: [
                    if (section == AppSection.projects)
                      GoRoute(
                        path: ':projectId',
                        builder: (context, state) => ProjectDetailScreen(
                          projectId: state.pathParameters['projectId']!,
                        ),
                      ),
                    if (section == AppSection.notes) ...[
                      // 'new' must precede ':noteId' so it wins the match.
                      GoRoute(
                        path: 'new',
                        builder: (context, state) => const NoteEditorScreen(),
                      ),
                      GoRoute(
                        path: ':noteId',
                        builder: (context, state) => NoteEditorScreen(
                          noteId: state.pathParameters['noteId']!,
                        ),
                      ),
                    ],
                  ],
                ),
              ],
            ),
        ],
      ),
      GoRoute(
        path: '/settings',
        builder: (context, state) => const SettingsScreen(),
      ),
      // Pushed on top of whichever list opened it (Inbox/Today/Upcoming/…).
      GoRoute(
        path: '/tasks/:taskId',
        builder: (context, state) =>
            TaskDetailScreen(taskId: state.pathParameters['taskId']!),
      ),
    ],
  );
  ref.onDispose(router.dispose);
  return router;
});
