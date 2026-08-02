import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../i18n/i18n.dart';
import '../data/social_sign_in.dart';
import '../providers.dart';

/// "Continue with Google / Apple", shared by the sign-in and register screens.
///
/// Apple's own rule shapes the layout: an app offering a third-party social
/// login on Apple platforms **must** also offer Sign in with Apple, and it must
/// not be visually subordinate. So on iOS/macOS both buttons render at the same
/// weight, with Apple first — and on Android the Apple button is absent, because
/// the web fallback there needs a Services ID this deployment may not have.
class SocialSignInButtons extends ConsumerStatefulWidget {
  const SocialSignInButtons({super.key, this.onSignedIn});

  /// Called after the AllisWell session exists. The router usually reacts to the
  /// session itself, so this is for extras like the first-run tour.
  final void Function({required bool created})? onSignedIn;

  @override
  ConsumerState<SocialSignInButtons> createState() =>
      _SocialSignInButtonsState();
}

class _SocialSignInButtonsState extends ConsumerState<SocialSignInButtons> {
  SocialProvider? _busy;
  String? _error;

  Future<void> _start(SocialProvider provider) async {
    setState(() {
      _busy = provider;
      _error = null;
    });
    try {
      final social = ref.read(socialSignInProvider);
      final idToken = switch (provider) {
        SocialProvider.google => await social.googleIdToken(),
        SocialProvider.apple => await social.appleIdToken(),
      };
      final session = await ref
          .read(authRepositoryProvider)
          .signInWithProvider(provider: provider.wire, idToken: idToken);
      if (!mounted) return;
      widget.onSignedIn?.call(created: session.created);
    } on SocialSignInCancelled {
      // Backing out is not a failure; showing an error for it would be rude.
      if (mounted) setState(() => _busy = null);
      return;
    } on SocialSignInFailed catch (error) {
      if (mounted) setState(() => _error = error.message);
    } on Object {
      // Anything from our own API — a refused token, an unconfigured provider,
      // an e-mail already taken. The message is deliberately generic here; the
      // server's own reason is surfaced by the shared error mapper.
      if (mounted) setState(() => _error = 'auth.socialFailed'.tr());
    } finally {
      if (mounted) setState(() => _busy = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final busy = _busy != null;
    final buttons = <Widget>[
      if (SocialSignIn.appleAvailable)
        _SocialButton(
          key: const Key('sign-in-apple'),
          label: 'auth.continueWithApple'.tr(),
          icon: Icons.apple,
          busy: _busy == SocialProvider.apple,
          onPressed: busy ? null : () => _start(SocialProvider.apple),
        ),
      _SocialButton(
        key: const Key('sign-in-google'),
        label: 'auth.continueWithGoogle'.tr(),
        icon: Icons.g_mobiledata,
        busy: _busy == SocialProvider.google,
        onPressed: busy ? null : () => _start(SocialProvider.google),
      ),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            const Expanded(child: Divider()),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Text(
                'auth.or'.tr(),
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
            const Expanded(child: Divider()),
          ],
        ),
        const SizedBox(height: 16),
        for (final (i, button) in buttons.indexed) ...[
          if (i > 0) const SizedBox(height: 10),
          button,
        ],
        if (_error != null) ...[
          const SizedBox(height: 12),
          Text(
            _error!,
            key: const Key('social-sign-in-error'),
            textAlign: TextAlign.center,
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
        ],
      ],
    );
  }
}

class _SocialButton extends StatelessWidget {
  const _SocialButton({
    super.key,
    required this.label,
    required this.icon,
    required this.busy,
    required this.onPressed,
  });

  final String label;
  final IconData icon;
  final bool busy;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return OutlinedButton.icon(
      onPressed: onPressed,
      // 48 high like every other control here (DESIGN G4).
      style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(48)),
      icon: busy
          ? const SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : Icon(icon, size: 22),
      label: Text(label),
    );
  }
}
