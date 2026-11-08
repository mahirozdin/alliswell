import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../i18n/i18n.dart';
import '../../../theme/tokens.dart';
import '../../../widgets/status_views.dart';
import '../data/models.dart';
import '../providers.dart';
import 'auth_messages.dart';
import 'auth_scaffold.dart';
import 'forgot_password_screen.dart';

/// Where a reset link lands: `<web app>/#/reset-password?token=…` (OPH-406).
const String kResetPasswordPath = '/reset-password';

/// The token in whatever was pasted: a whole link (`…?token=…`) or the bare
/// code the operator's command prints without a web address. Null when
/// nothing usable is there.
String? awResetTokenFrom(String input) {
  final text = input.trim();
  if (text.isEmpty) return null;
  final match = RegExp(r'[?&]token=([^&#\s]+)').firstMatch(text);
  if (match != null) return Uri.decodeQueryComponent(match.group(1)!);
  if (RegExp(r'^[A-Za-z0-9_-]{20,128}$').hasMatch(text)) return text;
  return null;
}

/// Sets a new password with a reset link. Opened by the link itself (the
/// token rides in the address) or from "I have a link", where the link is
/// pasted — the way a phone gets one that arrived on another device.
class ResetPasswordScreen extends ConsumerStatefulWidget {
  const ResetPasswordScreen({this.token, super.key});

  final String? token;

  @override
  ConsumerState<ResetPasswordScreen> createState() =>
      _ResetPasswordScreenState();
}

class _ResetPasswordScreenState extends ConsumerState<ResetPasswordScreen> {
  final _formKey = GlobalKey<FormState>();
  final _link = TextEditingController();
  final _password = TextEditingController();
  bool _showPassword = false;
  bool _submitting = false;
  bool _done = false;
  String? _error;

  /// The link stopped working (spent, expired, unknown): offer a new one.
  bool _linkDead = false;

  bool get _hasToken => (widget.token ?? '').isNotEmpty;

  @override
  void dispose() {
    _link.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    final token = _hasToken ? widget.token! : awResetTokenFrom(_link.text)!;
    setState(() {
      _submitting = true;
      _error = null;
      _linkDead = false;
    });
    try {
      await ref
          .read(authApiProvider)
          .resetPassword(token: token, password: _password.text);
      if (mounted) setState(() => _done = true);
    } on Object catch (e) {
      if (mounted) {
        setState(() {
          _error = friendlyAuthMessage(e);
          _linkDead = e is AuthException && e.code == 'AUTH_RESET_INVALID';
        });
      }
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (_done) {
      return AuthScaffold(
        title: 'auth.reset.title'.tr(),
        children: [
          Icon(
            Icons.check_circle_outline,
            size: AwSpace.x12,
            color: theme.colorScheme.primary,
          ),
          const SizedBox(height: AwSpace.x3),
          Text(
            'auth.reset.doneTitle'.tr(),
            key: const Key('reset-done'),
            textAlign: TextAlign.center,
            style: theme.textTheme.titleMedium,
          ),
          const SizedBox(height: AwSpace.x2),
          Text('auth.reset.doneBody'.tr(), style: theme.textTheme.bodyMedium),
          const SizedBox(height: AwSpace.x4),
          FilledButton(
            onPressed: () => context.go('/login'),
            child: Text('auth.signIn'.tr()),
          ),
        ],
      );
    }
    return AuthScaffold(
      title: 'auth.reset.title'.tr(),
      children: [
        Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (!_hasToken) ...[
                TextFormField(
                  key: const Key('reset-link'),
                  controller: _link,
                  keyboardType: TextInputType.url,
                  textInputAction: TextInputAction.next,
                  decoration: InputDecoration(
                    labelText: 'auth.reset.linkLabel'.tr(),
                    helperText: 'auth.reset.linkHelper'.tr(),
                    helperMaxLines: 2,
                    prefixIcon: const Icon(Icons.link),
                  ),
                  validator: (v) => awResetTokenFrom(v ?? '') == null
                      ? 'auth.reset.linkMissing'.tr()
                      : null,
                ),
                const SizedBox(height: AwSpace.x3),
              ],
              TextFormField(
                key: const Key('reset-password'),
                controller: _password,
                autofillHints: const [AutofillHints.newPassword],
                obscureText: !_showPassword,
                textInputAction: TextInputAction.done,
                onFieldSubmitted: (_) => _submit(),
                decoration: InputDecoration(
                  labelText: 'auth.reset.newPassword'.tr(),
                  helperText: 'auth.passwordHelper'.tr(),
                  prefixIcon: const Icon(Icons.lock_outline),
                  suffixIcon: IconButton(
                    tooltip: _showPassword
                        ? 'auth.hidePassword'.tr()
                        : 'auth.showPassword'.tr(),
                    icon: Icon(
                      _showPassword
                          ? Icons.visibility_off_outlined
                          : Icons.visibility_outlined,
                    ),
                    onPressed: () =>
                        setState(() => _showPassword = !_showPassword),
                  ),
                ),
                validator: (v) => (v == null || v.length < 8)
                    ? 'auth.passwordTooShort'.tr()
                    : null,
              ),
            ],
          ),
        ),
        if (_error != null) ...[
          const SizedBox(height: AwSpace.x3),
          AwInlineError(message: _error!, textKey: const Key('reset-error')),
        ],
        const SizedBox(height: AwSpace.x4),
        FilledButton(
          key: const Key('reset-save'),
          onPressed: _submitting ? null : _submit,
          child: _submitting
              ? const SizedBox(
                  width: AwSpace.x5,
                  height: AwSpace.x5,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : Text('auth.reset.save'.tr()),
        ),
        const SizedBox(height: AwSpace.x2),
        if (_linkDead)
          TextButton(
            key: const Key('reset-request-new'),
            onPressed: () => context.go(kForgotPasswordPath),
            child: Text('auth.reset.requestNew'.tr()),
          ),
        TextButton(
          onPressed: _submitting ? null : () => context.go('/login'),
          child: Text('auth.forgot.backToLogin'.tr()),
        ),
      ],
    );
  }
}
