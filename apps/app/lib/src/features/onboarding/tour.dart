import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/kv/local_kv.dart';
import '../../sections.dart';

/// Per-device flag: the first-run tour has been seen (skipped or finished).
const kOnboardingSeenKey = 'alliswell_onboarding_seen_v1';

/// Whether the first-run tour may auto-start. True in production; widget tests
/// override it to false (see `test/support/sync_overrides.dart`) so the overlay
/// never covers the app under test (OPH-111).
final tourAutoStartProvider = Provider<bool>((_) => true);

/// One step of the tour. [section] anchors the spotlight to a nav destination;
/// a null section is a plain centered card (welcome / farewell).
class TourStep {
  const TourStep({this.section, required this.title, required this.body});

  final AppSection? section;
  final String title;
  final String body;
}

/// The tour script: a welcome card, one spotlight per nav section, and a
/// farewell pointing at Settings. Section copy stays close to each
/// `AppSection.description` so the tour and the tooltips don't drift.
const List<TourStep> kTourSteps = [
  TourStep(
    title: 'Welcome to AllisWell',
    body: 'A 30-second tour of the essentials. You can skip it anytime.',
  ),
  TourStep(
    section: AppSection.home,
    title: 'Home',
    body:
        'Your day in one chronological list — overdue, dateless work, today, '
        'and the next 30 days. Quick-add at the top; the + button opens the '
        'full form.',
  ),
  TourStep(
    section: AppSection.inbox,
    title: 'Inbox',
    body:
        'Capture a thought fast. It stays here — out of Home — until you plan '
        'it, so nothing gets lost and nothing clutters your day.',
  ),
  TourStep(
    section: AppSection.calendar,
    title: 'Calendar',
    body:
        'Your month at a glance. Connect a calendar in Settings and your own '
        'events show up beside your tasks.',
  ),
  TourStep(
    section: AppSection.projects,
    title: 'Projects',
    body:
        'Group work with a color and a README overview, with its own tasks and '
        'notes. Archive a project when it is done.',
  ),
  TourStep(
    section: AppSection.notes,
    title: 'Notes',
    body: 'Rich notes you can pin, archive, and link to tasks and projects.',
  ),
  TourStep(
    title: 'You’re all set',
    body: 'Reopen this tour anytime from Settings → App tour.',
  ),
];

/// Tour position. [running] gates the overlay; [step] indexes [kTourSteps].
class TourState {
  const TourState({this.running = false, this.step = 0});

  final bool running;
  final int step;

  TourStep get current => kTourSteps[step];
  bool get isLast => step >= kTourSteps.length - 1;

  TourState copyWith({bool? running, int? step}) =>
      TourState(running: running ?? this.running, step: step ?? this.step);
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
    state = const TourState(running: true);
  }

  /// Replay from Settings (does NOT clear the seen flag — it just runs).
  void start() => state = const TourState(running: true);

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
