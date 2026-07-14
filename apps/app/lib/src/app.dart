import 'package:flutter/material.dart';
import 'package:flutter_quill/flutter_quill.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'router.dart';

/// AllisWell brand seed color — matches the default project color in the API
/// schema (`#2563EB`, see BLUEPRINT §10.2).
const kSeedColor = Color(0xFF2563EB);

class AllisWellApp extends ConsumerWidget {
  const AllisWellApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return MaterialApp.router(
      title: 'AllisWell',
      debugShowCheckedModeBanner: false,
      theme: _buildTheme(Brightness.light),
      darkTheme: _buildTheme(Brightness.dark),
      themeMode: ThemeMode.system,
      // Required by flutter_quill's editor widgets (OPH-044).
      localizationsDelegates: FlutterQuillLocalizations.localizationsDelegates,
      routerConfig: ref.watch(routerProvider),
    );
  }
}

ThemeData _buildTheme(Brightness brightness) {
  final colorScheme = ColorScheme.fromSeed(
    seedColor: kSeedColor,
    brightness: brightness,
  );
  return ThemeData(
    colorScheme: colorScheme,
    visualDensity: VisualDensity.adaptivePlatformDensity,
  );
}
