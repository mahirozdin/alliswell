import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'core/deep_link.dart';
import 'core/modal_observer.dart';
import 'features/auth/providers.dart';
import 'features/auth/ui/login_screen.dart';
import 'features/auth/ui/register_screen.dart';
import 'features/files/ui/files_screen.dart';
import 'features/home/home_screen.dart';
import 'features/notes/ui/markdown_import_screen.dart';
import 'features/notes/ui/note_editor_screen.dart';
import 'features/notes/ui/notes_screen.dart';
import 'features/projects/ui/project_detail_screen.dart';
import 'features/projects/ui/projects_screen.dart';
import 'features/tasks/ui/completed_screen.dart';
import 'features/tasks/ui/task_detail_screen.dart';
import 'features/tasks/ui/task_list_screen.dart';
import 'screens/home_shell.dart';
import 'features/settings/reminder_settings_screen.dart';
import 'features/ai/ui/ai_settings_screen.dart';
import 'features/ai/ui/share_log_screen.dart';
import 'notifications/alarm_log_screen.dart';
import 'screens/settings_screen.dart';
import 'screens/splash_screen.dart';
import 'sections.dart';
import 'widgets/glass.dart';
import 'widgets/status_views.dart';
import 'i18n/i18n.dart';

const _authLocations = {'/login', '/register'};

/// Where an unroutable location lands. A real route, so the screen it shows is
/// ours — themed, localized and with an exit that works.
const String _kNotFound = '/not-found';

/// Every route is wrapped in its own opaque wash (OPH-194, DESIGN §21 T1).
/// A route that lets the route beneath it show through is what made navigation
/// look like it was hanging; making that impossible is one wrapper, applied here
/// rather than trusted to each screen.
Widget _page(Widget child) => AwPageBackground(child: child);

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
    return AppSection.home.path;
  }
  return null;
}

/// Where a deep link should land once the app is ready for it (OPH-189).
///
/// A link that arrives while signed out is NOT dropped: it waits here, the auth
/// redirect sends the user to /login, and the destination is replayed after
/// sign-in. Losing the tap because the session had expired would be its own
/// small betrayal.
class PendingDeepLink extends Notifier<String?> {
  @override
  String? build() => null;

  void remember(String location) => state = location;

  /// Reads and clears in one step — a destination may only be replayed once.
  String? take() {
    final pending = state;
    if (pending != null) state = null;
    return pending;
  }
}

final pendingDeepLinkProvider = NotifierProvider<PendingDeepLink, String?>(
  PendingDeepLink.new,
);

/// The root navigator, exposed so surfaces that live ABOVE the router — the
/// quick-access bubble (OPH-200) — can still open a sheet. They have no
/// `Navigator` ancestor of their own; `Navigator.of` resolves this context to
/// the navigator itself.
final awRootNavigatorKey = GlobalKey<NavigatorState>(debugLabel: 'aw-root');

