import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:alliswell/src/core/runtime_config.dart';
import 'package:alliswell/src/features/auth/providers.dart';

void main() {
  test('non-web builds have no runtime config (the stub)', () {
    // The VM/native path: compiled binaries carry their API address, so the
    // runtime file must never claim one. The web implementation is exercised
    // by the container's own smoke test (docs/SELF-HOSTING.md).
    expect(readRuntimeApiBaseUrl(), isNull);
  });

  test('apiBaseUrlProvider falls back to the compile-time default', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    // Tests run without --dart-define, so this is the documented dev default —
    // proving the runtime lookup degrades instead of yielding null/empty.
    expect(container.read(apiBaseUrlProvider), 'http://localhost:3000');
  });
}
