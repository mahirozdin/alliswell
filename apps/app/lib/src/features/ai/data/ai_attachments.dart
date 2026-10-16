/// On-demand attachments for the AI chat (OPH-377, ADR-0058) — the PURE half:
/// the attachment model, the text formatters, the text-file test and the
/// request builder that turns picked items into fenced context segments.
///
/// Nothing here is automatic: an attachment exists only because the user
/// picked it with "@" in the composer. An [AiAttachment] holds DECODED TEXT
/// only — never bytes, a presigned URL or a storage key (AI.md §7); the type
/// has no field that could carry one.
library;

import 'dart:convert';

import 'ai_context_builder.dart';

enum AiAttachmentKind { note, file, task, project }

/// What the user picked — enough to draw a chip and to load it.
class AiAttachmentRef {
  const AiAttachmentRef({
    required this.kind,
    required this.id,
    required this.title,
    this.mime,
  });

  final AiAttachmentKind kind;
  final String id;
  final String title;

  /// Files only: the chip's icon follows the type.
  final String? mime;

  @override
  bool operator ==(Object other) =>
      other is AiAttachmentRef && other.kind == kind && other.id == id;

  @override
  int get hashCode => Object.hash(kind, id);
}

enum AiAttachmentStatus { loading, ready, refused }

enum AiAttachmentRefusal { notText, tooLarge, unavailable, empty }

/// Characters of one item that are sent (~3K tokens).
const int kAiAttachItemChars = 12000;

/// Characters of all attachments of one conversation (~10K tokens).
const int kAiAttachTotalChars = 40000;

/// Attachments the composer holds for one message.
const int kAiAttachPerMessage = 5;

/// The largest file that is fetched to be read as text (1 MiB).
const int kAiAttachFileMaxBytes = 1048576;

class AiAttachment {
  const AiAttachment({
    required this.ref,
    required this.status,
    this.text,
    this.totalChars = 0,
    this.refusal,
  });

  const AiAttachment.loading(this.ref)
    : status = AiAttachmentStatus.loading,
      text = null,
      totalChars = 0,
      refusal = null;

  AiAttachment.ready(this.ref, String this.text)
    : status = AiAttachmentStatus.ready,
      totalChars = text.length,
      refusal = null;

  const AiAttachment.refused(this.ref, AiAttachmentRefusal this.refusal)
    : status = AiAttachmentStatus.refused,
      text = null,
      totalChars = 0;

  final AiAttachmentRef ref;
  final AiAttachmentStatus status;

  /// The full decoded text (snapshotted when picked); cut only when packed.
  final String? text;
  final int totalChars;
  final AiAttachmentRefusal? refusal;

  bool get isReady => status == AiAttachmentStatus.ready;
  bool get truncated => isReady && totalChars > kAiAttachItemChars;
  int get sentChars =>
      totalChars > kAiAttachItemChars ? kAiAttachItemChars : totalChars;
}

// ── text files ────────────────────────────────────────────────────────────

const _textMimes = {
  'application/json',
  'application/xml',
  'application/yaml',
  'application/x-yaml',
  'application/javascript',
  'application/x-sh',
  'application/sql',
  'application/csv',
  'application/x-ndjson',
  'application/ld+json',
};

const _textExtensions = {
  'txt', 'md', 'markdown', 'csv', 'tsv', 'json', 'ndjson', 'xml', 'yaml', //
  'yml', 'log', 'ini', 'toml', 'conf', 'cfg', 'html', 'htm', 'ics', 'vcf',
  'srt', 'vtt', 'sql', 'sh', 'js', 'ts', 'py', 'dart', 'rb', 'go', 'java',
  'kt', 'swift', 'c', 'h', 'cpp', 'css', 'scss', 'tex', 'rst', 'org', 'adoc',
};

/// Whether a file can be attached at all: text by its type or by a known
/// text extension. PDF, images, Office files, audio, video and archives are
/// not — there is no safe extraction path for them (ADR-0058).
bool aiFileIsTextLike(String name, String mime) {
  final type = mime.toLowerCase().split(';').first.trim();
  if (type.startsWith('text/')) return true;
  if (_textMimes.contains(type)) return true;
  final lower = name.toLowerCase();
  if (lower.endsWith('.env.example')) return true;
  final dot = lower.lastIndexOf('.');
  if (dot < 0 || dot == lower.length - 1) return false;
  return _textExtensions.contains(lower.substring(dot + 1));
}

/// A NUL byte in the first 8 KiB means the "text" file is really binary.
bool aiLooksBinary(List<int> bytes) {
  final end = bytes.length < 8192 ? bytes.length : 8192;
  for (var i = 0; i < end; i++) {
    if (bytes[i] == 0) return true;
  }
  return false;
}

