import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api_exception.dart';
import '../../../i18n/i18n.dart';
import '../../../theme/tokens.dart';
import '../../../widgets/status_views.dart';
import '../../auth/providers.dart';
import '../data/caldav_api.dart';
import '../providers.dart';

/// Apple's own page on app-specific passwords (CALDAV.md §8 ref 6).
final Uri appleAppPasswordHelp = Uri.parse(
  'https://support.apple.com/en-us/102654',
);

/// Opens the connect form (OPH-380). Resolves the result on success, null when
/// the user closes it.
///
/// [offerIcloud] is false on an iPhone or Mac: there the Apple Calendar card
/// (EventKit) is the iCloud path, and an app-specific password is asked only
/// in sessions without an Apple device (CALDAV.md, ADR-0059). A reconnect of
/// an existing iCloud account still offers it.
Future<CaldavConnectResult?> showCaldavConnectSheet(
  BuildContext context, {
  required String workspaceId,
  required bool offerIcloud,
  CaldavAccount? reconnect,
}) => showModalBottomSheet<CaldavConnectResult>(
  context: context,
  // OPH-212: the ROOT navigator, above the shell's glass bar. Solid surface —
  // a form and its consent text are body text, never on glass (DESIGN §3).
  useRootNavigator: true,
  showDragHandle: true,
  isScrollControlled: true,
  useSafeArea: true,
  constraints: const BoxConstraints(maxWidth: 560),
  builder: (_) => CaldavConnectSheet(
    workspaceId: workspaceId,
    offerIcloud: offerIcloud || (reconnect?.isIcloud ?? false),
    reconnect: reconnect,
  ),
);

class CaldavConnectSheet extends ConsumerStatefulWidget {
  const CaldavConnectSheet({
    super.key,
    required this.workspaceId,
    required this.offerIcloud,
    this.reconnect,
  });

  final String workspaceId;
  final bool offerIcloud;
  final CaldavAccount? reconnect;

  @override
  ConsumerState<CaldavConnectSheet> createState() => _CaldavConnectSheetState();
}

