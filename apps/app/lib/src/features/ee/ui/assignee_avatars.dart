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
/// The row-under-a-card size, and the detail card's larger one. Two named
/// sizes rather than a literal repeated at three call sites (DESIGN §36).
const double _kAvatarSize = 24;
const double _kAvatarSizeLarge = 32;
const double _kTintAlpha = 0.20;
const int _kMaxAvatars = 4;

/// One person as a circle — the primitive, used by the assignment row AND by
/// the history tab (EE-071 made them one).
///
/// They were two. EE-026's history avatar filled the circle with the roster
/// colour and drew WHITE initials on it, under a comment saying "the server's
/// ten colours are all dark enough for it, and one rule beats per-colour
/// guessing". Measured with `scripts/design/contrast.py`'s own function, five
/// of the ten fail 4.5:1 (worst #CA8A04 at 2.94) — so half a roster has been
/// reading its own history through unreadable initials, and the sentence
/// claiming otherwise is exactly why nobody looked. One primitive now, so this
/// contrast decision cannot be made twice and drift once (DESIGN §36 W2/W5).
class AwPersonAvatar extends StatelessWidget {
  const AwPersonAvatar({
    super.key,
    required this.label,
    this.initials,
    this.colorRgb,
    this.known = true,
    this.size = _kAvatarSize,
    this.avatarKey,
  });

  /// Tooltip and semantics — a face with no name is not accessible.
  final String label;
  final String? initials;
  final String? colorRgb;

  /// False when this person is no longer in the roster: the neutral tombstone.
  final bool known;
  final double size;
  final Key? avatarKey;

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
    final colour = parseColor(colorRgb);
    final isKnown = known && colour != null;
    final fill = isKnown
        ? Color.alphaBlend(
            colour.withValues(alpha: _kTintAlpha),
            scheme.surface,
          )
        : scheme.surfaceContainerHighest;
    final ink = isKnown ? scheme.onSurface : scheme.onSurfaceVariant;

    return Tooltip(
      message: label,
      child: Semantics(
        label: label,
        child: Container(
          key: avatarKey,
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
            isKnown ? (initials ?? '?') : '—',
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

/// One assignee, as a circle.
class AwAssigneeAvatar extends StatelessWidget {
  const AwAssigneeAvatar({
    super.key,
    required this.assignee,
    this.size = _kAvatarSize,
  });

  final Assignee assignee;
  final double size;

  @override
  Widget build(BuildContext context) {
    // The tombstone case (churn grace): the roster has no row for this person
    // any more, but the assignment is still true until the server releases it.
    // A neutral circle says "somebody who is no longer here" — the honest
    // answer — instead of the row quietly losing an assignee.
    final known = assignee.isKnown;
    return AwPersonAvatar(
      avatarKey: Key('assignee-${assignee.userId}'),
      label: known
          ? (assignee.displayName ?? assignee.initials ?? '')
          : 'ee.assign.formerMember'.tr(),
      initials: assignee.initials,
      colorRgb: assignee.colorRgb,
      known: known,
      size: size,
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
    return AwAssigneeStrip(assignees: assignees, size: size);
  }
}

/// The row, given the people — with no opinion about what they are on.
///
/// Split out by EE-086 so a TICKET card can draw the same avatars as a task
/// card. The two owners keep separate tables (ADR-0011 §4, measured), but the
/// contrast decision above — tint, neutral ring, ordinary ink — must not be
/// made twice and drift once (DESIGN §36 W2/W5).
class AwAssigneeStrip extends StatelessWidget {
  const AwAssigneeStrip({
    super.key,
    required this.assignees,
    this.size = _kAvatarSize,
  });

  final List<Assignee> assignees;
  final double size;

  @override
  Widget build(BuildContext context) {
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
                      AwAssigneeAvatar(
                        assignee: assignee,
                        size: _kAvatarSizeLarge,
                      ),
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
                size: _kAvatarSizeLarge,
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
