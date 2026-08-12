/// The channel half of ADR-0030 (OPH-256).
///
/// Deliberately dumb, like `alliswell_eventkit`: it moves bytes and reports
/// facts. Every DECISION — what counts as writable, what refuses to be
/// written, what a conflict means — lives in
/// `features/notes/data/external_document.dart`, where it is pure and tested
/// with no disk and no channel.
///
/// The one exception is stated in the ADR and repeated here because it looks
/// like a violation: the expected-hash comparison happens NATIVELY, inside the
/// coordinated write. It is the only place check-then-write can be atomic.
library;

import 'package:flutter/services.dart';

const MethodChannel _channel = MethodChannel('alliswell/docref');

/// Thrown for nothing. Every failure is a value, because every failure here is
/// a state the UI has to render honestly rather than an exception to swallow.
class AlliswellDocref {
  const AlliswellDocref();

  /// Null when the platform has no implementation — the honest-unavailable
  /// idiom, distinguished from "the user cancelled" (which is a refusal).
  Future<Map<Object?, Object?>?> _call(
    String method, [
    Map<String, Object?>? args,
  ]) async {
    try {
      return await _channel.invokeMapMethod<Object?, Object?>(method, args);
    } on MissingPluginException {
      return null;
    }
  }

  Future<Map<Object?, Object?>?> pickExternal({required int maxBytes}) =>
      _call('pickExternal', {'maxBytes': maxBytes});

  Future<Map<Object?, Object?>?> open({
    required String token,
    required String kind,
    required int maxBytes,
  }) => _call('open', {'token': token, 'kind': kind, 'maxBytes': maxBytes});

  Future<Map<Object?, Object?>?> adopt({
    required String osToken,
    required int maxBytes,
  }) => _call('adopt', {'osToken': osToken, 'maxBytes': maxBytes});

  Future<Map<Object?, Object?>?> probe({
    required String token,
    required String kind,
  }) => _call('probe', {'token': token, 'kind': kind});

  /// [expectedSha256] is compared natively, inside the write. [force] skips
  /// that comparison and is reachable in the app only from a conflict.
  Future<Map<Object?, Object?>?> save({
    required String token,
    required String kind,
    required Uint8List bytes,
    required String expectedSha256,
    required bool force,
  }) => _call('save', {
    'token': token,
    'kind': kind,
    'bytes': bytes,
    'expectedSha256': expectedSha256,
    'force': force,
  });

  Future<Map<Object?, Object?>?> clipboardRead() => _call('clipboardRead');

  /// The mailbox for a document the OS opened (Finder double-click, iOS Files).
  ///
  /// A mailbox rather than a callback because the URL arrives before Dart is
  /// listening — the same shape `ShareInboxBridge` uses, and the trap OPH-242
  /// documented on iOS's scene lifecycle.
  Future<Map<Object?, Object?>?> takeOpenedDocument() =>
      _call('takeOpenedDocument');
}
