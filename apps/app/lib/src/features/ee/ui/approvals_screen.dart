import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/error_messages.dart';
import '../../../i18n/i18n.dart';
import '../../../theme/tokens.dart';
import '../../../widgets/count_badge.dart';
import '../../../widgets/status_views.dart';
import '../approvals_providers.dart';
import '../data/approvals_models.dart';
import 'approval_card.dart';
import 'approval_reason_dialog.dart';
import 'approval_detail_screen.dart';
import 'team_address_views.dart';

/// EE-184 / EE-294 — what is waiting on this person's decision.
///
/// ── WHERE IT LIVES ────────────────────────────────────────────────────────
///
/// Not in Settings any more (the owner, 2026-09-30: "a screen people have to
/// act on does not belong behind Settings"). It is `/approvals`, drawn in the
/// rail directly under Requests on a wide screen and pinned at the top of
/// Quick Access on a phone, for anybody with approval authority — and the old
/// `/settings/team/approvals` address still lands here (DESIGN §32 S3).
///
/// ── TWO TABS, ONE SUM ─────────────────────────────────────────────────────
///
/// "Bende" is what names me; "Takımda" is what is addressed to a role I
/// answer for (anybody holding it may answer — the first answer counts). The
/// navigation badge is the two together, and each tab carries its own: the
/// same rows, counted the way the server counted them (only what a decision
/// can still change). Somebody who answers for no role sees one list.
///
/// ── WHY IT IS A LIST AND NOT A BULK BUTTON ───────────────────────────────
///
/// Batching is what the SCREEN does — everything waiting on you, in one
/// place — and the decision stays one at a time because each one needs its
/// own reason. A tick box over twenty rows would produce twenty identical
/// sentences, which is the same as none.
class EeApprovalsScreen extends ConsumerWidget {
  const EeApprovalsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final approvals = ref.watch(eeApprovalsProvider);
    final summary = ref.watch(eeApprovalsSummaryProvider).value;
    final items = approvals.value ?? const <EeApproval>[];
    final roleTab =
        (summary?.answersForRole ?? false) ||
        items.any((a) => a.addressedTo == 'role');

    // The list's own count once it is here — the rows on screen — and the
    // server's until then.
    int countOf(String tab) => approvals.hasValue
        ? items.where((a) => a.addressedTo == tab && a.actionable).length
        : (tab == 'me' ? summary?.personal : summary?.role) ?? 0;

    final canPop =
        GoRouter.maybeOf(context)?.canPop() ?? Navigator.canPop(context);
    final body = approvals.when(
      skipLoadingOnRefresh: true,
      loading: () => const Center(child: CircularProgressIndicator()),
      // OPH-356 (UI-AUDIT #7): no team on this address is said, not drawn
      // as "nothing is waiting on you".
      error: (error, _) => eeTeamErrorView(
        ref,
        error,
        message: localizedError(error),
        onRetry: () => ref.invalidate(eeApprovalsProvider),
      ),
      data: (items) => roleTab
          ? TabBarView(
              children: [
                _ApprovalsTab(tab: 'me', items: items),
                _ApprovalsTab(tab: 'role', items: items),
              ],
            )
          : _ApprovalsTab(tab: 'me', items: items),
    );

    return DefaultTabController(
      // The tab count changes when the role tab appears; a controller built
      // for one length must not be asked about another.
      key: ValueKey(roleTab),
      length: roleTab ? 2 : 1,
      child: Scaffold(
        appBar: AppBar(
          // A web reload lands here with nothing under it: the way back is
          // Home rather than no way at all.
          leading: canPop
              ? null
              : IconButton(
                  key: const Key('ee-approvals-home'),
                  icon: const Icon(Icons.home_outlined),
                  tooltip: 'nav.home'.tr(),
                  onPressed: () => context.go('/home'),
                ),
          title: Text('ee.approvals.title'.tr()),
          bottom: roleTab
              ? TabBar(
                  tabs: [
                    _TabLabel(
                      tabKey: 'mine',
                      label: 'ee.approvals.tabMine'.tr(),
                      count: countOf('me'),
                    ),
                    _TabLabel(
                      tabKey: 'team',
                      label: 'ee.approvals.tabTeam'.tr(),
                      count: countOf('role'),
                    ),
                  ],
                )
              : null,
        ),
        body: body,
      ),
    );
  }
}

class _TabLabel extends StatelessWidget {
  const _TabLabel({
    required this.tabKey,
    required this.label,
    required this.count,
  });

  final String tabKey;
  final String label;
  final int count;

