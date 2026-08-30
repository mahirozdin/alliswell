import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../auth/providers.dart';
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

final eeMeetingListProvider =
    FutureProvider.family<List<EeMeetingSummary>?, String>((ref, workspaceId) {
      if (!ref.watch(eeFeatureProvider('meetings'))) return Future.value(null);
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
