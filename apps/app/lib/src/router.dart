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
import 'features/ee/admin/ui/admin_leads_screen.dart';
import 'features/ee/admin/ui/admin_packages_screen.dart';
import 'features/ee/admin/ui/admin_shell.dart';
import 'features/ee/admin/ui/admin_teams_screen.dart';
import 'features/ee/admin/ui/admin_usage_screen.dart';
import 'features/ee/ui/join_screen.dart';
import 'features/ee/ui/team_address_views.dart';
import 'features/files/ui/files_screen.dart';
import 'features/home/home_create.dart';
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
import 'features/ee/ui/notification_center_screen.dart';
import 'features/ee/ui/notification_prefs_screen.dart';
import 'features/ee/ui/shared_with_me_screen.dart';
import 'features/ee/ui/team_units_screen.dart';
import 'features/ee/ui/asset_detail_screen.dart';
import 'features/ee/ui/assets_screen.dart';
import 'features/ee/data/changes_models.dart';
import 'features/ee/ui/change_detail_screen.dart';
import 'features/ee/ui/changes_screen.dart';
import 'features/ee/ui/new_change_screen.dart';
import 'features/ee/data/problems_models.dart';
import 'features/ee/ui/new_problem_screen.dart';
import 'features/ee/ui/problem_detail_screen.dart';
import 'features/ee/ui/problems_screen.dart';
import 'features/ee/ui/kb_screen.dart';
import 'features/ee/ui/kb_article_screen.dart';
import 'features/ee/ui/team_settings_screen.dart';
import 'features/ee/ui/team_members_screen.dart';
import 'features/ee/ui/team_services_screen.dart';
import 'features/ee/ui/portal_links_screen.dart';
import 'features/ee/ui/customers_screen.dart';
import 'features/ee/ui/meeting_screen.dart';
import 'features/ee/ui/team_ai_keys_screen.dart';
import 'features/ee/ui/approval_detail_screen.dart';
import 'features/ee/ui/approvals_screen.dart';
import 'features/ee/ui/team_webhooks_screen.dart';
import 'features/ee/ui/team_identity_screen.dart';
import 'features/ee/ui/team_mail_screen.dart';
import 'features/ee/ui/sla_admin_screen.dart';
import 'features/ee/ui/my_tickets_screen.dart';
import 'features/ee/ui/absences_screen.dart';
import 'features/ee/ui/new_ticket_screen.dart';
import 'features/ee/ui/meetings_screen.dart';
import 'features/ee/ui/desk_paths.dart';
import 'features/ee/ui/my_units_screen.dart';
import 'features/ee/ui/performance_screen.dart';
import 'features/ee/ui/sla_dashboard_screen.dart';
import 'features/ee/ui/audit_log_screen.dart';
import 'features/ee/ui/ticket_detail_screen.dart';
import 'features/ee/ui/tickets_home.dart';
import 'features/ee/ui/team_invites_screen.dart';
import 'features/api_keys/ui/api_keys_screen.dart';
import 'features/ai/ui/share_log_screen.dart';
import 'notifications/alarm_log_screen.dart';
import 'screens/settings_screen.dart';
import 'screens/splash_screen.dart';
import 'sections.dart';
import 'sync/keep_current.dart';
import 'widgets/glass.dart';
import 'widgets/status_views.dart';
import 'i18n/i18n.dart';
import 'widgets/route_leading.dart';

const _authLocations = {'/login', '/register'};

/// Where an unroutable location lands. A real route, so the screen it shows is
/// ours — themed, localized and with an exit that works.
const String _kNotFound = '/not-found';

/// Every route is wrapped in its own opaque wash (OPH-194, DESIGN §21 T1).
/// A route that lets the route beneath it show through is what made navigation
/// look like it was hanging; making that impossible is one wrapper, applied here
/// rather than trusted to each screen.
Widget _page(Widget child) => AwPageBackground(child: child);

/// A signed-in destination outside the shell (OPH-359, UI-AUDIT #32).
///
/// The shell keeps the sync engines running while it is on screen — and a
/// destination opened by its ADDRESS (a request link, a notification, a page
/// reload on the web) is a top-level route that never mounts it. Nothing
/// pulled: "switch to its unit" changed the workspace and the request waited
/// forever for a copy that never came. Every such page keeps the replica
/// current itself. The auth screens, the splash and the operator console do
/// not use this: there is no person's replica there to keep.
Widget _contentPage(Widget child) => _page(AwKeepReplicaCurrent(child: child));

