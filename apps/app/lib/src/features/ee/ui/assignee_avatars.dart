import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../i18n/i18n.dart';
import '../../../theme/tokens.dart';
import '../assignments_providers.dart';

/// Item 9's avatar row: *"Her task'ın altında atanmış kişilerin yuvarlak avatar
/// ikonları görünür (atanmamışsa boş)."*
///
/// ── Why the person's colour is a TINT and a neutral ring, not a fill ──────
///
/// The roster's palette (EE-017) carries a comment saying every entry clears
/// contrast in both themes. Measured against `scripts/design/contrast.py`'s own
/// ratio function, it does not: white initials fail 4.5:1 on five of the ten
/// fills (worst #CA8A04 at 2.94), and picking the better ink per fill still
/// leaves #0284C7 at 4.22. As a bare shape the fills fail 3:1 too — 2.94 on the
/// light surface, 2.58 on dark glass.
///
/// So this follows the app's own precedent for an arbitrary colour, OPH-199's
/// quick-access dot: the colour is a low-alpha TINT (decoration and identity),
/// a neutral `outline` ring carries the shape's 3:1, and the initials are drawn
/// in ordinary surface ink, which clears 4.5:1 by a wide margin (worst ≈ 10.7).
/// One idiom in the app instead of two, and the pairs are pinned in the gate.
const double _kAvatarSize = 24;
const double _kTintAlpha = 0.20;
const int _kMaxAvatars = 4;

/// One person, as a circle.
class AwAssigneeAvatar extends StatelessWidget {
  const AwAssigneeAvatar({
    super.key,
    required this.assignee,
    this.size = _kAvatarSize,
  });

  final Assignee assignee;
  final double size;

  static Color? parseColor(String? rgb) {
    if (rgb == null) return null;
    final hex = rgb.replaceFirst('#', '');
    if (hex.length != 6) return null;
    final value = int.tryParse(hex, radix: 16);
    return value == null ? null : Color(0xFF000000 | value);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final colour = parseColor(assignee.colorRgb);
    // The tombstone case (churn grace): the roster has no row for this person
    // any more, but the assignment is still true until the server releases it.
    // A neutral circle says "somebody who is no longer here" — which is the
    // honest answer — instead of the row quietly losing an assignee.
    final known = assignee.isKnown && colour != null;
    final fill = known
        ? Color.alphaBlend(
            colour.withValues(alpha: _kTintAlpha),
            scheme.surface,
          )
        : scheme.surfaceContainerHighest;
    final ink = known ? scheme.onSurface : scheme.onSurfaceVariant;
    final label = known
        ? (assignee.displayName ?? assignee.initials ?? '')
        : 'ee.assign.formerMember'.tr();

    return Tooltip(
      message: label,
      child: Semantics(
        label: label,
        child: Container(
          key: Key('assignee-${assignee.userId}'),
          width: size,
          height: size,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: fill,
            shape: BoxShape.circle,
            // The ring is the contrast, not the fill (see the header).
            border: Border.all(color: scheme.outline, width: 1),
          ),
          child: Text(
            known ? (assignee.initials ?? '?') : '—',
            style: theme.textTheme.labelSmall?.copyWith(
              color: ink,
              fontWeight: FontWeight.w700,
              height: 1,
            ),
          ),
        ),
      ),
    );
  }
}

/// The row under a task card. Draws nothing at all when nobody is on the task
/// — item 9 says "atanmamışsa boş", and an empty-state placeholder in a list
/// row would be noise on every unassigned task in the app.
class AwAssigneeAvatarRow extends ConsumerWidget {
  const AwAssigneeAvatarRow({
    super.key,
    required this.taskId,
    this.size = _kAvatarSize,
  });

  final String taskId;
  final double size;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // `select` so one task gaining an assignee does not rebuild every other
    // row in the list — the `aiEnrichingTasksProvider` idiom, same reason.
    final assignees = ref.watch(
      workspaceAssigneesProvider.select(
        (value) => value.value?[taskId] ?? const <Assignee>[],
      ),
    );
    if (assignees.isEmpty) return const SizedBox.shrink();
    final shown = assignees.take(_kMaxAvatars).toList();
    final overflow = assignees.length - shown.length;
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: AwSpace.x1),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final assignee in shown) ...[
            AwAssigneeAvatar(assignee: assignee, size: size),
            const SizedBox(width: AwSpace.x1),
          ],
          if (overflow > 0)
            Text(
              '+$overflow',
              style: theme.textTheme.labelSmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
                fontWeight: FontWeight.w600,
              ),
            ),
        ],
      ),
    );
  }
}

