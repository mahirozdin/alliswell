import 'package:flutter/material.dart';

import '../../../i18n/i18n.dart';
import '../../../theme/tokens.dart';
import '../../../widgets/status_views.dart';
import '../data/models.dart';
import 'auth_messages.dart';

/// Runs a sign-in [attempt] and, when the account has a second factor, asks
/// for the code and runs the SAME attempt again with it (OPH-381).
///
/// [attempt] is called with `null` first. If the server answers
/// `AUTH_MFA_REQUIRED`, the prompt opens and every submit calls
/// `attempt(code)` — for Google / Apple that is the same ID token, so the
/// native provider sheet is never shown twice. Returns the session, or `null`
/// when the person cancelled the prompt (they stay on the sign-in screen with
/// no error: backing out is not a failure). Any other refusal of the first
/// attempt is rethrown for the screen to show as it always has.
///
/// [onPrompt] runs just before the prompt opens, so the screen can stop its
/// own spinner: from then on the prompt shows the work in progress.
Future<AuthSession?> signInWithSecondFactor(
  BuildContext context,
  Future<AuthSession> Function(String? totpCode) attempt, {
  VoidCallback? onPrompt,
}) async {
  try {
    return await attempt(null);
  } on AuthException catch (e) {
    if (e.code != 'AUTH_MFA_REQUIRED') rethrow;
  }
  if (!context.mounted) return null;
  onPrompt?.call();
  return showDialog<AuthSession>(
    context: context,
    useRootNavigator: true,
    // A tap beside the card must not throw away a half-typed code; Cancel
    // and the back gesture are the ways out.
    barrierDismissible: false,
    builder: (_) => SecondFactorDialog(submit: attempt),
  );
}

/// The code prompt itself. It owns its controller (DESIGN §25 R5) and stays
/// open on a wrong code, so a mistyped digit costs one retype, not a new
/// sign-in. Accepts an authenticator code or a recovery code — the server
/// tells them apart, so the field does not ask which one it is.
class SecondFactorDialog extends StatefulWidget {
  const SecondFactorDialog({super.key, required this.submit});

  final Future<AuthSession> Function(String totpCode) submit;

  @override
  State<SecondFactorDialog> createState() => _SecondFactorDialogState();
}

class _SecondFactorDialogState extends State<SecondFactorDialog> {
  final _code = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _code.dispose();
    super.dispose();
  }

  Future<void> _verify() async {
    if (_busy) return;
    final code = _code.text.trim();
    if (code.length < 6) {
      setState(() => _error = 'auth.mfa.enterCode'.tr());
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final session = await widget.submit(code);
      if (mounted) Navigator.of(context).pop(session);
    } on Object catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = e is AuthException && e.code == 'AUTH_MFA_INVALID'
            ? 'auth.mfa.invalid'.tr()
            : friendlyAuthMessage(e);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AlertDialog(
      key: const Key('second-factor-dialog'),
      icon: Icon(
        Icons.verified_user_outlined,
        color: theme.colorScheme.primary,
      ),
      title: Text('auth.mfa.title'.tr()),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 400),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'auth.mfa.body'.tr(),
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: AwSpace.x4),
            TextField(
              key: const Key('second-factor-code'),
              controller: _code,
              autofocus: true,
              enabled: !_busy,
              autofillHints: const [AutofillHints.oneTimeCode],
              // Text, not number: a recovery code has letters and a dash.
              keyboardType: TextInputType.visiblePassword,
              textCapitalization: TextCapitalization.characters,
              autocorrect: false,
              enableSuggestions: false,
              maxLength: 32,
              textInputAction: TextInputAction.done,
              onSubmitted: (_) => _verify(),
              decoration: InputDecoration(
                labelText: 'auth.mfa.code'.tr(),
                helperText: 'auth.mfa.codeHelp'.tr(),
                helperMaxLines: 2,
                prefixIcon: const Icon(Icons.pin_outlined),
                counterText: '',
              ),
            ),
            if (_error != null) ...[
              const SizedBox(height: AwSpace.x3),
              AwInlineError(
                message: _error!,
                textKey: const Key('second-factor-error'),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          key: const Key('second-factor-cancel'),
          onPressed: _busy ? null : () => Navigator.of(context).pop(),
          child: Text('common.cancel'.tr()),
        ),
        FilledButton(
          key: const Key('second-factor-verify'),
          onPressed: _busy ? null : _verify,
          child: _busy
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : Text('auth.mfa.verify'.tr()),
        ),
      ],
    );
  }
}
