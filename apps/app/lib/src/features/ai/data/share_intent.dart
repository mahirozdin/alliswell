import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:receive_sharing_intent/receive_sharing_intent.dart';

import '../../../sync/db/database.dart';
import '../../../sync/providers.dart';
import '../../notes/data/markdown_source.dart';
import '../../notes/ui/markdown_import_screen.dart';
import 'ai_context_builder.dart';
import 'share_log.dart';

/// Inbound share intents (OPH-225, ADR-0023), behind a seam. The rest of the
/// app talks only to [ShareIntentSource]; tests inject a fake. The provider is
/// nullable — a null source means sharing isn't wired here (web/desktop), so no
/// share surface ever appears.
///
/// The OS delivers two different intentions down ONE channel: "here is some
/// text, do something with it" (share) and "here is a document, open it"
/// (round 16 follow-up: `.md` files). They are separate members rather than one
/// union because they have separate consumers — the AI bubble and the markdown
/// viewer — and neither should have to filter the other's traffic.
abstract class ShareIntentSource {
  /// The share that launched the app cold — null when launched normally.
  Future<SharedPayload?> initialShare();

  /// Shares that arrive while the app is already running (warm).
  Stream<SharedPayload> shares();

  /// A document the OS asked us to OPEN at cold start, if any.
  Future<String?> initialDocument();

  /// Documents handed to us while the app is already running.
  Stream<String> documents();

  /// Acknowledge the initial share so a later resume doesn't replay it.
  void reset();
}

/// The path of the first markdown file in a media list, or null.
///
/// Matched on the FILE NAME, not the mime type: Android reports `.md` as
/// text/plain, application/octet-stream or nothing at all depending on which
/// app produced the intent, so trusting the mime type would drop most real
/// files.
String? markdownPathFromMedia(List<SharedMediaFile> media) {
  for (final m in media) {
    final path = m.path;
    if (path.isNotEmpty && isMarkdownPath(path)) return path;
  }
  return null;
}

/// Maps the plugin's media list to our text/URL payload; v1 drops files/images.
SharedPayload? payloadFromMedia(List<SharedMediaFile> media) {
  for (final m in media) {
    if (m.type == SharedMediaType.url) {
      return SharedPayload(text: m.message ?? m.path, url: m.path);
    }
    if (m.type == SharedMediaType.text) {
      return SharedPayload(text: m.message ?? m.path);
    }
  }
  return null;
}

class ReceiveSharingIntentSource implements ShareIntentSource {
  final _intent = ReceiveSharingIntent.instance;

  /// ONE fetch, read by both cold-start getters. Asking the plugin twice would
  /// work today (it caches until `reset()`) but only by accident.
  Future<List<SharedMediaFile>>? _initial;
  Future<List<SharedMediaFile>> _initialMedia() =>
      _initial ??= _intent.getInitialMedia();

  /// ONE subscription to the platform channel, fanned out. Calling
  /// `getMediaStream()` per consumer would register a second channel listener.
  late final Stream<List<SharedMediaFile>> _warm = _intent
      .getMediaStream()
      .asBroadcastStream();

  @override
  Future<SharedPayload?> initialShare() async =>
      payloadFromMedia(await _initialMedia());

  @override
  Future<String?> initialDocument() async =>
      markdownPathFromMedia(await _initialMedia());

  @override
  Stream<SharedPayload> shares() =>
      _warm.map(payloadFromMedia).where((p) => p != null).cast<SharedPayload>();

  @override
  Stream<String> documents() =>
      _warm.map(markdownPathFromMedia).where((p) => p != null).cast<String>();

  @override
  void reset() {
    _initial = null;
    _intent.reset();
  }
}

/// Only mobile carries the platform channel; elsewhere sharing is absent.
final shareIntentSourceProvider = Provider<ShareIntentSource?>((ref) {
  if (kIsWeb) return null;
  switch (defaultTargetPlatform) {
    case TargetPlatform.android:
    case TargetPlatform.iOS:
      return ReceiveSharingIntentSource();
    default:
      return null;
  }
});

