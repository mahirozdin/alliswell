import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/api_exception.dart';
import '../../../../core/error_messages.dart';
import '../../../../i18n/i18n.dart';
import '../../../../theme/tokens.dart';
import '../admin_providers.dart';

/// The operator's front door (EE-033). Three fields, always: e-mail, password
/// and a six-digit code. There is no shape of this form that signs an operator
/// in without the second factor, because there is no shape of the REQUEST that
/// does either (EE-028) — the screen simply refuses to imply otherwise.
class AdminLoginScreen extends ConsumerStatefulWidget {
  const AdminLoginScreen({super.key});

  @override
  ConsumerState<AdminLoginScreen> createState() => _AdminLoginScreenState();
}

class _AdminLoginScreenState extends ConsumerState<AdminLoginScreen> {
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _code = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    _code.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref
          .read(adminSessionProvider.notifier)
          .signIn(
            email: _email.text.trim(),
            password: _password.text,
            totpCode: _code.text.trim(),
          );
      if (mounted) context.go('/admin');
    } on ApiException catch (e) {
      // One message for every wrong half — which one it was lives in the
      // audit log, where the operator can read it and a guesser cannot.
      if (mounted) setState(() => _error = localizedError(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(title: Text('ee.admin.signIn.title'.tr())),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(AwSpace.x6),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'ee.admin.signIn.subtitle'.tr(),
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: AwSpace.x6),
                TextField(
                  controller: _email,
                  autofillHints: const [AutofillHints.email],
                  keyboardType: TextInputType.emailAddress,
                  decoration: InputDecoration(
                    labelText: 'ee.admin.signIn.email'.tr(),
                  ),
                ),
                const SizedBox(height: AwSpace.x4),
                TextField(
                  controller: _password,
                  obscureText: true,
                  decoration: InputDecoration(
                    labelText: 'ee.admin.signIn.password'.tr(),
                  ),
                ),
                const SizedBox(height: AwSpace.x4),
                TextField(
                  controller: _code,
                  keyboardType: TextInputType.number,
                  maxLength: 6,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  decoration: InputDecoration(
                    labelText: 'ee.admin.signIn.code'.tr(),
                    helperText: 'ee.admin.signIn.codeHelp'.tr(),
                  ),
                  onSubmitted: (_) => _submit(),
                ),
                if (_error != null) ...[
                  const SizedBox(height: AwSpace.x2),
                  Text(
                    _error!,
                    key: const Key('admin-login-error'),
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.error,
                    ),
                  ),
                ],
                const SizedBox(height: AwSpace.x6),
                FilledButton(
                  onPressed: _busy ? null : _submit,
                  child: Text(
                    _busy
                        ? 'ee.admin.signIn.working'.tr()
                        : 'ee.admin.signIn.action'.tr(),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
