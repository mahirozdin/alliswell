import 'dart:io';

import 'package:alliswell_eventkit/alliswell_eventkit.dart';
import 'package:flutter/foundation.dart';

export 'package:alliswell_eventkit/alliswell_eventkit.dart'
    show AppleCalendar, AppleEventSpec, EventKitAccess, EventKitException;

/// The seam between Apple calendar LOGIC and the platform channel (OPH-077) —
/// the same shape `notifications/gateway.dart` uses, and for the same reason:
/// widget tests swap in a fake, and no platform channel leaks into a screen.
abstract interface class AppleCalendarGateway {
  /// Whether this build can talk to EventKit at all. False everywhere except
  /// iOS/macOS — Android, web, Windows and Linux have no such thing, and the
  /// UI must hide rather than offer something that cannot work.
  bool get isSupported;

  Future<EventKitAccess> status();

  /// Prompts once; afterwards the OS answers from its own record.
  Future<EventKitAccess> requestAccess();

  /// Only meaningful with [EventKitAccess.fullAccess] — write-only permission
  /// can create events but cannot read them back.
  Future<List<AppleCalendar>> calendars();

  // ── Mirror write path (OPH-078) ─────────────────────────────────────────────

  /// Create ([AppleEventSpec.eventId] null) or update; returns the resulting
  /// event identifier to persist as the map key.
  Future<String> saveEvent(AppleEventSpec spec);

  /// Idempotent — deleting an already-gone event is success.
  Future<void> deleteEvent(String eventId);

  /// Re-link recovery: an event still carrying our task url, or null.
  Future<String?> findEventByUrl({
    required String calendarId,
    required String url,
    required DateTime from,
    required DateTime to,
  });
}

class EventKitCalendarGateway implements AppleCalendarGateway {
  const EventKitCalendarGateway([this._eventKit = const AlliswellEventKit()]);

  final AlliswellEventKit _eventKit;

  @override
  bool get isSupported => !kIsWeb && (Platform.isIOS || Platform.isMacOS);

  @override
  Future<EventKitAccess> status() => isSupported
      ? _eventKit.status()
      : Future.value(EventKitAccess.restricted);

  @override
  Future<EventKitAccess> requestAccess() => isSupported
      ? _eventKit.requestAccess()
      : Future.value(EventKitAccess.restricted);

  @override
  Future<List<AppleCalendar>> calendars() =>
      isSupported ? _eventKit.calendars() : Future.value(const []);

  @override
  Future<String> saveEvent(AppleEventSpec spec) => _eventKit.saveEvent(spec);

  @override
  Future<void> deleteEvent(String eventId) => _eventKit.deleteEvent(eventId);

  @override
  Future<String?> findEventByUrl({
    required String calendarId,
    required String url,
    required DateTime from,
    required DateTime to,
  }) => _eventKit.findEventByUrl(
    calendarId: calendarId,
    url: url,
    from: from,
    to: to,
  );
}
