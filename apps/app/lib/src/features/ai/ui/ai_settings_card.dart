import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../i18n/i18n.dart';
import '../../../theme/tokens.dart';
import '../../../widgets/status_views.dart';
import '../providers.dart';

/// The AI entry in Settings (OPH-220). Hidden entirely when AI is disabled on
/// the server; otherwise a connect CTA or a connected summary that links to the
/// full /settings/ai screen. Slots in after AppleCalendarCard.
class AiSettingsCard extends ConsumerWidget {
  const AiSettingsCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final status = ref.watch(aiStatusProvider);
    return status.when(
      loading: () => const SizedBox.shrink(),
      error: (_, _) => const SizedBox.shrink(),
      data: (data) {
        // Disabled (or a 404 from the server) → the whole surface is withdrawn.
        if (!data.enabled) return const SizedBox.shrink();
        final tokens = context.awTokens;
        return Card(
          child: ListTile(
            key: const Key('settings-ai'),
            leading: Icon(
              Icons.auto_awesome_outlined,
              color: data.configured ? tokens.success : null,
            ),
            title: Text('ai.settings.title'.tr()),
            subtitle: Text(
              data.configured
                  ? 'ai.settings.connectedSub'.tr()
                  : 'ai.settings.setupSub'.tr(),
            ),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => context.push('/settings/ai'),
          ),
        );
      },
    );
  }
}

/// Shown on the /settings/ai screen when the server has AI turned off — the
/// honest empty state (STORAGE_NOT_CONFIGURED idiom).
class AiDisabledState extends StatelessWidget {
  const AiDisabledState({super.key});
  @override
  Widget build(BuildContext context) => AwEmptyState(
    icon: Icons.auto_awesome_outlined,
    title: 'ai.settings.disabledTitle'.tr(),
    message: 'ai.settings.disabledBody'.tr(),
  );
}
