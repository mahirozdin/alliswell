import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../sync/providers.dart';
import '../auth/providers.dart';
import 'data/file_attachment.dart';
import 'data/files_api.dart';
import 'data/pick_files.dart';
import 'data/picked_upload.dart';
import 'data/upload_controller.dart';

export 'data/file_attachment.dart' show FileAttachment, ProjectFileEntry;
export 'data/files_api.dart' show FilesApi, StorageStatus, FileDownload;
export 'data/picked_upload.dart' show PickedUpload;
export 'data/upload_controller.dart'
    show UploadJob, UploadPhase, UploadsNotifier, mimeForName;

/// Attachment metadata reads, from the replica (OPH-153). Pull-only by
/// construction — the store has no write path (ADR-0011).
final fileStoreProvider = Provider<FileStore>(
  (ref) => FileStore(ref.watch(databaseProvider)),
);

final filesApiProvider = Provider<FilesApi>(
  (ref) => FilesApi(ref.watch(apiClientProvider)),
);

/// Deployment state (is storage configured, limits) — REST, never replicated:
/// a stale "configured" would be a lie. Refreshed per session.
final storageStatusProvider = FutureProvider<StorageStatus>(
  (ref) => ref.watch(filesApiProvider).storageStatus(),
);

/// The platform file picker behind a seam (the urlLauncherProvider pattern) —
/// widget tests inject picked files without a platform channel.
final filePickerProvider = Provider<Future<List<PickedUpload>> Function()>(
  (_) => pickUploads,
);

/// The presigned PUT itself. A BARE dio on purpose: the URL carries its own
/// SigV4 authorization, and our Authorization header would make the store
/// reject the request (two auth mechanisms). Tests swap in a fake transport.
typedef UploadTransport =
    Future<void> Function({
      required String url,
      required Map<String, String> headers,
      required PickedUpload source,
      void Function(int sent, int total)? onProgress,
      CancelToken? cancelToken,
    });

final uploadTransportProvider = Provider<UploadTransport>((ref) {
  final dio = Dio();
  ref.onDispose(dio.close);
  return ({
    required url,
    required headers,
    required source,
    onProgress,
    cancelToken,
  }) async {
    await dio.put<void>(
      url,
      data: source.open(),
      options: Options(
        headers: {
          ...headers,
          // dio cannot size a stream; the store requires the exact length.
          Headers.contentLengthHeader: source.sizeBytes,
        },
      ),
      onSendProgress: onProgress,
      cancelToken: cancelToken,
    );
  };
});

/// Every in-flight/failed upload (all targets — screens filter).
final uploadsProvider = NotifierProvider<UploadsNotifier, List<UploadJob>>(
  UploadsNotifier.new,
);

/// One entity's attachments, live from the replica.
final targetFilesProvider =
    StreamProvider.family<
      List<FileAttachment>,
      ({String targetType, String targetId})
    >((ref, key) {
      ref.watch(syncEngineProvider); // keep background sync alive
      return ref
          .watch(fileStoreProvider)
          .watchForTarget(targetType: key.targetType, targetId: key.targetId);
    });

/// The project "Files" tab aggregate, live from the replica.
final projectFilesProvider =
    StreamProvider.family<List<ProjectFileEntry>, String>((ref, projectId) {
      ref.watch(syncEngineProvider);
      return ref.watch(fileStoreProvider).watchForProject(projectId);
    });

/// Short-lived download URLs, cached per file until shortly before expiry so
/// list thumbnails do not re-mint on every rebuild. Presigned URLs are never
/// persisted anywhere (ATTACHMENTS.md §9).
class FileUrlCache {
  FileUrlCache(this._api);

  final FilesApi _api;
  final _cache = <String, FileDownload>{};

  Future<String?> urlFor(String fileId) async {
    final hit = _cache[fileId];
    if (hit != null &&
        (hit.expiresAt == null ||
            hit.expiresAt!.isAfter(
              DateTime.now().add(const Duration(minutes: 1)),
            ))) {
      return hit.url;
    }
    final fresh = await _api.download(fileId);
    if (fresh == null) return null;
    _cache[fileId] = fresh;
    return fresh.url;
  }

  void evict(String fileId) => _cache.remove(fileId);
}

final fileUrlCacheProvider = Provider<FileUrlCache>(
  (ref) => FileUrlCache(ref.watch(filesApiProvider)),
);
