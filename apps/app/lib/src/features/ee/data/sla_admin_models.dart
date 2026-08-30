import 'package:flutter/foundation.dart';

/// The SLA admin models (EE-099) — what a team admin may edit about a promise.

@immutable
class EeSlaTarget {
  const EeSlaTarget({
    required this.priority,
    this.firstResponseMinutes,
    this.resolutionMinutes,
  });

  final String priority;

  /// Null is "no promise on this clock", which is NOT zero — zero would mean
  /// "late the moment it arrives", and a form must not blur the two.
  final int? firstResponseMinutes;
  final int? resolutionMinutes;

  factory EeSlaTarget.fromJson(Map<String, dynamic> json) => EeSlaTarget(
    priority: json['priority'] as String,
    firstResponseMinutes: (json['firstResponseMinutes'] as num?)?.toInt(),
    resolutionMinutes: (json['resolutionMinutes'] as num?)?.toInt(),
  );
}

@immutable
class EeSlaPolicy {
  const EeSlaPolicy({
    required this.id,
    required this.name,
    this.calendarId,
    this.isDefault = false,
    this.warnPercent = 80,
    this.escalationMinutes = 60,
    this.targets = const [],
  });

  final String id;
  final String name;

  /// Null is 24/7 — a real contract, not a missing value (ADR-0012 §1).
  final String? calendarId;
  final bool isDefault;
  final int warnPercent;
  final int escalationMinutes;
  final List<EeSlaTarget> targets;

  EeSlaTarget? targetFor(String priority) {
    for (final t in targets) {
      if (t.priority == priority) return t;
    }
    return null;
  }

  factory EeSlaPolicy.fromJson(Map<String, dynamic> json) => EeSlaPolicy(
    id: json['id'] as String,
    name: json['name'] as String,
    calendarId: json['calendarId'] as String?,
    isDefault: json['isDefault'] as bool? ?? false,
    warnPercent: (json['warnPercent'] as num?)?.toInt() ?? 80,
    escalationMinutes: (json['escalationMinutes'] as num?)?.toInt() ?? 60,
    targets: ((json['targets'] as List?) ?? const [])
        .map((t) => EeSlaTarget.fromJson(t as Map<String, dynamic>))
        .toList(),
  );
}

/// One shift. `endMinute` may exceed 1440 — that is how a night shift is
/// spelled, and the screen has to say so in words (ADR-0012 §1's UI debt).
@immutable
class EeBusinessHour {
  const EeBusinessHour({
    required this.weekday,
    required this.startMinute,
    required this.endMinute,
  });

  final int weekday; // 1 = Monday … 7 = Sunday (ISO)
  final int startMinute;
  final int endMinute;

  bool get crossesMidnight => endMinute > 1440;

  Map<String, dynamic> toJson() => {
    'weekday': weekday,
    'startMinute': startMinute,
    'endMinute': endMinute,
  };

  factory EeBusinessHour.fromJson(Map<String, dynamic> json) => EeBusinessHour(
    weekday: (json['weekday'] as num).toInt(),
    startMinute: (json['startMinute'] as num).toInt(),
    endMinute: (json['endMinute'] as num).toInt(),
  );
}

@immutable
class EeHoliday {
  const EeHoliday({required this.date, this.name});
  final String date; // YYYY-MM-DD
  final String? name;

  Map<String, dynamic> toJson() => {
    'date': date,
    if (name != null) 'name': name,
  };

  factory EeHoliday.fromJson(Map<String, dynamic> json) =>
      EeHoliday(date: json['date'] as String, name: json['name'] as String?);
}

@immutable
class EeBusinessCalendar {
  const EeBusinessCalendar({
    required this.id,
    required this.name,
    this.timezone,
    this.hours = const [],
    this.holidays = const [],
  });

  final String id;
  final String name;

  /// Null follows the team's own zone, which follows UTC — two levels of
  /// "not chosen" rather than a default copied at create time.
  final String? timezone;
  final List<EeBusinessHour> hours;
  final List<EeHoliday> holidays;

  factory EeBusinessCalendar.fromJson(Map<String, dynamic> json) =>
      EeBusinessCalendar(
        id: json['id'] as String,
        name: json['name'] as String,
        timezone: json['timezone'] as String?,
        hours: ((json['hours'] as List?) ?? const [])
            .map((h) => EeBusinessHour.fromJson(h as Map<String, dynamic>))
            .toList(),
        holidays: ((json['holidays'] as List?) ?? const [])
            .map((h) => EeHoliday.fromJson(h as Map<String, dynamic>))
            .toList(),
      );
}

@immutable
class EeHealthCheck {
  const EeHealthCheck({
    required this.id,
    required this.name,
    required this.url,
    this.serviceId,
    this.intervalSec = 300,
    this.timeoutMs = 5000,
    this.expectStatus,
    this.expectBody,
    this.failureThreshold = 3,
    this.enabled = true,
    this.status = 'unknown',
    this.lastCheckedAt,
    this.lastError,
  });

  final String id;
  final String name;
  final String url;
  final String? serviceId;
  final int intervalSec;
  final int timeoutMs;
  final int? expectStatus;
  final String? expectBody;
  final int failureThreshold;
  final bool enabled;

  /// `unknown` until the first probe answers — distinct from up and from down.
  final String status;
  final DateTime? lastCheckedAt;
  final String? lastError;

  factory EeHealthCheck.fromJson(Map<String, dynamic> json) => EeHealthCheck(
    id: json['id'] as String,
    name: json['name'] as String,
    url: json['url'] as String,
    serviceId: json['serviceId'] as String?,
    intervalSec: (json['intervalSec'] as num?)?.toInt() ?? 300,
    timeoutMs: (json['timeoutMs'] as num?)?.toInt() ?? 5000,
    expectStatus: (json['expectStatus'] as num?)?.toInt(),
    expectBody: json['expectBody'] as String?,
    failureThreshold: (json['failureThreshold'] as num?)?.toInt() ?? 3,
    enabled: json['enabled'] as bool? ?? true,
    status: json['status'] as String? ?? 'unknown',
    lastCheckedAt: json['lastCheckedAt'] == null
        ? null
        : DateTime.parse(json['lastCheckedAt'] as String).toLocal(),
    lastError: json['lastError'] as String?,
  );
}

/// Everything the admin area needs, fetched together.
@immutable
class EeSlaAdminData {
  const EeSlaAdminData({
    this.policies = const [],
    this.calendars = const [],
    this.checks = const [],
  });

  final List<EeSlaPolicy> policies;
  final List<EeBusinessCalendar> calendars;
  final List<EeHealthCheck> checks;

  String? calendarName(String? id) {
    if (id == null) return null;
    for (final c in calendars) {
      if (c.id == id) return c.name;
    }
    return null;
  }
}
