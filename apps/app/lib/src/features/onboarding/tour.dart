import 'dart:async';

import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/kv/local_kv.dart';
import '../../i18n/i18n.dart';
import '../../sections.dart';
import '../ai/providers.dart' show aiStatusProvider;
import '../ee/providers.dart' show eeFeatureProvider, eeStatusProvider;
import '../ee/team_origin.dart' show teamOriginProvider;

/// Per-device flag: the first-run tour has been seen (skipped or finished).
const kOnboardingSeenKey = 'alliswell_onboarding_seen_v1';

/// Whether the first-run tour may auto-start. True in production; widget tests
/// override it to false (see `test/support/sync_overrides.dart`) so the overlay
/// never covers the app under test (OPH-111).
final tourAutoStartProvider = Provider<bool>((_) => true);

/// What a step points at besides a nav destination (OPH-404). Each one is
/// marked in the tree by a [TourAnchor]; a target that is not on screen
/// (a narrow window, a section that hides it) falls back to a centred card.
enum TourTarget { quickAdd, voice, search }

/// One step of the tour. [target] or [section] anchors the spotlight; both
/// null is a plain centred card (the urgent alarm has nothing on Home to
/// point at).
class TourStep {
  const TourStep({
    this.section,
    this.target,
    required this.titleKey,
    required this.bodyKey,
  });

  final AppSection? section;
  final TourTarget? target;
  final String titleKey;
  final String bodyKey;

  String get title => titleKey.tr();
  String get body => bodyKey.tr();
}

/// OPH-404 (U-33, research `ux-core-screens.md` §4.1, DESIGN §50): four
/// things a person does on day one, not a walk past every tab. The old
/// seven steps toured Notes and Files and never said how to add a task.
const TourStep kTourQuickAdd = TourStep(
  target: TourTarget.quickAdd,
  titleKey: 'tour.quickAddTitle',
  bodyKey: 'tour.quickAddBody',
);
const TourStep kTourVoice = TourStep(
  target: TourTarget.voice,
  titleKey: 'tour.voiceTitle',
  bodyKey: 'tour.voiceBody',
);
const TourStep kTourAlarm = TourStep(
  titleKey: 'tour.alarmTitle',
  bodyKey: 'tour.alarmBody',
);
const TourStep kTourSearch = TourStep(
  target: TourTarget.search,
  titleKey: 'tour.searchTitle',
  bodyKey: 'tour.searchBody',
);

/// The personal tour. [kTourVoice] only where the microphone is drawn
/// (`aiFabVisible`): a server without AI has no voice entry, and a step
/// about a button that is not there is worse than one step fewer. A cold
/// start answers "no AI" until the workspace loads, so a running tour
/// takes the late answer while it is still on its first step (R-01).
const List<TourStep> kTourSteps = [
  kTourQuickAdd,
  kTourVoice,
  kTourAlarm,
  kTourSearch,
];

/// The same tour for somebody in an organisation's window (OPH-356,
/// UI-AUDIT #83): the service desk is what they came for, so its step takes
/// the microphone's place (OPH-404).
const List<TourStep> kTeamTourSteps = [
  kTourQuickAdd,
  TourStep(
    section: AppSection.tickets,
    titleKey: 'tour.ticketsTitle',
    bodyKey: 'tour.ticketsBody',
  ),
  kTourAlarm,
  kTourSearch,
];

/// Which script this window gets: the team's where the service desk is drawn
/// — the same two answers the navigation asks (`home_shell`, EE-290) — and
/// the personal one everywhere else, without the voice step when AI is off.
final tourStepsProvider = Provider<List<TourStep>>((ref) {
  final desk =
      ref.watch(eeFeatureProvider('itsm')) &&
      ref.watch(teamOriginProvider) != null;
  if (desk) return kTeamTourSteps;
  final mic = ref.watch(aiStatusProvider).value?.enabled ?? false;
  if (mic) return kTourSteps;
  return [
    for (final s in kTourSteps)
      if (s != kTourVoice) s,
  ];
});

