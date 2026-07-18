import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api_exception.dart';
import '../../../core/ulid.dart';
import '../../../sync/providers.dart';
import '../providers.dart';

/// Visible, honest upload state (OPH-153, DESIGN §10 F2): uploads are explicit
/// foreground work — progress is shown, cancel works, failure offers retry.
/// There is deliberately NO background queue pretense: an upload needs the
/// network NOW or it fails now (ADR-0011).
enum UploadPhase { running, failed }

class UploadJob {
  const UploadJob({
    required this.localId,
    required this.workspaceId,
    required this.targetType,
    required this.targetId,
    required this.name,
    required this.sizeBytes,
    this.progress = 0,
    this.phase = UploadPhase.running,
    this.errorCode,
  });

  final String localId;
  final String workspaceId;
  final String targetType;
  final String targetId;
  final String name;
  final int sizeBytes;

  /// 0..1 — bytes sent over bytes total.
  final double progress;
  final UploadPhase phase;

  /// Stable API error code when [phase] is failed (`error.<CODE>` i18n).
  final String? errorCode;

  UploadJob copyWith({
    double? progress,
    UploadPhase? phase,
    String? errorCode,
  }) => UploadJob(
    localId: localId,
    workspaceId: workspaceId,
    targetType: targetType,
    targetId: targetId,
    name: name,
    sizeBytes: sizeBytes,
    progress: progress ?? this.progress,
    phase: phase ?? this.phase,
    errorCode: errorCode ?? this.errorCode,
  );
}

/// Every in-flight/failed upload, all targets — screens filter by target.
/// Completed uploads vanish from here; the synced replica row takes over.
class UploadsNotifier extends Notifier<List<UploadJob>> {
  final _sources = <String, PickedUpload>{};
  final _cancels = <String, CancelToken>{};
  final _fileIds = <String, String>{};

  @override
  List<UploadJob> build() => const [];

  /// Opens the picker and starts one job per picked file.
  Future<void> pickAndUpload({
    required String workspaceId,
    required String targetType,
    required String targetId,
  }) async {
    final picked = await ref.read(filePickerProvider)();
    for (final source in picked) {
      await start(
        workspaceId: workspaceId,
        targetType: targetType,
        targetId: targetId,
        source: source,
      );
    }
  }

  /// Starts one upload; resolves when it settles (done, failed or canceled).
  /// Exposed separately so the note editor can upload a picked file and then
  /// insert the embed itself (OPH-156).
  Future<String?> start({
    required String workspaceId,
    required String targetType,
    required String targetId,
    required PickedUpload source,
  }) {
    final job = UploadJob(
      localId: newUlid(),
      workspaceId: workspaceId,
      targetType: targetType,
      targetId: targetId,
      name: source.name,
      sizeBytes: source.sizeBytes,
    );
    _sources[job.localId] = source;
    state = [...state, job];
    return _run(job.localId);
  }

  /// Re-runs a failed job from scratch (fresh init — the old presigned URL
  /// may have expired; the server reaps the abandoned attempt).
  Future<String?> retry(String localId) {
    _patch(localId, (j) => j.copyWith(phase: UploadPhase.running, progress: 0));
    return _run(localId);
  }

  void cancel(String localId) {
    _cancels[localId]?.cancel('user-canceled');
  }

  /// Removes a FAILED job the user chose not to retry.
  void dismiss(String localId) => _remove(localId);

  Future<String?> _run(String localId) async {
    final job = state.firstWhere((j) => j.localId == localId);
    final source = _sources[localId]!;
    final api = ref.read(filesApiProvider);
    final cancelToken = CancelToken();
    _cancels[localId] = cancelToken;

    String? fileId;
    try {
      final ticket = await api.initUpload(
        workspaceId: job.workspaceId,
        targetType: job.targetType,
        targetId: job.targetId,
        name: job.name,
        sizeBytes: job.sizeBytes,
        mime: source.mime ?? mimeForName(job.name),
      );
      fileId = ticket.fileId;
      _fileIds[localId] = ticket.fileId;

      await ref.read(uploadTransportProvider)(
        url: ticket.url,
        headers: ticket.headers,
        source: source,
        cancelToken: cancelToken,
        onProgress: (sent, total) {
          final divisor = total > 0 ? total : job.sizeBytes;
          _patch(
            localId,
            (j) => j.copyWith(
              progress: divisor > 0 ? (sent / divisor).clamp(0.0, 1.0) : 0,
            ),
          );
        },
      );

      await api.complete(ticket.fileId);
      await ref.read(syncEngineProvider)?.syncNow();
      _remove(localId);
      return ticket.fileId;
    } on ApiException catch (e) {
      _patch(
        localId,
        (j) => j.copyWith(phase: UploadPhase.failed, errorCode: e.code),
      );
      return null;
    } on DioException catch (e) {
      if (CancelToken.isCancel(e)) {
        // The user aborted: drop the job and tell the server to clean up.
        _remove(localId);
        if (fileId != null) {
          try {
            await api.delete(fileId);
          } on ApiException {
            // Best effort — the server sweep reaps abandoned attempts anyway.
          }
        }
        return null;
      }
      // The direct-to-storage PUT failed (network, CORS on web, expiry…).
      _patch(
        localId,
        (j) => j.copyWith(
          phase: UploadPhase.failed,
          errorCode: 'UPLOAD_PUT_FAILED',
        ),
      );
      return null;
    } finally {
      _cancels.remove(localId);
    }
  }

  void _patch(String localId, UploadJob Function(UploadJob) fn) {
    state = [
      for (final j in state)
        if (j.localId == localId) fn(j) else j,
    ];
  }

  void _remove(String localId) {
    _sources.remove(localId);
    _fileIds.remove(localId);
    state = state.where((j) => j.localId != localId).toList();
  }
}

/// Extension → MIME for the picker's gaps, so images/videos get previews and
/// downloads carry a sensible type. Unknowns stay octet-stream (any file type
/// is allowed — ATTACHMENTS.md §3).
String mimeForName(String name) {
  final dot = name.lastIndexOf('.');
  final ext = dot < 0 ? '' : name.substring(dot + 1).toLowerCase();
  return _mimeByExt[ext] ?? 'application/octet-stream';
}

const _mimeByExt = <String, String>{
  'jpg': 'image/jpeg',
  'jpeg': 'image/jpeg',
  'png': 'image/png',
  'gif': 'image/gif',
  'webp': 'image/webp',
  'heic': 'image/heic',
  'heif': 'image/heif',
  'svg': 'image/svg+xml',
  'bmp': 'image/bmp',
  'mp4': 'video/mp4',
  'mov': 'video/quicktime',
  'm4v': 'video/x-m4v',
  'webm': 'video/webm',
  'mkv': 'video/x-matroska',
  'avi': 'video/x-msvideo',
  'mp3': 'audio/mpeg',
  'm4a': 'audio/mp4',
  'wav': 'audio/wav',
  'ogg': 'audio/ogg',
  'flac': 'audio/flac',
  'pdf': 'application/pdf',
  'zip': 'application/zip',
  'gz': 'application/gzip',
  'txt': 'text/plain',
  'md': 'text/markdown',
  'csv': 'text/csv',
  'json': 'application/json',
  'doc': 'application/msword',
  'docx':
      'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
  'xls': 'application/vnd.ms-excel',
  'xlsx': 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
  'ppt': 'application/vnd.ms-powerpoint',
  'pptx':
      'application/vnd.openxmlformats-officedocument.presentationml.presentation',
};
