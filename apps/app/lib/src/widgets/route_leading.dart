import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../i18n/i18n.dart';

/// The app bar's way out of a screen that has nothing under it (OPH-359,
/// UI-AUDIT #30).
///
/// A screen opened by its address — a pasted link, a notification, a page
/// reload on the web, a QR code by a machine — is the only page on the
/// stack. `AppBar` then draws no leading button at all, and a person on a
/// phone's web app (no browser back button) is stranded. The Approvals
/// screens solved it for themselves (EE-294); this is that answer, in one
/// place, for every routed screen:
///
///   • something to go back to → null, so `AppBar` draws its own back button
///     (and a screen that set `automaticallyImplyLeading: false` stays bare);
///   • nothing → a Home button that goes to Home.
///
/// Use it as `AppBar(leading: awRouteLeading(context), …)`.
Widget? awRouteLeading(BuildContext context) {
  // Inside a section the shell's navigation is the way out; a section's root
  // (the request tab is one) must not grow a Home button beside it.
  if (StatefulNavigationShell.maybeOf(context) != null) return null;
  if (Navigator.canPop(context)) return null;
  final canPop = GoRouter.maybeOf(context)?.canPop() ?? false;
  if (canPop) return null;
  // Hosted without a router (a widget test of one screen): there is no Home
  // to go to, and inventing one would be a button that throws.
  if (GoRouter.maybeOf(context) == null) return null;
  return IconButton(
    key: const Key('aw-route-home'),
    icon: const Icon(Icons.home_outlined),
    tooltip: 'nav.home'.tr(),
    onPressed: () => context.go('/home'),
  );
}
