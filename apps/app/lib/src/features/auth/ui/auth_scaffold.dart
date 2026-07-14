import 'package:flutter/material.dart';

import '../../../theme/tokens.dart';
import '../../../widgets/brand_mark.dart';

/// Shared centered-card layout for the login/register screens: the brand
/// mark and form float on a solid card over the aurora wash. The card is
/// intentionally opaque — form text never sits on blurred glass
/// (docs/DESIGN.md rule G1).
class AuthScaffold extends StatelessWidget {
  const AuthScaffold({required this.title, required this.children, super.key});

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(AwSpace.x6),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 430),
            child: Card(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(
                  AwSpace.x8,
                  AwSpace.x8,
                  AwSpace.x8,
                  AwSpace.x6,
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Center(child: BrandMark(size: 60)),
                    const SizedBox(height: AwSpace.x4),
                    Text(
                      'AllisWell',
                      textAlign: TextAlign.center,
                      style: theme.textTheme.headlineMedium,
                    ),
                    const SizedBox(height: AwSpace.x1),
                    Text(
                      title,
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodyLarge?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: AwSpace.x6),
                    ...children,
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
