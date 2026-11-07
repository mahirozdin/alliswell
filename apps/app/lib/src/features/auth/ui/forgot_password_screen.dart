import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../i18n/i18n.dart';
import '../../../theme/tokens.dart';
import '../../../widgets/status_views.dart';
import '../data/auth_api.dart';
import '../providers.dart';
import 'auth_messages.dart';
import 'auth_scaffold.dart';

/// Where "Forgot password?" leads (OPH-406, ADR-0064).
const String kForgotPasswordPath = '/forgot-password';

/// The command an operator runs when the server sends no mail. Not
/// translated: it is typed into a shell exactly like this.
String awResetLinkCommand(String email) =>
    'docker compose exec api node apps/api/src/cli/password-reset-link.js '
    '${email.isEmpty ? '<email>' : email}';

/// Asks the server for a reset link. The answer never says whether the
/// address has an account; it only says how this server hands links out —
/// by mail, or through its operator when it sends none.
class ForgotPasswordScreen extends ConsumerStatefulWidget {
  const ForgotPasswordScreen({this.initialEmail, super.key});

  /// What the sign-in form already had in its email field.
  final String? initialEmail;

  @override
  ConsumerState<ForgotPasswordScreen> createState() =>
      _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends ConsumerState<ForgotPasswordScreen> {
  final _formKey = GlobalKey<FormState>();
  late final _email = TextEditingController(text: widget.initialEmail ?? '');
  bool _submitting = false;
  String? _error;
  PasswordResetDelivery? _delivery;

  @override
  void dispose() {
    _email.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      final delivery = await ref
          .read(authApiProvider)
          .forgotPassword(
            email: _email.text.trim(),
            locale: AwI18n.instance.locale.languageCode,
          );
      if (mounted) setState(() => _delivery = delivery);
    } on Object catch (e) {
      if (mounted) setState(() => _error = friendlyAuthMessage(e));
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  Future<void> _copyCommand(String command) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      await Clipboard.setData(ClipboardData(text: command));
      messenger.showSnackBar(
        SnackBar(content: Text('auth.forgot.copied'.tr())),
      );
    } catch (_) {
      // The command stays selectable on screen; nothing is lost.
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final delivery = _delivery;
    return AuthScaffold(
      title: 'auth.forgot.title'.tr(),
      children: [
        if (delivery == null) ...[
          Text('auth.forgot.body'.tr(), style: theme.textTheme.bodyMedium),
          const SizedBox(height: AwSpace.x4),
          Form(
            key: _formKey,
            child: TextFormField(
              key: const Key('forgot-email'),
              controller: _email,
              autofillHints: const [AutofillHints.email],
              keyboardType: TextInputType.emailAddress,
              textInputAction: TextInputAction.send,
              onFieldSubmitted: (_) => _submit(),
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
          ),
          if (_error != null) ...[
            const SizedBox(height: AwSpace.x3),
            AwInlineError(message: _error!, textKey: const Key('forgot-error')),
          ],
          const SizedBox(height: AwSpace.x4),
          FilledButton(
            key: const Key('forgot-send'),
            onPressed: _submitting ? null : _submit,
            child: _submitting
                ? const SizedBox(
                    width: AwSpace.x5,
                    height: AwSpace.x5,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Text('auth.forgot.send'.tr()),
          ),
        ] else if (delivery == PasswordResetDelivery.email) ...[
          _Outcome(
            key: const Key('forgot-sent'),
            icon: Icons.mark_email_read_outlined,
            title: 'auth.forgot.sentTitle'.tr(),
            body: 'auth.forgot.sentBody'.tr(
              args: {'email': _email.text.trim()},
            ),
          ),
        ] else ...[
          _Outcome(
            key: const Key('forgot-admin'),
            icon: Icons.admin_panel_settings_outlined,
            title: 'auth.forgot.adminTitle'.tr(),
            body: 'auth.forgot.adminBody'.tr(),
          ),
          const SizedBox(height: AwSpace.x3),
          _CommandBox(
            command: awResetLinkCommand(_email.text.trim()),
            onCopy: _copyCommand,
          ),
        ],
        const SizedBox(height: AwSpace.x3),
        TextButton(
          key: const Key('forgot-have-link'),
          onPressed: _submitting ? null : () => context.go('/reset-password'),
          child: Text('auth.forgot.haveLink'.tr()),
        ),
        TextButton(
          onPressed: _submitting ? null : () => context.go('/login'),
          child: Text('auth.forgot.backToLogin'.tr()),
        ),
      ],
    );
  }
}

/// An answer in the card: icon, title, one paragraph.
class _Outcome extends StatelessWidget {
  const _Outcome({
    required this.icon,
    required this.title,
    required this.body,
    super.key,
  });

  final IconData icon;
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Icon(icon, size: AwSpace.x12, color: theme.colorScheme.primary),
        const SizedBox(height: AwSpace.x3),
        Text(
          title,
          textAlign: TextAlign.center,
          style: theme.textTheme.titleMedium,
        ),
        const SizedBox(height: AwSpace.x2),
        Text(body, style: theme.textTheme.bodyMedium),
      ],
    );
  }
}

/// The operator's command, selectable and with a copy button.
class _CommandBox extends StatelessWidget {
  const _CommandBox({required this.command, required this.onCopy});

  final String command;
  final Future<void> Function(String command) onCopy;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsetsDirectional.fromSTEB(
        AwSpace.x3,
        AwSpace.x2,
        AwSpace.x1,
        AwSpace.x2,
      ),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: const BorderRadius.all(Radius.circular(AwRadius.s)),
      ),
      child: Row(
        children: [
          Expanded(
            child: SelectableText(
              command,
              key: const Key('forgot-command'),
              style: theme.textTheme.bodySmall?.copyWith(
                fontFamily: 'monospace',
              ),
            ),
          ),
          IconButton(
            tooltip: 'auth.forgot.copyCommand'.tr(),
            icon: const Icon(Icons.copy_outlined),
            onPressed: () => onCopy(command),
          ),
        ],
      ),
    );
  }
}
