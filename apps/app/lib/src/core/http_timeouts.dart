import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart' show kIsWeb;

/// How long one phase of a short API call may take: opening the connection,
/// sending the body, and waiting for the answer (on native, also the longest
/// pause between two chunks of it). On the web dio folds connect + receive
/// into one XHR deadline for the whole call.
///
/// Only calls whose answer is small and quick carry it: the sync engine's
/// push/pull, the device registry, the auth endpoints. A loop that runs one
/// request at a time (the sync engine, the ring-answer refresh) would
/// otherwise stop for good on the first request that never answers (#46/#48).
/// The app's shared client stays unbounded: an AI stream, an import, a
/// transcription upload or an export may legitimately take minutes, and file
/// bytes go to storage over a bare client of their own.
const Duration kApiPhaseTimeout = Duration(seconds: 30);

/// The whole-call backstop a single-flight loop puts around its request:
/// connect + send + receive. It only fires when dio's own bounds did not —
/// an answer that trickles in forever on native, or a transport that ignores
/// its timeouts.
const Duration kApiCallDeadline = Duration(seconds: 90);

/// Per-request bounds for a short call on the shared (unbounded) client.
///
/// The web adapter warns about a send timeout on a request without a body and
/// measures the upload itself for one with a body, so the send bound is only
/// set on native, where it covers writing the body.
Options boundedApiCall({bool web = kIsWeb}) => Options(
  connectTimeout: kApiPhaseTimeout,
  receiveTimeout: kApiPhaseTimeout,
  sendTimeout: web ? null : kApiPhaseTimeout,
);

/// [BaseOptions] for a client that only ever makes short calls.
BaseOptions boundedBaseOptions(String baseUrl, {bool web = kIsWeb}) =>
    BaseOptions(
      baseUrl: baseUrl,
      connectTimeout: kApiPhaseTimeout,
      receiveTimeout: kApiPhaseTimeout,
      sendTimeout: web ? null : kApiPhaseTimeout,
    );
