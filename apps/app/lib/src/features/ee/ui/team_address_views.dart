import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/server_url.dart' show prettyServerUrl;
import '../../../i18n/i18n.dart';
import '../../../sections.dart';
import '../../../theme/tokens.dart';
import '../../../widgets/status_views.dart';
import '../data/team_address_api.dart';
import '../providers.dart';
import '../team_admin_providers.dart'
    show eeHoldsTeamVerbProvider, eeTeamProvider;
import '../team_origin.dart';

/// The one "your team's address is needed" state (OPH-356, UI-AUDIT #7).
///
/// Every team surface that cannot answer on this address draws THIS — not an
/// empty list, not "you may not", not an English HTTP code. When the server
/// has said where the person's team lives, the way there is one tap.
class EeTeamAddressRequiredView extends ConsumerWidget {
  const EeTeamAddressRequiredView({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final hint = ref.watch(eeTeamAddressHintProvider);
    final origin = hint?.origin;
    return AwEmptyState(
      key: const Key('ee-team-address-required'),
      icon: Icons.domain_outlined,
      title: 'ee.teamAddress.requiredTitle'.tr(),
      message: hint == null || origin == null
          ? 'ee.teamAddress.requiredBody'.tr()
          : 'ee.teamAddress.requiredBodyTeam'.tr(
              args: {'team': hint.name, 'host': prettyServerUrl(origin)},
            ),
      action: origin == null
          ? null
          : FilledButton.icon(
              key: const Key('ee-team-address-switch'),
              onPressed: () => switchToTeamOrigin(
                ProviderScope.containerOf(context, listen: false),
                origin,
                router: GoRouter.maybeOf(context),
              ),
              icon: const Icon(Icons.swap_horiz),
              label: Text(
                'ee.teamAddress.switch'.tr(
                  args: {'host': prettyServerUrl(origin)},
                ),
              ),
            ),
    );
  }
}

/// The one locked state for a team-administration screen this person may not
/// open (OPH-356, UI-AUDIT #61). It replaces six different answers — a red
/// "something went wrong" with a retry that could never succeed, an
/// "unavailable", a wrong reason — and the create buttons drawn over them.
class EeForbiddenView extends StatelessWidget {
  const EeForbiddenView({super.key});

  @override
  Widget build(BuildContext context) => AwEmptyState(
    key: const Key('ee-forbidden'),
    icon: Icons.lock_outline,
    title: 'ee.forbidden.title'.tr(),
    message: 'ee.forbidden.body'.tr(),
    action: OutlinedButton.icon(
      onPressed: () => context.go(AppSection.home.path),
      icon: const Icon(Icons.home_outlined),
      label: Text('ee.forbidden.back'.tr()),
    ),
  );
}

/// For a screen's error branch: the two typed answers get their own state,
/// everything else the shared error with a retry.
Widget eeTeamErrorView(
  WidgetRef ref,
  Object error, {
  required String message,
  VoidCallback? onRetry,
}) {
  if (error is EeNoTeamHereException) {
    if (ref.watch(teamOriginProvider) == null) {
      return const EeTeamAddressRequiredView();
    }
    return AwEmptyState(
      key: const Key('ee-not-in-team'),
      icon: Icons.group_off_outlined,
      title: 'ee.teamAddress.notInTeamTitle'.tr(),
      message: 'ee.teamAddress.notInTeamBody'.tr(),
    );
  }
  return AwErrorState(message: message, onRetry: onRetry);
}

/// The door in front of a team-administration route (OPH-356, UI-AUDIT #61).
///
/// The rows in Settings were already drawn only for the people they serve;
/// the ROUTES were not, so an address typed or shared opened the screen for
/// anyone, and the screen asked the server, drew its 403 as a failure and its
/// "+" as an invitation. Now the route answers first:
///
///   1. not on the team's address → [EeTeamAddressRequiredView];
///   2. nothing known yet → a spinner, never controls (a delegated manager
///      saw "New unit" for the second the permissions took to arrive);
///   3. not theirs → [EeForbiddenView];
///   4. otherwise the screen.
///
/// "Theirs": the verb, held by an owner/admin of the team or granted through
/// a governed role ([permission]); [adminOnly] screens are the owner's and
/// admins' alone. The server still decides every request (ADR-0007 §5).
class EeTeamRouteGate extends ConsumerWidget {
  const EeTeamRouteGate({
    super.key,
    required this.titleKey,
    required this.child,
    this.permission,
    this.adminOnly = false,
  });

