import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../features/auth/providers.dart';
import '../../features/onboarding/tour.dart';
import '../../i18n/i18n.dart';
import '../../notifications/alarm_overlay.dart';
import '../../router.dart';
import '../../theme/tokens.dart';
import '../../widgets/glass.dart';
import '../search_recents.dart';
import 'global_search_palette.dart';

/// The ways into search everywhere (OPH-374, ADR-0055, DESIGN §40 P1): the
/// keyboard shortcut at the app root, the rail's leading entry on wide
/// layouts, and the round button beside the phone's bottom bar.

/// Apple platforms (web on a Mac included) get ⌘K; everything else Ctrl+K.
/// Never both on Apple: Ctrl+K is the macOS text field's "kill to end of
/// line", and a root binding would take it from every field in the app.
bool _apple() =>
    defaultTargetPlatform == TargetPlatform.macOS ||
    defaultTargetPlatform == TargetPlatform.iOS;

List<ShortcutActivator> globalSearchActivators() => [
  _apple()
      ? const SingleActivator(LogicalKeyboardKey.keyK, meta: true)
      : const SingleActivator(LogicalKeyboardKey.keyK, control: true),
];

/// Key names — the same in every language.
String globalSearchShortcutLabel() => _apple() ? '⌘K' : 'Ctrl+K'; // i18n-ignore

/// A request to open the palette. The rail entry and the phone button bump
/// it; the host — the one widget whose `ref` outlives every route — opens.
class GlobalSearchRequests extends Notifier<int> {
  @override
  int build() => 0;

  void request() => state++;
}

final globalSearchRequestProvider = NotifierProvider<GlobalSearchRequests, int>(
  GlobalSearchRequests.new,
);

/// Mounted in `MaterialApp.builder` (app.dart), above every route.
///
/// Two jobs:
///  * the shortcut. Bound with [CallbackShortcuts] at the ROOT, so it is the
///    LAST handler a key event meets: a focused field that owns ⌘K/Ctrl+K
///    itself — the note editor's command palette — wins, and keeps it.
///  * the recents. It follows the router and records each task, project and
///    note the person opens, from anywhere (`recentFromLocation`).
class AwGlobalSearchHost extends ConsumerStatefulWidget {
  const AwGlobalSearchHost({super.key, required this.child});

  final Widget child;

  @override
  ConsumerState<AwGlobalSearchHost> createState() => _AwGlobalSearchHostState();
}

class _AwGlobalSearchHostState extends ConsumerState<AwGlobalSearchHost> {
  GoRouter? _router;
  String? _lastPath;

  @override
  void initState() {
    super.initState();
    _router = ref.read(routerProvider);
    _router!.routerDelegate.addListener(_onRoute);
  }

  @override
  void dispose() {
    _router?.routerDelegate.removeListener(_onRoute);
    super.dispose();
  }

  void _onRoute() {
    final delegate = _router!.routerDelegate;
    if (delegate.currentConfiguration.isEmpty) return;
    // `state`, not `currentConfiguration.uri`: the configuration's address
    // stays the shell's when a detail screen is PUSHED over it (task detail,
    // the note editor), and those are exactly the visits that count.
    final path = delegate.state.uri.path;
    if (path == _lastPath) return;
    _lastPath = path;
    final recent = recentFromLocation(path);
    if (recent == null) return;
    // Not inside the router's own notification: a provider written while a
    // widget builds is refused, and the delegate notifies mid-navigation.
    scheduleMicrotask(() {
      if (!mounted) return;
      if (ref.read(authControllerProvider).value == null) return;
      unawaited(ref.read(searchRecentsProvider.notifier).record(recent));
    });
  }

  void _open() {
    // The same gates the Quick Access bubble keeps: no session, the tour or
    // a ringing alarm (both paint inside the shell, under this layer).
    if (ref.read(authControllerProvider).value == null) return;
    if (ref.read(tourControllerProvider).running) return;
    if (ref.read(alarmOverlayControllerProvider).ringing != null) return;
    final rootContext = awRootNavigatorKey.currentContext;
    if (rootContext == null) return;
    unawaited(showGlobalSearch(rootContext, ref));
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(globalSearchRequestProvider, (_, _) => _open());
    return CallbackShortcuts(
      bindings: {
        for (final activator in globalSearchActivators()) activator: _open,
      },
      child: widget.child,
    );
  }
}

/// The wide layout's way in: the rail's LEADING slot. Extended, a solid
/// field-shaped button with the shortcut written on it; collapsed, a search
/// icon whose tooltip names the shortcut.
class AwGlobalSearchRailEntry extends ConsumerWidget {
  const AwGlobalSearchRailEntry({super.key, required this.extended});

  final bool extended;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    void open() => ref.read(globalSearchRequestProvider.notifier).request();
    if (!extended) {
      return Padding(
        padding: const EdgeInsets.only(bottom: AwSpace.x2),
        child: IconButton(
          key: const Key('global-search-rail'),
          tooltip: 'search.global.openWithShortcut'.tr(
            args: {'shortcut': globalSearchShortcutLabel()},
          ),
          icon: const Icon(Icons.search),
          onPressed: open,
        ),
      );
    }
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    const radius = BorderRadius.all(Radius.circular(AwRadius.s));
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AwSpace.x4,
        AwSpace.x1,
        AwSpace.x4,
        AwSpace.x3,
      ),
      child: Semantics(
        button: true,
        label: 'search.global.openWithShortcut'.tr(
          args: {'shortcut': globalSearchShortcutLabel()},
        ),
        excludeSemantics: true,
        onTap: open,
        child: Material(
          color: scheme.surfaceContainerHigh,
          shape: RoundedRectangleBorder(
            borderRadius: radius,
            side: BorderSide(color: scheme.outlineVariant),
          ),
          child: InkWell(
            key: const Key('global-search-rail'),
            borderRadius: radius,
            onTap: open,
            child: SizedBox(
              width: 224,
              height: 44,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: AwSpace.x3),
                child: Row(
                  children: [
                    Icon(
                      Icons.search,
                      size: 20,
                      color: scheme.onSurfaceVariant,
                    ),
                    const SizedBox(width: AwSpace.x2),
                    Expanded(
                      child: Text(
                        'search.global.open'.tr(),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                    Text(
                      globalSearchShortcutLabel(),
                      style: theme.textTheme.labelMedium?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The phone's way in: a round glass button at the end of the bottom bar's
/// row — the bar is chrome, so is this, and nothing is written on the glass
/// (G1). The app bars stay as they are: Home's phone bar is full, and a sixth
/// icon would cut its title again (OPH-359).
class AwGlobalSearchOrb extends ConsumerWidget {
  const AwGlobalSearchOrb({super.key, this.size = 64});

  /// The capsule's height, so the two read as one row.
  final double size;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    return SizedBox.square(
      dimension: size,
      child: GlassSurface(
        floating: true,
        borderRadius: BorderRadius.all(Radius.circular(size / 2)),
        child: Center(
          child: IconButton(
            key: const Key('global-search-orb'),
            tooltip: 'search.global.open'.tr(),
            iconSize: 26,
            color: scheme.onSurface,
            icon: const Icon(Icons.search),
            onPressed: () =>
                ref.read(globalSearchRequestProvider.notifier).request(),
          ),
        ),
      ),
    );
  }
}
