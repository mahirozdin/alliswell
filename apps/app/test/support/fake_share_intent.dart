import 'dart:async';

import 'package:alliswell/src/features/ai/data/ai_context_builder.dart';
import 'package:alliswell/src/features/ai/data/share_intent.dart';

/// A scripted [ShareIntentSource] for tests (OPH-225) — no platform channel.
/// Give it an [initial] cold-start payload and/or push warm ones with [emit].
class FakeShareIntentSource implements ShareIntentSource {
  FakeShareIntentSource({this.initial});

  final SharedPayload? initial;
  final _controller = StreamController<SharedPayload>.broadcast();
  final List<String> calls = [];

  @override
  Future<SharedPayload?> initialShare() async {
    calls.add('initialShare');
    return initial;
  }

  @override
  Stream<SharedPayload> shares() => _controller.stream;

  @override
  void reset() => calls.add('reset');

  /// Push a warm share (the app is already running).
  void emit(SharedPayload payload) => _controller.add(payload);

  void dispose() => _controller.close();
}
