import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../i18n/i18n.dart';
import 'list_detail.dart';

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
  // OPH-410: drawn in a list's detail pane, the way out is the pane's close
  // (DESIGN §51 D3) — never a back button that would pop the list behind.
  final closePane = AwPaneCloser.maybeOf(context);
  if (closePane != null) {
    return IconButton(
      key: const Key('list-detail-close'),
      icon: const Icon(Icons.close),
      tooltip: 'task.paneClose'.tr(),
      onPressed: closePane,
    );
  }
  // Inside a section the shell's navigation is the way out; a section's root
  // (the request tab is one) must not grow a Home button beside it.
  if (StatefulNavigationShell.maybeOf(context) != null) return null;
  // What AppBar itself asks: is there a route BELOW this one? Not
  // `Navigator.canPop`, which is also true for a sheet or page pushed ON TOP
  // (W-08): a screen that rebuilt under one lost its Home button, and nothing
  // rebuilt it after the pop. `ModalRoute.of` also makes the caller rebuild
  // whenever a route above it comes or goes, so the answer never goes stale.
  final route = ModalRoute.of(context);
  if (route?.impliesAppBarDismissal ?? false) return null;
  // Hosted without a router (a widget test of one screen): there is no Home
  // to go to, and inventing one would be a button that throws.
  final router = GoRouter.maybeOf(context);
  if (router == null) return null;
  // The router also counts a parent or shell navigator's pages. While
  // something sits on top of this screen it counts that too, which says
  // nothing about a way back under it — so it is asked only while this route
  // is the current one.
  if ((route?.isCurrent ?? true) && router.canPop()) return null;
  return IconButton(
    key: const Key('aw-route-home'),
    icon: const Icon(Icons.home_outlined),
    tooltip: 'nav.home'.tr(),
    onPressed: () => context.go('/home'),
  );
}
