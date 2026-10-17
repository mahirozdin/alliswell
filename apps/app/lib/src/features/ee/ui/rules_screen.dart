import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/error_messages.dart';
import '../../../i18n/i18n.dart';
import '../../../theme/tokens.dart';
import '../../../widgets/route_leading.dart';
import '../../../widgets/status_views.dart';
import '../../../widgets/swipe_actions.dart' show awConfirmDelete;
import '../rules_providers.dart';
import 'rules_widgets.dart';

/// EE-308 — the team's automation and routing rules, in the order they run.
///
/// ── TWO ENGINES, ONE SCREEN, TWO MEANINGS OF ORDER ──
///
/// Automation runs EVERY matching rule, top to bottom (ADR-0023); routing
/// takes the FIRST match. The same drag means different things on the two
/// tabs, so each tab says which in one line above its list.
///
/// ── REORDERING HAS TWO DOORS ──
///
/// Drag by the handle, or "Move up / Move down" in a row's menu — a screen
/// reader, a switch or a keyboard cannot drag (the form designer's rule).
class EeRulesScreen extends ConsumerWidget {
  const EeRulesScreen({super.key, this.initialTab = 0});

  final int initialTab;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return DefaultTabController(
      length: 2,
      initialIndex: initialTab,
      child: Builder(
        builder: (context) => Scaffold(
          appBar: AppBar(
            leading: awRouteLeading(context),
            title: Text('ee.rules.title'.tr()),
            actions: [
              IconButton(
                key: const Key('rules-new'),
                tooltip: 'ee.rules.newRule'.tr(),
                icon: const Icon(Icons.add),
                onPressed: () {
                  final tab = DefaultTabController.of(context).index;
                  context.push(
                    tab == 0
                        ? '/settings/team/rules/automation/new'
                        : '/settings/team/rules/routing/new',
                  );
                },
              ),
            ],
            bottom: TabBar(
              tabs: [
                Tab(
                  key: const Key('rules-tab-automation'),
                  text: 'ee.rules.tabAutomation'.tr(),
                ),
                Tab(
                  key: const Key('rules-tab-routing'),
                  text: 'ee.rules.tabRouting'.tr(),
                ),
              ],
            ),
          ),
          body: const TabBarView(children: [_AutomationTab(), _RoutingTab()]),
        ),
      ),
    );
  }
}

/// Runs a list action and says a refusal in a snackbar; a stale order also
/// says that the list was reloaded (the controller already re-read it).
Future<void> _guarded(BuildContext context, Future<void> Function() act) async {
  final messenger = ScaffoldMessenger.maybeOf(context);
  try {
    await act();
  } catch (e) {
    messenger?.showSnackBar(SnackBar(content: Text(localizedError(e))));
  }
}

List<String> _moved(List<String> ids, int from, int to) {
  final out = [...ids];
  final id = out.removeAt(from);
  out.insert(to.clamp(0, out.length), id);
  return out;
}