/// Holds a shared payload until a surface consumes it (the [PendingDeepLink]
/// analog). A payload is only ever replayed once — [take] reads and clears.
class PendingSharePayload extends Notifier<SharedPayload?> {
  @override
  SharedPayload? build() => null;

  void remember(SharedPayload payload) => state = payload;

  SharedPayload? take() {
    final pending = state;
    if (pending != null) state = null;
    return pending;
  }
}

final pendingSharePayloadProvider =
    NotifierProvider<PendingSharePayload, SharedPayload?>(
      PendingSharePayload.new,
    );

/// The share pipeline's device-local diagnostic trail (OPH-242).
final shareLogProvider = Provider<ShareLog>(
  (ref) => ShareLog(ref.watch(databaseProvider)),
);

/// Newest-first rows for the Settings diagnostic screen.
final shareLogRowsProvider = StreamProvider<List<ShareEvent>>(
  (ref) => ref.watch(shareLogProvider).watchRecent(),
);

/// Subscribes the share source to the pending holder. HomeShell keeps this
/// alive — and the shell only mounts once signed in, so a cold-start share
/// lands AFTER the session exists (it structurally sidesteps the auth-restore
/// race the deep-link path had to solve with remember/replay).
///
/// Every arrival is also written to the [ShareLog]. Round 17 #1 was a report
/// nothing could confirm or deny ("I shared a text and nothing happened");
/// the log makes the next such report measurable — including, crucially, when
/// it stays EMPTY, which places the fault before Dart.
final shareBinderProvider = Provider<void>((ref) {
  final source = ref.watch(shareIntentSourceProvider);
  if (source == null) return;
  final pending = ref.read(pendingSharePayloadProvider.notifier);
  final markdown = ref.read(pendingMarkdownProvider.notifier);
  final files = ref.read(markdownSourceProvider);
  final log = ref.read(shareLogProvider);

  void rememberShare(SharedPayload payload, {required bool cold}) {
    log.record(
      event: cold ? ShareLogEvent.initialShare : ShareLogEvent.warmShare,
      payloadKind: payload.url != null ? ShareLogKind.url : ShareLogKind.text,
      bytes: _utf8Bytes(payload.text),
    );
    pending.remember(payload);
  }

  Future<void> openDocument(String path, {required bool cold}) async {
    // Reading can fail (a permission-scoped URI that expired, a file that is
    // gone). Failing silently is still right for the UI — there is no screen to
    // show an error on yet, and the viewer's empty state tells the user what to
    // do — but it is no longer silent to the log.
    try {
      final doc = await files.read(path);
      if (doc == null) {
        log.record(
          event: ShareLogEvent.readFailed,
          payloadKind: ShareLogKind.markdown,
          detail: 'empty',
        );
        return;
      }
      log.record(
        event: cold
            ? ShareLogEvent.initialDocument
            : ShareLogEvent.warmDocument,
        payloadKind: ShareLogKind.markdown,
        bytes: _utf8Bytes(doc.markdown),
      );
      markdown.remember(doc);
    } on Object catch (error) {
      // The TYPE, never the path: a path can carry a document's name.
      log.record(
        event: ShareLogEvent.readFailed,
        payloadKind: ShareLogKind.markdown,
        detail: error.runtimeType.toString(),
      );
    }
  }

  // Cold start: read BOTH intentions before telling the plugin we took them.
  Future.wait([
    source.initialShare().then((payload) {
      if (payload != null) rememberShare(payload, cold: true);
    }),
    source.initialDocument().then((path) async {
      if (path != null) await openDocument(path, cold: true);
    }),
  ]).whenComplete(source.reset);

  // Warm deliveries while the app runs.
  final shares = source.shares().listen(
    (payload) => rememberShare(payload, cold: false),
  );
  final documents = source.documents().listen(
    (path) => openDocument(path, cold: false),
  );
  ref.onDispose(() {
    shares.cancel();
    documents.cancel();
  });
});

/// Size in bytes, not characters — a Turkish note is bigger than its length.
int _utf8Bytes(String text) => utf8.encode(text).length;