/// UTF-8 with a BOM stripped; malformed sequences become U+FFFD, never throw.
String aiDecodeText(List<int> bytes) {
  var start = 0;
  if (bytes.length >= 3 &&
      bytes[0] == 0xEF &&
      bytes[1] == 0xBB &&
      bytes[2] == 0xBF) {
    start = 3;
  }
  return const Utf8Decoder(allowMalformed: true).convert(bytes.sublist(start));
}

// ── formatters (model-facing text, English labels) ───────────────────────

String aiNoteText(String title, String markdown) {
  final body = markdown.trim();
  return body.isEmpty ? '# $title' : '# $title\n\n$body';
}

String aiFileText(String name, String text) => 'File: $name\n\n${text.trim()}';

String aiTaskText({
  required String title,
  required String status,
  String priority = 'none',
  String? dueLabel,
  String? whenLabel,
  int? minutes,
  String? projectName,
  String? description,
  List<(String, bool)> checklist = const [],
}) {
  final lines = <String>[
    'Task: $title',
    'Status: $status',
    if (priority != 'none') 'Priority: $priority',
    if (projectName != null) 'Project: $projectName',
    if (whenLabel != null) 'When: $whenLabel',
    if (dueLabel != null) 'Due: $dueLabel',
    if (minutes != null) 'Duration: $minutes min',
  ];
  final body = description?.trim() ?? '';
  if (body.isNotEmpty) lines.add('\n$body');
  if (checklist.isNotEmpty) {
    lines.add('\nChecklist:');
    for (final (text, done) in checklist) {
      lines.add('- [${done ? 'x' : ' '}] $text');
    }
  }
  return lines.join('\n');
}

/// Open tasks a project attachment lists before "… and N more".
const int kAiAttachProjectTaskCap = 50;

String aiProjectText({
  required String name,
  String? description,
  List<(String, String?)> openTasks = const [],
}) {
  final lines = <String>['Project: $name'];
  final body = description?.trim() ?? '';
  if (body.isNotEmpty) lines.add('\n$body');
  lines.add('\nOpen tasks (${openTasks.length}):');
  for (final (title, due) in openTasks.take(kAiAttachProjectTaskCap)) {
    lines.add(due == null ? '- $title' : '- $title — due $due');
  }
  if (openTasks.length > kAiAttachProjectTaskCap) {
    lines.add('… and ${openTasks.length - kAiAttachProjectTaskCap} more');
  }
  return lines.join('\n');
}

/// The short local "2026-08-06 16:00" label the live context uses too.
String aiDueLabel(DateTime at) =>
    awIsoWithOffset(at.toLocal()).replaceFirst('T', ' ').substring(0, 16);

// ── the request builder ─────────────────────────────────────────────────

/// The model-facing notice appended to an item cut at [kAiAttachItemChars].
String aiTruncationNotice(int total) =>
    '\n[Truncated: the first $kAiAttachItemChars of $total characters '
    'were attached.]';

/// The packed attachments of one request.
class AiAttachedPack {
  const AiAttachedPack({
    required this.segments,
    required this.truncated,
    required this.dropped,
  });

  final List<AiContextSegment> segments;

  /// An item was cut or left out — the bundle says so to the model.
  final bool truncated;

  /// Items left out whole because the conversation cap was reached.
  final List<AiAttachmentRef> dropped;
}

/// Turns the conversation's attachments ([attachments] NEWEST FIRST) into
/// `tier: attached` segments: ready items only, each deduplicated by ref (the
/// newest wins), each cut to [kAiAttachItemChars] with a visible notice, and
/// whole items left out once the [kAiAttachTotalChars] cap would be passed.
AiAttachedPack packAttachedSegments(List<AiAttachment> attachments) {
  final segments = <AiContextSegment>[];
  final dropped = <AiAttachmentRef>[];
  final seen = <AiAttachmentRef>{};
  var total = 0;
  var truncated = false;
  for (final attachment in attachments) {
    if (!attachment.isReady || attachment.text == null) continue;
    if (!seen.add(attachment.ref)) continue;
    final full = attachment.text!;
    final cut = full.length > kAiAttachItemChars;
    final body = cut ? full.substring(0, kAiAttachItemChars) : full;
    if (total + body.length > kAiAttachTotalChars) {
      dropped.add(attachment.ref);
      truncated = true;
      continue;
    }
    total += body.length;
    if (cut) truncated = true;
    segments.add(
      AiContextSegment(
        tier: 'attached',
        source: 'attached_${attachment.ref.kind.name}',
        id: attachment.ref.id,
        text: cut ? '$body${aiTruncationNotice(full.length)}' : body,
      ),
    );
  }
  return AiAttachedPack(
    segments: segments,
    truncated: truncated,
    dropped: dropped,
  );
}