class _Explainer extends StatelessWidget {
  const _Explainer(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AwSpace.x4,
        AwSpace.x3,
        AwSpace.x4,
        AwSpace.x1,
      ),
      child: Row(
        children: [
          Icon(
            Icons.swap_vert,
            size: 18,
            color: theme.colorScheme.onSurfaceVariant,
          ),
          const SizedBox(width: AwSpace.x2),
          Expanded(
            child: Text(
              text,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── automation ────────────────────────────────────────────────────────────

class _AutomationTab extends ConsumerWidget {
  const _AutomationTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final rules = ref.watch(eeAutomationRulesProvider);
    final options = ref.watch(eeRuleOptionsProvider).value;
    return rules.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => AwErrorState(
        message: localizedError(e),
        onRetry: () => ref.invalidate(eeAutomationRulesProvider),
      ),
      data: (list) {
        if (list == null) {
          return AwEmptyState(
            icon: Icons.rule_outlined,
            title: 'ee.rules.unavailable'.tr(),
            message: 'ee.rules.unavailableBody'.tr(),
          );
        }
        if (list.isEmpty) {
          return AwEmptyState(
            key: const Key('rules-automation-empty'),
            icon: Icons.bolt_outlined,
            title: 'ee.rules.emptyAutomation'.tr(),
            message: 'ee.rules.emptyAutomationBody'.tr(),
            action: FilledButton(
              onPressed: () =>
                  context.push('/settings/team/rules/automation/new'),
              child: Text('ee.rules.newAutomation'.tr()),
            ),
          );
        }
        final controller = ref.read(eeAutomationRulesProvider.notifier);
        final ids = [for (final r in list) r.id];
        return Column(
          children: [
            _Explainer('ee.rules.explainAutomation'.tr()),
            Expanded(
              child: ReorderableListView.builder(
                key: const Key('rules-automation-list'),
                buildDefaultDragHandles: false,
                padding: awListPadding(context),
                itemCount: list.length,
                // `onReorderItem` hands the index the row lands on, already
                // adjusted for the row taken out (the old `onReorder` did not).
                onReorderItem: (from, target) {
                  if (target == from) return;
                  _guarded(
                    context,
                    () => controller.reorder(_moved(ids, from, target)),
                  );
                },
                itemBuilder: (context, i) {
                  final rule = list[i];
                  return _RuleRow(
                    key: ValueKey('rule-${rule.id}'),
                    index: i,
                    count: list.length,
                    id: rule.id,
                    name: rule.name,
                    sentence: automationSentence(rule, options),
                    enabled: rule.enabled,
                    status: EeRuleStatusLine(
                      enabled: rule.enabled,
                      paused: rule.paused,
                      pausedReason: rule.pauseReason,
                      lastFiredAt: rule.lastFiredAt,
                      failure: rule.failingNow ? (rule.lastError ?? '') : null,
                    ),
                    onResume: rule.paused
                        ? () => _guarded(context, () => controller.resume(rule))
                        : null,
                    onToggle: (v) =>
                        _guarded(context, () => controller.setEnabled(rule, v)),
                    onOpen: () => context.push(
                      '/settings/team/rules/automation/${rule.id}',
                    ),
                    onDuplicate: () => _guarded(context, () async {
                      await controller.duplicate(rule.id);
                      if (context.mounted) {
                        ScaffoldMessenger.maybeOf(context)?.showSnackBar(
                          SnackBar(content: Text('ee.rules.duplicated'.tr())),
                        );
                      }
                    }),
                    onMove: (to) => _guarded(
                      context,
                      () => controller.reorder(_moved(ids, i, to)),
                    ),
                    onDelete: () async {
                      final ok = await awConfirmDelete(
                        context,
                        title: 'ee.rules.deleteTitle'.tr(),
                        body: 'ee.rules.deleteBody'.tr(
                          args: {'name': rule.name},
                        ),
                      );
                      if (ok && context.mounted) {
                        await _guarded(
                          context,
                          () => controller.delete(rule.id),
                        );
                      }
                    },
                  );
                },
              ),
            ),
          ],
        );
      },
    );
  }
}

// ── routing ───────────────────────────────────────────────────────────────

class _RoutingTab extends ConsumerWidget {
  const _RoutingTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final rules = ref.watch(eeRoutingRulesProvider);
    final options = ref.watch(eeRuleOptionsProvider).value;
    return rules.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => AwErrorState(
        message: localizedError(e),
        onRetry: () => ref.invalidate(eeRoutingRulesProvider),
      ),
      data: (list) {
        if (list == null) {
          return AwEmptyState(
            icon: Icons.rule_outlined,
            title: 'ee.rules.unavailable'.tr(),
            message: 'ee.rules.unavailableBody'.tr(),
          );
        }
        if (list.isEmpty) {
          return AwEmptyState(
            key: const Key('rules-routing-empty'),
            icon: Icons.alt_route,
            title: 'ee.rules.emptyRouting'.tr(),
            message: 'ee.rules.emptyRoutingBody'.tr(),
            action: FilledButton(
              onPressed: () => context.push('/settings/team/rules/routing/new'),
              child: Text('ee.rules.newRouting'.tr()),
            ),
          );
        }
        final controller = ref.read(eeRoutingRulesProvider.notifier);
        final ids = [for (final r in list) r.id];
        return Column(
          children: [
            _Explainer('ee.rules.explainRouting'.tr()),
            Expanded(
              child: ReorderableListView.builder(
                key: const Key('rules-routing-list'),
                buildDefaultDragHandles: false,
                padding: awListPadding(context),
                itemCount: list.length,
                onReorderItem: (from, target) {
                  if (target == from) return;
                  _guarded(
                    context,
                    () => controller.reorder(_moved(ids, from, target)),
                  );
                },
                itemBuilder: (context, i) {
                  final rule = list[i];
                  return _RuleRow(
                    key: ValueKey('rule-${rule.id}'),
                    index: i,
                    count: list.length,
                    id: rule.id,
                    name: rule.name,
                    sentence: routingSentence(rule, options),
                    enabled: rule.enabled,
                    // Routing leaves no ledger of its own (its applications
                    // are request history rows), so there is no "last ran".
                    status: rule.enabled
                        ? null
                        : EeRuleStatusLine(enabled: false, showActivity: false),
                    onToggle: (v) =>
                        _guarded(context, () => controller.setEnabled(rule, v)),
                    onOpen: () =>
                        context.push('/settings/team/rules/routing/${rule.id}'),
                    onDuplicate: () => _guarded(context, () async {
                      await controller.duplicate(rule.id);
                      if (context.mounted) {
                        ScaffoldMessenger.maybeOf(context)?.showSnackBar(
                          SnackBar(content: Text('ee.rules.duplicated'.tr())),
                        );
                      }
                    }),
                    onMove: (to) => _guarded(
                      context,
                      () => controller.reorder(_moved(ids, i, to)),
                    ),
                    onDelete: () async {
                      final ok = await awConfirmDelete(
                        context,
                        title: 'ee.rules.deleteTitle'.tr(),
                        body: 'ee.rules.deleteBody'.tr(
                          args: {'name': rule.name},
                        ),
                      );
                      if (ok && context.mounted) {
                        await _guarded(
                          context,
                          () => controller.delete(rule.id),
                        );
                      }
                    },
                  );
                },
              ),
            ),
          ],
        );
      },
    );
  }
}

// ── one row ───────────────────────────────────────────────────────────────

class _RuleRow extends StatelessWidget {
  const _RuleRow({
    super.key,
    required this.index,
    required this.count,
    required this.id,
    required this.name,
    required this.sentence,
    required this.enabled,
    required this.onToggle,
    required this.onOpen,
    required this.onDuplicate,
    required this.onMove,
    required this.onDelete,
    this.status,
    this.onResume,
  });

