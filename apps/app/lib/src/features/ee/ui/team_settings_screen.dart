import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/error_messages.dart';
import '../../../i18n/i18n.dart';
import '../../../theme/tokens.dart';
import '../../../widgets/color_swatch_dot.dart';
import '../../../widgets/status_views.dart';
import '../../files/data/attach_source.dart';
import '../../files/data/pick_files.dart';
import '../data/team_settings.dart';
import '../team_settings_providers.dart';
import '../../../widgets/route_leading.dart';

/// The team settings form (EE-037) — the first screen a team admin owns.
///
/// Two presentation rules the code below exists to keep:
///
///   • NULL IS A CHOICE, and it is spelled "follow the app / derived". Every
///     picker therefore carries an explicit "not set" option rather than
///     silently preselecting a default nobody chose.
///   • THE SERVER'S ANSWER WINS. Saving does not keep what was typed — the
///     response (trimmed name, uppercased colour) replaces the form, so what
///     is on screen is always what is stored.
class EeTeamSettingsScreen extends ConsumerStatefulWidget {
  const EeTeamSettingsScreen({super.key});

  @override
  ConsumerState<EeTeamSettingsScreen> createState() =>
      _EeTeamSettingsScreenState();
}

/// The colours a team may pick, matching the server's roster palette so a
/// team chip and a member avatar never clash by a shade.
const List<String> _kTeamColors = [
  '#2563EB',
  '#7C3AED',
  '#DB2777',
  '#DC2626',
  '#EA580C',
  '#CA8A04',
  '#16A34A',
  '#0D9488',
  '#0284C7',
  '#4F46E5',
];

List<String> _kTeamColorNames() => awColorNames([
  for (final hex in _kTeamColors)
    Color(int.parse('FF${hex.substring(1)}', radix: 16)),
]);

/// A short list, deliberately: these are the zones the product is sold into
/// today, and a 400-entry dropdown is not a setting, it is a search problem.
/// The server accepts any IANA id, so widening this is a one-line change.
const List<String> _kTimezones = [
  'Europe/Istanbul',
  'Europe/London',
  'Europe/Berlin',
  'Europe/Amsterdam',
  'America/New_York',
  'America/Chicago',
  'America/Los_Angeles',
  'Asia/Dubai',
  'UTC',
];

class _EeTeamSettingsScreenState extends ConsumerState<EeTeamSettingsScreen> {
  final _name = TextEditingController();
  String? _loadedFor;
  bool _busy = false;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  /// Fills the field from the server's answer once per loaded value — never
  /// on every rebuild, which would fight the user's cursor mid-word.
  void _adopt(EeTeamSettings settings) {
    final stamp = '${settings.name}\x00${settings.slug}';
    if (_loadedFor == stamp) return;
    _loadedFor = stamp;
    _name.text = settings.name;
  }

  Future<void> _run(Future<void> Function() action) async {
    setState(() => _busy = true);
    try {
      await action();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(eeTeamSettingsProvider);
    return Scaffold(
      appBar: AppBar(
        leading: awRouteLeading(context),
        title: Text('ee.team.settings.title'.tr()),
      ),
      body: async.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => AwErrorState(
          message: localizedError(error),
          onRetry: () => ref.invalidate(eeTeamSettingsProvider),
        ),
        data: (settings) {
          _adopt(settings);
          return _form(context, settings);
        },
      ),
    );
  }

