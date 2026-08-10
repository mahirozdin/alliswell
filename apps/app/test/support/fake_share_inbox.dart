import 'package:alliswell/src/features/ai/data/ai_context_builder.dart';
import 'package:alliswell/src/features/ai/data/share_inbox.dart';

/// The iOS App Group mailbox, faked (OPH-242, ADR-0029).
///
/// Records every [take] because the bug this seam exists to prevent is a
/// *count* bug, not a content bug: the drain runs at bind time AND on every
/// resume, so a mailbox that is not cleared — or a re-entrant read — turns one
/// share into several tasks. "How many times was it read" is the assertion.
class FakeShareInbox implements ShareInbox {
  FakeShareInbox({this.pending});

  /// Public on purpose: a named parameter cannot be a private initializing
  /// formal (Dart forbids named parameters starting with `_`), and a test that
  /// wants to assert the mailbox was actually emptied should be able to look.
  SharedPayload? pending;
  int takes = 0;

  /// Simulates the extension writing while the app is backgrounded.
  void deliver(SharedPayload payload) => pending = payload;

  @override
  Future<SharedPayload?> take() async {
    takes++;
    final payload = pending;
    pending = null; // read-and-clear, exactly like the native side
    return payload;
  }
}