/// A team route behind its door (OPH-356, UI-AUDIT #7 and #61): the team's
/// address first, then — for the administration — who may open it. See
/// [EeTeamRouteGate].
Widget _teamPage(
  Widget child, {
  required String title,
  String? permission,
  bool adminOnly = false,
}) => _contentPage(
  EeTeamRouteGate(
    titleKey: title,
    permission: permission,
    adminOnly: adminOnly,
    child: child,
  ),
);

/// A request's two addresses (EE-225, EE-251). **The order is the contract:**
/// go_router matches in declaration order, so `/tickets/new` must come before
/// `/tickets/:ticketId` or "new" would be read as an id. A function rather than
/// inline entries so a test reads the very list the router uses.
List<RouteBase> eeTicketRoutes() => [
  // EE-225: filing a request. A route rather than a pushed widget so the
  // queue and "my requests" reach ONE screen by one address, and so a link
  // (a printed sign by a machine, one day) can land on it.
  GoRoute(
    path: '/tickets/new',
    builder: (context, state) => _teamPage(
      title: 'ee.tickets.new.title',
      EeNewTicketScreen(
        // EE-252: a follow-up to a closed request rides in-app, in `extra`;
        // the address itself carries nothing.
        followUp: switch (state.extra) {
          final EeTicketFollowUp followUp => followUp,
          _ => null,
        },
        // EE-271: and so does the machine a card files it about.
        asset: switch (state.extra) {
          final EeTicketAsset asset => asset,
          _ => null,
        },
      ),
    ),
  ),
  // EE-251: one request by its address — what a notification, a pasted
  // `alliswell://ticket/{id}` and the queue all open. Before it, the detail
  // was only ever pushed, so nothing arriving from outside could reach it.
  GoRoute(
    path: '/tickets/:ticketId',
    builder: (context, state) => _teamPage(
      title: 'ee.tickets.detailTitle',
      EeTicketDetailScreen(ticketId: state.pathParameters['ticketId'] ?? ''),
    ),
  ),
];

/// The equipment register and one machine's card (EE-194). Real routes rather
/// than a pushed screen, because the second one is what a printed QR label
/// resolves to (`alliswell://asset/{id}` → `/assets/{id}`), and a deep link
/// needs somewhere to land. Since EE-238 that card opens from the device's own
/// copy — a function rather than inline entries so a test can scan a label into
/// the very list the router uses, with the network switched off.
List<RouteBase> eeAssetRoutes() => [
  GoRoute(
    path: '/assets',
    builder: (context, state) => _contentPage(const EeAssetsScreen()),
  ),
  GoRoute(
    path: '/assets/:assetId',
    builder: (context, state) => _contentPage(
      EeAssetDetailScreen(assetId: state.pathParameters['assetId'] ?? ''),
    ),
  ),
];

/// Planned work (EE-269): the list, the form, and one change by its address.
/// **The order is the contract**, as for requests: `/changes/new` before
/// `/changes/:changeId`, or "new" would be read as an id. Real routes because
/// a change is a thing you link to — the approver's queue, a request's
/// relations and a clash on another change's calendar all open one — and a
/// function so a test reads the very list the router uses.
List<RouteBase> eeChangeRoutes() => [
  GoRoute(
    path: '/changes',
    builder: (context, state) => _contentPage(const EeChangesScreen()),
  ),
  GoRoute(
    path: '/changes/new',
    builder: (context, state) => _contentPage(
      EeNewChangeScreen(
        // EE-279: the request it is raised from rides in-app, in `extra`;
        // the address itself carries nothing (EE-252's rule).
        source: switch (state.extra) {
          final EeChangeSource source => source,
          _ => null,
        },
      ),
    ),
  ),
  GoRoute(
    path: '/changes/:changeId',
    builder: (context, state) => _contentPage(
      EeChangeDetailScreen(changeId: state.pathParameters['changeId'] ?? ''),
    ),
  ),
];

