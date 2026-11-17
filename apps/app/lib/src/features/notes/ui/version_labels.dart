import '../../../core/date_format.dart';
import '../../../i18n/i18n.dart';
import '../../devices/data/device_api.dart';
import '../../devices/device_display_name.dart';
import '../data/note_versions_api.dart';

/// How a version names WHAT happened, WHERE and WHEN (OPH-494).
///
/// One person with several devices reads history by device — "which of my
/// machines wrote this, and exactly when". Version history, the version
/// preview, the conflict banner and its diff all name both the same way, so a
/// collision can be read as two concrete moments on two concrete devices.

/// What happened: edit, create, merge, conflict, restore, import, API, AI.
String versionOriginLabel(String origin) => switch (origin) {
  'merge' => 'versions.originMerge'.tr(),
  'conflict' => 'versions.originConflict'.tr(),
  'restore' => 'versions.originRestore'.tr(),
  'import' => 'versions.originImport'.tr(),
  'api' => 'versions.originApi'.tr(),
  'mcp' => 'versions.originAi'.tr(),
  'create' => 'versions.originCreate'.tr(),
  _ => 'versions.originEdit'.tr(),
};

/// Which device: "This device" when it is ours, the registry's name for one
/// of the person's other devices, a plain fallback for one that is not (or no
/// longer) on their list, and the writer's kind when no device wrote it.
String versionDeviceLabel({
  required String? clientId,
  required String? myClientId,
  String? deviceName,
  String? devicePlatform,
  String? origin,
}) {
  if (clientId != null && clientId == myClientId) {
    return 'versions.originThisDevice'.tr();
  }
  if (clientId != null) {
    final name = deviceDisplayName(
      DeviceInfo(
        id: clientId,
        platform: devicePlatform ?? '',
        name: deviceName,
      ),
    );
    return name.trim().isEmpty ? 'versions.deviceUnknown'.tr() : name;
  }
  return switch (origin) {
    'api' => 'versions.originApi'.tr(),
    'mcp' => 'versions.originAi'.tr(),
    _ => 'versions.deviceNone'.tr(),
  };
}

/// The exact local moment, to the second: "18 Kas 14:32:05".
String versionMoment(DateTime at, {required String dateFormat}) =>
    '${awFormatDate(at, format: dateFormat)} '
    '${awFormatTimeSeconds(at, format: dateFormat)}';

/// A list row's clock: the session's span when it rolled several saves into
/// one version ("14:02 – 14:09:31"), else the one moment.
String versionClock(NoteVersionSummary version, {required String dateFormat}) {
  final end = awFormatTimeSeconds(version.updatedAt, format: dateFormat);
  if (version.updatedAt.difference(version.createdAt).inSeconds < 1) return end;
  return '${awFormatTime(version.createdAt, format: dateFormat)} – $end';
}

/// "MacBook · 18 Kas 14:32:05" for a version.
String versionWho(
  NoteVersionSummary version, {
  required String? myClientId,
  required String dateFormat,
}) =>
    '${versionDeviceLabel(clientId: version.clientId, myClientId: myClientId, deviceName: version.deviceName, devicePlatform: version.devicePlatform, origin: version.origin)}'
    ' · ${versionMoment(version.updatedAt, dateFormat: dateFormat)}';

/// The same for the note as it is now (a diff's other side).
String currentSideWho(
  NoteDiffSide side, {
  required String? myClientId,
  required String dateFormat,
}) =>
    '${versionDeviceLabel(clientId: side.clientId, myClientId: myClientId, deviceName: side.deviceName, devicePlatform: side.devicePlatform, origin: side.origin)}'
    ' · ${versionMoment(side.updatedAt, dateFormat: dateFormat)}';
