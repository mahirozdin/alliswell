import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../i18n/i18n.dart';
import '../../../theme/tokens.dart' show AwSpace;
import '../workspaces.dart';

/// Which workspace this window is showing, and how to change it (EE-061).
///
/// Under ADR-0008 a unit IS a workspace, so this is the unit switcher: the
/// people in two departments have two workspaces, and the switch is what puts
/// one of them on screen. Everything follows from one provider — the sync
/// engine WATCHES `currentWorkspaceProvider` and is rebuilt for the new
/// workspace, so switching is not a special mode, it is the ordinary state of
/// the app pointed somewhere else.
///
/// Renders NOTHING for somebody with one workspace, which is every community
/// build and most personal accounts. A switcher offering one choice is not a
/// control, it is furniture — and the team chip beside it takes the same
/// stance for the same reason.
class AwWorkspaceSwitcher extends ConsumerWidget {
  const AwWorkspaceSwitcher({super.key, this.compactWidth = 600});

  /// Below this width only the icon is drawn.
  final double compactWidth;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final workspaces = ref.watch(workspacesProvider).value ?? const [];
    if (workspaces.length < 2) return const SizedBox.shrink();
    final current = ref.watch(currentWorkspaceProvider).value;
    if (current == null) return const SizedBox.shrink();

    final compact = MediaQuery.sizeOf(context).width < compactWidth;
    final label = 'workspace.switcher.tooltip'.tr(
      args: {'workspace': current.name},
    );

    // No Tooltip: the control already shows the workspace's name, so a tooltip
    // would repeat what is on screen — and a hover timer on a button that is
    // mostly tapped is a cost with no reader.
    return Semantics(
      button: true,
      label: label,
      child: InkWell(
        key: const Key('workspace-switcher'),
        borderRadius: BorderRadius.circular(999),
        onTap: () => _open(context, ref),
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AwSpace.x2,
            vertical: AwSpace.x1,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.workspaces_outline, size: 18),
              if (!compact) ...[
                const SizedBox(width: AwSpace.x1),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 160),
                  child: Text(
                    current.name,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.labelLarge,
                  ),
                ),
              ],
              const Icon(Icons.expand_more, size: 18),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _open(BuildContext context, WidgetRef ref) async {
    final workspaces = ref.read(workspacesProvider).value ?? const [];
    final current = ref.read(currentWorkspaceProvider).value;
    final chosen = await showModalBottomSheet<String>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.all(AwSpace.x4),
              child: Text(
                'workspace.switcher.title'.tr(),
                style: Theme.of(ctx).textTheme.titleMedium,
              ),
            ),
            for (final workspace in workspaces)
              ListTile(
                key: Key('workspace-option-${workspace.id}'),
                leading: Icon(
                  workspace.id == current?.id
                      ? Icons.radio_button_checked
                      : Icons.radio_button_unchecked,
                ),
                title: Text(workspace.name),
                onTap: () => Navigator.of(ctx).pop(workspace.id),
              ),
          ],
        ),
      ),
    );
    if (chosen != null && chosen != current?.id) {
      await ref.read(selectedWorkspaceIdProvider.notifier).select(chosen);
    }
  }
}
