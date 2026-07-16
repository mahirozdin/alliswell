/// Thin Dart side of the Apple EventKit bridge (OPH-077, BLUEPRINT §7.3).
///
/// This package is ONLY the channel: no policy, no caching, no decisions. The
/// app wraps it in a gateway it can fake (`features/calendar/apple/`), the same
/// seam notifications use — logic stays pure and testable, native stays dumb.
library;

import 'package:flutter/services.dart';

/// EventKit's authorization states, spelled the way Apple spells them.
enum EventKitAccess {
  notDetermined,
  restricted,
  denied,

  /// iOS 17+: may CREATE events but not read them back. Not good enough for
  /// us — re-linking our own events requires reading — so it is its own state
  /// rather than a flavour of "granted".
  writeOnly,
  fullAccess;

  static EventKitAccess parse(String? name) => switch (name) {
    'restricted' => EventKitAccess.restricted,
    'denied' => EventKitAccess.denied,
    'writeOnly' => EventKitAccess.writeOnly,
    'fullAccess' => EventKitAccess.fullAccess,
    _ => EventKitAccess.notDetermined,
  };

  bool get canMirror => this == EventKitAccess.fullAccess;

  /// Nothing the app does will change these — only the user, in Settings.
  bool get isFinal =>
      this == EventKitAccess.denied || this == EventKitAccess.restricted;
}

class AppleCalendar {
  const AppleCalendar({
    required this.id,
    required this.title,
    required this.isWritable,
    required this.isDefault,
    this.colorArgb,
    this.accountName,
  });

  factory AppleCalendar.fromMap(Map<Object?, Object?> map) => AppleCalendar(
    id: map['id']! as String,
    title: (map['title'] as String?) ?? '(Untitled)',
    isWritable: (map['isWritable'] as bool?) ?? false,
    isDefault: (map['isDefault'] as bool?) ?? false,
    colorArgb: map['colorArgb'] as int?,
    accountName: map['accountName'] as String?,
  );

  final String id;
  final String title;

  /// Holiday/subscribed calendars are read-only: mirroring into one would fail
  /// on every single write, so the picker has to be able to rule them out.
  final bool isWritable;
  final bool isDefault;
  final int? colorArgb;

  /// "iCloud", "Gmail", … — the same title can appear under two accounts.
  final String? accountName;
}

/// Raised when the channel itself fails. NOT raised for a denied user: that is
/// an ordinary [EventKitAccess] value, not an exceptional condition.
class EventKitException implements Exception {
  const EventKitException(this.message);

  final String message;

  @override
  String toString() => 'EventKitException: $message';
}

class AlliswellEventKit {
  const AlliswellEventKit({MethodChannel? channel})
    : _channel = channel ?? const MethodChannel('alliswell/eventkit');

  final MethodChannel _channel;

  /// What the OS currently thinks — cheap, prompts nothing, safe on build.
  Future<EventKitAccess> status() => _invoke('authorizationStatus');

  /// Prompts the FIRST time only; afterwards the OS answers from its record
  /// without showing anything. That is why this returns a status rather than
  /// "did they say yes" — the second call looks identical to the first.
  Future<EventKitAccess> requestAccess() => _invoke('requestFullAccess');

  Future<EventKitAccess> _invoke(String method) async {
    try {
      return EventKitAccess.parse(await _channel.invokeMethod<String>(method));
    } on MissingPluginException {
      // Android/web/Windows/Linux: there is no EventKit at all. Not an error —
      // the feature does not exist there, and `restricted` is exactly Apple's
      // word for "this device will never allow it", so the UI already hides it.
      return EventKitAccess.restricted;
    } on PlatformException catch (e) {
      throw EventKitException(e.message ?? e.code);
    }
  }

  Future<List<AppleCalendar>> calendars() async {
    try {
      final raw = await _channel.invokeListMethod<Object?>('calendars');
      return [
        for (final item in raw ?? const [])
          AppleCalendar.fromMap(item! as Map<Object?, Object?>),
      ];
    } on MissingPluginException {
      return const [];
    } on PlatformException catch (e) {
      throw EventKitException(e.message ?? e.code);
    }
  }
}
