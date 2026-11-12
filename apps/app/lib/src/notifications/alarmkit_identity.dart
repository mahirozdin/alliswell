/// AlarmKit occurrence identity (NOTIFICATIONS.md §2b.3 "Identity", #49).
///
/// Pure and shared byte for byte with the Swift side (`ios/Shared`), which
/// computes the same numbers for a native snooze without asking Dart. The
/// fixture `test/fixtures/alarmkit_identity_cases.json` is written from these
/// functions and read by the Swift tests, so the two can only drift loudly.
///
/// - The **id** names an occurrence: WHICH tasks ring and WHEN. Moving a task
///   from 09:00 to 10:00 changes it, so the scheduler's id diff replaces the
///   alarm and nothing is left at 09:00.
/// - The **fingerprint** names the presentation: title, body, sound, button
///   labels, snooze preset. Renaming a task keeps the id and changes only the
///   fingerprint, so the alarm is rebuilt in place instead of being treated as
///   a different occurrence.
library;

import 'gateway.dart';

/// [t] as UTC epoch milliseconds, floored to the whole second. Swift reaches
/// the same value from a `Date` without floating-point error creeping into the
/// id; the server keeps `DATETIME(3)`, so a whole second always round-trips.
int alarmKitFireAtMs(DateTime t) {
  final ms = t.toUtc().millisecondsSinceEpoch;
  return ms - ms % 1000;
}

/// The members exactly as they enter the id seed: de-duplicated and sorted by
/// UTF-16 code unit (Dart's `String.compareTo`, Swift's `utf16` ordering).
List<String> alarmKitMembers(Iterable<String> members) =>
    members.toSet().toList()..sort();

/// The string the occurrence id hashes. Exposed for the shared fixture.
String alarmKitOccurrenceSeed(Iterable<String> members, int fireAtMs) =>
    'akv2|${alarmKitMembers(members).join(',')}|$fireAtMs';

/// FNV-1a (UTF-16 code units, masked positive) of
/// `akv2|<sorted unique members>|<fireAtMs>`. The member key is the task id,
/// never the reminder id: a synthetic alarm and the reminder row that later
/// syncs down for it are the same occurrence.
int alarmKitOccurrenceId(List<String> members, int fireAtMs) =>
    notificationIdFor(alarmKitOccurrenceSeed(members, fireAtMs));

/// The string the fingerprint hashes. Exposed for the shared fixture.
String alarmKitFingerprintSeed({
  required String title,
  required String body,
  required String? soundName,
  required String stopLabel,
  required String snoozeLabel,
  required String snoozePreset,
}) =>
    'fp1|$title|$body|${soundName ?? ''}|$stopLabel|$snoozeLabel|'
    '$snoozePreset';

/// FNV-1a of everything the alert shows or does that is not the occurrence
/// itself. A null [soundName] (the system alarm sound) hashes like `''`.
int alarmKitFingerprint({
  required String title,
  required String body,
  required String? soundName,
  required String stopLabel,
  required String snoozeLabel,
  required String snoozePreset,
}) => notificationIdFor(
  alarmKitFingerprintSeed(
    title: title,
    body: body,
    soundName: soundName,
    stopLabel: stopLabel,
    snoozeLabel: snoozeLabel,
    snoozePreset: snoozePreset,
  ),
);
