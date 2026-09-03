import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/server_url.dart';
import '../../../i18n/i18n.dart';
import '../../integrations/providers.dart' show urlLauncherProvider;

/// The door to the public REST reference (OPH-296).
///
/// It exists in two places on purpose. The complaint that produced it was
/// "I made a key and there is no documentation" — and the moment that bites
/// is the moment the key appears, not later in a settings tree. So this row
/// sits both in Settings → Developer, where someone goes looking, and on the
/// keys screen itself, where someone has just minted one and is holding a
/// secret with nothing to do with it.
///
/// Launched through [urlLauncherProvider] so a widget test can observe the
/// hand-off without a platform channel.
class ApiDocsRow extends ConsumerWidget {
  const ApiDocsRow({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) => ListTile(
    key: const Key('settings-api-docs'),
    leading: const Icon(Icons.menu_book_outlined),
    title: Text('apiKeys.docsTitle'.tr()),
    subtitle: Text('apiKeys.docsSub'.tr()),
    // The app's established "this leaves the app" marker.
    trailing: const Icon(Icons.open_in_new),
    onTap: () => ref.read(urlLauncherProvider)(Uri.parse(kApiDocsUrl)),
  );
}
