import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:alliswell/src/core/retry.dart';
import 'package:alliswell/src/app.dart';
import 'package:alliswell/src/features/auth/data/secret_store.dart';
import 'package:alliswell/src/features/auth/data/token_storage.dart';
import 'package:alliswell/src/features/auth/providers.dart';
import 'package:alliswell/src/sync/sync_socket.dart';

import '../features/auth/test_support.dart';
import '../features/projects/fake_api.dart';
import '../support/sync_overrides.dart';

/// Captures what the app hands the socket layer so tests can play the server.
class FakeSocketHandle implements SyncSocketHandle {
  FakeSocketHandle(this.baseUrl, this.token, this.onSyncChanged);

  final String baseUrl;
  final String token;
  final void Function(Object? payload) onSyncChanged;
  bool closed = false;

  @override
  void close() => closed = true;
}

void main() {
  test(
    'syncChangedMatches accepts only well-formed events for the workspace',
    () {
      const ws = '01WSAAAAAAAAAAAAAAAAAAAAAA';
      expect(
        syncChangedMatches({'workspaceId': ws, 'toRevision': 7}, ws),
        isTrue,
      );
      expect(
        syncChangedMatches({'workspaceId': 'OTHER', 'toRevision': 7}, ws),
        isFalse,
      );
      expect(syncChangedMatches({'workspaceId': ws}, ws), isFalse);
      expect(syncChangedMatches('garbage', ws), isFalse);
      expect(syncChangedMatches(null, ws), isFalse);
    },
  );

  testWidgets('a sync:changed event pulls foreign edits into the UI', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final store = InMemorySecretStore();
    await TokenStorage(store).save(fakeSession());
    final api = FakeApi()..seedTask(title: 'Mevcut görev');

    final handles = <FakeSocketHandle>[];
    await tester.pumpWidget(
      ProviderScope(
        retry: awRetry,
        overrides: [
          // A capturing socket instead of the null test default.
          ...syncTestOverrides(
            socketFactory:
                ({
                  required String baseUrl,
                  required String token,
                  required void Function(Object? payload) onSyncChanged,
                }) {
                  final handle = FakeSocketHandle(
                    baseUrl,
                    token,
                    onSyncChanged,
                  );
                  handles.add(handle);
                  return handle;
                },
          ),
          secretStoreProvider.overrideWithValue(store),
          apiClientProvider.overrideWithValue(
            fakeDio(FakeHttpClientAdapter(api.handle)),
          ),
        ],
        child: const AllisWellApp(),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Mevcut görev'), findsOneWidget);
    expect(handles, hasLength(1));
    expect(handles.single.token, fakeSession().tokens.accessToken);

    // Another device writes: it appears server-side only, then the socket
    // announces it — no local write, no timer, just the live signal.
    api.seedTask(title: 'Başka cihazdan');
    expect(find.text('Başka cihazdan'), findsNothing);

    handles.single.onSyncChanged({
      'workspaceId': api.workspaceId,
      'toRevision': api.revision,
    });
    await tester.pumpAndSettle();

    expect(find.text('Başka cihazdan'), findsOneWidget);

    // Foreign-workspace noise pulls nothing (request count stays put).
    final pullsBefore = api.requests
        .where((r) => r.contains('/sync/pull'))
        .length;
    handles.single.onSyncChanged({
      'workspaceId': 'ELSEWHERE',
      'toRevision': 99,
    });
    await tester.pumpAndSettle();
    expect(
      api.requests.where((r) => r.contains('/sync/pull')).length,
      pullsBefore,
    );
  });
}