  final String titleKey;
  final Widget child;
  final String? permission;
  final bool adminOnly;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    Widget locked(Widget body) => Scaffold(
      appBar: AppBar(title: Text(titleKey.tr())),
      body: body,
    );

    if (ref.watch(eeTeamAddressRequiredProvider)) {
      return locked(const EeTeamAddressRequiredView());
    }
    if (permission == null && !adminOnly) return child;

    final status = ref.watch(eeStatusProvider);
    if (!status.hasValue) {
      return locked(const Center(child: CircularProgressIndicator()));
    }
    // A plain build has no team and no gate: the screen says so itself.
    if (!status.value!.has('teams')) return child;

    final bool? allowed;
    if (adminOnly) {
      final team = ref.watch(eeTeamProvider);
      allowed = team.hasValue ? (team.value?.isAdmin ?? false) : null;
    } else {
      allowed = ref.watch(eeHoldsTeamVerbProvider(permission!));
    }
    if (allowed == null) {
      return locked(
        const Center(
          key: Key('ee-gate-loading'),
          child: CircularProgressIndicator(),
        ),
      );
    }
    if (!allowed) return locked(const EeForbiddenView());
    return child;
  }
}

/// "Your team lives at X — switch" (OPH-356, UI-AUDIT #7), at the top of Home
/// for somebody signed in on the service's own address whose team the server
/// named. Renders nothing otherwise, and nothing once dismissed for that
/// address.
class EeTeamAddressBanner extends ConsumerWidget {
  const EeTeamAddressBanner({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final hint = ref.watch(eeTeamAddressHintProvider);
    final origin = hint?.origin;
    if (hint == null || origin == null) return const SizedBox.shrink();
    if (ref.watch(eeTeamHintDismissedProvider).value ?? true) {
      return const SizedBox.shrink();
    }
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final host = prettyServerUrl(origin);
    return Padding(
      padding: const EdgeInsets.fromLTRB(AwSpace.x4, AwSpace.x2, AwSpace.x4, 0),
      child: Material(
        key: const Key('ee-team-address-banner'),
        color: scheme.secondaryContainer,
        borderRadius: const BorderRadius.all(Radius.circular(AwRadius.m)),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
            AwSpace.x3,
            AwSpace.x3,
            AwSpace.x2,
            AwSpace.x2,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    Icons.domain_outlined,
                    size: 20,
                    color: scheme.onSecondaryContainer,
                  ),
                  const SizedBox(width: AwSpace.x2),
                  Expanded(
                    child: Text(
                      'ee.teamAddress.bannerBody'.tr(
                        args: {'team': hint.name, 'host': host},
                      ),
                      style: text.bodyMedium?.copyWith(
                        color: scheme.onSecondaryContainer,
                      ),
                    ),
                  ),
                ],
              ),
              Wrap(
                alignment: WrapAlignment.end,
                spacing: AwSpace.x2,
                children: [
                  TextButton(
                    key: const Key('ee-team-address-dismiss'),
                    onPressed: () => dismissTeamHint(ref),
                    style: TextButton.styleFrom(
                      foregroundColor: scheme.onSecondaryContainer,
                      minimumSize: const Size(44, 44),
                    ),
                    child: Text('ee.teamAddress.bannerDismiss'.tr()),
                  ),
                  FilledButton(
                    key: const Key('ee-team-address-banner-switch'),
                    onPressed: () => switchToTeamOrigin(
                      ProviderScope.containerOf(context, listen: false),
                      origin,
                      router: GoRouter.maybeOf(context),
                    ),
                    style: FilledButton.styleFrom(
                      minimumSize: const Size(44, 44),
                    ),
                    child: Text(
                      'ee.teamAddress.switch'.tr(args: {'host': host}),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
