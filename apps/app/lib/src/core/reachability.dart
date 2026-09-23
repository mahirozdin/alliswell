import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Did the server answer the last time anything asked it? (OPH-342)
///
/// Most of the app never needs to know: it is local-first, and a write waits
/// in the outbox until the network comes back. The surfaces that write
/// straight to the server do — a button that cannot work offline has to be
/// disabled BEFORE it is pressed, with the reason next to it, rather than
/// fail after somebody typed a paragraph into it.
///
/// It is derived from traffic the app already makes, not from the OS's
/// network state: the sync engine pulls on a timer through the same client
/// every REST call uses, so the answer is refreshed for free, and it is the
/// right question — a phone on hotel wi-fi has a network and reaches nothing.
///
/// `null` until anything has been asked: unknown is not "offline", and a
/// surface that greyed itself out at start-up until the first pull finished
/// would be wrong for everybody who is, in fact, online.
class ServerReachability extends Notifier<bool?> {
  @override
  bool? build() => null;

  /// The server answered — with anything, a 4xx included: an answer, even
  /// "no", proves the way there is open.
  void answered() {
    if (state != true) state = true;
  }

  /// The request never reached an answer.
  void unreachable() {
    if (state != false) state = false;
  }
}

final serverReachabilityProvider = NotifierProvider<ServerReachability, bool?>(
  ServerReachability.new,
);

/// Feeds [ServerReachability] from every request the app's client makes.
///
/// Only failures that mean "there was no answer" count as unreachable: no
/// route, refused, timed out while connecting or sending. A cancelled request
/// says nothing about the network, and an error WITH a response is an answer.
class ReachabilityInterceptor extends Interceptor {
  ReachabilityInterceptor(this._reachability);

  final ServerReachability _reachability;

  static bool meansUnreachable(DioException error) =>
      error.response == null &&
      switch (error.type) {
        DioExceptionType.connectionError ||
        DioExceptionType.connectionTimeout ||
        DioExceptionType.sendTimeout => true,
        _ => false,
      };

  @override
  void onResponse(
    Response<dynamic> response,
    ResponseInterceptorHandler handler,
  ) {
    _reachability.answered();
    handler.next(response);
  }

  @override
  void onError(DioException err, ErrorInterceptorHandler handler) {
    if (err.response != null) {
      _reachability.answered();
    } else if (meansUnreachable(err)) {
      _reachability.unreachable();
    }
    handler.next(err);
  }
}
