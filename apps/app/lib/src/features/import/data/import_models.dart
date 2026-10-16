import 'package:flutter/foundation.dart';

/// The import wizard's vocabulary (OPH-371, ADR-0052).
///
/// The server does all the parsing (POST /workspaces/:id/import/apps); these
/// are the shapes it answers with. Apple Reminders is deliberately absent: it
/// has no export file.
enum ImportSource {
  todoist('todoist', 'Todoist'),
  ticktick('ticktick', 'TickTick');

  const ImportSource(this.wire, this.label);

  /// The `source` the API expects.
  final String wire;

  /// The product's own name — never translated.
  final String label;
}

/// One export file as text, ready to send.
@immutable
class ImportFileText {
  const ImportFileText({
    required this.name,
    required this.content,
    required this.bytes,
  });

  final String name;
  final String content;

  /// The size it had on disk (or inside the ZIP) — shown as provenance.
  final int bytes;

  Map<String, Object> toJson() => {'name': name, 'content': content};
}

int _int(Object? v) => v is num ? v.toInt() : 0;

@immutable
class ImportWarningExample {
  const ImportWarningExample({this.file, this.row, this.title, this.value});

  factory ImportWarningExample.fromJson(Map<String, dynamic> json) =>
      ImportWarningExample(
        file: json['file'] as String?,
        row: (json['row'] as num?)?.toInt(),
        title: json['title'] as String?,
        value: json['value'] as String?,
      );

  final String? file;
  final int? row;
  final String? title;
  final String? value;
}

@immutable
class ImportWarningGroup {
  const ImportWarningGroup({
    required this.code,
    required this.count,
    this.examples = const [],
  });

  factory ImportWarningGroup.fromJson(Map<String, dynamic> json) =>
      ImportWarningGroup(
        code: json['code'] as String? ?? 'IMPORT_UNKNOWN',
        count: _int(json['count']),
        examples: [
          for (final e in (json['examples'] as List?) ?? const [])
            ImportWarningExample.fromJson(e as Map<String, dynamic>),
        ],
      );

  final String code;
  final int count;
  final List<ImportWarningExample> examples;
}

@immutable
class ImportItemError {
  const ImportItemError({
    required this.code,
    required this.message,
    this.file,
    this.row,
  });

  factory ImportItemError.fromJson(Map<String, dynamic> json) =>
      ImportItemError(
        code: json['code'] as String? ?? 'IMPORT_ITEM_FAILED',
        message: json['message'] as String? ?? '',
        file: json['file'] as String?,
        row: (json['row'] as num?)?.toInt(),
      );

  final String code;
  final String message;
  final String? file;
  final int? row;
}

@immutable
class ImportCreated {
  const ImportCreated({
    this.projects = 0,
    this.tags = 0,
    this.tasks = 0,
    this.checklistItems = 0,
    this.notes = 0,
    this.series = 0,
  });

  factory ImportCreated.fromJson(Map<String, dynamic>? json) => ImportCreated(
    projects: _int(json?['projects']),
    tags: _int(json?['tags']),
    tasks: _int(json?['tasks']),
    checklistItems: _int(json?['checklistItems']),
    notes: _int(json?['notes']),
    series: _int(json?['series']),
  );

  final int projects;
  final int tags;
  final int tasks;
  final int checklistItems;
  final int notes;
  final int series;

  /// The things a person counts as "imported": tasks, repeats and notes.
  int get items => tasks + notes + series;

  ImportCreated operator +(ImportCreated o) => ImportCreated(
    projects: projects + o.projects,
    tags: tags + o.tags,
    tasks: tasks + o.tasks,
    checklistItems: checklistItems + o.checklistItems,
    notes: notes + o.notes,
    series: series + o.series,
  );
}

/// The server's answer — the preview (dryRun) and every import batch.
@immutable
class ImportSummary {
  const ImportSummary({
    required this.total,
    this.projectsNew = 0,
    this.projectsExisting = 0,
    this.tagsNew = 0,
    this.tagsExisting = 0,
    this.tasks = 0,
    this.series = 0,
    this.checklistItems = 0,
    this.notes = 0,
    this.completedIncluded = 0,
    this.completedSkipped = 0,
    this.alreadyImported = 0,
    this.googleConnected = false,
    this.googleTasks = 0,
    this.googleUndated = 0,
    this.priority = const [],
    this.warnings = const [],
    this.created = const ImportCreated(),
    this.errors = const [],
    this.remaining = 0,
  });

  factory ImportSummary.fromJson(Map<String, dynamic> json) {
    Map<String, dynamic> obj(String k) =>
        (json[k] as Map?)?.cast<String, dynamic>() ?? const {};
    final mapping = obj('mapping');
    return ImportSummary(
      total: _int(json['total']),
      projectsNew: _int(obj('projects')['new']),
      projectsExisting: _int(obj('projects')['existing']),
      tagsNew: _int(obj('tags')['new']),
      tagsExisting: _int(obj('tags')['existing']),
      tasks: _int(json['tasks']),
      series: _int(json['series']),
      checklistItems: _int(json['checklistItems']),
      notes: _int(json['notes']),
      completedIncluded: _int(obj('completed')['included']),
      completedSkipped: _int(obj('completed')['skipped']),
      alreadyImported: _int(json['alreadyImported']),
      googleConnected: obj('googleMirror')['connected'] == true,
      googleTasks: _int(obj('googleMirror')['tasks']),
      googleUndated: _int(obj('googleMirror')['undated']),
      priority: [
        for (final p in (mapping['priority'] as List?) ?? const [])
          (
            from: (p as Map)['from'] as String? ?? '',
            to: p['to'] as String? ?? 'none',
          ),
      ],
      warnings: [
        for (final w in (json['warnings'] as List?) ?? const [])
          ImportWarningGroup.fromJson(w as Map<String, dynamic>),
      ],
      created: ImportCreated.fromJson(
        (json['created'] as Map?)?.cast<String, dynamic>(),
      ),
      errors: [
        for (final e in (json['errors'] as List?) ?? const [])
          ImportItemError.fromJson(e as Map<String, dynamic>),
      ],
      remaining: _int(json['remaining']),
    );
  }

  /// Items this import would write (tasks + repeats + notes).
  final int total;
  final int projectsNew;
  final int projectsExisting;
  final int tagsNew;
  final int tagsExisting;
  final int tasks;
  final int series;
  final int checklistItems;
  final int notes;
  final int completedIncluded;
  final int completedSkipped;
  final int alreadyImported;
  final bool googleConnected;
  final int googleTasks;
  final int googleUndated;
  final List<({String from, String to})> priority;
  final List<ImportWarningGroup> warnings;
  final ImportCreated created;
  final List<ImportItemError> errors;
  final int remaining;
}

/// What the wizard tells the person at the end — every batch added up.
@immutable
class ImportReport {
  const ImportReport({
    required this.created,
    required this.alreadyImported,
    required this.completedSkipped,
    required this.errors,
  });

  final ImportCreated created;
  final int alreadyImported;
  final int completedSkipped;
  final List<ImportItemError> errors;
}
