import 'package:flutter/material.dart';

import '../sections.dart';
import 'home_shell.dart';

/// Temporary screen shown for a section until its feature epic is implemented.
class PlaceholderScreen extends StatelessWidget {
  const PlaceholderScreen({super.key, required this.section});

  final AppSection section;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: buildSectionAppBar(context, section.title),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                section.selectedIcon,
                size: 72,
                color: theme.colorScheme.primary,
              ),
              const SizedBox(height: 16),
              Text(section.title, style: theme.textTheme.headlineMedium),
              const SizedBox(height: 8),
              Text(
                section.description,
                style: theme.textTheme.bodyLarge,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),
              Chip(
                avatar: const Icon(Icons.construction, size: 18),
                label: Text('Coming soon — ${section.taskRef}'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