/// Known faults (EE-270): the list, the form, and one problem by its address —
/// in that order, `new` before the id, for the requests' reason. A request's
/// linked-problem card opens one, which is why they are real routes.
List<RouteBase> eeProblemRoutes() => [
  GoRoute(
    path: '/problems',
    builder: (context, state) => _contentPage(const EeProblemsScreen()),
  ),
  GoRoute(
    path: '/problems/new',
    builder: (context, state) => _contentPage(
      EeNewProblemScreen(
        // EE-280: the request it is raised from rides in `extra`.
        source: switch (state.extra) {
          final EeProblemSource source => source,
          _ => null,
        },
      ),
    ),
  ),
  GoRoute(
    path: '/problems/:problemId',
    builder: (context, state) => _contentPage(
      EeProblemDetailScreen(problemId: state.pathParameters['problemId'] ?? ''),
    ),
  ),
];

/// The desk's three boards (OPH-359, UI-AUDIT #59): the SLA dashboard, the
/// performance board and "my units". They were pushed as widgets from the
/// queue's ⋮ menu, with no address of their own — so the URL kept saying
/// `#/tickets`, a reload landed on the queue, and nobody could send a link to
/// one. EE-098's reason for not giving them one ("a second way in") does not
/// hold once the menu itself opens the address: there is still ONE way in.
List<RouteBase> eeDeskBoardRoutes() => [
  GoRoute(
    path: kAwSlaDashboardPath,
    builder: (context, state) =>
        _teamPage(const EeSlaDashboardScreen(), title: 'ee.slaDash.title'),
  ),
  GoRoute(
    path: kAwPerformancePath,
    builder: (context, state) =>
        _teamPage(const EePerformanceScreen(), title: 'ee.perfPanel.title'),
  ),
  GoRoute(
    path: kAwMyUnitsPath,
    builder: (context, state) => _teamPage(
      EeMyUnitsScreen(alertsOnly: state.uri.queryParameters['alerts'] == '1'),
      title: 'ee.myUnits.title',
    ),
  ),
];

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

