import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../i18n/i18n.dart';
import '../../../theme/tokens.dart' show AwRadius, AwSpace;
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
///
/// It offers what [switchableWorkspacesOf] offers (EE-296): in an
/// organisation, its workspaces and never the account's own — there is no
/// personal space in an organisation's app, and the one the account owns only
/// carries unsent drafts.
class AwWorkspaceSwitcher extends ConsumerWidget {
  const AwWorkspaceSwitcher({
    super.key,
    this.compactWidth = 600,
    this.title,
    this.leading,
  });

  /// Below this width only the icon is drawn.
  final double compactWidth;

  /// A screen title to carry ABOVE the unit's name (OPH-359, UI-AUDIT #58):
  /// on a phone the section bar's title and the switcher are one control —
  /// two lines, one ≥ 44 px target — instead of a title squeezed to "A…" by
  /// an icon-only switcher in the action row. With one workspace it is the
  /// title alone (and [leading]), with nothing to tap.
  final String? title;

  /// Drawn before the unit's name under [title] — the team's dot.
  final Widget? leading;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final workspaces = switchableWorkspacesOf(
      ref.watch(workspacesProvider).value ?? const [],
    );
    // The selection is only asked about when there is one to make: with one
    // workspace nothing here depends on it.
    final switchable = workspaces.length >= 2;
    final current = switchable
        ? ref.watch(currentWorkspaceProvider).value
        : null;
    final heading = title;
    if (heading != null) return _titled(context, ref, heading, current);
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
                // Flexible: under a phone's title (OPH-359) the row gets what
                // is left of the bar, and a long unit name shortens rather
                // than overflowing it.
                Flexible(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 160),
                    child: Text(
                      current.name,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.labelLarge,
                    ),
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

  Widget _titled(
    BuildContext context,
    WidgetRef ref,
    String heading,
    WorkspaceSummary? current,
  ) {
    final lead = leading;
    final column = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(heading, maxLines: 1, overflow: TextOverflow.ellipsis),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            ?lead,
            if (current != null) ...[
              Flexible(
                child: Text(
                  current.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.labelLarge,
                ),
              ),
              const Icon(Icons.expand_more, size: 18),
            ],
          ],
        ),
      ],
    );
    if (current == null) return column;
    return Semantics(
      button: true,
      label: 'workspace.switcher.tooltip'.tr(args: {'workspace': current.name}),
      child: InkWell(
        key: const Key('workspace-switcher'),
        borderRadius: BorderRadius.circular(AwRadius.m),
        onTap: () => _open(context, ref),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 48),
          child: Align(
            alignment: AlignmentDirectional.centerStart,
            widthFactor: 1,
            child: column,
          ),
        ),
      ),
    );
  }

  Future<void> _open(BuildContext context, WidgetRef ref) async {
    final workspaces = switchableWorkspacesOf(
      ref.read(workspacesProvider).value ?? const [],
    );
    final current = ref.read(currentWorkspaceProvider).value;
    // OPH-359 (UI-AUDIT #11): a person in ten units has ten rows, and the
    // sheet used to be a plain Column in a sheet capped at 9/16 of the
    // screen — the last three units were cut off with no way to scroll to
    // them. The sheet may now grow (`isScrollControlled`), is capped at most
    // of the screen, and the rows SCROLL. On the root navigator, so the
    // shell's bar and floating buttons are under it rather than over it.
    final chosen = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      useRootNavigator: true,
      builder: (ctx) => SafeArea(
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.sizeOf(ctx).height * 0.85,
          ),
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
              Flexible(
                child: ListView(
                  key: const Key('workspace-options'),
                  shrinkWrap: true,
                  children: [
                    for (final workspace in workspaces)
                      ListTile(
                        key: Key('workspace-option-${workspace.id}'),
                        leading: Icon(
                          workspace.id == current?.id
                              ? Icons.radio_button_checked
                              : Icons.radio_button_unchecked,
                        ),
                        title: Text(workspace.name),
                        selected: workspace.id == current?.id,
                        onTap: () => Navigator.of(ctx).pop(workspace.id),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
    if (chosen != null && chosen != current?.id) {
      await ref.read(selectedWorkspaceIdProvider.notifier).select(chosen);
    }
  }
}
