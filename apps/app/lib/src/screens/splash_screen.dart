import 'package:flutter/material.dart';

/// Shown only while the persisted session is being restored at startup —
/// prevents a flash of the login screen (or of protected content).
class SplashScreen extends StatelessWidget {
  const SplashScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const Scaffold(body: Center(child: CircularProgressIndicator()));
  }
}
