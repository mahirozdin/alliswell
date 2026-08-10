import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api_exception.dart';
import '../../sync/providers.dart';
import '../auth/providers.dart';
import '../workspaces/workspaces.dart';
import 'data/attach_source.dart';
import 'data/file_attachment.dart';
import 'data/folder_store.dart';
import 'data/files_api.dart';
import 'data/pick_files.dart';
import 'data/picked_upload.dart';
import 'data/upload_controller.dart';

export 'data/attach_source.dart';
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

/// Runs one named way of picking (OPH-244). Required positional argument, not
/// an optional one: the bug this replaced was a call that forgot to say what it
/// wanted, and a default would let that happen again.
typedef FilePickerFn = Future<List<PickedUpload>> Function(AttachSource source);

/// The platform file picker behind a seam (the urlLauncherProvider pattern) —
/// widget tests inject picked files without a platform channel.
final filePickerProvider = Provider<FilePickerFn>((_) => pickUploads);

/// Which named ways this build offers (DESIGN §30 A1). A provider rather than a
/// bare call so a widget test can choose a platform instead of inheriting the
/// host's — `flutter_test` forces `defaultTargetPlatform` to android.
final attachSourcesProvider = Provider<List<AttachSource>>(
  (_) => attachMenuSources(isWeb: kIsWeb, platform: defaultTargetPlatform),
);

/// How a minted URL becomes pixels, behind a seam (the [filePickerProvider]
/// pattern). Not a nicety: `flutter_test`'s HTTP mock answers EVERY request
/// with zero bytes, so before this seam no test in the repo could assert on a
/// rendered image — only on the failure path (OPH-245). Tests inject a
/// [MemoryImage]; production stays [NetworkImage].
typedef AwImageProviderFn = ImageProvider Function(String url);

final networkImageProvider = Provider<AwImageProviderFn>(
  (_) => NetworkImage.new,
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
///
/// Memoizes the FUTURE, not just the value: widgets may call this from build,
/// and handing back a fresh future per build would never let the tree settle.
/// A null answer (offline, not ready) is cached briefly too — the honest
/// placeholder must be stable, not a retry storm.
class FileUrlCache {
  FileUrlCache(this._api);

  final FilesApi _api;
  final _futures = <String, Future<String?>>{};
  final _validUntil = <String, DateTime>{};
  final _lastError = <String, String>{};

  Future<String?> urlFor(String fileId) {
    final cached = _futures[fileId];
    final until = _validUntil[fileId];
    if (cached != null && (until == null || until.isAfter(DateTime.now()))) {
      return cached;
    }
    final future = () async {
      try {
        final fresh = await _api.download(fileId);
        _lastError.remove(fileId);
        if (fresh != null) {
          // Renew a minute before the store would refuse the URL.
          _validUntil[fileId] =
              (fresh.expiresAt ??
                      DateTime.now().add(const Duration(minutes: 55)))
                  .subtract(const Duration(minutes: 1));
          return fresh.url;
        }
      } on ApiException catch (e) {
        // Unreachable/denied: fall through to the placeholder answer, but KEEP
        // the code. Until OPH-245 this catch threw the reason away, which is
        // why DESIGN §30 A8 ("failure states a reason") could not be built —
        // "offline" and "the file is gone" arrived here as the same null.
        _lastError[fileId] = e.code;
      }
      _validUntil[fileId] = DateTime.now().add(const Duration(minutes: 2));
      return null;
    }();
    _futures[fileId] = future;
    return future;
  }

  /// Why the most recent mint for [fileId] produced no URL, or null when it
  /// did not fail (a null URL with no code means the server answered and the
  /// file simply is not downloadable yet).
  String? errorCodeFor(String fileId) => _lastError[fileId];

  void evict(String fileId) {
    _futures.remove(fileId);
    _validUntil.remove(fileId);
    _lastError.remove(fileId);
  }
}

final fileUrlCacheProvider = Provider<FileUrlCache>(
  (ref) => FileUrlCache(ref.watch(filesApiProvider)),
);

/// Build-safe wrappers for per-file lookups: riverpod caches the future per
/// id, so widgets `watch` these instead of minting futures inside build.
final fileUrlProvider = FutureProvider.autoDispose.family<String?, String>(
  (ref, fileId) => ref.watch(fileUrlCacheProvider).urlFor(fileId),
);

/// The URL *and*, when there is none, why — DESIGN §30 A8. Only the viewer
/// needs the reason; rows and embeds keep using [fileUrlProvider] and fall
/// back to their placeholder tile. Both read the same memoized future, so a
/// file is still minted exactly once.
typedef FileUrlResult = ({String? url, String? errorCode});

final fileUrlResultProvider = FutureProvider.autoDispose
    .family<FileUrlResult, String>((ref, fileId) async {
      final cache = ref.watch(fileUrlCacheProvider);
      final url = await cache.urlFor(fileId);
      return (url: url, errorCode: cache.errorCodeFor(fileId));
    });

final fileByIdProvider = FutureProvider.autoDispose
    .family<FileAttachment?, String>(
      (ref, fileId) => ref.watch(fileStoreProvider).byId(fileId),
    );

/// Workspace storage footprint for the Files-tab footer (OPH-157) — REST,
/// fetched per mount (autoDispose): usage is server truth, not replica data.
final workspaceFilesUsageProvider =
    FutureProvider.autoDispose<({int totalBytes, int fileCount})?>((ref) async {
      final workspace = ref.watch(currentWorkspaceProvider).value;
      if (workspace == null) return null;
      return ref.watch(filesApiProvider).usage(workspace.id);
    });

/// OPH-170 — the Dosyalar section's local-first folder machinery (ADR-0014).
final folderStoreProvider = Provider<FolderStore>(
  (ref) => FolderStore(
    ref.watch(databaseProvider),
    onMutation: () => ref.read(syncEngineProvider)?.notifyLocalWrite(),
  ),
);

/// The workspace's whole live folder tree, name-ordered.
final foldersProvider = StreamProvider<List<Folder>>((ref) async* {
  ref.watch(syncEngineProvider);
  final workspaces = await ref.watch(workspacesProvider.future);
  if (workspaces.isEmpty) {
    yield const [];
    return;
  }
  yield* ref.read(folderStoreProvider).watchAll(workspaces.first.id);
});

/// One folder level of workspace files (null = root).
final workspaceLevelFilesProvider = StreamProvider.autoDispose
    .family<List<FileAttachment>, String?>((ref, folderId) async* {
      ref.watch(syncEngineProvider);
      final workspaces = await ref.watch(workspacesProvider.future);
      if (workspaces.isEmpty) {
        yield const [];
        return;
      }
      yield* ref
          .read(fileStoreProvider)
          .watchWorkspaceLevel(workspaces.first.id, folderId: folderId);
    });

/// Every attached file in the workspace, source-labeled (Kaynaklar).
final workspaceAttachedFilesProvider =
    StreamProvider.autoDispose<List<ProjectFileEntry>>((ref) async* {
      ref.watch(syncEngineProvider);
      final workspaces = await ref.watch(workspacesProvider.future);
      if (workspaces.isEmpty) {
        yield const [];
        return;
      }
      yield* ref
          .read(fileStoreProvider)
          .watchWorkspaceAttached(workspaces.first.id);
    });