/// Marks the widget a [TourTarget] step spotlights (OPH-404). A registry of
/// ACTIVE contexts, not a GlobalKey: the search entry and the microphone
/// are rebuilt by layout switches and FAB transitions, where a GlobalKey
/// mounted twice for a frame is a crash and a stale context is only a
/// missing spotlight. An anchor leaves the registry when it is deactivated,
/// not when it is disposed (R-01): between the two it is still `mounted`,
/// and measuring it was the red "renderObject of inactive element" screen
/// of the first run.
class TourAnchor extends StatefulWidget {
  const TourAnchor({super.key, required this.target, required this.child});

  final TourTarget target;
  final Widget child;

  static final Map<TourTarget, BuildContext> _mounted = {};

  /// Bumped after an anchor mounts or leaves, once its frame is laid out:
  /// Home's field arrives after the tour has started, and the overlay must
  /// move its spotlight onto it rather than keep a centred card.
  static final ValueNotifier<int> changes = ValueNotifier(0);

  static void _announce() {
    SchedulerBinding.instance.addPostFrameCallback((_) => changes.value++);
  }

  /// The target's on-screen rect, or null when it is not laid out.
  static Rect? rectOf(TourTarget target) {
    final context = _mounted[target];
    if (context == null || !context.mounted) return null;
    // Only active elements are registered (see [_TourAnchorState.deactivate]).
    final box = context.findRenderObject() as RenderBox?;
    if (box == null || !box.hasSize || !box.attached) return null;
    return box.localToGlobal(Offset.zero) & box.size;
  }

  @override
  State<TourAnchor> createState() => _TourAnchorState();
}

class _TourAnchorState extends State<TourAnchor> {
  @override
  void initState() {
    super.initState();
    TourAnchor._mounted[widget.target] = context;
    TourAnchor._announce();
  }

  @override
  void didUpdateWidget(TourAnchor old) {
    super.didUpdateWidget(old);
    if (old.target != widget.target) {
      _release(old.target);
      TourAnchor._mounted[widget.target] = context;
    }
  }

  // A GlobalKey move above the anchor deactivates and reactivates it in
  // one frame: it is back in the registry once it is in the tree again.
  @override
  void activate() {
    super.activate();
    TourAnchor._mounted[widget.target] = context;
    TourAnchor._announce();
  }

  @override
  void deactivate() {
    _release(widget.target);
    super.deactivate();
  }

  void _release(TourTarget target) {
    if (identical(TourAnchor._mounted[target], context)) {
      TourAnchor._mounted.remove(target);
      TourAnchor._announce();
    }
  }

  @override
  void dispose() {
    _release(widget.target);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

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
  TourState build() {
    // R-01: the answers that pick the script (AI status, the service desk)
    // can arrive after the tour started — a cold start reads "no AI" until
    // the workspace loads, and an organisation's status after a slow first
    // sync. Until the first "Next" both scripts show the same step, so the
    // tour takes the late answer; after it the numbering stays put.
    ref.listen(tourStepsProvider, (_, steps) {
      if (state.running && state.step == 0 && !identical(state.steps, steps)) {
        state = TourState(running: true, steps: steps);
      }
    });
    return const TourState();
  }

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
    // The voice step depends on whether the microphone is drawn (OPH-404).
    if (ref.read(aiStatusProvider).isLoading) {
      try {
        await ref
            .read(aiStatusProvider.future)
            .timeout(const Duration(seconds: 3));
      } catch (_) {}
    }
    if (!ref.mounted) return;
    // R-01: the first step points at Home's field — wait for its first
    // laid-out frame, or the card opens over a blank window with no
    // spotlight. Bounded: a window that never draws it (a deep link to
    // another section) gets a centred card.
    final first = ref.read(tourStepsProvider).first.target;
    if (first != null) await _untilLaidOut(first);
    if (!ref.mounted) return;
    start();
  }

  static Future<void> _untilLaidOut(TourTarget target) async {
    if (TourAnchor.rectOf(target) != null) return;
    final laidOut = Completer<void>();
    void check() {
      if (!laidOut.isCompleted && TourAnchor.rectOf(target) != null) {
        laidOut.complete();
      }
    }

    TourAnchor.changes.addListener(check);
    try {
      await laidOut.future.timeout(const Duration(seconds: 3));
    } on TimeoutException catch (_) {
      // Start anyway; the overlay picks the field up if it arrives later.
    } finally {
      TourAnchor.changes.removeListener(check);
    }
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
