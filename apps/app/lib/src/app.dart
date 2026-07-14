import 'package:flutter/material.dart';
import 'package:flutter_quill/flutter_quill.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'router.dart';
import 'theme/theme.dart';
import 'widgets/glass.dart';

export 'theme/theme.dart' show kSeedColor;

class AllisWellApp extends ConsumerWidget {
  const AllisWellApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return MaterialApp.router(
      title: 'AllisWell',
      debugShowCheckedModeBanner: false,
      theme: buildAwTheme(Brightness.light),
      darkTheme: buildAwTheme(Brightness.dark),
      themeMode: ThemeMode.system,
      // The aurora wash paints once here, under every route; scaffolds use a
      // translucent veil over it (see theme.dart / docs/DESIGN.md).
      builder: (context, child) =>
          AuroraBackground(child: child ?? const SizedBox.shrink()),
      // Required by flutter_quill's editor widgets (OPH-044).
      localizationsDelegates: FlutterQuillLocalizations.localizationsDelegates,
      routerConfig: ref.watch(routerProvider),
    );
  }
}
