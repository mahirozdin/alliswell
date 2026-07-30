import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../i18n/i18n.dart';
import '../../../theme/tokens.dart';
import '../data/ai_models.dart';
import '../providers.dart';

/// Consent is a screen, not a checkbox (DESIGN §24 AI8): before a provider's
/// first use, we state what leaves the device, where the key lives, and the
/// provider's retention/training stance — with an amber warning where the
/// truth is uncomfortable (Gemini's free tier trains on your data).
///
/// [ensureAiConsent] is the gate every sending surface calls: returns true if
/// already consented, else shows this screen and returns the user's decision.
Future<bool> ensureAiConsent(
  BuildContext context,
  WidgetRef ref,
  String provider,
) async {
  final consent = ref.read(aiConsentProvider.notifier);
  if (await consent.has(provider)) return true;
  if (!context.mounted) return false;
  final granted = await Navigator.of(context, rootNavigator: true).push<bool>(
    MaterialPageRoute(
      fullscreenDialog: true,
      builder: (_) => AiConsentScreen(provider: provider),
    ),
  );
  return granted ?? false;
}

class AiConsentScreen extends ConsumerWidget {
  const AiConsentScreen({super.key, required this.provider});

  final String provider;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = context.awTokens;
    final theme = Theme.of(context);
    final trainsOnData = kAiTrainsOnData.contains(provider);

    return Scaffold(
      appBar: AppBar(
        title: Text(
          'ai.consent.title'.tr(args: {'provider': _label(provider)}),
        ),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(AwSpace.x4),
          children: [
            Text('ai.consent.intro'.tr(), style: theme.textTheme.bodyLarge),
            const SizedBox(height: AwSpace.x4),
            _point(
              context,
              Icons.upload_outlined,
              'ai.consent.leavesTitle',
              'ai.consent.leavesBody',
            ),
            _point(
              context,
              Icons.lock_outlined,
              'ai.consent.keyTitle',
              'ai.consent.keyBody',
            ),
            _point(
              context,
              Icons.policy_outlined,
              'ai.consent.retentionTitle',
              'ai.consent.retention.$provider',
            ),
            if (trainsOnData) ...[
              const SizedBox(height: AwSpace.x2),
              Container(
                key: const Key('ai-consent-amber'),
                padding: const EdgeInsets.all(AwSpace.x3),
                decoration: BoxDecoration(
                  color: theme.colorScheme.surfaceContainerHigh,
                  borderRadius: const BorderRadius.all(
                    Radius.circular(AwRadius.m),
                  ),
                  border: Border.all(color: tokens.warning),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.warning_amber_rounded, color: tokens.warning),
                    const SizedBox(width: AwSpace.x3),
                    Expanded(
                      child: Text(
                        'ai.consent.trainsWarning'.tr(),
                        style: theme.textTheme.bodyMedium,
                      ),
                    ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: AwSpace.x6),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                key: const Key('ai-consent-accept'),
                onPressed: () async {
                  await ref.read(aiConsentProvider.notifier).grant(provider);
                  if (context.mounted) Navigator.of(context).pop(true);
                },
                child: Text('ai.consent.accept'.tr()),
              ),
            ),
            const SizedBox(height: AwSpace.x2),
            SizedBox(
              width: double.infinity,
              child: TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: Text('ai.consent.cancel'.tr()),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _point(
    BuildContext context,
    IconData icon,
    String titleKey,
    String bodyKey,
  ) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: AwSpace.x3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: theme.colorScheme.onSurfaceVariant),
          const SizedBox(width: AwSpace.x3),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(titleKey.tr(), style: theme.textTheme.titleSmall),
                const SizedBox(height: 2),
                Text(bodyKey.tr(), style: theme.textTheme.bodyMedium),
              ],
            ),
          ),
        ],
      ),
    );
  }

  static String _label(String provider) => switch (provider) {
    'anthropic' => 'Anthropic Claude',
    'openai' => 'OpenAI',
    'gemini' => 'Google Gemini',
    'openrouter' => 'OpenRouter',
    'ollama' => 'Ollama',
    _ => provider,
  };
}
