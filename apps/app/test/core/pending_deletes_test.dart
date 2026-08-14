import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:alliswell/src/core/pending_deletes.dart';

/// OPH-257 — the undo window's own contract.
///
/// The bar that offers this window was measured never to auto-dismiss (Flutter
/// 3.44 defaults `SnackBar.persist` to `action != null`, so any bar with a
/// button opts out of its own timeout). Fixing the bar is one half. The other
/// half is here: `undo` has to be able to SAY that it was too late, so a tap
/// that arrives after the commit can be answered honestly instead of silently
/// doing nothing — which is exactly what it did before.
void main() {
  late ProviderContainer container;

  setUp(() => container = ProviderContainer());
  tearDown(() => container.dispose());

  PendingDeletes pending() => container.read(pendingDeletesProvider.notifier);

  test('undo reports that it really took the delete back', () async {
    final p = pending();
    var committed = false;
    p.schedule(
      'a',
      () async => committed = true,
      window: const Duration(seconds: 5),
    );

    expect(p.isPending('a'), isTrue);
    expect(p.undo('a'), isTrue, reason: 'the window was still open');
    expect(p.isPending('a'), isFalse);
    expect(committed, isFalse, reason: 'undo means the delete never happened');

    expect(
      p.undo('a'),
      isFalse,
      reason: 'a second undo has nothing left to take back',
    );
    expect(p.undo('never-scheduled'), isFalse);
  });

  test('undo is too late once the window has closed', () async {
    final p = pending();
    var committed = false;
    p.schedule('a', () async => committed = true, window: Duration.zero);
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(committed, isTrue);

    expect(
      p.undo('a'),
      isFalse,
      reason: 'the delete is written; there is no taking it back',
    );
  });

  test('commitNow closes the window early, and only once', () async {
    final p = pending();
    var commits = 0;
    p.schedule('a', () async => commits++, window: const Duration(seconds: 5));

    p.commitNow('a');
    await Future<void>.delayed(Duration.zero);
    expect(commits, 1, reason: 'the bar left the screen, so the delete stands');

    // Both of these must be no-ops: the undo bar's `closed` future and the
    // backstop timer can race, and a delete pushed twice is a real bug.
    p.commitNow('a');
    p.commitNow('never-scheduled');
    await Future<void>.delayed(Duration.zero);
    expect(commits, 1);
  });

  test('an undone delete is never committed by a later commitNow', () async {
    final p = pending();
    var commits = 0;
    p.schedule('a', () async => commits++, window: const Duration(seconds: 5));

    expect(p.undo('a'), isTrue);
    p.commitNow('a');
    await Future<void>.delayed(const Duration(milliseconds: 20));

    expect(
      commits,
      0,
      reason: 'the bar closing must not resurrect a cancelled delete',
    );
  });
}
