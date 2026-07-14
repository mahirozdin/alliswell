import 'package:flutter/material.dart';

/// Mirrors the API's project shape (apps/api routes/projects.js).
class Project {
  const Project({
    required this.id,
    required this.workspaceId,
    required this.name,
    required this.colorRgb,
    required this.status,
    required this.sortOrder,
    required this.isFavorite,
    required this.revision,
    this.description,
    this.icon,
    this.readmeNoteId,
    this.startAt,
    this.dueAt,
  });

  factory Project.fromJson(Map<String, dynamic> json) => Project(
    id: json['id'] as String,
    workspaceId: json['workspaceId'] as String,
    name: json['name'] as String,
    description: json['description'] as String?,
    colorRgb: json['colorRgb'] as String,
    icon: json['icon'] as String?,
    readmeNoteId: json['readmeNoteId'] as String?,
    status: json['status'] as String,
    startAt: json['startAt'] != null
        ? DateTime.parse(json['startAt'] as String)
        : null,
    dueAt: json['dueAt'] != null
        ? DateTime.parse(json['dueAt'] as String)
        : null,
    sortOrder: json['sortOrder'] as int,
    isFavorite: json['isFavorite'] as bool,
    revision: json['revision'] as int,
  );

  final String id;
  final String workspaceId;
  final String name;
  final String? description;
  final String colorRgb;
  final String? icon;
  final String? readmeNoteId;
  final String status;
  final DateTime? startAt;
  final DateTime? dueAt;
  final int sortOrder;
  final bool isFavorite;
  final int revision;

  Color get color => colorFromRgbHex(colorRgb);
}

/// `#RRGGBB` → opaque [Color]; falls back to the brand blue on garbage.
Color colorFromRgbHex(String rgb) {
  final hex = int.tryParse(rgb.replaceFirst('#', ''), radix: 16);
  return Color(0xFF000000 | (hex ?? 0x2563EB));
}
