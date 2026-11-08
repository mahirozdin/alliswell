import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/reachability.dart';
import '../i18n/i18n.dart';
import '../theme/tokens.dart';

/// The phone's "the server is not answering" line (OPH-392, E-22).
///
/// A wide window has a refresh button whose failure says so (DESIGN §15 R4,
/// R5); a phone had nothing, so a cut network looked exactly like a quiet
/// day. This strip sits above the section, under the status bar, for as long
/// as [serverReachabilityProvider] says the last request got no answer — it
/// is derived from the sync engine's own pulls, so it clears by itself on the
/// first answer. Unknown (nothing asked yet) is not offline: no strip.
///
/// Not glass (DESIGN G1: glass is chrome that floats; this is a status line
/// in the flow) and not an error colour: offline is a state of a local-first
/// app, not a failure (R4).
class AwOfflineStrip extends ConsumerWidget {
  const AwOfflineStrip({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final offline = ref.watch(
      serverReachabilityProvider.select((up) => up == false),
    );
    if (!offline) return child;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Column(
      children: [
        Material(
          key: const Key('offline-strip'),
          color: scheme.surfaceContainerHighest,
          child: SafeArea(
            bottom: false,
            child: Semantics(
              container: true,
              liveRegion: true,
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: AwSpace.x4,
                  vertical: AwSpace.x2,
                ),
                child: Row(
                  children: [
                    ExcludeSemantics(
                      child: Icon(
                        Icons.cloud_off_outlined,
                        size: 18,
                        color: scheme.onSurface,
                      ),
                    ),
                    const SizedBox(width: AwSpace.x2),
                    Expanded(
                      child: Text(
                        'common.offline'.tr(),
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: scheme.onSurface,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
        // The strip took the status bar's inset; the section's own app bar
        // must not add it a second time.
        Expanded(
          child: MediaQuery.removePadding(
            context: context,
            removeTop: true,
            child: child,
          ),
        ),
      ],
    );
  }
}
