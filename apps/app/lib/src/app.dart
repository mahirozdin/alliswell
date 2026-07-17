import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_quill/flutter_quill.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'i18n/i18n.dart';
import 'router.dart';
import 'theme/theme.dart';
import 'widgets/glass.dart';

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
        // The aurora wash paints once here, under every route; scaffolds use a
        // translucent veil over it (see theme.dart / docs/DESIGN.md).
        builder: (context, child) =>
            AuroraBackground(child: child ?? const SizedBox.shrink()),
        routerConfig: router,
      ),
    );
  }
}
