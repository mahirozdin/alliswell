import 'dart:async';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:alliswell/src/core/api_exception.dart';
import 'package:alliswell/src/features/files/data/files_api.dart';
import 'package:alliswell/src/features/files/providers.dart';
import 'package:alliswell/src/sync/providers.dart';

// OPH-153 — the upload state machine, platform-channel-free: fake API + fake
// transport drive init → PUT(progress) → complete, failure/retry, cancel.

const ws = 'W1000000000000000000000000';

class FakeFilesApi extends FilesApi {
  FakeFilesApi() : super(Dio());

  int _seq = 0;
  ApiException? failInitWith;
  final completed = <String>[];
  final deleted = <String>[];
  final initNames = <String>[];

  @override
  Future<UploadTicket> initUpload({
    required String workspaceId,
    required String targetType,
    required String targetId,
    required String name,
    required int sizeBytes,
    String? mime,
    String? folderId,
  }) async {
    final failure = failInitWith;
    if (failure != null) throw failure;
    _seq += 1;
    initNames.add(name);
    final id = 'F$_seq'.padRight(26, '0');
    return UploadTicket(
      fileId: id,
      url: 'https://store/put/$id',
      headers: {'content-type': mime ?? 'application/octet-stream'},
    );
  }

  @override
  Future<void> complete(String fileId) async => completed.add(fileId);

  @override
  Future<void> delete(String fileId) async => deleted.add(fileId);
}

enum TransportMode { succeed, fail, hangUntilCanceled }

class FakeTransport {
  TransportMode mode = TransportMode.succeed;
  final calls = <({String url, Map<String, String> headers})>[];
  Completer<void>? started;

  Future<void> call({
    required String url,
    required Map<String, String> headers,
    required PickedUpload source,
    void Function(int sent, int total)? onProgress,
    CancelToken? cancelToken,
  }) async {
    calls.add((url: url, headers: headers));
    started?.complete();
    switch (mode) {
      case TransportMode.succeed:
        onProgress?.call(source.sizeBytes ~/ 2, source.sizeBytes);
        onProgress?.call(source.sizeBytes, source.sizeBytes);
        await source.open().drain<void>(); // exercise the re-openable stream
      case TransportMode.fail:
        throw DioException(
          requestOptions: RequestOptions(path: url),
          type: DioExceptionType.connectionError,
        );
      case TransportMode.hangUntilCanceled:
        await cancelToken!.whenCancel;
        throw DioException.requestCancelled(
          requestOptions: RequestOptions(path: url),
          reason: 'user-canceled',
        );
    }
  }
}

PickedUpload picked(String name, [int size = 10]) => PickedUpload.fromBytes(
  name: name,
  bytes: Uint8List.fromList(List.filled(size, 7)),
);

void main() {
  late FakeFilesApi api;
  late FakeTransport transport;
  late ProviderContainer container;

  ProviderContainer build({List<PickedUpload> picks = const []}) =>
      ProviderContainer(
        overrides: [
          filesApiProvider.overrideWithValue(api),
          uploadTransportProvider.overrideWithValue(transport.call),
          filePickerProvider.overrideWithValue(() async => picks),
          syncEngineProvider.overrideWith((ref) => null),
        ],
      );

  setUp(() {
    api = FakeFilesApi();
    transport = FakeTransport();
  });

  tearDown(() => container.dispose());

  test(
    'happy path: every picked file inits, PUTs with progress, completes',
    () async {
      container = build(picks: [picked('a.png'), picked('b.mp4')]);
      final snapshots = <List<UploadJob>>[];
      container.listen(uploadsProvider, (_, next) => snapshots.add(next));

      await container
          .read(uploadsProvider.notifier)
          .pickAndUpload(workspaceId: ws, targetType: 'task', targetId: 'T1');

      expect(container.read(uploadsProvider), isEmpty); // done jobs vanish
      expect(api.initNames, ['a.png', 'b.mp4']);
      expect(api.completed, hasLength(2));
      expect(transport.calls, hasLength(2));
      // The signed content type traveled to the PUT…
      expect(transport.calls.first.headers['content-type'], 'image/png');
      // …and progress was visible along the way (0.5 snapshot observed).
      expect(
        snapshots.any((s) => s.any((j) => j.progress == 0.5)),
        isTrue,
        reason: 'onSendProgress must surface as job progress',
      );
      expect(api.deleted, isEmpty);
    },
  );

  test(
    'init failure marks the job failed with the API code; retry succeeds',
    () async {
      container = build();
      api.failInitWith = const ApiException(
        'STORAGE_NOT_CONFIGURED',
        'storage off',
      );
      final notifier = container.read(uploadsProvider.notifier);

      await notifier.start(
        workspaceId: ws,
        targetType: 'project',
        targetId: 'P1',
        source: picked('rapor.pdf'),
      );
      final failed = container.read(uploadsProvider).single;
      expect(failed.phase, UploadPhase.failed);
      expect(failed.errorCode, 'STORAGE_NOT_CONFIGURED');

      api.failInitWith = null;
      await notifier.retry(failed.localId);
      expect(container.read(uploadsProvider), isEmpty);
      expect(api.completed, hasLength(1));
    },
  );

  test('a failed PUT is retryable and dismissable', () async {
    container = build();
    transport.mode = TransportMode.fail;
    final notifier = container.read(uploadsProvider.notifier);

    await notifier.start(
      workspaceId: ws,
      targetType: 'note',
      targetId: 'N1',
      source: picked('video.mov'),
    );
    final failed = container.read(uploadsProvider).single;
    expect(failed.phase, UploadPhase.failed);
    expect(failed.errorCode, 'UPLOAD_PUT_FAILED');
    expect(api.completed, isEmpty);

    notifier.dismiss(failed.localId);
    expect(container.read(uploadsProvider), isEmpty);
  });

  test('cancel aborts the PUT, drops the job and tells the server', () async {
    container = build();
    transport.mode = TransportMode.hangUntilCanceled;
    transport.started = Completer<void>();
    final notifier = container.read(uploadsProvider.notifier);

    final settled = notifier.start(
      workspaceId: ws,
      targetType: 'task',
      targetId: 'T1',
      source: picked('big.zip'),
    );
    await transport.started!.future; // the PUT is genuinely in flight
    notifier.cancel(container.read(uploadsProvider).single.localId);
    expect(await settled, isNull);

    expect(container.read(uploadsProvider), isEmpty);
    expect(api.completed, isEmpty);
    expect(api.deleted, ['F1'.padRight(26, '0')]); // abort reached the API
  });

  test('mimeForName covers previews and falls back honestly', () {
    expect(mimeForName('Özet.JPG'), 'image/jpeg');
    expect(mimeForName('clip.mov'), 'video/quicktime');
    expect(mimeForName('archive.tar.gz'), 'application/gzip');
    expect(mimeForName('unknown.xyz'), 'application/octet-stream');
    expect(mimeForName('no-extension'), 'application/octet-stream');
  });
}
