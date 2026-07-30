import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:receive_sharing_intent/receive_sharing_intent.dart';

import 'ai_context_builder.dart';

/// Inbound share intents (OPH-225, ADR-0023), behind a seam. The rest of the
/// app talks only to [ShareIntentSource]; tests inject a fake. The provider is
/// nullable — a null source means sharing isn't wired here (web/desktop), so no
/// share surface ever appears. v1 handles text and URLs only.
abstract class ShareIntentSource {
  /// The share that launched the app cold — null when launched normally.
  Future<SharedPayload?> initialShare();

  /// Shares that arrive while the app is already running (warm).
  Stream<SharedPayload> shares();

  /// Acknowledge the initial share so a later resume doesn't replay it.
  void reset();
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

  @override
  Future<SharedPayload?> initialShare() async =>
      payloadFromMedia(await _intent.getInitialMedia());

  @override
  Stream<SharedPayload> shares() => _intent
      .getMediaStream()
      .map(payloadFromMedia)
      .where((p) => p != null)
      .cast<SharedPayload>();

  @override
  void reset() => _intent.reset();
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

/// Subscribes the share source to the pending holder. HomeShell keeps this
/// alive — and the shell only mounts once signed in, so a cold-start share
/// lands AFTER the session exists (it structurally sidesteps the auth-restore
/// race the deep-link path had to solve with remember/replay).
final shareBinderProvider = Provider<void>((ref) {
  final source = ref.watch(shareIntentSourceProvider);
  if (source == null) return;
  final pending = ref.read(pendingSharePayloadProvider.notifier);
  // Cold-start share, then tell the plugin we took it.
  source.initialShare().then((payload) {
    if (payload != null) pending.remember(payload);
    source.reset();
  });
  // Warm shares while the app runs.
  final sub = source.shares().listen(pending.remember);
  ref.onDispose(sub.cancel);
});
