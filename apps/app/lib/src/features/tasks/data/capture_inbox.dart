import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/quick_parse.dart';
import '../../workspaces/workspaces.dart';
import 'quick_add_apply.dart';

/// Voice capture (OPH-376, ADR-0057): "Hey Siri, add a task in AllisWell".
///
/// The App Intents (`ios/Shared/AWAppShortcuts.swift`) run IN the app with
/// `openAppWhenRun`, park what was said in a small mailbox and bring the app
/// forward; this side drains the mailbox into the SAME write path the Inbox
/// quick-add bar uses ([createCapture]) — parser, tags, series, outbox and,
/// above all, the alarm the deadline arms. A URL never carries the text
/// (ADR-0016: `alliswell://` only navigates).

/// The most entries one drain accepts — the native queue keeps the same cap.
const int kAwCaptureMax = 32;

/// The API's title limit; the native side cuts at the same length.
const int kAwCaptureTextMax = 500;

enum AwCaptureKind { add, today }

/// One parked request from Siri, Shortcuts or Spotlight.
@immutable
class AwCapture {
  const AwCapture({required this.id, required this.kind, this.text});

  final String id;
  final AwCaptureKind kind;

  /// What was said — only for [AwCaptureKind.add], trimmed and capped.
  final String? text;

  @override
  bool operator ==(Object other) =>
      other is AwCapture &&
      other.id == id &&
      other.kind == kind &&
      other.text == text;

  @override
  int get hashCode => Object.hash(id, kind, text);

  @override
  String toString() => 'AwCapture($kind, $id)';
}

/// Pure decoder for the native mailbox (`[{id, kind, text?, at}]`).
///
/// Untrusted on principle, as everything that crosses a channel: a malformed
/// entry is dropped and the rest survive; an unknown kind is dropped (the
/// sender may be a newer build); an `add` without words is nothing to add.
@visibleForTesting
List<AwCapture> capturesFromMailbox(Object? raw) {
  if (raw is! List) return const [];
  final out = <AwCapture>[];
  for (final entry in raw) {
    if (out.length >= kAwCaptureMax) break;
    if (entry is! Map) continue;
    final kindName = entry['kind'];
    final kind = AwCaptureKind.values.where((k) => k.name == kindName);
    if (kind.isEmpty) continue;
    final rawId = entry['id'];
    final id = rawId is String && rawId.isNotEmpty ? rawId : '${out.length}';
    switch (kind.single) {
      case AwCaptureKind.add:
        final text = entry['text'];
        if (text is! String) continue;
        final trimmed = text.trim();
        if (trimmed.isEmpty) continue;
        out.add(
          AwCapture(
            id: id,
            kind: AwCaptureKind.add,
            text: trimmed.length > kAwCaptureTextMax
                ? trimmed.substring(0, kAwCaptureTextMax).trim()
                : trimmed,
          ),
        );
      case AwCaptureKind.today:
        out.add(AwCapture(id: id, kind: AwCaptureKind.today));
    }
  }
  return out;
}

/// The mailbox, behind a seam (the `ShareInbox` precedent).
abstract class CaptureInbox {
  /// Read-and-clear.
  Future<List<AwCapture>> take();

  /// Fires when the native side parked something while the app was already in
  /// front — a warm Siri request has no resume to wake the drain.
  Stream<void> get changes;
}

/// Platforms without App Intents (Android, web, Windows, Linux).
class NoCaptureInbox implements CaptureInbox {
  const NoCaptureInbox();

  @override
  Future<List<AwCapture>> take() async => const [];

  @override
  Stream<void> get changes => const Stream.empty();
}

class MethodChannelCaptureInbox implements CaptureInbox {
  MethodChannelCaptureInbox({MethodChannel? channel})
    : _channel = channel ?? const MethodChannel(channelName) {
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'changed') _changes.add(null);
      return null;
    });
  }

  static const channelName = 'alliswell/capture';

  final MethodChannel _channel;
  final _changes = StreamController<void>.broadcast();

  @override
  Stream<void> get changes => _changes.stream;

  @override
  Future<List<AwCapture>> take() async {
    try {
      final raw = await _channel.invokeListMethod<Object?>('take');
      return capturesFromMailbox(raw);
    } on MissingPluginException {
      return const [];
    } on PlatformException {
      return const [];
    }
  }

  void dispose() {
    _channel.setMethodCallHandler(null);
    unawaited(_changes.close());
  }
}

