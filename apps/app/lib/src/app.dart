import 'package:flutter/material.dart';

import 'router.dart';

/// AllisWell brand seed color — matches the default project color in the API
/// schema (`#2563EB`, see BLUEPRINT §10.2).
const kSeedColor = Color(0xFF2563EB);

class AllisWellApp extends StatelessWidget {
  const AllisWellApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      title: 'AllisWell',
      debugShowCheckedModeBanner: false,
      theme: _buildTheme(Brightness.light),
      darkTheme: _buildTheme(Brightness.dark),
      themeMode: ThemeMode.system,
      routerConfig: appRouter,
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
