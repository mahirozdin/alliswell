import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_quill/flutter_quill.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_slidable/flutter_slidable.dart';

import 'i18n/i18n.dart';
import 'router.dart';
import 'theme/theme.dart';
import 'theme/tokens.dart';

export 'theme/theme.dart' show kSeedColor;

/// The app root. A [ListenableBuilder] on [AwI18n.instance] rebuilds the
/// `MaterialApp` when the language changes (Epic 11, ADR-0009) so every `.tr()`
/// re-resolves and Material/Cupertino re-localize. The `MaterialApp` is built
/// INSIDE the builder (not handed in as a const child, which Flutter would skip
/// rebuilding). Translations load synchronously before `runApp` (`AwI18n.boot()`
/// in `main()`; `test/flutter_test_config.dart` for tests), so there is no
/// first-frame flicker and widget tests need no async gymnastics.
class AllisWellApp extends ConsumerWidget {
  const AllisWellApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final router = ref.watch(routerProvider);
    return ListenableBuilder(
      listenable: AwI18n.instance,
      builder: (context, _) => MaterialApp.router(
        onGenerateTitle: (context) => 'app.title'.tr(),
        debugShowCheckedModeBanner: false,
        theme: buildAwTheme(Brightness.light),
        darkTheme: buildAwTheme(Brightness.dark),
        themeMode: ThemeMode.system,
        // App strings come from AwI18n (`.tr()`); these delegates localize the
        // built-in Material/Cupertino widgets and the Flutter Quill editor
        // (OPH-044) for the active locale.
        locale: AwI18n.instance.locale,
        supportedLocales: awSupportedLocales,
        localizationsDelegates: const [
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
          ...FlutterQuillLocalizations.localizationsDelegates,
        ],
        // OPH-194: the aurora is NO LONGER painted here. A single wash below the
        // Navigator plus ~50 %-opaque scaffolds meant every route was
        // see-through to the route beneath it, which is what made transitions
        // look stuck. Each route paints its own now (`AwPageBackground` in
        // router.dart); what stays here is a solid floor so a transition can
        // never flash black, and `SlidableAutoCloseBehavior` — a group
        // notification ancestor, so ONE above the router makes every
        // swipe-to-delete row in the app close when another opens (OPH-184).
        builder: (context, child) => SlidableAutoCloseBehavior(
          child: ColoredBox(
            color: context.awTokens.auroraTop,
            child: child ?? const SizedBox.shrink(),
          ),
        ),
        routerConfig: router,
      ),
    );
  }
}
