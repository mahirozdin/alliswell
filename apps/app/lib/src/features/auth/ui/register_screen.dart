import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../i18n/i18n.dart';
import '../../../widgets/status_views.dart';
import '../providers.dart';
import 'auth_messages.dart';
import 'auth_scaffold.dart';

class RegisterScreen extends ConsumerStatefulWidget {
  const RegisterScreen({super.key});

  @override
  ConsumerState<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends ConsumerState<RegisterScreen> {
  final _formKey = GlobalKey<FormState>();
  final _displayName = TextEditingController();
  final _email = TextEditingController();
  final _password = TextEditingController();
  bool _submitting = false;
  bool _showPassword = false;
  String? _error;

  @override
  void dispose() {
    _displayName.dispose();
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      await ref
          .read(authControllerProvider.notifier)
          .register(
            email: _email.text.trim(),
            password: _password.text,
            displayName: _displayName.text.trim(),
          );
      // Success: the router redirect leaves this screen.
    } on Object catch (e) {
      setState(() => _error = friendlyAuthMessage(e));
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AuthScaffold(
      title: 'auth.registerTitle'.tr(),
      children: [
        Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextFormField(
                controller: _displayName,
                autofillHints: const [AutofillHints.name],
                textInputAction: TextInputAction.next,
                decoration: InputDecoration(
                  labelText: 'auth.name'.tr(),
                  prefixIcon: const Icon(Icons.person_outline),
                ),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _email,
                autofillHints: const [AutofillHints.email],
                keyboardType: TextInputType.emailAddress,
                textInputAction: TextInputAction.next,
                decoration: InputDecoration(
                  labelText: 'auth.email'.tr(),
                  prefixIcon: const Icon(Icons.alternate_email),
                ),
                validator: (v) {
                  final value = v?.trim() ?? '';
                  if (value.isEmpty || !value.contains('@')) {
                    return 'auth.invalidEmail'.tr();
                  }
                  return null;
                },
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _password,
                autofillHints: const [AutofillHints.newPassword],
                obscureText: !_showPassword,
                textInputAction: TextInputAction.done,
                onFieldSubmitted: (_) => _submit(),
                decoration: InputDecoration(
                  labelText: 'auth.password'.tr(),
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
          const SizedBox(height: 12),
          AwInlineError(message: _error!, textKey: const Key('register-error')),
        ],
        const SizedBox(height: 16),
        FilledButton(
          onPressed: _submitting ? null : _submit,
          child: _submitting
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : Text('auth.createAccount'.tr()),
        ),
        const SizedBox(height: 8),
        TextButton(
          onPressed: _submitting ? null : () => context.go('/login'),
          child: Text('auth.toLogin'.tr()),
        ),
      ],
    );
  }
}
