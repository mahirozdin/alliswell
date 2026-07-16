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

  // ── Event CRUD (OPH-078) ────────────────────────────────────────────────────

  /// Create ([spec.eventId] null) or update. Returns the resulting event
  /// identifier — which the caller must persist, because EventKit's identifier
  /// can change on an iCloud move, and the stored id is the primary map key.
  Future<String> saveEvent(AppleEventSpec spec) async {
    try {
      final res = await _channel.invokeMapMethod<String, Object?>(
        'saveEvent',
        spec.toArgs(),
      );
      final id = res?['id'] as String?;
      if (id == null) throw const EventKitException('saveEvent returned no id');
      return id;
    } on PlatformException catch (e) {
      throw EventKitException(e.message ?? e.code);
    }
  }

  /// Idempotent: deleting an already-gone event succeeds (the intent — no such
  /// event — is satisfied), so reconciling can run repeatedly without error.
  Future<void> deleteEvent(String eventId) async {
    try {
      await _channel.invokeMethod<bool>('deleteEvent', {'id': eventId});
    } on PlatformException catch (e) {
      throw EventKitException(e.message ?? e.code);
    }
  }

  /// Re-link recovery: find an event still carrying our task url when the stored
  /// identifier has gone stale (ADR-0003). Null when none matches.
  Future<String?> findEventByUrl({
    required String calendarId,
    required String url,
    required DateTime from,
    required DateTime to,
  }) async {
    try {
      return await _channel.invokeMethod<String>('findEventByUrl', {
        'calendarId': calendarId,
        'url': url,
        'fromMs': from.toUtc().millisecondsSinceEpoch,
        'toMs': to.toUtc().millisecondsSinceEpoch,
      });
    } on MissingPluginException {
      return null;
    } on PlatformException catch (e) {
      throw EventKitException(e.message ?? e.code);
    }
  }
}

/// What to write to EventKit for one task (OPH-078). Purely data — the decision
/// to write it, and what it should contain, is made by `desiredAppleEvent` in
/// the app; this package only carries it across the channel.
class AppleEventSpec {
  const AppleEventSpec({
    required this.calendarId,
    required this.title,
    required this.url,
    required this.start,
    required this.end,
    this.eventId,
    this.notes,
    this.isAllDay = false,
  });

  /// Null on create; the stored EventKit identifier on update.
  final String? eventId;

  /// Which calendar to create INTO (ignored on update — an event keeps its
  /// calendar unless explicitly moved, which v1 does not do).
  final String calendarId;
  final String title;

  /// `alliswell://task/{id}` — the re-link recovery key (ADR-0003).
  final String url;
  final String? notes;
  final DateTime start;
  final DateTime end;
  final bool isAllDay;

  Map<String, Object?> toArgs() => {
    if (eventId != null) 'id': eventId,
    'calendarId': calendarId,
    'title': title,
    'url': url,
    'notes': notes,
    'startMs': start.toUtc().millisecondsSinceEpoch,
    'endMs': end.toUtc().millisecondsSinceEpoch,
    'isAllDay': isAllDay,
  };
}
