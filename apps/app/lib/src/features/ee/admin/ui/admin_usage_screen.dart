import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/error_messages.dart';
import '../../../../i18n/i18n.dart';
import '../../../../theme/tokens.dart';
import '../../../../widgets/status_views.dart';
import '../admin_providers.dart';
import '../data/admin_models.dart';
import 'admin_shell.dart';

/// The console's landing page (EE-033): what this instance is using, next to
/// what it is allowed. The operator's first question is "who is about to hit a
/// wall?", so the answer is a list sorted by how close each team is to one.
class AdminUsageScreen extends ConsumerWidget {
  const AdminUsageScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final usage = ref.watch(adminUsageProvider);
    return RefreshIndicator(
      onRefresh: () async => ref.refresh(adminUsageProvider.future),
      child: usage.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => AwErrorState(
          message: localizedError(error),
          onRetry: () => ref.invalidate(adminUsageProvider),
        ),
        data: (report) => ListView(
          padding: const EdgeInsets.all(AwSpace.x4),
          children: [
            _InstanceCard(report: report),
            const SizedBox(height: AwSpace.x4),
            Text(
              'ee.admin.usage.teams'.tr(),
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: AwSpace.x2),
            if (report.rows.isEmpty)
              AwEmptyState(
                icon: Icons.groups_outlined,
                title: 'ee.admin.usage.emptyTitle'.tr(),
                message: 'ee.admin.usage.emptyBody'.tr(),
              )
            else
              for (final row in _byPressure(report.rows))
                Card(
                  margin: const EdgeInsets.only(bottom: AwSpace.x2),
                  child: ListTile(
                    onTap: () => context.go('/admin/teams/${row.id}'),
                    title: Text(row.name),
                    subtitle: Padding(
                      padding: const EdgeInsets.only(top: AwSpace.x1),
                      child: AdminSeatBar(
                        used: row.seats.used,
                        max: row.seats.max,
                        exceeded: row.seats.exceeded,
                      ),
                    ),
                    trailing: _StatusChip(status: row.status),
                  ),
                ),
          ],
        ),
      ),
    );
  }

  /// Fullest first: a dashboard that lists alphabetically makes the operator
  /// find the problem instead of showing it to them.
  static List<TeamUsage> _byPressure(List<TeamUsage> rows) {
    double pressure(TeamUsage row) {
      final max = row.seats.max;
      if (max == null) return -1; // uncapped teams cannot be "nearly full"
      if (max == 0) return double.infinity;
      return row.seats.used / max;
    }

    final sorted = [...rows]
      ..sort((a, b) => pressure(b).compareTo(pressure(a)));
    return sorted;
  }
}

class _InstanceCard extends StatelessWidget {
  const _InstanceCard({required this.report});
  final InstanceUsage report;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AwSpace.x4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'ee.admin.usage.instance'.tr(),
              style: theme.textTheme.titleMedium,
            ),
            const SizedBox(height: AwSpace.x2),
            AdminSeatBar(
              used: report.teamsUsed,
              max: report.teamsMax,
              exceeded:
                  report.teamsMax != null &&
                  report.teamsUsed > report.teamsMax!,
              countKey: 'ee.admin.teamsBar.count',
              unlimitedKey: 'ee.admin.teamsBar.unlimited',
            ),
          ],
        ),
      ),
    );
  }
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.status});
  final AdminTeamStatus status;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final (label, color) = switch (status) {
      AdminTeamStatus.active => (
        'ee.admin.status.active',
        theme.colorScheme.primary,
      ),
      AdminTeamStatus.suspended => (
        'ee.admin.status.suspended',
        theme.colorScheme.error,
      ),
      AdminTeamStatus.pendingDelete => (
        'ee.admin.status.pendingDelete',
        theme.colorScheme.error,
      ),
    };
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AwSpace.x3,
        vertical: AwSpace.x1,
      ),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(AwRadius.pill),
      ),
      child: Text(
        label.tr(),
        style: theme.textTheme.labelSmall?.copyWith(color: color),
      ),
    );
  }
}
