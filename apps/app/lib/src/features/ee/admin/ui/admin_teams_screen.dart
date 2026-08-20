import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/api_exception.dart';
import '../../../../core/error_messages.dart';
import '../../../../i18n/i18n.dart';
import '../../../../theme/tokens.dart';
import '../../../../widgets/status_views.dart';
import '../admin_providers.dart';
import '../data/admin_models.dart';
import 'admin_shell.dart';

/// The customer list (EE-033). Every destructive control on this screen says
/// what it will do BEFORE it does it, because the smallest mistake here is
/// somebody else's outage.
class AdminTeamsScreen extends ConsumerWidget {
  const AdminTeamsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final teams = ref.watch(adminTeamsProvider);
    return teams.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (error, _) => AwErrorState(
        message: localizedError(error),
        onRetry: () => ref.invalidate(adminTeamsProvider),
      ),
      data: (rows) => rows.isEmpty
          ? AwEmptyState(
              icon: Icons.groups_outlined,
              title: 'ee.admin.teams.emptyTitle'.tr(),
              message: 'ee.admin.teams.emptyBody'.tr(),
            )
          : ListView.builder(
              padding: const EdgeInsets.all(AwSpace.x4),
              itemCount: rows.length,
              itemBuilder: (context, i) {
                final team = rows[i];
                return Card(
                  margin: const EdgeInsets.only(bottom: AwSpace.x2),
                  child: ListTile(
                    onTap: () => context.go('/admin/teams/${team.id}'),
                    title: Text(team.name),
                    subtitle: Text(
                      '${team.slug} · ${team.packageName ?? 'ee.admin.teams.noPackage'.tr()}',
                    ),
                    trailing: Text(
                      team.seatsLimit == null
                          ? 'ee.admin.seats.unlimited'.tr(
                              args: {'used': '${team.seatsUsed}'},
                            )
                          : 'ee.admin.seats.count'.tr(
                              args: {
                                'used': '${team.seatsUsed}',
                                'max': '${team.seatsLimit}',
                              },
                            ),
                    ),
                  ),
                );
              },
            ),
    );
  }
}

/// One customer, and the four things an operator can do to them.
class AdminTeamDetailScreen extends ConsumerStatefulWidget {
  const AdminTeamDetailScreen({super.key, required this.teamId});
  final String teamId;

  @override
  ConsumerState<AdminTeamDetailScreen> createState() =>
      _AdminTeamDetailScreenState();
}

class _AdminTeamDetailScreenState extends ConsumerState<AdminTeamDetailScreen> {
  bool _busy = false;