class _CaldavConnectSheetState extends ConsumerState<CaldavConnectSheet> {
  late String _server;
  final _url = TextEditingController();
  final _username = TextEditingController();
  final _password = TextEditingController();
  bool _showPassword = false;
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    final reconnect = widget.reconnect;
    _server = reconnect != null
        ? reconnect.server
        : (widget.offerIcloud ? 'icloud' : 'generic');
    if (reconnect != null) {
      _username.text = reconnect.username;
      if (!reconnect.isIcloud) {
        _url.text = reconnect.serverUrl ?? 'https://${reconnect.serverHost}';
      }
    }
  }

  @override
  void dispose() {
    _url.dispose();
    _username.dispose();
    _password.dispose();
    super.dispose();
  }

  bool get _icloud => _server == 'icloud';

  /// The host this app talks to — the server that will hold the password.
  String _serverHost() {
    final base = Uri.tryParse(ref.read(apiClientProvider).options.baseUrl);
    if (base != null && base.host.isNotEmpty) return base.host;
    if (Uri.base.host.isNotEmpty) return Uri.base.host;
    return 'calendar.caldav.thisServer'.tr();
  }

  /// Server codes → a sentence a person can act on (no jargon, DESIGN §12).
  String _message(ApiException e) => switch (e.code) {
    'CALDAV_AUTH_FAILED' =>
      _icloud
          ? 'calendar.caldav.authFailedIcloud'.tr()
          : 'calendar.caldav.authFailedGeneric'.tr(),
    'CALDAV_NOT_CALDAV' => 'calendar.caldav.notCaldav'.tr(),
    'CALDAV_NO_CALENDARS' => 'calendar.caldav.noCalendars'.tr(),
    'CALDAV_BLOCKED_ADDRESS' ||
    'CALDAV_BAD_URL' => 'calendar.caldav.blockedAddress'.tr(),
    'CALDAV_REDIRECT_OFF_HOST' => 'calendar.caldav.redirectOffHost'.tr(),
    'CALDAV_UNREACHABLE' ||
    'CALDAV_REQUEST_FAILED' => 'calendar.caldav.unreachable'.tr(),
    'CALDAV_ALREADY_CONNECTED' => 'calendar.caldav.alreadyConnected'.tr(),
    'CALDAV_NOT_ENABLED' => 'calendar.caldav.notEnabled'.tr(),
    'NETWORK_ERROR' => 'calendar.networkError'.tr(),
    _ => e.message,
  };

  bool get _complete =>
      _username.text.trim().isNotEmpty &&
      _password.text.isNotEmpty &&
      (_icloud || _url.text.trim().isNotEmpty);

  Future<void> _submit() async {
    if (_busy || !_complete) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final result = await ref
          .read(caldavIntegrationsApiProvider)
          .connect(
            widget.workspaceId,
            server: _server,
            url: _icloud ? null : _url.text.trim(),
            username: _username.text.trim(),
            password: _password.text,
          );
      if (mounted) Navigator.of(context).pop(result);
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = _message(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final consent = _icloud
        ? 'calendar.caldav.consentIcloud'.tr(args: {'server': _serverHost()})
        : 'calendar.caldav.consentGeneric'.tr(args: {'server': _serverHost()});
    return Padding(
      padding: EdgeInsets.fromLTRB(
        AwSpace.x4,
        0,
        AwSpace.x4,
        AwSpace.x4 + MediaQuery.viewInsetsOf(context).bottom,
      ),
      child: SingleChildScrollView(
        child: AutofillGroup(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'calendar.caldav.connectTitle'.tr(),
                style: theme.textTheme.titleMedium,
              ),
              const SizedBox(height: AwSpace.x3),
              if (widget.offerIcloud && widget.reconnect == null) ...[
                SegmentedButton<String>(
                  key: const Key('caldav-server'),
                  segments: [
                    ButtonSegment(
                      value: 'icloud',
                      label: Text('calendar.caldav.icloudSegment'.tr()),
                    ),
                    ButtonSegment(
                      value: 'generic',
                      label: Text('calendar.caldav.genericSegment'.tr()),
                    ),
                  ],
                  selected: {_server},
                  showSelectedIcon: false,
                  onSelectionChanged: _busy
                      ? null
                      : (value) => setState(() {
                          _server = value.first;
                          _error = null;
                        }),
                ),
                const SizedBox(height: AwSpace.x4),
              ],
              if (!_icloud) ...[
                TextField(
                  key: const Key('caldav-url'),
                  controller: _url,
                  enabled: !_busy,
                  keyboardType: TextInputType.url,
                  autocorrect: false,
                  enableSuggestions: false,
                  autofillHints: const [AutofillHints.url],
                  decoration: InputDecoration(
                    labelText: 'calendar.caldav.serverLabel'.tr(),
                    hintText: 'https://cloud.example.org', // i18n-ignore: a URL
                  ),
                  onChanged: (_) => setState(() {}),
                ),
                const SizedBox(height: AwSpace.x3),
              ],
              TextField(
                key: const Key('caldav-username'),
                controller: _username,
                enabled: !_busy,
                keyboardType: _icloud
                    ? TextInputType.emailAddress
                    : TextInputType.text,
                autocorrect: false,
                enableSuggestions: false,
                autofillHints: [
                  _icloud ? AutofillHints.email : AutofillHints.username,
                ],
                decoration: InputDecoration(
                  labelText: _icloud
                      ? 'calendar.caldav.appleIdLabel'.tr()
                      : 'calendar.caldav.usernameLabel'.tr(),
                ),
                onChanged: (_) => setState(() {}),
              ),
              const SizedBox(height: AwSpace.x3),
              TextField(
                key: const Key('caldav-password'),
                controller: _password,
                enabled: !_busy,
                obscureText: !_showPassword,
                autocorrect: false,
                enableSuggestions: false,
                decoration: InputDecoration(
                  labelText: _icloud
                      ? 'calendar.caldav.appPasswordLabel'.tr()
                      : 'calendar.caldav.passwordLabel'.tr(),
                  hintText: _icloud ? 'xxxx-xxxx-xxxx-xxxx' : null,
                  suffixIcon: IconButton(
                    key: const Key('caldav-password-toggle'),
                    tooltip: _showPassword
                        ? 'calendar.caldav.hidePassword'.tr()
                        : 'calendar.caldav.showPassword'.tr(),
                    icon: Icon(
                      _showPassword
                          ? Icons.visibility_off_outlined
                          : Icons.visibility_outlined,
                    ),
                    onPressed: () =>
                        setState(() => _showPassword = !_showPassword),
                  ),
                ),
                onChanged: (_) => setState(() {}),
                onSubmitted: (_) => _submit(),
              ),
              if (_icloud)
                Align(
                  alignment: AlignmentDirectional.centerStart,
                  child: TextButton(
                    key: const Key('caldav-help'),
                    onPressed: () =>
                        ref.read(urlLauncherProvider)(appleAppPasswordHelp),
                    child: Text('calendar.caldav.howToMake'.tr()),
                  ),
                ),
              const SizedBox(height: AwSpace.x3),
              // CALDAV.md §3.3: informed consent, in the user's words, ABOVE
              // the button — not in a help page afterwards.
              Text(
                consent,
                key: const Key('caldav-consent'),
                style: theme.textTheme.bodySmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
              if (_error != null) ...[
                const SizedBox(height: AwSpace.x3),
                AwInlineError(key: const Key('caldav-error'), message: _error!),
              ],
              const SizedBox(height: AwSpace.x4),
              FilledButton(
                key: const Key('caldav-submit'),
                style: FilledButton.styleFrom(
                  minimumSize: const Size.fromHeight(48),
                ),
                onPressed: _busy || !_complete ? null : _submit,
                child: _busy
                    ? const SizedBox.square(
                        dimension: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : Text('calendar.connect'.tr()),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
