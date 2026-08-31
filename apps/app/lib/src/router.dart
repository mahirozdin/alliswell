import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'core/deep_link.dart';
import 'core/modal_observer.dart';
import 'features/auth/providers.dart';
import 'features/auth/ui/login_screen.dart';
import 'features/auth/ui/register_screen.dart';
import 'features/ee/admin/admin_providers.dart';
import 'features/ee/admin/ui/admin_login_screen.dart';
import 'features/ee/admin/ui/admin_packages_screen.dart';
import 'features/ee/admin/ui/admin_shell.dart';
import 'features/ee/admin/ui/admin_teams_screen.dart';
import 'features/ee/admin/ui/admin_usage_screen.dart';
import 'features/ee/ui/join_screen.dart';
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
import 'features/ee/ui/team_roles_screen.dart';
import 'features/ee/ui/task_history_screen.dart';
import 'features/ee/ui/assigned_to_me_screen.dart';
import 'features/ee/ui/notification_center_screen.dart';
import 'features/ee/ui/notification_prefs_screen.dart';
import 'features/ee/ui/shared_with_me_screen.dart';
import 'features/ee/ui/team_units_screen.dart';
import 'features/ee/ui/team_settings_screen.dart';
import 'features/ee/ui/team_members_screen.dart';
import 'features/ee/ui/team_services_screen.dart';
import 'features/ee/ui/portal_links_screen.dart';
import 'features/ee/ui/meeting_screen.dart';
import 'features/ee/ui/team_ai_keys_screen.dart';
import 'features/ee/ui/team_identity_screen.dart';
import 'features/ee/ui/sla_admin_screen.dart';
import 'features/ee/ui/my_tickets_screen.dart';
import 'features/ee/ui/ticket_queue_screen.dart';
import 'features/ee/ui/team_invites_screen.dart';
import 'features/api_keys/ui/api_keys_screen.dart';
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

/// The operator console lives on its own realm (EE-033): a different identity
/// table, a different token audience, and therefore a different session on
/// this device. `/admin` is reachable while the app is signed OUT — on a
/// self-hosted install the operator may hold no AllisWell account at all —
/// and is NOT reachable by a signed-in workspace user, who has none of the
/// credentials it needs.
const String kAdminRoot = '/admin';
const String kAdminLogin = '/admin/login';

bool isAdminLocation(String location) =>
    location == kAdminRoot || location.startsWith('$kAdminRoot/');

