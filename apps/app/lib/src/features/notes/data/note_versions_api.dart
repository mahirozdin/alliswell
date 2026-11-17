import 'package:dio/dio.dart';

import '../../../core/api_exception.dart';

/// Note history over REST (OPH-269, ADR-0031 §1 / DESIGN §35 V6).
///
/// An ONLINE surface, on purpose: historical bodies live on the server and are
/// never replicated. Offline the screen says so rather than showing a list it
/// cannot open.

/// One row of the history list — metadata only, never a body.
class NoteVersionSummary {
  const NoteVersionSummary({
    required this.id,
    required this.origin,
    required this.createdAt,
    required this.sizeBytes,
    this.clientId,
    this.title = '',
    this.contentFormat = 'markdown',
    DateTime? updatedAt,
    this.deviceName,
    this.devicePlatform,
  }) : updatedAt = updatedAt ?? createdAt;

  final String id;

  /// create · edit · merge · restore · conflict · import · api · mcp
  final String origin;
  final DateTime createdAt;
  final int sizeBytes;

  /// Which device wrote it — compared with our own client id to say
  /// "This device" instead of a meaningless ULID (DESIGN §35 V4).
  final String? clientId;
  final String title;
  final String contentFormat;

  /// When this body was last written (OPH-494). A same-device session rolls
  /// into one version, which keeps the session's start as [createdAt]; an
  /// older server sends no `updatedAt`, and then it is [createdAt].
  final DateTime updatedAt;

  /// The writing device from the person's own device registry, joined by the
  /// server on [clientId] (OPH-494). Null when it is not a registered device
  /// of theirs, or the server predates the field.
  final String? deviceName;
  final String? devicePlatform;

  factory NoteVersionSummary.fromJson(Map<String, dynamic> json) =>
      NoteVersionSummary(
        id: json['id'] as String,
        origin: json['origin'] as String? ?? 'edit',
        createdAt:
            DateTime.tryParse(json['createdAt'] as String? ?? '')?.toLocal() ??
            DateTime.now(),
        sizeBytes: (json['sizeBytes'] as num?)?.toInt() ?? 0,
        clientId: json['clientId'] as String?,
        title: json['title'] as String? ?? '',
        contentFormat: json['contentFormat'] as String? ?? 'markdown',
        updatedAt: DateTime.tryParse(
          json['updatedAt'] as String? ?? '',
        )?.toLocal(),
        deviceName: json['deviceName'] as String?,
        devicePlatform: json['devicePlatform'] as String?,
      );
}

/// The other side of a diff — the note as it is now (OPH-494): when it was
/// last written, and by which device.
class NoteDiffSide {
  const NoteDiffSide({
    required this.updatedAt,
    this.origin,
    this.clientId,
    this.deviceName,
    this.devicePlatform,
  });

  final DateTime updatedAt;
  final String? origin;
  final String? clientId;
  final String? deviceName;
  final String? devicePlatform;

  static NoteDiffSide? fromJson(Object? json) {
    if (json is! Map<String, dynamic>) return null;
    final at = DateTime.tryParse(json['updatedAt'] as String? ?? '');
    if (at == null) return null;
    return NoteDiffSide(
      updatedAt: at.toLocal(),
      origin: json['origin'] as String?,
      clientId: json['clientId'] as String?,
      deviceName: json['deviceName'] as String?,
      devicePlatform: json['devicePlatform'] as String?,
    );
  }
}

/// What `…/diff` answers: the segments, and who the current side is.
class NoteDiff {
  const NoteDiff({required this.segments, this.current});

  final List<NoteDiffSegment> segments;

  /// Null from a server that predates OPH-494.
  final NoteDiffSide? current;
}

class NoteVersionDetail {
  const NoteVersionDetail({required this.summary, required this.markdown});

  final NoteVersionSummary summary;

  /// What this version's body reads as. A delta-canonical version is rendered
  /// from its markdown twin; the preview is a READ, not an edit surface.
  final String markdown;

  factory NoteVersionDetail.fromJson(Map<String, dynamic> json) =>
      NoteVersionDetail(
        summary: NoteVersionSummary.fromJson(json),
        markdown: json['contentMarkdown'] as String? ?? '',
      );
}

/// One run of the server's word diff. The client only draws these (ADR-0031 §8).
class NoteDiffSegment {
  const NoteDiffSegment({required this.type, required this.value});

  /// equal · added · removed
  final String type;
  final String value;

  factory NoteDiffSegment.fromJson(Map<String, dynamic> json) =>
      NoteDiffSegment(
        type: json['type'] as String? ?? 'equal',
        value: json['value'] as String? ?? '',
      );
}

class NoteVersionsApi {
  const NoteVersionsApi(this._dio);
  final Dio _dio;

  Future<List<NoteVersionSummary>> list(String noteId) => _run(() async {
    final res = await _dio.get<Map<String, dynamic>>(
      '/api/v1/notes/$noteId/versions',
    );
    final items = (res.data?['items'] as List?) ?? const [];
    return items
        .map((v) => NoteVersionSummary.fromJson(v as Map<String, dynamic>))
        .toList();
  });

  Future<NoteVersionDetail> detail(String noteId, String versionId) =>
      _run(() async {
        final res = await _dio.get<Map<String, dynamic>>(
          '/api/v1/notes/$noteId/versions/$versionId',
        );
        return NoteVersionDetail.fromJson(res.data ?? const {});
      });

  Future<NoteDiff> diff(String noteId, String versionId) => _run(() async {
    final res = await _dio.get<Map<String, dynamic>>(
      '/api/v1/notes/$noteId/versions/$versionId/diff',
    );
    final segments = (res.data?['segments'] as List?) ?? const [];
    return NoteDiff(
      segments: segments
          .map((s) => NoteDiffSegment.fromJson(s as Map<String, dynamic>))
          .toList(),
      current: NoteDiffSide.fromJson(res.data?['current']),
    );
  });

  /// `replace` writes the old body as a NEW head (history is never rewritten,
  /// DESIGN §35 V5); `copy` births a separate note.
  Future<Map<String, dynamic>> restore(
    String noteId,
    String versionId, {
    required String mode,
  }) => _run(() async {
    final res = await _dio.post<Map<String, dynamic>>(
      '/api/v1/notes/$noteId/versions/$versionId/restore',
      data: {'mode': mode},
    );
    return res.data ?? const {};
  });

  Future<T> _run<T>(Future<T> Function() call) async {
    try {
      return await call();
    } on DioException catch (e) {
      throw asApiException(e);
    }
  }
}
