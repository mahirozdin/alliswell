import 'package:go_router/go_router.dart';

import 'screens/home_shell.dart';
import 'screens/placeholder_screen.dart';
import 'screens/settings_screen.dart';
import 'sections.dart';

/// App navigation. The five main sections live in an indexed-stack shell so
/// each keeps its own navigation state; Settings is pushed on top.
final appRouter = GoRouter(
  initialLocation: AppSection.today.path,
  routes: [
    StatefulShellRoute.indexedStack(
      builder: (context, state, navigationShell) =>
          HomeShell(navigationShell: navigationShell),
      branches: [
        for (final section in AppSection.values)
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: section.path,
                builder: (context, state) =>
                    PlaceholderScreen(section: section),
              ),
            ],
          ),
      ],
    ),
    GoRoute(
      path: '/settings',
      builder: (context, state) => const SettingsScreen(),
    ),
  ],
);
