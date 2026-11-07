import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/server_url.dart';
import '../../../i18n/i18n.dart';
import '../../../theme/tokens.dart';

/// Whether [url] points at this machine only — `localhost` (and `*.localhost`),
/// `127.0.0.0/8`, `::1` or `0.0.0.0` (OPH-395, E-28).
///
/// A connector address like that is one Claude and ChatGPT can never reach:
/// they call it from their own servers. A self-hoster behind a reverse proxy
/// whose API_PUBLIC_URL was never set sees exactly this, and copied it
/// without a word before.
bool awIsLoopbackUrl(String url) {
  final uri = Uri.tryParse(url.trim());
  if (uri == null || !uri.hasScheme || uri.host.isEmpty) return false;
  final host = uri.host.toLowerCase();
  if (host == 'localhost' || host.endsWith('.localhost')) return true;
  if (host == '::1' || host == '0.0.0.0') return true;
  return RegExp(r'^127(\.\d{1,3}){3}$').hasMatch(host);
}

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
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
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
          if (awIsLoopbackUrl(mcpUrl))
            // DESIGN §7: the state colour tints the surface at 10% and the
            // icon only; the words stay onSurface.
            Container(
              key: const Key('ai-mcp-loopback-warning'),
              margin: const EdgeInsets.fromLTRB(
                AwSpace.x4,
                0,
                AwSpace.x4,
                AwSpace.x4,
              ),
              padding: const EdgeInsets.all(AwSpace.x3),
              decoration: BoxDecoration(
                color: Color.alphaBlend(
                  context.awTokens.warning.withValues(alpha: 0.10),
                  scheme.surface,
                ),
                borderRadius: const BorderRadius.all(
                  Radius.circular(AwRadius.m),
                ),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    Icons.warning_amber_rounded,
                    size: 20,
                    color: context.awTokens.warning,
                  ),
                  const SizedBox(width: AwSpace.x3),
                  Expanded(
                    child: Text(
                      'ai.settings.mcpLoopback'.tr(),
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: scheme.onSurface,
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
}