/// A team invitation's landing place (OPH-356). Reachable signed OUT: the
/// person it is for often has no account yet, and the team's address refuses
/// free registration — the join screen is where that account is made.
bool isJoinLocation(String location) => location.startsWith('/join/');

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
  // OPH-356: an invitation is reachable in every state — even mid-restore,
  // where parking it on the splash lost it on a cold start. The join screen
  // waits for the session itself.
  if (isJoinLocation(location)) return null;
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

  // OPH-359 (UI-AUDIT #59): a screen opened with `push` carries its own
  // address. Off, go_router keeps the URL of the page UNDER the push — a
  // request opened from the queue said `#/tickets`, an approval said
  // `#/home` — so a reload dropped the person one screen back and a copied
  // link opened the wrong thing. Every push in this app is to a real route,
  // which is exactly the case the option exists for.
  GoRouter.optionURLReflectsImperativeAPIs = true;
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
      // OPH-333: our own scheme is resolved HERE, before route matching can
      // swallow it. go_router rewrites an EMPTY path to '/', so a bare-host
      // URL (`alliswell://add`, `alliswell://open`) matches the root route and
      // never reaches `onException`, where this table used to be consulted.
      // `open` only ever worked because '/' happens to redirect to Home; `add`
      // silently became Home too — measured, the first cut opened nothing.
      final appLink = state.uri.scheme == kAwScheme
          ? awRouteForUri(state.uri)
          : null;
      if (appLink != null) {
        if (auth.value != null && !auth.isLoading) return appLink;
        // Not ready (restoring, or signed out): park it — it wins once the
        // session exists. A cold start is exactly this case: a restoring
        // session parks every location on /splash, and before this the link
        // was dropped there.
        ref.read(pendingDeepLinkProvider.notifier).remember(appLink);
      }
      // OPH-333: `?add=1` is a REQUEST, not a place. Once there is a session
      // to act for, it becomes a flag Home consumes and the location becomes
      // plain Home. A query that has to survive the auth dance does not: after
      // a restore, a second refresh in the same frame re-parses the stale
      // /splash and lands on /home without it (measured on a cold start). A
      // flag waits until Home is there to read it.
      if (auth.value != null &&
          !auth.isLoading &&
          state.matchedLocation == AppSection.home.path &&
          state.uri.queryParameters[kAwAddParam] == '1') {
        ref.read(homeCreateRequestProvider.notifier).request();
        return AppSection.home.path;
      }
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
      // Not while a session is restoring: its previous value is still there,
      // and replaying then would bounce between the place and the splash.
      if (auth.value != null &&
          !auth.isLoading &&
          (decision == AppSection.home.path || decision == null)) {
        final pending = ref.read(pendingDeepLinkProvider.notifier).take();
        if (pending != null && pending != state.matchedLocation) return pending;
      }
      // OPH-298: the share extension's callback is NOT a destination, so it is
      // never remembered. Replaying it after sign-in would replay an
      // unroutable location; the payload it announces waits in the App Group
      // and the shell drains it the moment it mounts.
      if (auth.value == null &&
          !auth.isLoading &&
          !awIsShareCallback(state.uri)) {
        final wanted = awRouteForUri(state.uri) ?? state.matchedLocation;
        // A join link is reachable signed out (it remembers itself, query
        // and all, when it sends somebody to sign in).
        if (!_authLocations.contains(wanted) &&
            wanted != '/splash' &&
            !isJoinLocation(wanted)) {
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
      // OPH-298: the iOS share extension's `ShareMedia-<bundle id>:share`
      // callback. ADR-0029 expected it never to arrive; on iOS 26 it does, and
      // it used to land on `/not-found` — an error screen for a share that had
      // in fact been saved, and (because that screen lives outside the shell)
      // the reason the App Group was never drained. Home is the answer to both
      // halves: no error, and the surface that consumes the payload is mounted.
      if (awIsShareCallback(uri)) {
        router.go(AppSection.home.path);
        return;
      }
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
      // purpose — a signed-in person may open one too.
      //
      // OPH-356: reachable signed out (`isJoinLocation`), and the link's
      // `server` — the team's own address (ADR-0021) — rides along.
      GoRoute(
        path: '/join/:token',
        builder: (context, state) => _page(
          JoinTeamScreen(
            token: state.pathParameters['token'] ?? '',
            server: state.uri.queryParameters['server'],
          ),
        ),
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
          // EE-160: the sales inbox. `:leadId` is a child route so the shell
          // keeps Leads selected on the detail screen, the same way team
          // detail keeps Teams selected.
          GoRoute(
            path: '/admin/leads',
            builder: (context, state) => const AdminLeadsScreen(),
            routes: [
              GoRoute(
                path: ':leadId',
                builder: (context, state) => AdminLeadDetailScreen(
                  leadId: state.pathParameters['leadId'] ?? '',
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
                    // EE-253: what it shows depends on who is looking.
                    AppSection.tickets => const EeTicketsHome(),
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
        builder: (context, state) => _contentPage(const SettingsScreen()),
      ),
      // OPH-176: the alarm log — a diagnostic surface, pushed from Settings.
      // OPH-260 (DESIGN §32 S3): the groups are real routes, so a settings
      // URL keeps working and each page is somewhere you can be sent.
      GoRoute(
        path: '/settings/account',
        builder: (context, state) =>
            _contentPage(const SettingsAccountScreen()),
      ),
      GoRoute(
        path: '/settings/general',
        builder: (context, state) =>
            _contentPage(const SettingsGeneralScreen()),
      ),
      GoRoute(
        path: '/settings/notifications',
        builder: (context, state) =>
            _contentPage(const SettingsNotificationsScreen()),
      ),
      GoRoute(
        path: '/settings/integrations',
        builder: (context, state) =>
            _contentPage(const SettingsIntegrationsScreen()),
      ),
      // OPH-292: Developer — API access and the public reference. A real
      // route like its five siblings, so it can be linked and deep-linked.
      GoRoute(
        path: '/settings/developer',
        builder: (context, state) =>
            _contentPage(const SettingsDeveloperScreen()),
      ),
      GoRoute(
        path: '/settings/data',
        builder: (context, state) => _contentPage(const SettingsDataScreen()),
      ),
      GoRoute(
        path: '/settings/alarm-log',
        builder: (context, state) => _contentPage(const AlarmLogScreen()),
      ),
      // OPH-242: the share log — the same kind of surface, for the same kind of
      // unanswerable report ("I shared something and nothing happened").
      GoRoute(
        path: '/settings/share-log',
        builder: (context, state) => _contentPage(const ShareLogScreen()),
      ),
      // OPH-179: how insistent alarms are — one destination (DESIGN §18 N1).
      GoRoute(
        path: '/settings/reminders',
        builder: (context, state) =>
            _contentPage(const ReminderSettingsScreen()),
      ),
      // OPH-186 (DESIGN §20 C4): everything you have finished. Behind Settings
      // rather than a sixth tab — round 1's "one rich Home, few tabs" holds.
      GoRoute(
        path: '/settings/completed',
        builder: (context, state) => _contentPage(const CompletedScreen()),
      ),
      // EE-042: the team-admin area. Real routes like every other settings
      // group (§32 S3), so a team URL keeps working and each page is
      // somewhere somebody can be sent. Nothing links here unless the
      // instance is entitled AND the caller is a team admin — but the routes
      // themselves exist, because a 404 on a link an admin was sent is worse
      // than a screen that says "not yours".
      ...eeAssetRoutes(),
      ...eeChangeRoutes(),
      ...eeProblemRoutes(),
      ...eeTicketRoutes(),
      // EE-196: the knowledge base. Reached from the request queue's bar —
      // where the person who wants it is already standing (EE-098's rule for
      // the SLA dashboard, and the same sentence applies: a screen nothing
      // opens is not a feature). Routes rather than pushed widgets so an
      // article can be linked to.
      GoRoute(
        path: '/kb',
        builder: (context, state) => _contentPage(const EeKbScreen()),
      ),
      ...eeDeskBoardRoutes(),
      GoRoute(
        path: '/kb/:articleId',
        builder: (context, state) => _contentPage(
          EeKbArticleScreen(articleId: state.pathParameters['articleId'] ?? ''),
        ),
      ),
      GoRoute(
        path: '/settings/team',
        builder: (context, state) => _teamPage(
          const EeTeamSettingsScreen(),
          title: 'ee.team.settings.title',
          adminOnly: true,
        ),
      ),
      GoRoute(
        path: '/settings/team/members',
        builder: (context, state) => _teamPage(
          const EeTeamMembersScreen(),
          title: 'ee.team.members.title',
          permission: 'team.manage_members',
        ),
      ),
      GoRoute(
        path: '/settings/team/invites',
        builder: (context, state) => _teamPage(
          const EeTeamInvitesScreen(),
          title: 'ee.team.invites.title',
          permission: 'team.manage_invites',
        ),
      ),
      // EE-053: roles and their grant matrix.
      GoRoute(
        path: '/settings/team/roles',
        builder: (context, state) => _teamPage(
          const EeTeamRolesScreen(),
          title: 'ee.team.roles.title',
          permission: 'team.manage_roles',
        ),
      ),
      // EE-082: the service catalogue — what people may ask for, and which
      // unit answers each one.
      GoRoute(
        path: '/settings/team/services',
        builder: (context, state) => _teamPage(
          const EeTeamServicesScreen(),
          title: 'ee.team.services.title',
          permission: 'services.manage',
        ),
      ),
      // EE-099: what an admin may edit about a promise — policies, business
      // calendars and health monitors, all behind `sla.manage`.
      GoRoute(
        path: '/settings/team/sla',
        builder: (context, state) => _teamPage(
          const EeSlaAdminScreen(),
          title: 'ee.slaAdmin.title',
          permission: 'sla.manage',
        ),
      ),
      // EE-106: the public request links — create, pause, extend, revoke,
      // behind `portal.manage_links`. The URL a link carries is shown once at
      // creation and never again, because the server keeps only its digest.
      GoRoute(
        path: '/settings/team/portal',
        builder: (context, state) => _teamPage(
          const EePortalLinksScreen(),
          title: 'ee.portal.title',
          permission: 'portal.manage_links',
        ),
      ),
      // OPH-360 (UI-AUDIT #18): the companies the team serves and their
      // people — list, add, invite, switch off, rename, archive — behind
      // `customers.manage`. Before it a contact who left the customer kept
      // their way into the company portal.
      GoRoute(
        path: '/settings/team/customers',
        builder: (context, state) => _teamPage(
          const EeCustomersScreen(),
          title: 'ee.customers.title',
          permission: 'customers.manage',
        ),
      ),
      // EE-111: the team's AI provider keys and the personal-key policy,
      // behind `team.manage_ai_keys`. A key goes in once and is never shown
      // again — the server can recover it and declines to, so the screen shows
      // four characters and offers to replace rather than to reveal.
      GoRoute(
        path: '/settings/team/ai-keys',
        builder: (context, state) => _teamPage(
          const EeTeamAiKeysScreen(),
          title: 'ee.teamAi.title',
          permission: 'team.manage_ai_keys',
        ),
      ),
      // OPH-287: the team's identity sources — connect, TEST, then switch on,
      // behind `team.manage_identity`. Its own row rather than a section of
      // the security screen: which system answers "is this person who they
      // say" is a different authority from the password rules, and often a
      // different person's job.
      GoRoute(
        path: '/settings/team/identity',
        builder: (context, state) => _teamPage(
          const EeTeamIdentityScreen(),
          title: 'ee.identity.title',
          permission: 'team.manage_identity',
        ),
      ),
      // OPH-290: the team's own mail relay. Its own row for the reason the one
      // above has one — this hands us a credential for the company's mail
      // system and decides which server every notification leaves through,
      // which is not the authority that picks a logo.
      GoRoute(
        path: '/settings/team/mail',
        builder: (context, state) => _teamPage(
          const EeTeamMailScreen(),
          title: 'ee.mail.title',
          permission: 'team.manage_mail',
        ),
      ),
      // EE-176: the team's outgoing endpoints, behind `webhooks.manage`. Its
      // own row for the reason the mail relay has one: this decides which
      // outside systems learn what happens in here, and the secret it mints is
      // shown exactly once.
      GoRoute(
        path: '/settings/team/webhooks',
        builder: (context, state) => _teamPage(
          const EeTeamWebhooksScreen(),
          title: 'ee.webhooks.title',
          permission: 'webhooks.manage',
        ),
      ),
      // EE-271: the team's whole history (EE-130). The screen was written
      // with its filters and its three honest empties and had no route at
      // all — only its test imported it. Behind `team.view_audit`, which the
      // server checks; the settings row is drawn only for whoever holds it.
      GoRoute(
        path: '/settings/team/audit',
        builder: (context, state) => _teamPage(
          const EeAuditLogScreen(),
          title: 'ee.audit.title',
          permission: 'team.view_audit',
        ),
      ),
      // EE-184: what is waiting on your decision. Its own route rather than a
      // tab on the queue, because the people who answer approvals are not
      // necessarily the people who work the queue — a purchasing manager has
      // no reason to open a service desk.
      //
      // EE-294: out of Settings and into the navigation (the rail under
      // Requests, Quick Access on a phone). The old address still lands
      // here — a settings URL that worked yesterday works tomorrow (DESIGN
      // §32 S3), and it is what every notification and e-mail before this
      // release pointed at.
      GoRoute(
        path: '/approvals',
        builder: (context, state) =>
            _teamPage(const EeApprovalsScreen(), title: 'ee.approvals.title'),
      ),
      // EE-295: one approval, whole — what a row of the queue and an
      // approval notification open (the approver's window, ADR-0018).
      GoRoute(
        path: '/approvals/:approvalId',
        builder: (context, state) => _teamPage(
          title: 'ee.approvals.detailTitle',
          EeApprovalDetailScreen(
            approvalId: state.pathParameters['approvalId'] ?? '',
          ),
        ),
      ),
      GoRoute(
        path: '/settings/team/approvals',
        redirect: (context, state) => '/approvals',
      ),
      // EE-271: the unit's meetings — the door the route below shipped
      // without (a meeting could be read only by somebody who already had its
      // address). Declared BEFORE `/meetings/:meetingId`, the way `/new` sits
      // before an id: order is the contract.
      GoRoute(
        path: '/meetings',
        builder: (context, state) => _contentPage(const EeMeetingsScreen()),
      ),
      // EE-115: one meeting — what it decided, and who said what. A route
      // rather than a tab, for the reason EE-069's task history is one: this
      // is a destination people link to and come back to, not a mode of
      // another screen.
      GoRoute(
        path: '/meetings/:meetingId',
        builder: (context, state) => _contentPage(
          EeMeetingScreen(meetingId: state.pathParameters['meetingId']!),
        ),
      ),
      // EE-061: what other units shared with this one. Reachable by anyone in
      // a unit — receiving something is not an admin act.
      GoRoute(
        path: '/settings/team/shared',
        builder: (context, state) =>
            _teamPage(const EeSharedWithMeScreen(), title: 'ee.shared.title'),
      ),
      // EE-069: one task's whole story. A route rather than a tab on the
      // detail screen — see the screen's own header for why.
      GoRoute(
        path: '/tasks/:taskId/history',
        builder: (context, state) => _contentPage(
          EeTaskHistoryScreen(taskId: state.pathParameters['taskId']!),
        ),
      ),
      // EE-077: the notification centre and its preferences. Two routes
      // rather than a screen with a tab: the centre is a work surface people
      // reach constantly and the preferences are a settings page they visit
      // twice, and a tab bar would charge the first for the second.
      GoRoute(
        path: '/notifications',
        builder: (context, state) =>
            _contentPage(const EeNotificationCenterScreen()),
      ),
      // `/settings/team/...` and not `/settings/notifications`: that path is
      // already core's, for the device's own alarms. Two different things share
      // the word "notification" here — a local reminder this phone rings, and a
      // message the server sends about other people's actions — and giving them
      // one screen would make "turn these off" ambiguous in the only place it
      // must not be.
      GoRoute(
        path: '/settings/team/notifications',
        builder: (context, state) =>
            _contentPage(const EeNotificationPrefsScreen()),
      ),
      // EE-068's "assigned to me" list, retired by EE-296: in an
      // organisation Home IS the person's work — everything assigned to them,
      // from every unit — so a second list of the same work would be the
      // thing to explain. The address stays, for links and habits, and lands
      // where that work now is.
      GoRoute(
        path: '/settings/team/assignments',
        redirect: (context, state) => '/',
      ),
      // EE-087: "my requests". Reachable by anyone in a team — asking for
      // something is the least privileged act in the product.
      GoRoute(
        path: '/settings/team/my-tickets',
        builder: (context, state) =>
            _teamPage(const EeMyTicketsScreen(), title: 'ee.tickets.mineTitle'),
      ),
      // EE-236: absences and the on-call cover they cause. Reachable by
      // anyone in a team — saying "I am away next week" needs no verb.
      GoRoute(
        path: '/settings/team/absences',
        builder: (context, state) =>
            _teamPage(const EeAbsencesScreen(), title: 'ee.absences.title'),
      ),
      // EE-057: units. The one team route a NON-admin can legitimately reach
      // — a delegated unit manager is an ordinary member everywhere else, so
      // this path is gated by what the server hands back, not by the role.
      GoRoute(
        path: '/settings/team/units',
        builder: (context, state) =>
            _teamPage(const EeTeamUnitsScreen(), title: 'ee.team.units.title'),
      ),
      // OPH-220: AI settings — connections, models, the MCP connector URL.
      GoRoute(
        path: '/settings/ai',
        builder: (context, state) => _contentPage(const AiSettingsScreen()),
      ),
      // OPH-265: API access — the keys a person hands to their own scripts.
      GoRoute(
        path: '/settings/api-keys',
        builder: (context, state) => _contentPage(const ApiKeysScreen()),
      ),
      // Pushed on top of whichever list opened it (Inbox/Today/Upcoming/…).
      GoRoute(
        path: '/tasks/:taskId',
        builder: (context, state) => _contentPage(
          TaskDetailScreen(taskId: state.pathParameters['taskId']!),
        ),
      ),
      // README editing stays in the project's context (OPH-109): the Overview
      // pushes this full-screen and back pops to the Overview, instead of
      // switching to the Notes branch.
      GoRoute(
        path: '/edit-note/:noteId',
        builder: (context, state) => _contentPage(
          NoteEditorScreen(noteId: state.pathParameters['noteId']!),
        ),
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
      appBar: AppBar(leading: awRouteLeading(context)),
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
