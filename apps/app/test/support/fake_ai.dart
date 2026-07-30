import 'dart:async';

import 'package:alliswell/src/features/ai/data/ai_stream_client.dart';

/// A scripted AiStreamClient for widget tests (OPH-221) — emit-on-command,
/// records cancels. Inject via syncTestOverrides(aiStreamClient: …).
class ScriptedAiStreamClient implements AiStreamClient {
  ScriptedAiStreamClient({this.script = const []});

  /// The events one chat() call replays, in order. Set before pumping.
  List<AiStreamEvent> script;

  final List<String> cancelled = [];
  final List<AiChatRequest> requests = [];

  /// When true, chat() emits the script's text but never a terminal Done —
  /// the stall path, ended only by the consumer cancelling.
  bool hang = false;

  @override
  Stream<AiStreamEvent> chat(AiChatRequest request) {
    requests.add(request);
    final controller = StreamController<AiStreamEvent>();
    controller.onListen = () async {
      for (final event in script) {
        if (controller.isClosed) return;
        controller.add(event);
        await Future<void>.delayed(Duration.zero);
      }
      if (!hang && !controller.isClosed) {
        controller.add(const AiStreamDone());
        await controller.close();
      }
    };
    controller.onCancel = () {
      cancelled.add(request.requestId);
    };
    return controller.stream;
  }

  @override
  Future<void> cancel(String workspaceId, String requestId) async {
    cancelled.add(requestId);
  }
}