  Widget _form(BuildContext context, EeTeamSettings settings) {
    final controller = ref.read(eeTeamSettingsProvider.notifier);
    return ListView(
      padding: const EdgeInsets.all(AwSpace.x4),
      children: [
        _logo(settings, controller),
        const SizedBox(height: AwSpace.x6),
        TextField(
          controller: _name,
          enabled: !_busy,
          decoration: InputDecoration(
            labelText: 'ee.team.settings.name'.tr(),
            // The subdomain is not editable here and saying why costs a line:
            // a slug that moved would break every link anybody saved.
            helperText: 'ee.team.settings.slugFixed'.tr(
              args: {'slug': settings.slug},
            ),
          ),
          onSubmitted: (value) =>
              _run(() => controller.save(name: value.trim())),
        ),
        const SizedBox(height: AwSpace.x6),
        _localePicker(settings, controller),
        const SizedBox(height: AwSpace.x6),
        _timezonePicker(settings, controller),
        const SizedBox(height: AwSpace.x6),
        _colorPicker(settings, controller),
        const SizedBox(height: AwSpace.x8),
        FilledButton(
          onPressed: _busy
              ? null
              : () => _run(() => controller.save(name: _name.text.trim())),
          child: Text('common.save'.tr()),
        ),
        const SizedBox(height: AwSpace.x6),
        // EE-042: the other two halves of the team area. Rows rather than
        // tabs, for the same reason the settings groups are rows — each one
        // is a place somebody can be sent to.
        Card(
          child: Column(
            children: [
              ListTile(
                key: const Key('team-open-members'),
                leading: const Icon(Icons.people_outline),
                title: Text('ee.team.open.members'.tr()),
                subtitle: Text('ee.team.open.membersSub'.tr()),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => context.push('/settings/team/members'),
              ),
              const Divider(indent: AwSpace.x4, endIndent: AwSpace.x4),
              ListTile(
                key: const Key('team-open-invites'),
                leading: const Icon(Icons.mail_outline),
                title: Text('ee.team.open.invites'.tr()),
                subtitle: Text('ee.team.open.invitesSub'.tr()),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => context.push('/settings/team/invites'),
              ),
              const Divider(indent: AwSpace.x4, endIndent: AwSpace.x4),
              // EE-053: the third thing a team admin owns. Next to the other
              // two because they are the same job — who is here, how they got
              // here, and what they may do.
              ListTile(
                key: const Key('team-open-roles'),
                leading: const Icon(Icons.badge_outlined),
                title: Text('ee.team.open.roles'.tr()),
                subtitle: Text('ee.team.open.rolesSub'.tr()),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => context.push('/settings/team/roles'),
              ),
              const Divider(indent: AwSpace.x4, endIndent: AwSpace.x4),
              // EE-057: units — the team's SHAPE, next to the three rows about
              // its people, because "who is here" and "where they work" are
              // one job split in two.
              ListTile(
                key: const Key('team-open-units'),
                leading: const Icon(Icons.apartment_outlined),
                title: Text('ee.team.open.units'.tr()),
                subtitle: Text('ee.team.open.unitsSub'.tr()),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => context.push('/settings/team/units'),
              ),
              const Divider(indent: AwSpace.x4, endIndent: AwSpace.x4),
              // EE-061: the receiving end of EE-059's bridge.
              ListTile(
                key: const Key('team-open-shared'),
                leading: const Icon(Icons.move_to_inbox_outlined),
                title: Text('ee.team.open.shared'.tr()),
                subtitle: Text('ee.team.open.sharedSub'.tr()),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => context.push('/settings/team/shared'),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _logo(EeTeamSettings settings, EeTeamSettingsController controller) {
    return Row(
      children: [
        SizedBox(
          width: 64,
          height: 64,
          child: settings.logoUrl == null
              ? DecoratedBox(
                  decoration: BoxDecoration(
                    color: Theme.of(
                      context,
                    ).colorScheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(AwRadius.m),
                  ),
                  child: const Icon(Icons.groups_outlined),
                )
              : ClipRRect(
                  borderRadius: BorderRadius.circular(AwRadius.m),
                  child: Image.network(settings.logoUrl!, fit: BoxFit.cover),
                ),
        ),
        const SizedBox(width: AwSpace.x4),
        Expanded(
          child: Wrap(
            spacing: AwSpace.x2,
            children: [
              OutlinedButton(
                onPressed: _busy ? null : () => _pickLogo(controller),
                child: Text('ee.team.settings.logoPick'.tr()),
              ),
              if (settings.hasLogo)
                TextButton(
                  onPressed: _busy ? null : () => _run(controller.removeLogo),
                  child: Text('ee.team.settings.logoRemove'.tr()),
                ),
            ],
          ),
        ),
      ],
    );
  }

  Future<void> _pickLogo(EeTeamSettingsController controller) async {
    final picked = await pickUploads(AttachSource.imageLibrary);
    if (picked.isEmpty) return;
    await _run(() => controller.uploadLogo(picked.first));
  }

  /// A CONTROLLED dropdown, not a `DropdownButtonFormField`: a form field
  /// keeps its own copy of the selection and never adopts a changed
  /// `initialValue`, so a save that failed would leave the picker showing a
  /// value the server rejected. Here the only source of truth is `settings`.
  Widget _picker({
    required String label,
    String? helper,
    required String? value,
    required List<DropdownMenuItem<String?>> items,
    required void Function(String?) onChanged,
  }) => InputDecorator(
    decoration: InputDecoration(labelText: label, helperText: helper),
    child: DropdownButtonHideUnderline(
      child: DropdownButton<String?>(
        value: value,
        isExpanded: true,
        items: items,
        onChanged: _busy ? null : onChanged,
      ),
    ),
  );

  Widget _localePicker(
    EeTeamSettings settings,
    EeTeamSettingsController controller,
  ) => _picker(
    label: 'ee.team.settings.language'.tr(),
    value: settings.locale,
    items: [
      DropdownMenuItem(
        value: null,
        child: Text('ee.team.settings.languageUnset'.tr()),
      ),
      for (final locale in awSupportedLocales)
        DropdownMenuItem(
          value: locale.languageCode,
          child: Text(
            awLanguageEndonyms[locale.languageCode] ?? locale.languageCode,
          ),
        ),
    ],
    onChanged: (value) => _run(
      () => value == null
          ? controller.save(clear: const {'locale'})
          : controller.save(locale: value),
    ),
  );

  Widget _timezonePicker(
    EeTeamSettings settings,
    EeTeamSettingsController controller,
  ) => _picker(
    label: 'ee.team.settings.timezone'.tr(),
    helper: 'ee.team.settings.timezoneHelp'.tr(),
    value: settings.timezone,
    items: [
      DropdownMenuItem(
        value: null,
        child: Text('ee.team.settings.timezoneUnset'.tr()),
      ),
      // A stored zone outside the short list must still be shown, not
      // silently replaced by "not set" the moment somebody opens this screen.
      for (final zone in {
        ..._kTimezones,
        if (settings.timezone != null) settings.timezone!,
      })
        DropdownMenuItem(value: zone, child: Text(zone)),
    ],
    onChanged: (value) => _run(
      () => value == null
          ? controller.save(clear: const {'timezone'})
          : controller.save(timezone: value),
    ),
  );

  Widget _colorPicker(
    EeTeamSettings settings,
    EeTeamSettingsController controller,
  ) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        'ee.team.settings.color'.tr(),
        style: Theme.of(context).textTheme.labelLarge,
      ),
      const SizedBox(height: AwSpace.x2),
      Wrap(
        spacing: AwSpace.x2,
        runSpacing: AwSpace.x2,
        children: [
          _swatch(
            label: 'ee.team.settings.colorUnset'.tr(),
            selected: settings.colorRgb == null,
            color: null,
            onTap: () => _run(() => controller.save(clear: const {'colorRgb'})),
          ),
          for (final (i, hex) in _kTeamColors.indexed)
            _swatch(
              // OPH-359 (UI-AUDIT #64): a colour's name, not its hex.
              label: _kTeamColorNames()[i],
              selected: settings.colorRgb == hex,
              color: Color(int.parse('FF${hex.substring(1)}', radix: 16)),
              onTap: () => _run(() => controller.save(colorRgb: hex)),
            ),
        ],
      ),
    ],
  );

  Widget _swatch({
    required String label,
    required bool selected,
    required Color? color,
    required VoidCallback onTap,
  }) => Semantics(
    label: label,
    selected: selected,
    button: true,
    child: InkWell(
      onTap: _busy ? null : onTap,
      borderRadius: BorderRadius.circular(AwRadius.m),
      child: Container(
        width: 36,
        height: 36,
        decoration: BoxDecoration(
          color: color ?? Theme.of(context).colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(AwRadius.m),
          border: Border.all(
            color: selected
                ? Theme.of(context).colorScheme.onSurface
                : Colors.transparent,
            width: 2,
          ),
        ),
        child: color == null ? const Icon(Icons.block, size: 18) : null,
      ),
    ),
  );
}
