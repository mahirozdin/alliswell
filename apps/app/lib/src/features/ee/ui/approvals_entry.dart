import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../i18n/i18n.dart';
import '../../../theme/tokens.dart';
import '../../../widgets/count_badge.dart';
import '../../quick_access/pinned.dart';
import '../approvals_providers.dart';

/// The Approvals entry's address and glyph — one place, three surfaces.
const String kAwApprovalsPath = '/approvals';
const IconData kAwApprovalsIcon = Icons.how_to_reg_outlined;

/// EE-294 — Approvals in the navigation, for whoever has approval authority.
///
/// ── WHERE, AND WHY NOT A SECTION ──────────────────────────────────────────
///
/// On a wide layout it sits in the rail DIRECTLY UNDER Requests: Requests is
/// the rail's last destination, and this is the first thing in the rail's
/// `trailing`, above Quick Access. It is deliberately NOT an `AppSection`:
/// sections are positional identity for the shell's branches
/// (`sections.dart`), a section drawn in the rail and not in the phone's bar
/// is a branch the shell would bounce back to Home, and the tour asks a step
/// of every section. The screen is a pushed page like the notification
/// centre, so the entry is a link, not a place (DESIGN §23 Q10).
///
/// On a phone the bottom bar has no room, so the same entry is pinned at the
/// top of Quick Access ([eeApprovalsPinProvider]) — fixed: it cannot be
/// renamed, moved or removed, and it is not a stored shortcut.
///
/// Drawn only on a positive answer from the server (`eeApprovalsDoorProvider`),
/// never on `canProvider`'s "nobody is asking, so yes".
class EeApprovalsRailEntry extends ConsumerWidget {
  const EeApprovalsRailEntry({super.key, required this.extended});

  /// The extended rail (≥1160) draws icon + label + badge in a row; the
  /// narrow one (800–1160) an icon with the badge on it and the label below,
  /// like its destinations.
  final bool extended;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!ref.watch(eeApprovalsDoorProvider)) return const SizedBox.shrink();
    final count = ref.watch(eeApprovalsBadgeProvider);
    final theme = Theme.of(context);
    final ink = theme.colorScheme.onSurfaceVariant;
    final label = 'ee.approvals.title'.tr();
    final semantics = count > 0
        ? '$label, ${'ee.approvals.badge'.tr(args: {'count': '$count'})}'
        : label;
    void open() => GoRouter.of(context).push(kAwApprovalsPath);

    // OPH-359 (UI-AUDIT #57): in the extended rail the icon sits in the same
    // centred column as the destinations' icons and the label starts where
    // theirs do — it used to be drawn 14 px and 32 px to their left, which
    // read as "not part of this list".
    final child = extended
        ? Padding(
            padding: const EdgeInsets.only(
              right: AwSpace.x4,
              top: AwSpace.x3,
              bottom: AwSpace.x3,
            ),
            child: Row(
              children: [
                SizedBox(
                  width: kAwRailMinWidth,
                  child: Center(
                    child: Icon(
                      kAwApprovalsIcon,
                      key: const Key('nav-approvals-icon'),
                      color: ink,
                    ),
                  ),
                ),
                Expanded(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.labelLarge?.copyWith(color: ink),
                  ),
                ),
                AwCountBadge(
                  badgeKey: const Key('nav-approvals-badge'),
                  count: count,
                  semanticsLabel: 'ee.approvals.badge'.tr(
                    args: {'count': '$count'},
                  ),
                ),
              ],
            ),
          )
        : Padding(
            padding: const EdgeInsets.symmetric(vertical: AwSpace.x2),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                AwBadgedIcon(
                  icon: kAwApprovalsIcon,
                  color: ink,
                  count: count,
                  badgeKey: const Key('nav-approvals-badge'),
                  semanticsLabel: 'ee.approvals.badge'.tr(
                    args: {'count': '$count'},
                  ),
                ),
                const SizedBox(height: AwSpace.x1),
                Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.labelMedium?.copyWith(color: ink),
                ),
              ],
            ),
          );

    // UI-AUDIT #12 (retest): ONE node that is the button — its label, and
    // the InkWell's tap and focus merged into it. `excludeSemantics` here
    // used to drop the InkWell's own node with them, which left "button"
    // over nothing: no tap action, not focusable, so on the web no tabindex
    // — Tab jumped from Requests straight to Quick Access and Enter did
    // nothing. Only the drawn parts (icon, word, badge) are hidden; the
    // label above already says all of them.
    return Tooltip(
      message: 'ee.approvals.navHint'.tr(),
      waitDuration: const Duration(milliseconds: 600),
      excludeFromSemantics: true,
      child: Semantics(
        button: true,
        label: semantics,
        child: InkWell(
          key: const Key('nav-approvals'),
          borderRadius: const BorderRadius.all(Radius.circular(AwRadius.pill)),
          onTap: open,
          // 44 px is the floor for a target (DESIGN §5); a row is taller.
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 48),
            child: ExcludeSemantics(child: child),
          ),
        ),
      ),
    );
  }
}

/// The phone's entry: Approvals pinned at the top of Quick Access (EE-294,
/// DESIGN §23 Q10). Null — no pin — for anybody without approval authority.
final eeApprovalsPinProvider = Provider.autoDispose<QuickAccessPin?>((ref) {
  if (!ref.watch(eeApprovalsDoorProvider)) return null;
  final count = ref.watch(eeApprovalsBadgeProvider);
  return QuickAccessPin(
    id: 'approvals',
    icon: kAwApprovalsIcon,
    title: 'ee.approvals.title'.tr(),
    subtitle: 'ee.approvals.navHint'.tr(),
    route: kAwApprovalsPath,
    badge: count,
    badgeSemantics: 'ee.approvals.badge'.tr(args: {'count': '$count'}),
  );
});
