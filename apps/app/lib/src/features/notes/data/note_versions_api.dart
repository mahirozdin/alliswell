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
  });

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
      );
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

  Future<List<NoteDiffSegment>> diff(String noteId, String versionId) =>
      _run(() async {
        final res = await _dio.get<Map<String, dynamic>>(
          '/api/v1/notes/$noteId/versions/$versionId/diff',
        );
        final segments = (res.data?['segments'] as List?) ?? const [];
        return segments
            .map((s) => NoteDiffSegment.fromJson(s as Map<String, dynamic>))
            .toList();
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
