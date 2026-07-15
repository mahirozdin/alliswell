import 'package:socket_io_client/socket_io_client.dart' as io;

/// Something that holds a live socket and can be torn down. The default
/// implementation wraps socket_io_client; widget tests override the factory
/// (no sockets, no reconnect timers).
abstract class SyncSocketHandle {
  void close();
}

typedef SyncSocketFactory =
    SyncSocketHandle Function({
      required String baseUrl,
      required String token,
      required void Function(Object? payload) onSyncChanged,
    });

/// Parses one `sync:changed {workspaceId, toRevision}` payload and decides
/// whether it concerns [workspaceId] — pure, so the trigger logic is testable
/// without a socket (OPH-057).
bool syncChangedMatches(Object? payload, String workspaceId) {
  if (payload is! Map) return false;
  return payload['workspaceId'] == workspaceId && payload['toRevision'] is int;
}

class _IoSocketHandle implements SyncSocketHandle {
  _IoSocketHandle(this._socket);

  final io.Socket _socket;

  @override
  void close() => _socket.dispose();
}

/// Production factory: websocket transport, socket.io's built-in reconnect
/// backoff, token in the connect handshake. `forceNew` because the manager
/// caches by URI — a rebuilt provider (fresh access token) must not reuse the
/// old handshake.
SyncSocketHandle defaultSyncSocketFactory({
  required String baseUrl,
  required String token,
  required void Function(Object? payload) onSyncChanged,
}) {
  final socket = io.io(
    baseUrl,
    io.OptionBuilder()
        .setTransports(['websocket'])
        .setAuth({'token': token})
        .enableForceNew()
        .build(),
  );
  socket.on('sync:changed', onSyncChanged);
  return _IoSocketHandle(socket);
}
