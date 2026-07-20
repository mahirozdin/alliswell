import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/kv/local_kv.dart';
import '../../i18n/i18n.dart';
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
  TourStep(titleKey: 'tour.doneTitle', bodyKey: 'tour.doneBody'),
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