/// App navigation. The five main sections live in an indexed-stack shell so
/// each keeps its own navigation state; Settings is pushed on top. Everything
/// outside /login, /register and /splash requires a session (OPH-024).
final routerProvider = Provider<GoRouter>((ref) {
  // go_router re-evaluates `redirect` whenever this notifier fires.
  final authChanged = ValueNotifier(0);
  ref.listen(authControllerProvider, (_, _) => authChanged.value++);
  ref.onDispose(authChanged.dispose);

  final router = GoRouter(
    navigatorKey: awRootNavigatorKey,
    // ONE observer, on the root only: go_router merges root observers into
    // every branch navigator, so this sees dialogs (root) and section sheets
    // (branch) alike — which is what lets the bubble hide behind modals.
    observers: [ref.watch(awModalObserverProvider)],
    initialLocation: '/splash',
    refreshListenable: authChanged,
    redirect: (context, state) {
      final auth = ref.read(authControllerProvider);
      final decision = computeAuthRedirect(
        isRestoring: auth.isLoading,
        isLoggedIn: auth.value != null,
        location: state.matchedLocation,
      );
      // OPH-189: a deep link that arrived signed-out waits, then wins once the
      // session exists. `computeAuthRedirect` stays pure and separately tested;
      // this is the one stateful layer on top of it.
      if (auth.value != null &&
          (decision == AppSection.home.path || decision == null)) {
        final pending = ref.read(pendingDeepLinkProvider.notifier).take();
        if (pending != null && pending != state.matchedLocation) return pending;
      }
      if (auth.value == null && !auth.isLoading) {
        final wanted = awRouteForUri(state.uri) ?? state.matchedLocation;
        if (!_authLocations.contains(wanted) && wanted != '/splash') {
          ref.read(pendingDeepLinkProvider.notifier).remember(wanted);
        }
      }
      return decision;
    },
    // OPH-189: an incoming `alliswell://…` URL reaches go_router as a raw
    // LOCATION, which is why the widget's tap produced "No route for
    // alliswell://open/". Resolve it before matching; anything unresolvable is
    // a no-op (the sender may be a newer app), never an error screen.
    //
    // `onException` rather than `errorBuilder` — go_router accepts exactly ONE
    // of them, and only this one can redirect, which is the whole point here.
    // Genuinely unroutable locations land on our own `/not-found` screen, so
    // the "error page" is a real route with a working way out.
    onException: (context, state, router) {
      final uri = state.uri;
      final resolved = awRouteForUri(uri);
      if (resolved != null) {
        router.go(resolved);
        return;
      }
      if (uri.scheme == kAwScheme) {
        // Ours but unroutable — open normally rather than strand the user.
        router.go(AppSection.home.path);
        return;
      }
      router.go(_kNotFound, extra: uri.toString());
    },
    routes: [
      // A real route for `/` — go_router's own default error page links here,
      // so before this existed the recovery button produced a SECOND error
      // ("no routes for location: /"). The error screen's own way out was
      // broken.
      GoRoute(
        path: '/',
        redirect: (context, state) =>
            ref.read(authControllerProvider).value != null
            ? AppSection.home.path
            : '/login',
      ),
      GoRoute(
        path: _kNotFound,
        builder: (context, state) =>
            _page(_RouteNotFound(location: state.extra as String?)),
      ),
      GoRoute(
        path: '/splash',
        builder: (context, state) => _page(const SplashScreen()),
      ),
      GoRoute(
        path: '/login',
        builder: (context, state) => _page(const LoginScreen()),
      ),
      GoRoute(
        path: '/register',
        builder: (context, state) => _page(const RegisterScreen()),
      ),
      StatefulShellRoute.indexedStack(
        builder: (context, state, navigationShell) =>
            // One background for the whole shell: switching sections is an
            // IndexedStack swap, not a route transition (OPH-108), so the five
            // branches legitimately share one wash.
            _page(HomeShell(navigationShell: navigationShell)),
        branches: [
          for (final section in AppSection.values)
            StatefulShellBranch(
              routes: [
                GoRoute(
                  path: section.path,
                  builder: (context, state) => switch (section) {
                    AppSection.home => const HomeScreen(),
                    AppSection.inbox => const InboxScreen(),
                    AppSection.files => const FilesScreen(),
                    AppSection.projects => const ProjectsScreen(),
                    AppSection.notes => const NotesScreen(),
                  },
                  routes: [
                    // OPH-199: a folder shortcut needs an ADDRESS, not a
                    // provider — tapping the Files tab calls
                    // `goBranch(initialLocation: true)`, which resets the
                    // location but would not reset lifted state, so a shortcut
                    // would keep re-opening its folder after the user asked
                    // for the section root (OPH-108's rule). The route is the
                    // entry point, not an address per breadcrumb level.
                    if (section == AppSection.files)
                      GoRoute(
                        path: 'folder/:folderId',
                        builder: (context, state) => _page(
                          FilesScreen(
                            initialFolderId: state.pathParameters['folderId']!,
                          ),
                        ),
                      ),
                    if (section == AppSection.projects)
                      GoRoute(
                        path: ':projectId',
                        builder: (context, state) => _page(
                          ProjectDetailScreen(
                            projectId: state.pathParameters['projectId']!,
                          ),
                        ),
                      ),
                    if (section == AppSection.notes) ...[
                      // Round 16 follow-up: the markdown viewer. Like 'new', it
                      // must precede ':noteId' so it wins the match.
                      GoRoute(
                        path: 'import',
                        builder: (context, state) =>
                            _page(const MarkdownImportScreen()),
                      ),
                      // 'new' must precede ':noteId' so it wins the match.
                      GoRoute(
                        path: 'new',
                        builder: (context, state) =>
                            _page(const NoteEditorScreen()),
                      ),
                      GoRoute(
                        path: ':noteId',
                        builder: (context, state) => _page(
                          NoteEditorScreen(
                            noteId: state.pathParameters['noteId']!,
                          ),
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
        builder: (context, state) => _page(const SettingsScreen()),
      ),
      // OPH-176: the alarm log — a diagnostic surface, pushed from Settings.
      GoRoute(
        path: '/settings/alarm-log',
        builder: (context, state) => _page(const AlarmLogScreen()),
      ),
      // OPH-242: the share log — the same kind of surface, for the same kind of
      // unanswerable report ("I shared something and nothing happened").
      GoRoute(
        path: '/settings/share-log',
        builder: (context, state) => _page(const ShareLogScreen()),
      ),
      // OPH-179: how insistent alarms are — one destination (DESIGN §18 N1).
      GoRoute(
        path: '/settings/reminders',
        builder: (context, state) => _page(const ReminderSettingsScreen()),
      ),
      // OPH-186 (DESIGN §20 C4): everything you have finished. Behind Settings
      // rather than a sixth tab — round 1's "one rich Home, few tabs" holds.
      GoRoute(
        path: '/settings/completed',
        builder: (context, state) => _page(const CompletedScreen()),
      ),
      // OPH-220: AI settings — connections, models, the MCP connector URL.
      GoRoute(
        path: '/settings/ai',
        builder: (context, state) => _page(const AiSettingsScreen()),
      ),
      // Pushed on top of whichever list opened it (Inbox/Today/Upcoming/…).
      GoRoute(
        path: '/tasks/:taskId',
        builder: (context, state) =>
            _page(TaskDetailScreen(taskId: state.pathParameters['taskId']!)),
      ),
      // README editing stays in the project's context (OPH-109): the Overview
      // pushes this full-screen and back pops to the Overview, instead of
      // switching to the Notes branch.
      GoRoute(
        path: '/edit-note/:noteId',
        builder: (context, state) =>
            _page(NoteEditorScreen(noteId: state.pathParameters['noteId']!)),
      ),
    ],
  );
  ref.onDispose(router.dispose);
  return router;
});

/// The router's own error screen (OPH-189).
///
/// go_router's default is an unthemed, untranslated page whose "Home" button
/// navigates to `/` — which, until this task, was not a route either. So the
/// error screen produced an error. This one uses the shared state widget and
/// goes somewhere that exists.
class _RouteNotFound extends StatelessWidget {
  const _RouteNotFound({this.location});

  final String? location;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(),
      body: AwErrorState(
        message: 'error.routeNotFound'.tr(),
        retryLabel: 'error.goHome'.tr(),
        retryIcon: Icons.home_outlined,
        onRetry: () => GoRouter.of(context).go(AppSection.home.path),
        // The offending location in small print: useful in a bug report,
        // invisible to everyone else.
        detail: location,
      ),
    );
  }
}
