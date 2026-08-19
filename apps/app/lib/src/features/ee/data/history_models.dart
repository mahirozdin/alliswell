import 'package:flutter/material.dart';

/// One recorded fact about an entity (EE-026). Mirrors the server's history
/// serializer; the app never invents fields it was not told.
@immutable
class EeHistoryEvent {
  const EeHistoryEvent({
    required this.id,
    required this.occurredAt,
    required this.actor,
    required this.verb,
    required this.entityType,
    required this.entityId,
    this.actorId,
    this.actorName,
    this.actorInitials,
    this.actorColorRgb,
    this.workspaceId,
    this.diff,
  });

  final String id;
  final DateTime occurredAt;

  /// `user` | `system` | `public` — a repair sweep and a person are not the
  /// same author, and the widget says so rather than blaming the last human.
  final String actor;
  final String verb;
  final String entityType;
  final String entityId;
  final String? actorId;
  final String? actorName;
  final String? actorInitials;
  final String? actorColorRgb;
  final String? workspaceId;
  final Map<String, dynamic>? diff;

  bool get isSystem => actor == 'system';

  /// The palette colour the server chose for this person, or null (the widget
  /// falls back to a theme colour rather than picking a second scheme).
  Color? get actorColor {
    final raw = actorColorRgb;
    if (raw == null || !RegExp(r'^#[0-9A-Fa-f]{6}$').hasMatch(raw)) return null;
    return Color(int.parse('FF${raw.substring(1)}', radix: 16));
  }

  factory EeHistoryEvent.fromJson(Map<String, dynamic> json) => EeHistoryEvent(
    id: json['id'] as String,
    occurredAt: DateTime.parse(json['occurredAt'] as String).toLocal(),
    actor: (json['actor'] as String?) ?? 'system',
    verb: (json['verb'] as String?) ?? 'updated',
    entityType: (json['entityType'] as String?) ?? '',
    entityId: (json['entityId'] as String?) ?? '',
    actorId: json['actorId'] as String?,
    actorName: json['actorName'] as String?,
    actorInitials: json['actorInitials'] as String?,
    actorColorRgb: json['actorColorRgb'] as String?,
    workspaceId: json['workspaceId'] as String?,
    diff: (json['diff'] as Map?)?.cast<String, dynamic>(),
  );
}

/// One page of history plus the cursor that continues it (never an offset —
/// the server's reasoning is in ADR-0005 / API-EE.md).
@immutable
class EeHistoryPage {
  const EeHistoryPage({required this.items, this.nextCursor});

  final List<EeHistoryEvent> items;
  final String? nextCursor;

  bool get hasMore => nextCursor != null;

  factory EeHistoryPage.fromJson(Map<String, dynamic> json) => EeHistoryPage(
    items: ((json['items'] as List?) ?? const [])
        .map((e) => EeHistoryEvent.fromJson((e as Map).cast<String, dynamic>()))
        .toList(),
    nextCursor: json['nextCursor'] as String?,
  );
}
