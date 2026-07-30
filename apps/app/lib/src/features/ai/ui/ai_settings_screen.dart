import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api_exception.dart';
import '../../../core/error_messages.dart';
import '../../../core/server_url.dart';
import '../../../i18n/i18n.dart';
import '../../../theme/tokens.dart';
import '../../../widgets/status_views.dart';
import '../../workspaces/workspaces.dart';
import '../data/ai_models.dart';
import '../providers.dart';
import 'ai_consent_screen.dart';
import 'ai_settings_card.dart';

/// The full AI settings screen (OPH-220): connections list, add flow (provider
/// → consent → key → test → connect), model pickers, and the MCP connector
/// card (BLUEPRINT §12.16).
class AiSettingsScreen extends ConsumerStatefulWidget {
  const AiSettingsScreen({super.key});
  @override
  ConsumerState<AiSettingsScreen> createState() => _AiSettingsScreenState();
}

class _AiSettingsScreenState extends ConsumerState<AiSettingsScreen> {
  bool _busy = false;

  Future<void> _guard(Future<void> Function() action) async {
    if (_busy) return;
    setState(() => _busy = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      await action();
    } on ApiException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(localizedError(e))));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final status = ref.watch(aiStatusProvider);
    return Scaffold(
      appBar: AppBar(title: Text('ai.settings.title'.tr())),
      body: status.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (_, _) => AwErrorState(
          message: 'ai.settings.couldNotCheck'.tr(),
          onRetry: () => ref.read(aiStatusProvider.notifier).refresh(),
        ),
        data: (data) {
          if (!data.enabled) return const AiDisabledState();
          return Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 720),
              child: ListView(
                padding: awListPadding(context, top: AwSpace.x2),
                children: [
                  _connectionsCard(),
                  const SizedBox(height: AwSpace.x3),
                  const _McpConnectorCard(),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _connectionsCard() {
    final connections = ref.watch(aiConnectionsProvider);
    return Card(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            leading: const Icon(Icons.auto_awesome_outlined),
            title: Text('ai.settings.connectionsTitle'.tr()),
            subtitle: Text('ai.settings.connectionsSub'.tr()),
          ),
          connections.when(
            loading: () => const Padding(
              padding: EdgeInsets.all(AwSpace.x4),
              child: Center(child: CircularProgressIndicator()),
            ),
            error: (_, _) =>
                AwInlineError(message: 'ai.settings.couldNotCheck'.tr()),
            data: (list) => Column(
              children: [
                for (final c in list)
                  _ConnectionRow(connection: c, busy: _busy, guard: _guard),
                Padding(
                  padding: const EdgeInsets.fromLTRB(
                    AwSpace.x4,
                    AwSpace.x2,
                    AwSpace.x4,
                    AwSpace.x4,
                  ),
                  child: SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      key: const Key('ai-add-provider'),
                      onPressed: _busy ? null : _startAdd,
                      icon: const Icon(Icons.add),
                      label: Text('ai.settings.addProvider'.tr()),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _startAdd() async {
    final connected = ref.read(aiConnectionsProvider).value ?? const [];
    final taken = connected.map((c) => c.provider).toSet();
    final available = kAiProviders.where((p) => !taken.contains(p)).toList();
    if (available.isEmpty) return;

    final provider = await showModalBottomSheet<String>(
      context: context,
      useRootNavigator: true,
      useSafeArea: true,
      showDragHandle: true,
      constraints: const BoxConstraints(maxWidth: 560),
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final p in available)
              ListTile(
                key: Key('ai-provider-$p'),
                title: Text(providerLabel(p)),
                onTap: () => Navigator.of(sheetContext).pop(p),
              ),
          ],
        ),
      ),
    );
    if (provider == null || !mounted) return;

    // Consent BEFORE the key form — no key travels without it.
    final consented = await ensureAiConsent(context, ref, provider);
    if (!consented || !mounted) return;

    final creds = await _promptForKey(provider);
    if (creds == null || !mounted) return;

    final workspace = ref.read(currentWorkspaceProvider).value;
    if (workspace == null) return;
    await _guard(() async {
      await ref
          .read(aiApiProvider)
          .connect(
            workspace.id,
            provider: provider,
            apiKey: creds.apiKey,
            baseUrl: creds.baseUrl,
          );
      ref.invalidate(aiConnectionsProvider);
      await ref.read(aiStatusProvider.notifier).refresh();
    });
  }

  Future<({String? apiKey, String? baseUrl})?> _promptForKey(String provider) {
    final needsBaseUrl = provider == 'ollama';
    final keyController = TextEditingController();
    final baseUrlController = TextEditingController();
    return showModalBottomSheet<({String? apiKey, String? baseUrl})>(
      context: context,
      useRootNavigator: true,
      isScrollControlled: true,
      useSafeArea: true,
      constraints: const BoxConstraints(maxWidth: 560),
      builder: (sheetContext) => Padding(
        padding: EdgeInsets.fromLTRB(
          AwSpace.x4,
          AwSpace.x4,
          AwSpace.x4,
          AwSpace.x4 + MediaQuery.viewInsetsOf(sheetContext).bottom,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              providerLabel(provider),
              style: Theme.of(sheetContext).textTheme.titleMedium,
            ),
            const SizedBox(height: AwSpace.x3),
            if (needsBaseUrl)
              TextField(
                key: const Key('ai-base-url-field'),
                controller: baseUrlController,
                decoration: InputDecoration(
                  labelText: 'ai.settings.baseUrlLabel'.tr(),
                ),
                keyboardType: TextInputType.url,
              )
            else
              TextField(
                key: const Key('ai-key-field'),
                controller: keyController,
                decoration: InputDecoration(
                  labelText: 'ai.settings.keyLabel'.tr(),
                ),
                obscureText: true,
                autocorrect: false,
                enableSuggestions: false,
              ),
            const SizedBox(height: AwSpace.x4),
            FilledButton(
              key: const Key('ai-key-save'),
              onPressed: () => Navigator.of(sheetContext).pop((
                apiKey: needsBaseUrl ? null : keyController.text.trim(),
                baseUrl: needsBaseUrl ? baseUrlController.text.trim() : null,
              )),
              child: Text('ai.settings.connect'.tr()),
            ),
          ],
        ),
      ),
    );
  }
}

class _ConnectionRow extends ConsumerWidget {
  const _ConnectionRow({
    required this.connection,
    required this.busy,
    required this.guard,
  });
  final AiConnection connection;
  final bool busy;
  final Future<void> Function(Future<void> Function()) guard;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = context.awTokens;
    final subtitle = connection.keyLast4 != null
        ? '••••${connection.keyLast4}'
        : (connection.baseUrl ?? 'ai.settings.instanceManaged'.tr());
    return Column(
      children: [
        const Divider(indent: AwSpace.x4, endIndent: AwSpace.x4),
        ListTile(
          key: Key('ai-connection-${connection.provider}'),
          leading: Icon(
            Icons.check_circle_outline,
            color: connection.hasError
                ? Theme.of(context).colorScheme.error
                : tokens.success,
          ),
          title: Text(providerLabel(connection.provider)),
          subtitle: Text(subtitle),
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextButton(
                key: Key('ai-test-${connection.provider}'),
                onPressed: busy ? null : () => _test(context, ref),
                child: Text('ai.settings.test'.tr()),
              ),
              IconButton(
                key: Key('ai-remove-${connection.provider}'),
                tooltip: 'ai.settings.remove'.tr(),
                icon: const Icon(Icons.delete_outline),
                onPressed: busy ? null : () => _remove(ref),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Future<void> _test(BuildContext context, WidgetRef ref) => guard(() async {
    final result = await ref.read(aiApiProvider).test(connection.id);
    ref.invalidate(aiConnectionsProvider);
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            result.ok
                ? 'ai.settings.testOk'.tr()
                : 'ai.settings.testFailed'.tr(),
          ),
        ),
      );
    }
  });

  Future<void> _remove(WidgetRef ref) => guard(() async {
    await ref.read(aiApiProvider).remove(connection.id);
    ref.invalidate(aiConnectionsProvider);
    await ref.read(aiStatusProvider.notifier).refresh();
  });
}

/// The instance's MCP connector URL, for "Add AllisWell to Claude/ChatGPT".
class _McpConnectorCard extends ConsumerWidget {
  const _McpConnectorCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final base = ref.watch(apiBaseUrlProvider);
    final mcpUrl = '${base.replaceAll(RegExp(r'/+$'), '')}/mcp';
    return Card(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            leading: const Icon(Icons.hub_outlined),
            title: Text('ai.settings.mcpTitle'.tr()),
            subtitle: Text('ai.settings.mcpSub'.tr()),
          ),
          ListTile(
            title: Text(mcpUrl, style: Theme.of(context).textTheme.bodySmall),
            trailing: IconButton(
              key: const Key('ai-mcp-copy'),
              tooltip: 'ai.settings.copy'.tr(),
              icon: const Icon(Icons.copy_outlined),
              onPressed: () async {
                await Clipboard.setData(ClipboardData(text: mcpUrl));
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('ai.settings.copied'.tr())),
                  );
                }
              },
            ),
          ),
        ],
      ),
    );
  }
}

String providerLabel(String provider) => switch (provider) {
  'anthropic' => 'Anthropic Claude',
  'openai' => 'OpenAI',
  'gemini' => 'Google Gemini',
  'openrouter' => 'OpenRouter',
  'ollama' => 'Ollama',
  _ => provider,
};
