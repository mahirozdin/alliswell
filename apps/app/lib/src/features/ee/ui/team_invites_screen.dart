import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/error_messages.dart';
import '../../../i18n/i18n.dart';
import '../../../theme/tokens.dart';
import '../../../widgets/status_views.dart';
import '../data/team_admin_models.dart';
import '../team_admin_providers.dart';

/// Invitations (EE-042).
///
/// The screen exists to protect one property of the credential: THE LINK AND
/// THE CODE TRAVEL SEPARATELY. So they are shown apart, copied apart, and
/// there is deliberately no "copy both" — a single button that puts a working
/// credential on the clipboard would undo the reason there are two halves.
///
/// The other thing it must not do is imply delivery it cannot perform. When
/// the server sends no mail, the sheet says so plainly and hands the admin
/// the link, because on that instance THEY are the delivery mechanism.
class EeTeamInvitesScreen extends ConsumerWidget {
  const EeTeamInvitesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final invites = ref.watch(eeInvitesProvider);
    return Scaffold(
      appBar: AppBar(title: Text('ee.team.invites.title'.tr())),
      floatingActionButton: FloatingActionButton.extended(
        key: const Key('invite-create'),
        // The app theme sets a CircleBorder for every FAB and this Flutter
        // has no separate slot for the extended one, so the pill has to be
        // asked for here — without it the label spills past a circle.
        shape: const StadiumBorder(),
        onPressed: () => _create(context, ref),
        icon: const Icon(Icons.person_add_alt),
        label: Text('ee.team.invites.new'.tr()),
      ),
      body: invites.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => AwErrorState(
          message: localizedError(error),
          onRetry: () => ref.invalidate(eeInvitesProvider),
        ),
        data: (items) => items.isEmpty
            ? AwEmptyState(
                icon: Icons.mark_email_unread_outlined,
                title: 'ee.team.invites.emptyTitle'.tr(),
                message: 'ee.team.invites.emptyBody'.tr(),
              )
            : ListView.builder(
                padding: const EdgeInsets.all(AwSpace.x4),
                itemCount: items.length,
                itemBuilder: (context, i) => _InviteTile(invite: items[i]),
              ),
      ),
    );
  }

  Future<void> _create(BuildContext context, WidgetRef ref) async {
    final email = TextEditingController();
    var role = 'member';
    final asked = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: Text('ee.team.invites.new'.tr()),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                key: const Key('invite-email'),
                controller: email,
                autofocus: true,
                keyboardType: TextInputType.emailAddress,
                decoration: InputDecoration(
                  labelText: 'ee.team.invites.email'.tr(),
                ),
              ),
              const SizedBox(height: AwSpace.x4),
              InputDecorator(
                decoration: InputDecoration(
                  labelText: 'ee.team.invites.role'.tr(),
                ),
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<String>(
                    value: role,
                    isExpanded: true,
                    items: [
                      for (final r in ['member', 'admin'])
                        DropdownMenuItem(
                          value: r,
                          child: Text('ee.team.role.$r'.tr()),
                        ),
                    ],
                    onChanged: (value) =>
                        setState(() => role = value ?? 'member'),
                  ),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: Text('common.cancel'.tr()),
            ),
            FilledButton(
              key: const Key('invite-submit'),
              onPressed: () => Navigator.of(context).pop(true),
              child: Text('ee.team.invites.send'.tr()),
            ),
          ],
        ),
      ),
    );
    if (asked != true || email.text.trim().isEmpty) return;

    final minted = await ref
        .read(eeInvitesProvider.notifier)
        .mint(email: email.text.trim(), role: role);
    if (context.mounted) await _showCredential(context, minted);
  }

  /// The one and only time both halves exist outside somebody's memory. The
  /// sheet says that out loud, because there is no endpoint that can show
  /// them again — only digests were stored.
  Future<void> _showCredential(BuildContext context, EeMintedInvite minted) {
    return showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        key: const Key('invite-credential'),
        title: Text('ee.team.invites.readyTitle'.tr()),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              minted.sendsMail
                  ? 'ee.team.invites.mailed'.tr(
                      args: {'email': minted.invite.email},
                    )
                  : 'ee.team.invites.manual'.tr(
                      args: {'email': minted.invite.email},
                    ),
            ),
            const SizedBox(height: AwSpace.x4),
            _CopyRow(
              keyName: 'invite-copy-link',
              label: 'ee.team.invites.link'.tr(),
              value: minted.link,
            ),
            const SizedBox(height: AwSpace.x3),
            _CopyRow(
              keyName: 'invite-copy-code',
              label: 'ee.team.invites.code'.tr(),
              value: minted.code,
              emphasize: true,
            ),
            const SizedBox(height: AwSpace.x3),
            // Said plainly rather than implied by the layout: the two halves
            // are useless apart and dangerous together.
            Text(
              'ee.team.invites.separately'.tr(),
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
        actions: [
          FilledButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text('common.done'.tr()),
          ),
        ],
      ),
    );
  }
}

class _CopyRow extends StatelessWidget {
  const _CopyRow({
    required this.keyName,
    required this.label,
    required this.value,
    this.emphasize = false,
  });

  final String keyName;
  final String label;
  final String value;
  final bool emphasize;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: theme.textTheme.labelSmall),
              SelectableText(
                value,
                style: emphasize
                    ? theme.textTheme.headlineSmall?.copyWith(letterSpacing: 4)
                    : theme.textTheme.bodySmall,
              ),
            ],
          ),
        ),
        IconButton(
          key: Key(keyName),
          tooltip: 'common.copy'.tr(),
          icon: const Icon(Icons.copy_outlined),
          onPressed: () => Clipboard.setData(ClipboardData(text: value)),
        ),
      ],
    );
  }
}

class _InviteTile extends ConsumerWidget {
  const _InviteTile({required this.invite});
  final EeInvite invite;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ListTile(
      key: Key('invite-${invite.id}'),
      leading: Icon(
        invite.isLive ? Icons.schedule : Icons.block_outlined,
        color: invite.isLive ? null : Theme.of(context).disabledColor,
      ),
      title: Text(invite.email),
      subtitle: Text(
        // One vocabulary with the server: pending / accepted / revoked /
        // expired / burned, each with its own sentence.
        '${'ee.team.role.${invite.role}'.tr()} · ${'ee.invite.state.${invite.state}'.tr()}',
      ),
      trailing: invite.isLive
          ? IconButton(
              key: Key('invite-revoke-${invite.id}'),
              tooltip: 'ee.team.invites.revoke'.tr(),
              icon: const Icon(Icons.cancel_outlined),
              onPressed: () =>
                  ref.read(eeInvitesProvider.notifier).revoke(invite.id),
            )
          : null,
    );
  }
}
