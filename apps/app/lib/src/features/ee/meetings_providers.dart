import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api_exception.dart';
import '../../core/reachability.dart';
import '../../i18n/i18n.dart';
import '../auth/providers.dart';
import '../files/providers.dart'
    show PickedUpload, mimeForName, uploadTransportProvider;
import 'data/meeting_models.dart';
import 'data/meetings_api.dart';
import 'providers.dart';

/// Meeting providers (EE-115).
///
/// Keyed by meeting id rather than held as one "current meeting": two screens
/// can be alive at once (a list behind a detail), and a single slot would make
/// the one behind show the one in front's transcript.
final eeMeetingsApiProvider = Provider<EeMeetingsApi>(
  (ref) => EeMeetingsApi(ref.watch(apiClientProvider)),
);

const ApiException _unreachable = ApiException(
  'NETWORK_ERROR',
  'Could not reach the AllisWell server',
);

/// True when [error] means "there was no answer".
bool meetingsNeedConnection(Object? error) =>
    error is ApiException && error.code == 'NETWORK_ERROR';

/// EE-271 — one unit's meetings, for the list that finally opens them.
///
/// Written with EE-115 and read by nothing until now: the detail had a route
/// and no door. Read from the server every time the list opens — autoDispose
/// for the asset history's reason, a list kept alive would show last week's
/// "summarizing" as today's — and offline it fails without asking (OPH-342),
/// so the screen says the list needs a connection instead of drawing an old
/// one as current. Null without the entitlement, like the detail.
final eeMeetingListProvider = FutureProvider.autoDispose
    .family<List<EeMeetingSummary>?, String>((ref, workspaceId) async {
      if (!ref.watch(eeFeatureProvider('meetings'))) return null;
      if (ref.watch(serverReachabilityProvider.select((up) => up == false))) {
        throw _unreachable;
      }
      return ref.watch(eeMeetingsApiProvider).list(workspaceId);
    });

final eeMeetingProvider = FutureProvider.family<EeMeetingDetail?, String>((
  ref,
  meetingId,
) {
  if (!ref.watch(eeFeatureProvider('meetings'))) return Future.value(null);
  return ref.watch(eeMeetingsApiProvider).detail(meetingId);
});

/// Names every voice at once, then re-reads.
///
/// The whole map goes, not one entry: the screen shows all the speakers and is
/// therefore stating the complete answer. Re-reading rather than trusting the
/// optimistic value is the idiom EE-099 settled — and it earns its keep here,
/// because the server trims and refuses names, so what comes back is what is
/// true rather than what was hoped for.
/// Turns a decision into work, then re-reads so the row shows what it became.
Future<EeDecisionRecord> createDecisionRecord(
  WidgetRef ref,
  String meetingId,
  int decisionIndex,
) async {
  final record = await ref
      .read(eeMeetingsApiProvider)
      .createRecord(meetingId, decisionIndex);
  ref.invalidate(eeMeetingProvider(meetingId));
  return record;
}

Future<void> nameMeetingSpeakers(
  WidgetRef ref,
  String meetingId,
  Map<String, String> names,
) async {
  await ref.read(eeMeetingsApiProvider).nameSpeakers(meetingId, names);
  ref.invalidate(eeMeetingProvider(meetingId));
}

/// Puts a recording in front of the meeting pipeline (OPH-359, UI-AUDIT #54):
/// open the meeting, PUT the bytes to the slot the server minted, then say it
/// is there. The list is asked again, so the new row appears as "queued".
///
/// The empty list said "once a meeting's recording is uploaded…" and nothing
/// in the app could upload one — the endpoint existed for scripts only.
Future<EeMeetingSummary> uploadMeetingRecording(
  WidgetRef ref, {
  required String workspaceId,
  required PickedUpload file,
}) async {
  final api = ref.read(eeMeetingsApiProvider);
  final dot = file.name.lastIndexOf('.');
  final slot = await api.create(
    workspaceId: workspaceId,
    mime: file.mime ?? mimeForName(file.name),
    sizeBytes: file.sizeBytes,
    title: dot > 0 ? file.name.substring(0, dot) : file.name,
  );
  await ref.read(uploadTransportProvider)(
    url: slot.url,
    headers: slot.headers,
    source: file,
  );
  final done = await api.complete(slot.meeting.id);
  ref.invalidate(eeMeetingListProvider(workspaceId));
  return done;
}

/// What a failed (or stalled) meeting says about why, in the reader's
/// language (OPH-359, UI-AUDIT #54). Read from `failureCode` — the server's
/// `failureMessage` is English prose for logs and is never shown (EE-303).
/// An unknown code still gets a sentence: a new server must not leave a bare
/// "failed" behind.
String? eeMeetingFailureText(String? code) {
  if (code == null || code.isEmpty) return null;
  return AwI18n.instance.maybeTranslate('ee.meeting.failure.$code') ??
      'ee.meeting.failure.generic'.tr();
}

/// The failures a team admin fixes by adding a provider key.
bool eeMeetingFailureNeedsAiKey(String? code) =>
    code == 'MEETING_NO_TRANSCRIBER' || code == 'MEETING_NO_SUMMARISER';

/// A meeting that does not exist (or is not this person's to see) — a 404,
/// with the server's `MEETING_NOT_FOUND` code or without one (EE-303).
bool eeMeetingNotFound(Object? error) =>
    error is ApiException &&
    (error.code == 'MEETING_NOT_FOUND' || error.statusCode == 404);
