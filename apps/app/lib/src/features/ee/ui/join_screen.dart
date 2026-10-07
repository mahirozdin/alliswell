import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/api_exception.dart';
import '../../../core/error_messages.dart';
import '../../../core/server_url.dart';
import '../../../i18n/i18n.dart';
import '../../../router.dart' show pendingDeepLinkProvider;
import '../../../sections.dart';
import '../../../theme/tokens.dart';
import '../../../widgets/status_views.dart';
import '../../auth/providers.dart';
import '../data/team_address_api.dart';
import '../providers.dart';
import '../team_origin.dart';
import '../../../widgets/route_leading.dart';

/// Where an invitation was resolved to: the address its endpoints answer on,
/// and what the invitation says there.
class JoinTarget {
  const JoinTarget({required this.origin, required this.preview, this.team});

  final String origin;
  final EeInvitePreview preview;

  /// The team the link's `server` names, when it named one.
  final AwTeamOrigin? team;
}

/// The link's `server` is not a team of the instance this app trusts
/// (ADR-0021 §4) — said, with the host, never silently ignored.
class JoinWrongServer implements Exception {
  const JoinWrongServer(this.host);
  final String host;
}

/// Resolves `/join/:token?server=…` (OPH-356, UI-AUDIT #5).
///
/// Without `server` the invitation is asked on the address the app is on —
/// the behaviour before the link carried one. With it, the value must be an
/// https team host hanging off the apex this app already trusts
/// ([trustedTeamApexes]): signed in, the one `/ee/status` names; signed out,
/// the server's own domain. The invitation must then agree that it belongs to
/// that team. Anything else is [JoinWrongServer].
Future<JoinTarget> resolveJoinTarget(
  WidgetRef ref, {
  required String token,
  String? server,
}) async {
  // A cold start opens this before the session has restored: who is asking
  // decides which domain is trusted, so that is known first.
  if (ref.read(authControllerProvider).isLoading) {
    try {
      await ref.read(authControllerProvider.future);
    } catch (_) {}
  }
  final current = ref.read(apiBaseUrlProvider);
  final raw = server?.trim() ?? '';
  if (raw.isEmpty) {
    final preview = await eeInviteApiFor(ref, current).preview(token);
    return JoinTarget(origin: current, preview: preview);
  }
  final host = Uri.tryParse(raw)?.host ?? '';
  final signedIn = ref.read(authControllerProvider).value != null;
  String? baseDomain;
  if (signedIn) {
    baseDomain = (await ref.read(eeStatusProvider.future)).baseDomain;
    // Signed in to an instance that names no apex: nothing here can vouch
    // for the link's host, and this session must not travel to it.
    if (baseDomain == null || baseDomain.isEmpty) {
      throw JoinWrongServer(host.isEmpty ? raw : host);
    }
  }
  final accepted = acceptJoinServer(
    raw,
    trustedTeamApexes(current, baseDomain: baseDomain),
  );
  if (accepted == null) throw JoinWrongServer(host.isEmpty ? raw : host);
  final preview = await eeInviteApiFor(ref, accepted.origin).preview(token);
  final slug = preview.teamSlug;
  if (slug != null && slug != accepted.team.slug) {
    throw JoinWrongServer(host);
  }
  return JoinTarget(
    origin: accepted.origin,
    preview: preview,
    team: accepted.team,
  );
}

/// `/join/:token` (EE-018, EE-039; OPH-356) — the landing place for a team
/// invitation, and now the place it is redeemed.
///
/// Reachable signed out: the person an invitation is for very often has no
/// account yet, and a team host refuses free registration — this screen is
/// where that account is made. The link names the team's address (`server`);
/// the screen shows that address before anything is sent to it.
class JoinTeamScreen extends ConsumerStatefulWidget {
  const JoinTeamScreen({super.key, required this.token, this.server});

  final String token;

  /// The `?server=` of the link (ADR-0021 §3), or null.
  final String? server;

  @override
  ConsumerState<JoinTeamScreen> createState() => _JoinTeamScreenState();
}

