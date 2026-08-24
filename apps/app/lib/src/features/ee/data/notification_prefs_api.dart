import 'package:dio/dio.dart';

import '../../../core/api_exception.dart';

/// One event class's row in the preference matrix (EE-076).
///
/// `silenceable` arrives as DATA rather than being decided here, and that is
/// the whole reason the endpoint returns a matrix instead of the stored row:
/// the policy about what may never be switched off lives in the server's
/// routing table, and a copy of it in Dart would be a second answer to drift
/// away from the first (DESIGN §22 — a control that lies is worse than one
/// that is missing).
class EeNotificationPrefRow {
  const EeNotificationPrefRow({
    required this.eventClass,
    required this.channels,
    required this.muted,
    required this.silenceable,
  });

  factory EeNotificationPrefRow.fromJson(Map<String, dynamic> json) =>
      EeNotificationPrefRow(
        eventClass: json['eventClass'] as String,
        channels: ((json['channels'] as List?) ?? const [])
            .map((c) => '$c')
            .toList(growable: false),
        muted: ((json['muted'] as List?) ?? const [])
            .map((c) => '$c')
            .toList(growable: false),
        silenceable: json['silenceable'] as bool? ?? true,
      );

  final String eventClass;
  final List<String> channels;
  final List<String> muted;
  final bool silenceable;

  bool isMuted(String channel) => muted.contains(channel);
}

class EeNotificationPrefs {
  const EeNotificationPrefs({
    required this.matrix,
    required this.timezone,
    this.quietFrom,
    this.quietTo,
  });

  factory EeNotificationPrefs.fromJson(Map<String, dynamic> json) =>
      EeNotificationPrefs(
        matrix: ((json['matrix'] as List?) ?? const [])
            .map(
              (row) =>
                  EeNotificationPrefRow.fromJson(row as Map<String, dynamic>),
            )
            .toList(growable: false),
        timezone: json['timezone'] as String? ?? 'UTC',
        quietFrom: (json['quietFrom'] as num?)?.toInt(),
        quietTo: (json['quietTo'] as num?)?.toInt(),
      );

  final List<EeNotificationPrefRow> matrix;

  /// The person's own zone, so the screen can label the window without
  /// guessing — 22:00 means 22:00 where they are.
  final String timezone;

  /// Minutes from midnight, or null for no window.
  final int? quietFrom;
  final int? quietTo;

  bool get hasQuietHours => quietFrom != null && quietTo != null;

  /// Every muted pair, flattened the way the PUT expects it.
  List<String> get mutedPairs => [
    for (final row in matrix)
      for (final channel in row.muted) '${row.eventClass}:$channel',
  ];
}

/// Notification preferences client (EE-076).
///
/// The PUT sends the WHOLE matrix, because the server accepts nothing else: a
/// patch protocol would need a rule for "a class you did not mention", and
/// every answer to that is a way to lose somebody's choice.
class EeNotificationPrefsApi {
  const EeNotificationPrefsApi(this._dio);
  final Dio _dio;

  static const _base = '/api/v1/ee/me/notification-preferences';

  Future<EeNotificationPrefs> read() => _run(() async {
    final res = await _dio.get<Map<String, dynamic>>(_base);
    return EeNotificationPrefs.fromJson(res.data ?? const {});
  });

  Future<EeNotificationPrefs> update({
    List<String>? muted,
    int? quietFrom,
    int? quietTo,
    bool clearQuietHours = false,
  }) => _run(() async {
    final body = <String, dynamic>{
      'muted': ?muted,
      // Both ends together, always: the server refuses half a window, and
      // sending one would turn a UI slip into a 400 the user cannot read.
      if (clearQuietHours) ...{'quietFrom': null, 'quietTo': null},
      if (!clearQuietHours && quietFrom != null && quietTo != null) ...{
        'quietFrom': quietFrom,
        'quietTo': quietTo,
      },
    };
    final res = await _dio.put<Map<String, dynamic>>(_base, data: body);
    return EeNotificationPrefs.fromJson(res.data ?? const {});
  });

  Future<T> _run<T>(Future<T> Function() call) async {
    try {
      return await call();
    } on DioException catch (error) {
      throw asApiException(error);
    }
  }
}
