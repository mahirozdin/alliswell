/// Mirrors the API's note shapes (apps/api routes/notes.js): list rows carry
/// a snippet; the detail carries full delta/markdown content and links.
class NoteRow {
  const NoteRow({
    required this.id,
    required this.workspaceId,
    required this.title,
    required this.snippet,
    required this.isPinned,
    required this.isArchived,
    required this.revision,
    this.projectId,
    this.createdFromTaskId,
    this.updatedAt,
  });

  factory NoteRow.fromJson(Map<String, dynamic> json) => NoteRow(
    id: json['id'] as String,
    workspaceId: json['workspaceId'] as String,
    projectId: json['projectId'] as String?,
    createdFromTaskId: json['createdFromTaskId'] as String?,
    title: json['title'] as String,
    snippet: (json['snippet'] as String?) ?? '',
    isPinned: json['isPinned'] as bool,
    isArchived: json['isArchived'] as bool,
    revision: json['revision'] as int,
    updatedAt: json['updatedAt'] != null
        ? DateTime.parse(json['updatedAt'] as String)
        : null,
  );

  final String id;
  final String workspaceId;
  final String? projectId;
  final String? createdFromTaskId;
  final String title;
  final String snippet;
  final bool isPinned;
  final bool isArchived;
  final int revision;
  final DateTime? updatedAt;
}

class NoteDetail extends NoteRow {
  const NoteDetail({
    required super.id,
    required super.workspaceId,
    required super.title,
    required super.snippet,
    required super.isPinned,
    required super.isArchived,
    required super.revision,
    super.projectId,
    super.createdFromTaskId,
    super.updatedAt,
    this.contentDelta,
    this.contentMarkdown,
    this.links = const [],
  });

  factory NoteDetail.fromJson(Map<String, dynamic> json) {
    final row = NoteRow.fromJson(json);
    return NoteDetail(
      id: row.id,
      workspaceId: row.workspaceId,
      projectId: row.projectId,
      createdFromTaskId: row.createdFromTaskId,
      title: row.title,
      snippet: row.snippet,
      isPinned: row.isPinned,
      isArchived: row.isArchived,
      revision: row.revision,
      updatedAt: row.updatedAt,
      contentDelta: (json['contentDelta'] as List?)
          ?.cast<Map<String, dynamic>>(),
      contentMarkdown: json['contentMarkdown'] as String?,
      links: ((json['links'] as List?) ?? const [])
          .map((l) => NoteLink.fromJson(l as Map<String, dynamic>))
          .toList(),
    );
  }

  final List<Map<String, dynamic>>? contentDelta;
  final String? contentMarkdown;
  final List<NoteLink> links;
}

class NoteLink {
  const NoteLink({
    required this.id,
    required this.entityType,
    required this.entityId,
  });

  factory NoteLink.fromJson(Map<String, dynamic> json) => NoteLink(
    id: json['id'] as String,
    entityType: json['entityType'] as String,
    entityId: json['entityId'] as String,
  );

  final String id;
  final String entityType;
  final String entityId;
}
