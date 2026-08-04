import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../auth/providers.dart';

/// The chat transport seam (OPH-221, mirroring OPH-217's server contract). One
/// interface, two impls behind a nullable provider so widget tests inject a
/// scripted stream — exactly like syncSocketFactoryProvider. The UI never
/// knows which transport carried the tokens.

sealed class AiStreamEvent {
  const AiStreamEvent();
}

class AiTextDelta extends AiStreamEvent {
  const AiTextDelta(this.text);
  final String text;
}

class AiUsage extends AiStreamEvent {
  const AiUsage({this.inputTokens, this.outputTokens});
  final int? inputTokens;
  final int? outputTokens;
}

class AiStreamDone extends AiStreamEvent {
  const AiStreamDone({this.cancelled = false});
  final bool cancelled;
}

class AiStreamFailure extends AiStreamEvent {
  const AiStreamFailure(this.code, this.message);
  final String code;
  final String message;
}

class AiChatMessage {
  const AiChatMessage({required this.role, required this.content});
  final String role; // user | assistant
  final String content;
  Map<String, dynamic> toJson() => {'role': role, 'content': content};
}

class AiChatRequest {
  const AiChatRequest({
    required this.workspaceId,
    required this.requestId,
    required this.messages,
    this.context,
    this.model,
  });
  final String workspaceId;
  final String requestId;
  final List<AiChatMessage> messages;
  final Map<String, dynamic>? context;
  final String? model;
}

abstract class AiStreamClient {
  /// Cancelling the returned subscription aborts the upstream request.
  Stream<AiStreamEvent> chat(AiChatRequest request);

  /// Best-effort cancel of an in-flight generation (the dismissed-bubble path).
  Future<void> cancel(String workspaceId, String requestId);
}

/// SSE-over-POST via dio's byte stream (mobile/desktop). The web path is a
/// Socket.IO room (parked behind the same seam; the interface is transport-
/// agnostic so it can be swapped without the UI noticing).
class DioAiStreamClient implements AiStreamClient {
  DioAiStreamClient(this._dio);
  final Dio _dio;

  @override
  Stream<AiStreamEvent> chat(AiChatRequest request) {
    final controller = StreamController<AiStreamEvent>();
    final cancelToken = CancelToken();

    Future<void> run() async {
      try {
        final response = await _dio.post<ResponseBody>(
          '/api/v1/workspaces/${request.workspaceId}/ai/chat',
          data: {
            'requestId': request.requestId,
            'messages': request.messages.map((m) => m.toJson()).toList(),
            'context': ?request.context,
            'model': ?request.model,
          },
          options: Options(
            responseType: ResponseType.stream,
            // `identity`: a reverse proxy that gzips this stream also BUFFERS
            // it (zlib wants full blocks), and a buffered SSE dies at the edge
            // timeout — the live alliswell.space failure. Browsers ignore the
            // header (they own it); native/desktop honor it.
            headers: {
              'accept': 'text/event-stream',
              'accept-encoding': 'identity',
            },
          ),
          cancelToken: cancelToken,
        );
        final stream = response.data!.stream;
        await for (final event in _parseSse(stream)) {
          if (controller.isClosed) break;
          controller.add(event);
        }
        if (!controller.isClosed) controller.add(const AiStreamDone());
      } on DioException catch (e) {
        if (CancelToken.isCancel(e)) {
          if (!controller.isClosed) {
            controller.add(const AiStreamDone(cancelled: true));
          }
        } else if (!controller.isClosed) {
          controller.add(
            const AiStreamFailure('AI_UPSTREAM_ERROR', 'The AI request failed'),
          );
        }
      } catch (_) {
        if (!controller.isClosed) {
          controller.add(
            const AiStreamFailure('AI_UPSTREAM_ERROR', 'The AI request failed'),
          );
        }
      } finally {
        await controller.close();
      }
    }

    controller.onCancel = () {
      if (!cancelToken.isCancelled) cancelToken.cancel('bubble-dismissed');
      // Fire-and-forget the server-side cancel so other workers stop too.
      unawaited(cancel(request.workspaceId, request.requestId));
    };
    unawaited(run());
    return controller.stream;
  }

  @override
  Future<void> cancel(String workspaceId, String requestId) async {
    try {
      await _dio.post<void>(
        '/api/v1/workspaces/$workspaceId/ai/chat/$requestId/cancel',
      );
    } catch (_) {
      // Best-effort — a finished stream is a legitimate no-op.
    }
  }

  /// Minimal SSE line parser (the server's ~80-line parser, Dart side): split
  /// on blank lines, ignore `:` heartbeats, JSON-decode `data:` per event.
  Stream<AiStreamEvent> _parseSse(Stream<List<int>> bytes) async* {
    var buffer = '';
    String eventName = 'message';
    final dataLines = <String>[];

    AiStreamEvent? dispatch() {
      if (dataLines.isEmpty) return null;
      final data = dataLines.join('\n');
      final name = eventName;
      eventName = 'message';
      dataLines.clear();
      if (data == '[DONE]') return null;
      final json = jsonDecode(data) as Map<String, dynamic>;
      return switch (name) {
        'text' => AiTextDelta(json['text'] as String? ?? ''),
        'usage' => AiUsage(
          inputTokens: json['inputTokens'] as int?,
          outputTokens: json['outputTokens'] as int?,
        ),
        'done' => AiStreamDone(cancelled: json['cancelled'] as bool? ?? false),
        'error' => AiStreamFailure(
          json['code'] as String? ?? 'AI_UPSTREAM_ERROR',
          json['message'] as String? ?? 'The AI request failed',
        ),
        _ => null,
      };
    }

    await for (final chunk in bytes) {
      buffer += utf8.decode(chunk, allowMalformed: true);
      var newline = buffer.indexOf('\n');
      while (newline != -1) {
        var line = buffer.substring(0, newline);
        buffer = buffer.substring(newline + 1);
        if (line.endsWith('\r')) line = line.substring(0, line.length - 1);
        if (line.isEmpty) {
          final event = dispatch();
          if (event != null) yield event;
        } else if (line.startsWith(':')) {
          // heartbeat — ignore
        } else {
          final colon = line.indexOf(':');
          final field = colon == -1 ? line : line.substring(0, colon);
          var value = colon == -1 ? '' : line.substring(colon + 1);
          if (value.startsWith(' ')) value = value.substring(1);
          if (field == 'data') {
            dataLines.add(value);
          } else if (field == 'event') {
            eventName = value;
          }
        }
        newline = buffer.indexOf('\n');
      }
    }
  }
}

typedef AiStreamClientFactory = AiStreamClient Function(Ref ref);

/// Nullable so tests inject a scripted client (the syncSocketFactory pattern).
/// Default: dio SSE on every platform (the web Socket.IO path lands later
/// behind this same seam).
final aiStreamClientProvider = Provider<AiStreamClient?>((ref) {
  if (kIsWeb) {
    // Web streaming rides a Socket.IO room (parked); until then, the bubble
    // treats a null client as "streaming unavailable here".
    return DioAiStreamClient(ref.watch(apiClientProvider));
  }
  return DioAiStreamClient(ref.watch(apiClientProvider));
});
