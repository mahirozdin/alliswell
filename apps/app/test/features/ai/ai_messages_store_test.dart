import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:alliswell/src/features/ai/data/ai_messages_store.dart';
import 'package:alliswell/src/sync/db/database.dart';

/// OPH-221 — the device-local chat history ring buffer.
void main() {
  late AwDatabase db;
  late AiMessagesStore store;

  setUp(() {
    db = AwDatabase(
      DatabaseConnection(NativeDatabase.memory(), closeStreamsSynchronously: true),
    );
    store = AiMessagesStore(db);
  });
  tearDown(() => db.close());

  test('adds and reads back newest-first, scoped to the workspace', () async {
    await store.add(workspaceId: 'W1', role: 'user', content: 'ilk');
    await store.add(workspaceId: 'W1', role: 'assistant', content: 'ikinci');
    await store.add(
      workspaceId: 'W2',
      role: 'user',
      content: 'başka workspace',
    );

    final rows = await store.watchRecent('W1').first;
    expect(rows.map((r) => r.content), ['ikinci', 'ilk']);
  });

  test('ring-buffers to kAiMessageLimit', () async {
    for (var i = 0; i < kAiMessageLimit + 20; i++) {
      await store.add(workspaceId: 'W1', role: 'user', content: 'm$i');
    }
    final all = await (db.select(db.aiMessages)).get();
    expect(all.length, lessThanOrEqualTo(kAiMessageLimit));
  });

  test('clear empties one workspace', () async {
    await store.add(workspaceId: 'W1', role: 'user', content: 'x');
    await store.clear('W1');
    expect(await store.watchRecent('W1').first, isEmpty);
  });
}