/// The task detail's assignee section (EE-068): the avatars, plus the control
/// that changes them.
///
/// Built only when this workspace HAS a roster — on a plain build, or a
/// personal workspace, there is nobody to assign to and a card offering it
/// would be a promise nothing keeps (DESIGN §22). That test is the replica's
/// own data rather than an entitlement call, so it is right offline too.
class AwAssigneeSection extends ConsumerWidget {
  const AwAssigneeSection({
    super.key,
    required this.workspaceId,
    required this.taskId,
  });

  final String workspaceId;
  final String taskId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final assignees =
        ref.watch(taskAssigneesProvider(taskId)).value ?? const [];
    final theme = Theme.of(context);
    return Row(
      children: [
        Expanded(
          child: assignees.isEmpty
              // Item 9's empty state, in the one place it belongs: the row
              // under a card stays blank, but the card that OFFERS the action
              // has to say what the blank means.
              ? Text(
                  'ee.assign.nobody'.tr(),
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                )
              : Wrap(
                  spacing: AwSpace.x2,
                  runSpacing: AwSpace.x2,
                  children: [
                    for (final assignee in assignees)
                      AwAssigneeAvatar(assignee: assignee, size: 32),
                  ],
                ),
        ),
        IconButton(
          key: const Key('assignee-picker-open'),
          tooltip: 'ee.assign.manage'.tr(),
          icon: const Icon(Icons.person_add_alt_outlined),
          onPressed: () => showAssigneePicker(
            context,
            workspaceId: workspaceId,
            taskId: taskId,
          ),
        ),
      ],
    );
  }
}

/// Who is on this task, and who could be. One sheet for both directions:
/// tapping a person on the list puts them on or takes them off, so there is no
/// separate "remove" gesture to discover.
Future<void> showAssigneePicker(
  BuildContext context, {
  required String workspaceId,
  required String taskId,
}) => showModalBottomSheet<void>(
  context: context,
  isScrollControlled: true,
  showDragHandle: true,
  builder: (context) =>
      _AssigneePicker(workspaceId: workspaceId, taskId: taskId),
);

class _AssigneePicker extends ConsumerWidget {
  const _AssigneePicker({required this.workspaceId, required this.taskId});

  final String workspaceId;
  final String taskId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final roster = ref.watch(workspaceRosterProvider).value ?? const [];
    final assignees =
        ref.watch(taskAssigneesProvider(taskId)).value ?? const [];
    final byUser = {for (final a in assignees) a.userId: a};
    final store = ref.read(assignmentStoreProvider);
    final theme = Theme.of(context);

    return SafeArea(
      child: ListView(
        shrinkWrap: true,
        padding: const EdgeInsets.fromLTRB(
          AwSpace.x4,
          0,
          AwSpace.x4,
          AwSpace.x4,
        ),
        children: [
          Text('ee.assign.title'.tr(), style: theme.textTheme.titleMedium),
          const SizedBox(height: AwSpace.x3),
          if (roster.isEmpty)
            Text(
              'ee.assign.noRoster'.tr(),
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          for (final person in roster)
            CheckboxListTile(
              key: Key('assignee-option-${person.userId}'),
              value: byUser.containsKey(person.userId),
              title: Text(person.displayName ?? person.initials ?? '—'),
              secondary: AwAssigneeAvatar(
                assignee: Assignee(
                  assignmentId: '',
                  userId: person.userId,
                  displayName: person.displayName,
                  initials: person.initials,
                  colorRgb: person.colorRgb,
                ),
                size: 32,
              ),
              onChanged: (checked) async {
                // The write is local-first and the server decides on arrival.
                // A refusal is parked, not lost (EE-051), so the sheet does
                // not pretend to know the answer before the push lands.
                if (checked ?? false) {
                  await store.assign(
                    workspaceId: workspaceId,
                    taskId: taskId,
                    userId: person.userId,
                  );
                } else {
                  final existing = byUser[person.userId];
                  if (existing != null) {
                    await store.release(existing.assignmentId);
                  }
                }
              },
            ),
        ],
      ),
    );
  }
}