/// Pure redirect policy (unit-tested in test/router_redirect_test.dart):
/// admin locations answer to the operator session ALONE; then restoring →
/// splash; signed out → login/register only; signed in → keep auth/splash
/// pages unreachable.
String? computeAuthRedirect({
  required bool isRestoring,
  required bool isLoggedIn,
  required String location,
  bool isInstanceAdmin = false,
}) {
  // Answered FIRST and entirely on its own terms: the person's session — even
  // mid-restore — decides nothing here, in either direction.
  if (isAdminLocation(location)) {
    if (location == kAdminLogin) return isInstanceAdmin ? kAdminRoot : null;
    return isInstanceAdmin ? null : kAdminLogin;
  }
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
  // The operator session moves the router too — signing in or out of the
  // console must land somewhere without a manual navigation (EE-033).
  ref.listen(adminSessionProvider, (_, _) => authChanged.value++);
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
        isInstanceAdmin: ref.read(isInstanceAdminProvider),
      );
      // The operator console never participates in the deep-link replay or
      // the pending-destination machinery below: those exist to carry a
      // PERSON back to what they tapped, and an operator's session is not
      // theirs.
      if (isAdminLocation(state.matchedLocation)) return decision;
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
      // EE-018: a team invite's landing place. Not in `_authLocations` on
      // purpose — an invite arriving signed-out is remembered by the pending
      // deep-link machinery and replayed after sign-in, which is exactly the
      // flow an invite wants.
      GoRoute(
        path: '/join/:token',
        builder: (context, state) =>
            _page(JoinTeamScreen(token: state.pathParameters['token'] ?? '')),
      ),
      // EE-033 — the instance-operator console. Outside the shell on purpose:
      // it is not one of the person's five sections, it has its own frame,
      // and nothing in it should be reachable from theirs.
      GoRoute(
        path: kAdminLogin,
        builder: (context, state) => _page(const AdminLoginScreen()),
      ),
      ShellRoute(
        builder: (context, state, child) =>
            _page(AdminShell(location: state.matchedLocation, child: child)),
        routes: [
          GoRoute(
            path: kAdminRoot,
            builder: (context, state) => const AdminUsageScreen(),
          ),
          GoRoute(
            path: '/admin/teams',
            builder: (context, state) => const AdminTeamsScreen(),
            routes: [
              GoRoute(
                path: ':teamId',
                builder: (context, state) => AdminTeamDetailScreen(
                  teamId: state.pathParameters['teamId'] ?? '',
                ),
              ),
            ],
          ),
          GoRoute(
            path: '/admin/packages',
            builder: (context, state) => const AdminPackagesScreen(),
          ),
        ],
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
                    // EE-084. The BRANCH always exists — only the navigation
                    // destination is conditional (see `home_shell`), because
                    // dropping a branch would renumber every one after it.
                    AppSection.tickets => const EeTicketQueueScreen(),
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
                      // OPH-251: somebody else's file, in our own editor.
                      // Before ':noteId' for the same reason 'new' is.
                      GoRoute(
                        path: 'file',
                        builder: (context, state) =>
                            _page(const NoteEditorScreen(external: true)),
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
      // OPH-260 (DESIGN §32 S3): the groups are real routes, so a settings
      // URL keeps working and each page is somewhere you can be sent.
      GoRoute(
        path: '/settings/account',
        builder: (context, state) => _page(const SettingsAccountScreen()),
      ),
      GoRoute(
        path: '/settings/general',
        builder: (context, state) => _page(const SettingsGeneralScreen()),
      ),
      GoRoute(
        path: '/settings/notifications',
        builder: (context, state) => _page(const SettingsNotificationsScreen()),
      ),
      GoRoute(
        path: '/settings/integrations',
        builder: (context, state) => _page(const SettingsIntegrationsScreen()),
      ),
      GoRoute(
        path: '/settings/data',
        builder: (context, state) => _page(const SettingsDataScreen()),
      ),
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
      // EE-042: the team-admin area. Real routes like every other settings
      // group (§32 S3), so a team URL keeps working and each page is
      // somewhere somebody can be sent. Nothing links here unless the
      // instance is entitled AND the caller is a team admin — but the routes
      // themselves exist, because a 404 on a link an admin was sent is worse
      // than a screen that says "not yours".
      GoRoute(
        path: '/settings/team',
        builder: (context, state) => _page(const EeTeamSettingsScreen()),
      ),
      GoRoute(
        path: '/settings/team/members',
        builder: (context, state) => _page(const EeTeamMembersScreen()),
      ),
      GoRoute(
        path: '/settings/team/invites',
        builder: (context, state) => _page(const EeTeamInvitesScreen()),
      ),
      // EE-053: roles and their grant matrix.
      GoRoute(
        path: '/settings/team/roles',
        builder: (context, state) => _page(const EeTeamRolesScreen()),
      ),
      // EE-082: the service catalogue — what people may ask for, and which
      // unit answers each one.
      GoRoute(
        path: '/settings/team/services',
        builder: (context, state) => _page(const EeTeamServicesScreen()),
      ),
      // EE-099: what an admin may edit about a promise — policies, business
      // calendars and health monitors, all behind `sla.manage`.
      GoRoute(
        path: '/settings/team/sla',
        builder: (context, state) => _page(const EeSlaAdminScreen()),
      ),
      // EE-106: the public request links — create, pause, extend, revoke,
      // behind `portal.manage_links`. The URL a link carries is shown once at
      // creation and never again, because the server keeps only its digest.
      GoRoute(
        path: '/settings/team/portal',
        builder: (context, state) => _page(const EePortalLinksScreen()),
      ),
      // EE-111: the team's AI provider keys and the personal-key policy,
      // behind `team.manage_ai_keys`. A key goes in once and is never shown
      // again — the server can recover it and declines to, so the screen shows
      // four characters and offers to replace rather than to reveal.
      GoRoute(
        path: '/settings/team/ai-keys',
        builder: (context, state) => _page(const EeTeamAiKeysScreen()),
      ),
      // OPH-287: the team's identity sources — connect, TEST, then switch on,
      // behind `team.manage_identity`. Its own row rather than a section of
      // the security screen: which system answers "is this person who they
      // say" is a different authority from the password rules, and often a
      // different person's job.
      GoRoute(
        path: '/settings/team/identity',
        builder: (context, state) => _page(const EeTeamIdentityScreen()),
      ),
      // EE-115: one meeting — what it decided, and who said what. A route
      // rather than a tab, for the reason EE-069's task history is one: this
      // is a destination people link to and come back to, not a mode of
      // another screen.
      GoRoute(
        path: '/meetings/:meetingId',
        builder: (context, state) => _page(
          EeMeetingScreen(meetingId: state.pathParameters['meetingId']!),
        ),
      ),
      // EE-061: what other units shared with this one. Reachable by anyone in
      // a unit — receiving something is not an admin act.
      GoRoute(
        path: '/settings/team/shared',
        builder: (context, state) => _page(const EeSharedWithMeScreen()),
      ),
      // EE-069: one task's whole story. A route rather than a tab on the
      // detail screen — see the screen's own header for why.
      GoRoute(
        path: '/tasks/:taskId/history',
        builder: (context, state) =>
            _page(EeTaskHistoryScreen(taskId: state.pathParameters['taskId']!)),
      ),
      // EE-077: the notification centre and its preferences. Two routes
      // rather than a screen with a tab: the centre is a work surface people
      // reach constantly and the preferences are a settings page they visit
      // twice, and a tab bar would charge the first for the second.
      GoRoute(
        path: '/notifications',
        builder: (context, state) => _page(const EeNotificationCenterScreen()),
      ),
      // `/settings/team/...` and not `/settings/notifications`: that path is
      // already core's, for the device's own alarms. Two different things share
      // the word "notification" here — a local reminder this phone rings, and a
      // message the server sends about other people's actions — and giving them
      // one screen would make "turn these off" ambiguous in the only place it
      // must not be.
      GoRoute(
        path: '/settings/team/notifications',
        builder: (context, state) => _page(const EeNotificationPrefsScreen()),
      ),
      // EE-068: "assigned to me". Not an admin route and not a settings
      // screen in spirit — it is a work list — but it lives under the team
      // path because it only exists where there is a team to be assigned by.
      GoRoute(
        path: '/settings/team/assignments',
        builder: (context, state) => _page(const EeAssignedToMeScreen()),
      ),
      // EE-087: "my requests". Reachable by anyone in a team — asking for
      // something is the least privileged act in the product.
      GoRoute(
        path: '/settings/team/my-tickets',
        builder: (context, state) => _page(const EeMyTicketsScreen()),
      ),
      // EE-057: units. The one team route a NON-admin can legitimately reach
      // — a delegated unit manager is an ordinary member everywhere else, so
      // this path is gated by what the server hands back, not by the role.
      GoRoute(
        path: '/settings/team/units',
        builder: (context, state) => _page(const EeTeamUnitsScreen()),
      ),
      // OPH-220: AI settings — connections, models, the MCP connector URL.
      GoRoute(
        path: '/settings/ai',
        builder: (context, state) => _page(const AiSettingsScreen()),
      ),
      // OPH-265: API access — the keys a person hands to their own scripts.
      GoRoute(
        path: '/settings/api-keys',
        builder: (context, state) => _page(const ApiKeysScreen()),
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
