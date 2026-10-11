import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/server_url.dart';
import '../../../i18n/i18n.dart';

/// The instance's MCP connector URL, for "Add AllisWell to Claude/ChatGPT".
///
/// OPH-364: it used to live inside the AI settings screen, which a server
/// with AI_ENABLED=false never shows — and the MCP track does not depend on
/// that switch (ADR-0022), so on exactly those servers the one place that
/// named the connector URL was unreachable. It stands on its own now, in
/// Settings ▸ Integrations, whatever the AI switch says.
class McpConnectorCard extends ConsumerWidget {
  const McpConnectorCard({super.key});

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
