import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../i18n/i18n.dart';
import '../../../sections.dart';
import '../../../widgets/status_views.dart';
import '../providers.dart';
import '../team_origin.dart';

/// `/join/:token` (EE-018) — the landing place for a team invite.
///
/// The invite EXCHANGE is E04's work; what exists here is the destination, so
/// a link never lands on a blank page or a "no route" error. Signed-out taps
/// are already handled upstream: the router remembers the location, sends the
/// visitor to sign in, and replays it afterwards — so by the time this builds
/// there is a session, and the only questions left are whether this server
/// runs teams at all and whether the token can be redeemed yet.
class JoinTeamScreen extends ConsumerWidget {
  const JoinTeamScreen({super.key, required this.token});

  final String token;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final teamsEnabled = ref.watch(eeFeatureProvider('teams'));
    final team = ref.watch(teamOriginProvider);
    final home = FilledButton(
      onPressed: () => context.go(AppSection.home.path),
      child: Text('ee.join.goHome'.tr()),
    );

    return Scaffold(
      appBar: AppBar(title: Text('ee.join.title'.tr())),
      body: teamsEnabled
          // The token is not redeemable until E04 ships the exchange. Saying
          // so plainly beats a spinner that never resolves.
          ? AwEmptyState(
              icon: Icons.hourglass_empty_outlined,
              title: 'ee.join.pendingTitle'.tr(),
              message: team == null
                  ? 'ee.join.pendingBody'.tr()
                  : 'ee.join.pendingBodyTeam'.tr(
                      args: {'team': team.displayName},
                    ),
              action: home,
            )
          // A CE server (or one without the teams entitlement) cannot honour
          // an invite — the honest answer, not a 404 the user must decode.
          : AwEmptyState(
              icon: Icons.link_off_outlined,
              title: 'ee.join.unavailableTitle'.tr(),
              message: 'ee.join.unavailableBody'.tr(),
              action: home,
            ),
    );
  }
}