/// iOS and macOS carry the intents; everything else has nothing to drain.
final captureInboxProvider = Provider<CaptureInbox>((ref) {
  if (kIsWeb) return const NoCaptureInbox();
  switch (defaultTargetPlatform) {
    case TargetPlatform.iOS:
    case TargetPlatform.macOS:
      final inbox = MethodChannelCaptureInbox();
      ref.onDispose(inbox.dispose);
      return inbox;
    default:
      return const NoCaptureInbox();
  }
});

/// What a drained capture did — HomeShell turns it into a SnackBar or a
/// navigation.
sealed class CaptureOutcome {
  const CaptureOutcome();
}

class CaptureAdded extends CaptureOutcome {
  const CaptureAdded({
    required this.taskId,
    required this.title,
    this.dueAt,
    required this.inbox,
  });

  final String taskId;
  final String title;
  final DateTime? dueAt;

  /// Dateless → the Inbox (DESIGN §26 C3).
  final bool inbox;
}

class CaptureShowToday extends CaptureOutcome {
  const CaptureShowToday();
}

/// Holds outcomes until HomeShell consumes them (the `PendingSharePayload`
/// analog, but a queue: two Shortcuts runs in a row are two tasks).
class PendingCaptureOutcomes extends Notifier<List<CaptureOutcome>> {
  @override
  List<CaptureOutcome> build() => const [];

  void remember(CaptureOutcome outcome) => state = [...state, outcome];

  /// Read-and-clear.
  List<CaptureOutcome> take() {
    final pending = state;
    if (pending.isNotEmpty) state = const [];
    return pending;
  }
}

final pendingCaptureOutcomesProvider =
    NotifierProvider<PendingCaptureOutcomes, List<CaptureOutcome>>(
      PendingCaptureOutcomes.new,
    );

/// Drains the mailbox into tasks. HomeShell keeps it alive — it mounts only
/// signed in — and the drain waits for a workspace BEFORE it takes, so a
/// request made while signed out stays parked instead of being lost.
///
/// Triggers: bind, every resume, the native `changed` signal and the active
/// workspace arriving. A trigger during a drain schedules one more pass
/// rather than a second concurrent read.
final captureBinderProvider = Provider<void>((ref) {
  final inbox = ref.read(captureInboxProvider);
  final outcomes = ref.read(pendingCaptureOutcomesProvider.notifier);
  var disposed = false;
  var draining = false;
  var again = false;

  Future<void> handle(AwCapture capture) async {
    switch (capture.kind) {
      case AwCaptureKind.today:
        outcomes.remember(const CaptureShowToday());
      case AwCaptureKind.add:
        final text = capture.text!;
        final parse = awParseQuickAdd(text, quickParseOptions(ref.read));
        final id = await createCapture(
          ref.read,
          QuickAddSubmission(raw: text, parse: parse),
        );
        if (id == null) throw StateError('No workspace available');
        if (disposed) return;
        outcomes.remember(
          CaptureAdded(
            taskId: id,
            title: parse.title,
            dueAt: parse.dueAt,
            inbox: parse.dueAt == null,
          ),
        );
    }
  }

  Future<void> drain() async {
    if (draining) {
      again = true;
      return;
    }
    draining = true;
    try {
      do {
        again = false;
        if (disposed) return;
        final workspaceId = await ref.read(activeWorkspaceIdProvider.future);
        if (workspaceId == null || disposed) return;
        final captures = await inbox.take();
        for (final capture in captures) {
          if (disposed) return;
          try {
            await handle(capture);
          } on Object catch (error) {
            // The TYPE only: what was said is the user's words.
            debugPrint(
              'capture: ${capture.kind.name} failed '
              '(${error.runtimeType})',
            );
          }
        }
      } while (again);
    } on Object catch (error) {
      debugPrint('capture: drain failed (${error.runtimeType})');
    } finally {
      draining = false;
    }
  }

  unawaited(drain());
  final changes = inbox.changes.listen((_) => unawaited(drain()));
  ref.listen(activeWorkspaceIdProvider, (previous, next) {
    if (next.value != null && previous?.value != next.value) {
      unawaited(drain());
    }
  });
  final resume = _ResumeObserver(() => unawaited(drain()));
  WidgetsBinding.instance.addObserver(resume);
  ref.onDispose(() {
    disposed = true;
    changes.cancel();
    WidgetsBinding.instance.removeObserver(resume);
  });
});

class _ResumeObserver with WidgetsBindingObserver {
  _ResumeObserver(this.onResumed);

  final VoidCallback onResumed;

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) onResumed();
  }
}
