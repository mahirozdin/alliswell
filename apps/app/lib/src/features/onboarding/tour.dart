import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/kv/local_kv.dart';
import '../../i18n/i18n.dart';
import '../../sections.dart';
import '../ee/providers.dart' show eeFeatureProvider, eeStatusProvider;
import '../ee/team_origin.dart' show teamOriginProvider;

/// Per-device flag: the first-run tour has been seen (skipped or finished).
const kOnboardingSeenKey = 'alliswell_onboarding_seen_v1';

/// Whether the first-run tour may auto-start. True in production; widget tests
/// override it to false (see `test/support/sync_overrides.dart`) so the overlay
/// never covers the app under test (OPH-111).
final tourAutoStartProvider = Provider<bool>((_) => true);

/// One step of the tour. [section] anchors the spotlight to a nav destination;
/// a null section is a plain centered card (welcome / farewell).
class TourStep {
  const TourStep({this.section, required this.titleKey, required this.bodyKey});

  final AppSection? section;
  final String titleKey;
  final String bodyKey;

  String get title => titleKey.tr();
  String get body => bodyKey.tr();
}

/// The tour script: a welcome card, one spotlight per nav section, and a
/// farewell pointing at Settings. Section copy stays close to each
/// `AppSection.description` so the tour and the tooltips don't drift.
const List<TourStep> kTourSteps = [
  TourStep(titleKey: 'tour.welcomeTitle', bodyKey: 'tour.welcomeBody'),
  TourStep(
    section: AppSection.home,
    titleKey: 'tour.homeTitle',
    bodyKey: 'tour.homeBody',
  ),
  TourStep(
    section: AppSection.inbox,
    titleKey: 'tour.inboxTitle',
    bodyKey: 'tour.inboxBody',
  ),
  TourStep(
    section: AppSection.projects,
    titleKey: 'tour.projectsTitle',
    bodyKey: 'tour.projectsBody',
  ),
  TourStep(
    section: AppSection.notes,
    titleKey: 'tour.notesTitle',
    bodyKey: 'tour.notesBody',
  ),
  TourStep(
    section: AppSection.files,
    titleKey: 'tour.filesTitle',
    bodyKey: 'tour.filesBody',
  ),
  TourStep(titleKey: 'tour.doneTitle', bodyKey: 'tour.doneBody'),
];

/// The same tour for somebody in an organisation's window (OPH-356,
/// UI-AUDIT #83): the service desk is in their navigation, so the tour shows
/// them where to ask for something and follow it — and Files does not promise
/// "personal folders" in an app where the organisation's handbook says there
/// is no personal space.
const List<TourStep> kTeamTourSteps = [
  TourStep(titleKey: 'tour.welcomeTitle', bodyKey: 'tour.welcomeBody'),
  TourStep(
    section: AppSection.home,
    titleKey: 'tour.homeTitle',
    bodyKey: 'tour.homeBody',
  ),
  TourStep(
    section: AppSection.tickets,
    titleKey: 'tour.ticketsTitle',
    bodyKey: 'tour.ticketsBody',
  ),
  TourStep(
    section: AppSection.inbox,
    titleKey: 'tour.inboxTitle',
    bodyKey: 'tour.inboxBody',
  ),
  TourStep(
    section: AppSection.projects,
    titleKey: 'tour.projectsTitle',
    bodyKey: 'tour.projectsBody',
  ),
  TourStep(
    section: AppSection.notes,
    titleKey: 'tour.notesTitle',
    bodyKey: 'tour.notesBody',
  ),
  TourStep(
    section: AppSection.files,
    titleKey: 'tour.filesTitle',
    bodyKey: 'tour.filesBodyTeam',
  ),
  TourStep(titleKey: 'tour.doneTitle', bodyKey: 'tour.doneBody'),
];

/// Which script this window gets: the team's where the service desk is drawn
/// — the same two answers the navigation asks (`home_shell`, EE-290) — and
/// the personal one everywhere else.
final tourStepsProvider = Provider<List<TourStep>>((ref) {
  final desk =
      ref.watch(eeFeatureProvider('itsm')) &&
      ref.watch(teamOriginProvider) != null;
  return desk ? kTeamTourSteps : kTourSteps;
});

/// Tour position. [running] gates the overlay; [step] indexes [steps] — the
/// script fixed when the tour started, so a window that changes under a
/// running tour cannot renumber it.
class TourState {
  const TourState({
    this.running = false,
    this.step = 0,
    this.steps = kTourSteps,
  });

  final bool running;
  final int step;
  final List<TourStep> steps;

  TourStep get current => steps[step];
  bool get isLast => step >= steps.length - 1;

  TourState copyWith({bool? running, int? step}) => TourState(
    running: running ?? this.running,
    step: step ?? this.step,
    steps: steps,
  );
}

class TourController extends Notifier<TourState> {
  bool _autoAttempted = false;

  @override
  TourState build() => const TourState();

  /// Called once from Home's first frame. Starts the tour only in production
  /// (see [tourAutoStartProvider]) and only if this device hasn't seen it.
  /// Reads the flag DIRECTLY (async) to avoid a hydration race that could flash
  /// the tour at a returning user.
  Future<void> maybeAutoStart() async {
    if (_autoAttempted) return;
    _autoAttempted = true;
    if (!ref.read(tourAutoStartProvider)) return;
    if (await localKv.get(kOnboardingSeenKey) == 'true') return;
    // The script depends on what this instance runs (OPH-356): a first
    // launch has no cached answer yet, and starting before it arrives would
    // walk a desk agent through the personal app. Bounded — a server that
    // does not answer gets the personal tour, not no tour.
    if (ref.read(eeStatusProvider).isLoading) {
      try {
        await ref
            .read(eeStatusProvider.future)
            .timeout(const Duration(seconds: 3));
      } catch (_) {}
    }
    start();
  }

  /// Replay from Settings (does NOT clear the seen flag — it just runs).
  void start() =>
      state = TourState(running: true, steps: ref.read(tourStepsProvider));

  void next() {
    if (state.isLast) {
      finish();
      return;
    }
    state = state.copyWith(step: state.step + 1);
  }

  void skip() => finish();

  void finish() {
    localKv.set(kOnboardingSeenKey, 'true');
    state = const TourState();
  }
}

final tourControllerProvider = NotifierProvider<TourController, TourState>(
  TourController.new,
);
