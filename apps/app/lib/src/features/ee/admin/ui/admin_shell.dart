import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../i18n/i18n.dart';
import '../../../../theme/tokens.dart';
import '../admin_providers.dart';

/// The console's frame (EE-033): a title, the three destinations and a way
/// out. Deliberately plain — this is an operator tool, not a product surface,
/// and it should look like the thing it is rather than borrow the app's
/// warmth for something that can suspend a customer.
class AdminShell extends ConsumerWidget {
  const AdminShell({super.key, required this.child, required this.location});

  final Widget child;
  final String location;

  static const destinations = <({String path, IconData icon, String label})>[
    (
      path: '/admin',
      icon: Icons.insights_outlined,
      label: 'ee.admin.nav.usage',
    ),
    (
      path: '/admin/teams',
      icon: Icons.groups_outlined,
      label: 'ee.admin.nav.teams',
    ),
    (
      path: '/admin/packages',
      icon: Icons.inventory_2_outlined,
      label: 'ee.admin.nav.packages',
    ),
  ];

  int get _index {
    // Longest match wins, so /admin/teams/:id keeps Teams selected.
    var best = 0;
    for (var i = 0; i < destinations.length; i++) {
      final path = destinations[i].path;
      if (location == path || location.startsWith('$path/')) {
        if (path.length >= destinations[best].path.length) best = i;
      }
    }
    return best;
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final email = ref.watch(adminSessionProvider).value?.email ?? '';
    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        title: Text('ee.admin.title'.tr()),
        actions: [
          if (email.isNotEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: AwSpace.x2),
              child: Center(
                child: Text(
                  email,
                  style: Theme.of(context).textTheme.labelMedium,
                ),
              ),
            ),
          IconButton(
            tooltip: 'ee.admin.signOut'.tr(),
            icon: const Icon(Icons.logout),
            onPressed: () async {
              await ref.read(adminSessionProvider.notifier).signOut();
              if (context.mounted) context.go('/admin/login');
            },
          ),
        ],
      ),
      body: Row(
        children: [
          NavigationRail(
            selectedIndex: _index,
            labelType: NavigationRailLabelType.all,
            onDestinationSelected: (i) => context.go(destinations[i].path),
            destinations: [
              for (final d in destinations)
                NavigationRailDestination(
                  icon: Icon(d.icon),
                  label: Text(d.label.tr()),
                ),
            ],
          ),
          const VerticalDivider(width: 1),
          Expanded(child: child),
        ],
      ),
    );
  }
}

/// One row of "used / allowed", with the two questions EE-032 keeps apart:
/// being over a plan is not the same as being unable to grow.
class AdminSeatBar extends StatelessWidget {
  const AdminSeatBar({
    super.key,
    required this.used,
    required this.max,
    required this.exceeded,
    this.countKey = 'ee.admin.seats.count',
    this.unlimitedKey = 'ee.admin.seats.unlimited',
  });

  final int used;
  final int? max;
  final bool exceeded;

  /// The bar draws two numbers; what they COUNT belongs to the caller. The
  /// instance card counts teams, and a shared "seats" string there produced
  /// "4 of 5 seats" for a row that was never about seats — caught by looking
  /// at the golden, which is what the golden is for.
  final String countKey;
  final String unlimitedKey;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (max == null) {
      return Text(
        unlimitedKey.tr(args: {'used': '$used'}),
        style: theme.textTheme.bodySmall,
      );
    }
    final ratio = max! == 0 ? 1.0 : (used / max!).clamp(0.0, 1.0);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          countKey.tr(args: {'used': '$used', 'max': '${max!}'}),
          style: theme.textTheme.bodySmall?.copyWith(
            color: exceeded ? theme.colorScheme.error : null,
          ),
        ),
        const SizedBox(height: AwSpace.x1),
        ClipRRect(
          borderRadius: BorderRadius.circular(AwRadius.s),
          child: LinearProgressIndicator(
            value: ratio,
            minHeight: 6,
            color: exceeded
                ? theme.colorScheme.error
                : theme.colorScheme.primary,
            backgroundColor: theme.colorScheme.surfaceContainerHighest,
          ),
        ),
      ],
    );
  }
}
