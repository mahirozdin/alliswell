/// A meeting, client side (EE-113/114/115).
///
/// The list and the detail are DIFFERENT types on purpose. The list carries
/// counts; the detail carries the transcript, and an hour of one is 228 KiB.
/// A single nullable `transcript` field on one type would invite a list screen
/// to read it and a server to start sending it — two types cannot be confused.
class EeMeetingSummary {
  const EeMeetingSummary({
    required this.id,
    required this.workspaceId,
    required this.status,
    required this.attempts,
    required this.decisionCount,
    required this.ideaCount,
    required this.createdAt,
    this.title,
    this.summary,
    this.noteId,
    this.provider,
    this.durationMs,
    this.failureCode,
    this.failureMessage,
  });

  factory EeMeetingSummary.fromJson(Map<String, dynamic> json) =>
      EeMeetingSummary(
        id: json['id'] as String,
        workspaceId: json['workspaceId'] as String,
        status: EeMeetingStatus.parse(json['status'] as String?),
        attempts: (json['attempts'] as num?)?.toInt() ?? 0,
        decisionCount: (json['decisionCount'] as num?)?.toInt() ?? 0,
        ideaCount: (json['ideaCount'] as num?)?.toInt() ?? 0,
        createdAt: DateTime.parse(json['createdAt'] as String).toLocal(),
        title: json['title'] as String?,
        summary: json['summary'] as String?,
        noteId: json['noteId'] as String?,
        provider: json['provider'] as String?,
        durationMs: (json['durationMs'] as num?)?.toInt(),
        failureCode: json['failureCode'] as String?,
        failureMessage: json['failureMessage'] as String?,
      );

  final String id;
  final String workspaceId;
  final EeMeetingStatus status;
  final int attempts;
  final int decisionCount;
  final int ideaCount;
  final DateTime createdAt;
  final String? title;
  final String? summary;
  final String? noteId;
  final String? provider;
  final int? durationMs;
  final String? failureCode;
  final String? failureMessage;
}

/// The pipeline's state machine, as the server spells it.
///
/// `transcribed` is a WAITING state, not a finished one: the words are safe
/// and the note has not been written yet (the summariser was unavailable).
/// A screen that showed it as done would be telling somebody their meeting is
/// ready when half of it is missing.
enum EeMeetingStatus {
  awaitingUpload,
  queued,
  transcribing,
  transcribed,
  summarizing,
  ready,
  failed;

  static EeMeetingStatus parse(String? raw) => switch (raw) {
    'queued' => EeMeetingStatus.queued,
    'transcribing' => EeMeetingStatus.transcribing,
    'transcribed' => EeMeetingStatus.transcribed,
    'summarizing' => EeMeetingStatus.summarizing,
    'ready' => EeMeetingStatus.ready,
    'failed' => EeMeetingStatus.failed,
    _ => EeMeetingStatus.awaitingUpload,
  };

  /// Still moving. Everything else is a resting place, one of them unhappy.
  bool get isWorking =>
      this == EeMeetingStatus.queued ||
      this == EeMeetingStatus.transcribing ||
      this == EeMeetingStatus.summarizing;
}

class EeTranscriptSegment {
  const EeTranscriptSegment({
    required this.speaker,
    required this.startMs,
    required this.endMs,
    required this.text,
  });

  factory EeTranscriptSegment.fromJson(Map<String, dynamic> json) =>
      EeTranscriptSegment(
        speaker: json['speaker'] as String,
        startMs: (json['startMs'] as num).toInt(),
        endMs: (json['endMs'] as num).toInt(),
        text: json['text'] as String,
      );

  /// The VENDOR's label ("A", "Speaker 1"), never a person's name. The name a
  /// human gave it lives in [EeMeetingDetail.speakerNames], keyed by this —
  /// which is what makes a rename reach 1 800 lines without rewriting one.
  final String speaker;
  final int startMs;
  final int endMs;
  final String text;
}

class EeTranscript {
  const EeTranscript({
    required this.segments,
    required this.speakers,
    this.durationMs,
    this.language,
  });

  factory EeTranscript.fromJson(Map<String, dynamic> json) => EeTranscript(
    segments: ((json['segments'] as List<dynamic>?) ?? const [])
        .map((e) => EeTranscriptSegment.fromJson(e as Map<String, dynamic>))
        .toList(growable: false),
    speakers: ((json['speakers'] as List<dynamic>?) ?? const [])
        .map((e) => e as String)
        .toList(growable: false),
    durationMs: (json['durationMs'] as num?)?.toInt(),
    language: json['language'] as String?,
  );

  final List<EeTranscriptSegment> segments;
  final List<String> speakers;
  final int? durationMs;
  final String? language;
}

class EeMeetingDecision {
  const EeMeetingDecision({required this.text, this.owner});

  factory EeMeetingDecision.fromJson(Map<String, dynamic> json) =>
      EeMeetingDecision(
        text: json['text'] as String,
        owner: json['owner'] as String?,
      );

  final String text;

  /// The transcript's own word for who owes it — a speaker LABEL, not a user.
  final String? owner;
}

class EeMeetingDetail {
  const EeMeetingDetail({
    required this.summary,
    required this.decisions,
    required this.ideas,
    required this.speakerNames,
    this.transcript,
  });

  factory EeMeetingDetail.fromJson(Map<String, dynamic> json) =>
      EeMeetingDetail(
        summary: EeMeetingSummary.fromJson(json),
        decisions: ((json['decisions'] as List<dynamic>?) ?? const [])
            .map((e) => EeMeetingDecision.fromJson(e as Map<String, dynamic>))
            .toList(growable: false),
        ideas: ((json['ideas'] as List<dynamic>?) ?? const [])
            .map((e) => (e as Map<String, dynamic>)['text'] as String)
            .toList(growable: false),
        speakerNames:
            ((json['speakerNames'] as Map<String, dynamic>?) ?? const {}).map(
              (k, v) => MapEntry(k, v as String),
            ),
        transcript: json['transcript'] == null
            ? null
            : EeTranscript.fromJson(json['transcript'] as Map<String, dynamic>),
      );

  final EeMeetingSummary summary;
  final List<EeMeetingDecision> decisions;
  final List<String> ideas;

  /// Vendor label → the name a human gave it. Empty until somebody says.
  final Map<String, String> speakerNames;
  final EeTranscript? transcript;

  /// What to CALL a speaker: the human name if there is one, otherwise the
  /// vendor's label. One function, so a rename reaches every place at once.
  String displayName(String label) => speakerNames[label] ?? label;
}