class _JoinTeamScreenState extends ConsumerState<JoinTeamScreen> {
  late final Future<JoinTarget> _target = _resolve();
  final _code = TextEditingController();
  final _name = TextEditingController();
  final _password = TextEditingController();
  bool _busy = false;
  String? _error;

  Future<JoinTarget> _resolve() =>
      resolveJoinTarget(ref, token: widget.token, server: widget.server);

  @override
  void dispose() {
    _code.dispose();
    _name.dispose();
    _password.dispose();
    super.dispose();
  }

  void _goHome() => context.go(AppSection.home.path);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: awRouteLeading(context),
        title: Text('ee.join.title'.tr()),
      ),
      body: FutureBuilder<JoinTarget>(
        future: _target,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          final error = snapshot.error;
          if (error is JoinWrongServer) {
            return AwEmptyState(
              key: const Key('join-wrong-server'),
              icon: Icons.gpp_bad_outlined,
              title: 'ee.join.wrongServerTitle'.tr(),
              message: 'ee.join.wrongServerBody'.tr(
                args: {
                  'host': error.host,
                  'server': prettyServerUrl(ref.read(apiBaseUrlProvider)),
                },
              ),
              action: _homeButton(),
            );
          }
          if (error != null) {
            // The route is not there at all: a server without teams.
            if (error is ApiException && error.code == 'HTTP_404') {
              return AwEmptyState(
                key: const Key('join-unavailable'),
                icon: Icons.link_off_outlined,
                title: 'ee.join.unavailableTitle'.tr(),
                message: 'ee.join.unavailableBody'.tr(),
                action: _homeButton(),
              );
            }
            return AwEmptyState(
              key: const Key('join-failed'),
              icon: Icons.link_off_outlined,
              title: 'ee.join.failedTitle'.tr(),
              message: localizedError(error),
              action: _homeButton(),
            );
          }
          return _form(context, snapshot.requireData);
        },
      ),
    );
  }

  Widget _homeButton() {
    final signedIn = ref.watch(authControllerProvider).value != null;
    return FilledButton(
      onPressed: signedIn ? _goHome : () => context.go('/login'),
      child: Text(signedIn ? 'ee.join.goHome'.tr() : 'ee.join.goSignIn'.tr()),
    );
  }

  Widget _form(BuildContext context, JoinTarget target) {
    final theme = Theme.of(context);
    final session = ref.watch(authControllerProvider).value;
    final preview = target.preview;
    final teamName =
        preview.teamName ?? target.team?.displayName ?? preview.teamSlug ?? '';
    final wrongAccount =
        session != null &&
        session.user.email.toLowerCase() != preview.email.toLowerCase();
    final needsSignIn = session == null && preview.accountExists;
    final createsAccount = session == null && !preview.accountExists;

    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(AwSpace.x6),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 430),
          child: Card(
            child: Padding(
              padding: const EdgeInsets.all(AwSpace.x6),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'ee.join.forTeam'.tr(args: {'team': teamName}),
                    style: theme.textTheme.titleLarge,
                  ),
                  const SizedBox(height: AwSpace.x2),
                  // The address is shown BEFORE anything is sent to it: the
                  // link chose it, the person should see which one.
                  Row(
                    children: [
                      Icon(
                        Icons.dns_outlined,
                        size: 18,
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                      const SizedBox(width: AwSpace.x2),
                      Expanded(
                        child: Text(
                          'ee.join.hostLine'.tr(
                            args: {'host': prettyServerUrl(target.origin)},
                          ),
                          key: const Key('join-host'),
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: AwSpace.x1),
                  Text(
                    'ee.join.invitedAs'.tr(args: {'email': preview.email}),
                    style: theme.textTheme.bodyMedium,
                  ),
                  const SizedBox(height: AwSpace.x5),
                  if (wrongAccount)
                    AwInlineError(
                      textKey: const Key('join-wrong-account'),
                      message: 'ee.join.wrongAccount'.tr(
                        args: {
                          'email': preview.email,
                          'current': session.user.email,
                        },
                      ),
                    )
                  else if (needsSignIn) ...[
                    Text(
                      'ee.join.signInFirst'.tr(),
                      style: theme.textTheme.bodyMedium,
                    ),
                    const SizedBox(height: AwSpace.x4),
                    FilledButton(
                      key: const Key('join-sign-in'),
                      onPressed: () => _signInFirst(target),
                      child: Text('ee.join.signIn'.tr()),
                    ),
                  ] else ...[
                    TextField(
                      key: const Key('join-code'),
                      controller: _code,
                      keyboardType: TextInputType.number,
                      maxLength: 6,
                      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                      decoration: InputDecoration(
                        labelText: 'ee.join.codeLabel'.tr(),
                        helperText: 'ee.join.codeHelp'.tr(),
                      ),
                    ),
                    if (createsAccount) ...[
                      const SizedBox(height: AwSpace.x3),
                      TextField(
                        key: const Key('join-name'),
                        controller: _name,
                        textCapitalization: TextCapitalization.words,
                        decoration: InputDecoration(
                          labelText: 'ee.join.nameLabel'.tr(),
                        ),
                      ),
                      const SizedBox(height: AwSpace.x3),
                      TextField(
                        key: const Key('join-password'),
                        controller: _password,
                        obscureText: true,
                        decoration: InputDecoration(
                          labelText: 'ee.join.passwordLabel'.tr(),
                          helperText: 'ee.join.passwordHelp'.tr(),
                        ),
                      ),
                    ],
                    if (_error != null) ...[
                      const SizedBox(height: AwSpace.x3),
                      AwInlineError(
                        textKey: const Key('join-error'),
                        message: _error!,
                      ),
                    ],
                    const SizedBox(height: AwSpace.x4),
                    FilledButton(
                      key: const Key('join-accept'),
                      onPressed: _busy
                          ? null
                          : () => _accept(target, createsAccount),
                      child: _busy
                          ? const SizedBox.square(
                              dimension: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : Text('ee.join.accept'.tr()),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// The address has an account: sign in on the TEAM's address, then come
  /// back here — the pending deep link carries the whole link, `server` and
  /// all, through the sign-in.
  Future<void> _signInFirst(JoinTarget target) async {
    final location = GoRouterState.of(context).uri.toString();
    final container = ProviderScope.containerOf(context, listen: false);
    if (target.origin != container.read(apiBaseUrlProvider)) {
      await container
          .read(serverUrlOverrideProvider.notifier)
          .set(target.origin == compiledApiBaseUrl ? '' : target.origin);
    }
    container.read(pendingDeepLinkProvider.notifier).remember(location);
    if (mounted) context.go('/login');
  }

  Future<void> _accept(JoinTarget target, bool createsAccount) async {
    final code = _code.text.trim();
    if (code.length != 6) {
      setState(() => _error = 'ee.join.codeInvalid'.tr());
      return;
    }
    final password = _password.text;
    if (createsAccount && password.length < 8) {
      setState(() => _error = 'ee.join.passwordShort'.tr());
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    final container = ProviderScope.containerOf(context, listen: false);
    final messenger = ScaffoldMessenger.maybeOf(context);
    final router = GoRouter.of(context);
    try {
      final accepted = await eeInviteApiFor(ref, target.origin).accept(
        widget.token,
        code: code,
        password: createsAccount ? password : null,
        displayName: createsAccount ? _name.text : null,
      );
      // Home first, THEN the address (see `switchToTeamOrigin`): the
      // invitation is spent, and Home is where a new member starts.
      if (target.origin != container.read(apiBaseUrlProvider)) {
        await switchToTeamOrigin(container, target.origin, router: router);
      } else {
        router.go(AppSection.home.path);
      }
      if (accepted.created) {
        await container.read(authControllerProvider.future);
        await container
            .read(authControllerProvider.notifier)
            .login(email: accepted.email, password: password);
      } else {
        container.invalidate(eeStatusProvider);
        container.invalidate(eePermissionsProvider);
      }
      messenger?.showSnackBar(
        SnackBar(
          content: Text(
            'ee.join.joined'.tr(
              args: {
                'team':
                    target.preview.teamName ?? target.team?.displayName ?? '',
              },
            ),
          ),
        ),
      );
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = localizedError(e);
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = 'error.unknown'.tr();
      });
    }
  }
}
