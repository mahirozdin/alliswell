import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:receive_sharing_intent/receive_sharing_intent.dart';

import 'ai_context_builder.dart';
import 'share_intent.dart';

/// The iOS App Group mailbox, behind a seam (OPH-242, ADR-0029).
///
/// `receive_sharing_intent` fills its buffers **only** from a URL open —
/// `didFinishLaunchingWithOptions[.url]`, `application:openURL:`,
/// `application:continue:`. Since ADR-0029 stopped trying to open the host app
/// (an appex cannot, on iOS 18+), no URL ever arrives on this platform, so
/// `getInitialMedia()` answers with an empty list forever while the payload
/// sits unread in `UserDefaults`. This reads it.
///
/// It is a second transport, not a replacement: Android still delivers through
/// the plugin exactly as before, and so does an iOS `.md` "Open in AllisWell",
/// which really is a URL open. The [ShareLog] records which one fired, because
/// "which transport" is the first question the next bug report will need.
abstract class ShareInbox {
  /// Read-and-clear. Null when the mailbox was empty.
  Future<SharedPayload?> take();
}

/// Nothing to drain: every other platform either has no share extension or
/// gets its payload through the plugin.
class NoShareInbox implements ShareInbox {
  const NoShareInbox();

  @override
  Future<SharedPayload?> take() async => null;
}

class MethodChannelShareInbox implements ShareInbox {
  const MethodChannelShareInbox();

  static const channel = MethodChannel('alliswell/share_inbox');

  @override
  Future<SharedPayload?> take() async {
    final raw = await channel.invokeMapMethod<String, Object?>('take');
    if (raw == null) return null;
    return payloadFromMailbox(
      mediaJson: raw['media'] as String?,
      message: raw['message'] as String?,
    );
  }
}

/// Pure decoder for what the extension left behind — kept out of the channel
/// class so it can be tested without a platform.
///
/// Mirrors the plugin's own merge (`SwiftReceiveSharingIntentPlugin.handleUrl`):
/// the compose sheet's text is stored ONCE under its own key and belongs on
/// every entry, because [payloadFromMedia] reads `message ?? path` and for a
/// URL share the path is the link, not the sentence the user typed.
@visibleForTesting
SharedPayload? payloadFromMailbox({
  required String? mediaJson,
  required String? message,
}) {
  if (mediaJson == null || mediaJson.isEmpty) {
    // A compose sheet posted with no attachment at all is still a share.
    if (message == null || message.trim().isEmpty) return null;
    return SharedPayload(text: message);
  }
  final Object? decoded;
  try {
    decoded = jsonDecode(mediaJson);
  } on FormatException {
    return null;
  }
  if (decoded is! List) return null;
  final media = <SharedMediaFile>[];
  for (final entry in decoded) {
    if (entry is! Map) continue;
    final map = Map<String, dynamic>.from(entry);
    map['message'] = message;
    try {
      media.add(SharedMediaFile.fromMap(map));
    } on Object {
      // One malformed entry must not lose the rest of the mailbox.
      continue;
    }
  }
  final payload = payloadFromMedia(media);
  if (payload != null) return payload;
  if (message != null && message.trim().isNotEmpty) {
    return SharedPayload(text: message);
  }
  return null;
}

/// iOS only — see the class doc for why no other platform needs it.
final shareInboxProvider = Provider<ShareInbox>((ref) {
  if (kIsWeb) return const NoShareInbox();
  return defaultTargetPlatform == TargetPlatform.iOS
      ? const MethodChannelShareInbox()
      : const NoShareInbox();
});