  final int index;
  final int count;
  final String id;
  final String name;
  final String sentence;
  final bool enabled;
  final Widget? status;
  final VoidCallback? onResume;
  final ValueChanged<bool> onToggle;
  final VoidCallback onOpen;
  final VoidCallback onDuplicate;
  final ValueChanged<int> onMove;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Padding(
      padding: kAwListRowPadding,
      child: Card(
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onOpen,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: AwSpace.x2),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                ReorderableDragStartListener(
                  index: index,
                  child: Tooltip(
                    message: 'ee.rules.dragHandle'.tr(),
                    child: SizedBox(
                      key: Key('rule-handle-$id'),
                      width: 44,
                      height: 44,
                      child: Icon(
                        Icons.drag_indicator,
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                ),
                SizedBox(
                  width: 28,
                  child: Text(
                    '${index + 1}.',
                    style: theme.textTheme.titleSmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        name,
                        key: Key('rule-name-$id'),
                        style: theme.textTheme.titleSmall,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 2),
                      Text(
                        sentence,
                        key: Key('rule-sentence-$id'),
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                      ),
                      if (status != null) ...[
                        const SizedBox(height: AwSpace.x1),
                        status!,
                      ],
                      if (onResume != null)
                        Align(
                          alignment: AlignmentDirectional.centerStart,
                          child: TextButton.icon(
                            key: Key('rule-resume-$id'),
                            style: TextButton.styleFrom(
                              minimumSize: const Size(44, 44),
                            ),
                            onPressed: onResume,
                            icon: const Icon(Icons.play_arrow, size: 18),
                            label: Text('ee.rules.resume'.tr()),
                          ),
                        ),
                    ],
                  ),
                ),
                Semantics(
                  label: 'ee.rules.enabledLabel'.tr(),
                  child: SizedBox(
                    height: 44,
                    child: Switch(
                      key: Key('rule-switch-$id'),
                      value: enabled,
                      onChanged: onToggle,
                    ),
                  ),
                ),
                PopupMenuButton<String>(
                  key: Key('rule-menu-$id'),
                  tooltip: 'ee.rules.more'.tr(),
                  onSelected: (v) {
                    switch (v) {
                      case 'edit':
                        onOpen();
                      case 'duplicate':
                        onDuplicate();
                      case 'up':
                        onMove(index - 1);
                      case 'down':
                        onMove(index + 1);
                      case 'delete':
                        onDelete();
                    }
                  },
                  itemBuilder: (_) => [
                    PopupMenuItem(
                      value: 'edit',
                      child: Text('ee.rules.edit'.tr()),
                    ),
                    PopupMenuItem(
                      key: Key('rule-duplicate-$id'),
                      value: 'duplicate',
                      child: Text('ee.rules.duplicate'.tr()),
                    ),
                    if (index > 0)
                      PopupMenuItem(
                        key: Key('rule-up-$id'),
                        value: 'up',
                        child: Text('ee.rules.moveUp'.tr()),
                      ),
                    if (index < count - 1)
                      PopupMenuItem(
                        key: Key('rule-down-$id'),
                        value: 'down',
                        child: Text('ee.rules.moveDown'.tr()),
                      ),
                    PopupMenuItem(
                      key: Key('rule-delete-$id'),
                      value: 'delete',
                      child: Text('ee.rules.delete'.tr()),
                    ),
                  ],
                ),
                const SizedBox(width: AwSpace.x1),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