  Future<void> _run(Future<void> Function(String token) action) async {
    if (_busy) return;
    final token = ref.read(adminSessionProvider).value?.accessToken;
    if (token == null) return;
    setState(() => _busy = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      await action(token);
      ref.invalidate(adminTeamsProvider);
      ref.invalidate(adminUsageProvider);
    } on ApiException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(localizedError(e))));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<bool> _confirm(
    String titleKey,
    String bodyKey, {
    required String name,
  }) async {
    final answer = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(titleKey.tr()),
        content: Text(bodyKey.tr(args: {'team': name})),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text('common.cancel'.tr()),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text('common.ok'.tr()),
          ),
        ],
      ),
    );
    return answer ?? false;
  }

  Future<void> _invite(AdminTeam team) async {
    final controller = TextEditingController();
    final email = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('ee.admin.invite.title'.tr()),
        content: TextField(
          controller: controller,
          autofocus: true,
          keyboardType: TextInputType.emailAddress,
          decoration: InputDecoration(labelText: 'ee.admin.invite.email'.tr()),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text('common.cancel'.tr()),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(controller.text.trim()),
            child: Text('ee.admin.invite.action'.tr()),
          ),
        ],
      ),
    );
    if (email == null || email.isEmpty) return;

    await _run((token) async {
      final minted = await ref
          .read(adminApiProvider)
          .invite(token, team.id, email);
      if (!mounted) return;
      // Shown exactly once, and the screen says so: nothing can read the
      // credential back (EE-031 stores only digests).
      await showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (context) => AlertDialog(
          title: Text('ee.admin.invite.mintedTitle'.tr()),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('ee.admin.invite.onceWarning'.tr()),
              const SizedBox(height: AwSpace.x4),
              SelectableText(
                minted.token,
                style: const TextStyle(fontFamily: 'monospace'),
              ),
              const SizedBox(height: AwSpace.x2),
              SelectableText(
                'ee.admin.invite.code'.tr(args: {'code': minted.code}),
                style: const TextStyle(fontFamily: 'monospace'),
              ),
              const SizedBox(height: AwSpace.x2),
              Text(
                'ee.admin.invite.separately'.tr(),
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () =>
                  Clipboard.setData(ClipboardData(text: minted.token)),
              child: Text('ee.admin.invite.copyLink'.tr()),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text('common.done'.tr()),
            ),
          ],
        ),
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final teams = ref.watch(adminTeamsProvider);
    return teams.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (error, _) => AwErrorState(
        message: localizedError(error),
        onRetry: () => ref.invalidate(adminTeamsProvider),
      ),
      data: (rows) {
        AdminTeam? team;
        for (final row in rows) {
          if (row.id == widget.teamId) team = row;
        }
        if (team == null) {
          return AwEmptyState(
            icon: Icons.search_off,
            title: 'ee.admin.teams.goneTitle'.tr(),
            message: 'ee.admin.teams.goneBody'.tr(),
          );
        }
        final found = team;
        final api = ref.read(adminApiProvider);
        return ListView(
          padding: const EdgeInsets.all(AwSpace.x4),
          children: [
            Text(found.name, style: Theme.of(context).textTheme.headlineSmall),
            Text(found.slug, style: Theme.of(context).textTheme.bodySmall),
            const SizedBox(height: AwSpace.x4),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(AwSpace.x4),
                child: AdminSeatBar(
                  used: found.seatsUsed,
                  max: found.seatsLimit,
                  exceeded:
                      found.seatsLimit != null &&
                      found.seatsUsed > found.seatsLimit!,
                ),
              ),
            ),
            const SizedBox(height: AwSpace.x4),
            if (found.status == AdminTeamStatus.pendingDelete)
              Padding(
                padding: const EdgeInsets.only(bottom: AwSpace.x4),
                child: AwInlineError(message: 'ee.admin.teams.scheduled'.tr()),
              ),
            Wrap(
              spacing: AwSpace.x2,
              runSpacing: AwSpace.x2,
              children: [
                if (found.status == AdminTeamStatus.active)
                  OutlinedButton.icon(
                    onPressed: _busy
                        ? null
                        : () async {
                            if (await _confirm(
                              'ee.admin.teams.suspendTitle',
                              'ee.admin.teams.suspendBody',
                              name: found.name,
                            )) {
                              await _run(
                                (t) => api.teamAction(t, found.id, 'suspend'),
                              );
                            }
                          },
                    icon: const Icon(Icons.pause_circle_outline),
                    label: Text('ee.admin.teams.suspend'.tr()),
                  ),
                if (found.status == AdminTeamStatus.suspended)
                  FilledButton.icon(
                    onPressed: _busy
                        ? null
                        : () => _run(
                            (t) => api.teamAction(t, found.id, 'resume'),
                          ),
                    icon: const Icon(Icons.play_circle_outline),
                    label: Text('ee.admin.teams.resume'.tr()),
                  ),
                if (found.status == AdminTeamStatus.pendingDelete)
                  FilledButton.icon(
                    onPressed: _busy
                        ? null
                        : () => _run(
                            (t) => api.teamAction(t, found.id, 'restore'),
                          ),
                    icon: const Icon(Icons.restore),
                    label: Text('ee.admin.teams.restore'.tr()),
                  ),
                OutlinedButton.icon(
                  onPressed: _busy ? null : () => _invite(found),
                  icon: const Icon(Icons.mail_outline),
                  label: Text('ee.admin.invite.action'.tr()),
                ),
                if (found.status != AdminTeamStatus.pendingDelete)
                  TextButton.icon(
                    onPressed: _busy
                        ? null
                        : () async {
                            if (await _confirm(
                              'ee.admin.teams.deleteTitle',
                              'ee.admin.teams.deleteBody',
                              name: found.name,
                            )) {
                              await _run(
                                (t) => api.scheduleTeamDeletion(t, found.id),
                              );
                            }
                          },
                    icon: const Icon(Icons.delete_outline),
                    label: Text('ee.admin.teams.delete'.tr()),
                  ),
              ],
            ),
          ],
        );
      },
    );
  }
}