  @override
  Widget build(BuildContext context) {
    return Tab(
      key: Key('ee-approvals-tab-$tabKey'),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Flexible(child: Text(label, overflow: TextOverflow.ellipsis)),
          if (count > 0) ...[
            const SizedBox(width: AwSpace.x2),
            AwCountBadge(
              badgeKey: Key('ee-approvals-badge-$tabKey'),
              count: count,
              semanticsLabel: 'ee.approvals.badge'.tr(
                args: {'count': '$count'},
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// One tab: what a decision can still change first, then — collapsed — the
/// rest of the team's queue (role tab only) and what no longer needs a
/// decision.
class _ApprovalsTab extends ConsumerWidget {
  const _ApprovalsTab({required this.tab, required this.items});

  /// `me` or `role` — the `addressedTo` this tab lists.
  final String tab;
  final List<EeApproval> items;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final text = Theme.of(context).textTheme;
    final mine = items.where((a) => a.addressedTo == tab).toList();
    final open = mine.where((a) => a.live).toList();
    final settled = mine.where((a) => !a.live).toList();
    final controller = ref.read(eeApprovalsProvider.notifier);

    Future<void> refresh() => controller.refresh();

    if (open.isEmpty && settled.isEmpty && tab == 'me') {
      return RefreshIndicator(
        onRefresh: refresh,
        child: AwEmptyState(
          physics: const AlwaysScrollableScrollPhysics(),
          icon: Icons.how_to_reg_outlined,
          title: 'ee.approvals.empty'.tr(),
          message: 'ee.approvals.emptyBody'.tr(),
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: refresh,
      child: ListView(
        key: Key('ee-approvals-list-$tab'),
        physics: const AlwaysScrollableScrollPhysics(),
        padding: awListPadding(context),
        children: [
          Padding(
            padding: const EdgeInsets.only(bottom: AwSpace.x3),
            child: Text(
              tab == 'me'
                  ? 'ee.approvals.tabMineHint'.tr()
                  : 'ee.approvals.tabTeamHint'.tr(),
              style: text.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          if (open.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: AwSpace.x4),
              child: Text(
                tab == 'me'
                    ? 'ee.approvals.empty'.tr()
                    : 'ee.approvals.emptyTeam'.tr(),
                key: Key('ee-approvals-empty-$tab'),
                style: text.bodyMedium,
              ),
            ),
          // OPH-353: the list rhythm every card list keeps (DESIGN §4).
          for (final approval in open)
            Padding(
              padding: kAwListRowPadding,
              child: EeApprovalCard(
                key: ValueKey('ee-approval-${approval.id}'),
                approval: approval,
                onOpen: _opener(context, approval),
                onDecide: (approve) =>
                    _askForReason(context, ref, approval, approve: approve),
              ),
            ),
          if (tab == 'role') const _OthersGroup(),
          if (settled.isNotEmpty)
            ExpansionTile(
              key: Key('ee-approvals-settled-$tab'),
              tilePadding: EdgeInsets.zero,
              title: Text(
                'ee.approvals.settledGroup'.tr(
                  args: {'count': '${settled.length}'},
                ),
                style: text.titleSmall,
              ),
              children: [
                for (final approval in settled)
                  Padding(
                    padding: kAwListRowPadding,
                    child: EeApprovalCard(
                      approval: approval,
                      onOpen: _opener(context, approval),
                    ),
                  ),
              ],
            ),
        ],
      ),
    );
  }
}

/// The team's queue beyond my own — waiting on somebody else. Read only when
/// opened, and drawn without buttons: those rows are not mine to answer.
class _OthersGroup extends ConsumerStatefulWidget {
  const _OthersGroup();

  @override
  ConsumerState<_OthersGroup> createState() => _OthersGroupState();
}

class _OthersGroupState extends ConsumerState<_OthersGroup> {
  bool _open = false;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final others = _open ? ref.watch(eeApprovalsOthersProvider) : null;
    return ExpansionTile(
      key: const Key('ee-approvals-others'),
      tilePadding: EdgeInsets.zero,
      onExpansionChanged: (open) => setState(() => _open = open),
      title: Text('ee.approvals.othersGroup'.tr(), style: text.titleSmall),
      children: [
        if (others == null)
          const SizedBox.shrink()
        else
          others.when(
            loading: () => const Padding(
              padding: EdgeInsets.all(AwSpace.x4),
              child: Center(child: CircularProgressIndicator()),
            ),
            error: (error, _) => AwInlineError(message: localizedError(error)),
            data: (rows) => rows.isEmpty
                ? Padding(
                    padding: const EdgeInsets.symmetric(vertical: AwSpace.x3),
                    child: Text(
                      'ee.approvals.othersEmpty'.tr(),
                      style: text.bodyMedium,
                    ),
                  )
                : Column(
                    children: [
                      for (final approval in rows)
                        Padding(
                          padding: kAwListRowPadding,
                          child: EeApprovalCard(
                            approval: approval,
                            onOpen: _opener(context, approval),
                          ),
                        ),
                    ],
                  ),
          ),
      ],
    );
  }
}

/// Where a row goes when tapped — EVERY row, since EE-295: the approval's own
/// page, which reads the request whole for the approver and opens the
/// request, the change or the task from there. Until then only a change's
/// row opened (EE-269), and a request's row was a line with nowhere to go.
VoidCallback? _opener(BuildContext context, EeApproval approval) =>
    () => awOpenApproval(context, approval.id);

Future<void> _askForReason(
  BuildContext context,
  WidgetRef ref,
  EeApproval approval, {
  required bool approve,
}) async {
  final reason = await askApprovalReason(context, approve: approve);
  if (reason == null || !context.mounted) return;
  final messenger = ScaffoldMessenger.of(context);
  try {
    await ref
        .read(eeApprovalsProvider.notifier)
        .decide(approval.id, approve: approve, reason: reason);
    messenger.showSnackBar(
      SnackBar(
        content: Text(
          approve
              ? 'ee.approvals.approvedToast'.tr()
              : 'ee.approvals.rejectedToast'.tr(),
        ),
      ),
    );
  } catch (error) {
    // The server's sentence reaches the person intact. "Somebody answered
    // first" and "you are not the one being asked" are different facts and a
    // generic failure would collapse them.
    messenger.showSnackBar(SnackBar(content: Text(localizedError(error))));
  }
}
