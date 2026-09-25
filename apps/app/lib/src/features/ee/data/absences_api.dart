import 'package:dio/dio.dart';

import '../../../core/api_exception.dart';

/// EE-236 (AW-E18) — who is away, and who is on call because of it.
///
/// Read and written online, like "My requests": an absence moves tonight's
/// on-call turn, so it goes to the server when it is written or not at all —
/// a queued absence that reached the rota after the night it was for would be
/// worse than a refused one. Whole days only (`YYYY-MM-DD`, both ends
/// inclusive, in the team's time zone); no approval, no half days, and no
/// reason field — the server keeps dates and nothing else.
class EeAbsence {
  const EeAbsence({
    required this.id,
    required this.userId,
    required this.startDate,
    required this.endDate,
    this.userName,
    this.createdBy,
  });

  factory EeAbsence.fromJson(Map<String, dynamic> json) => EeAbsence(
    id: json['id'] as String,
    userId: json['userId'] as String,
    userName: json['userName'] as String?,
    startDate: _day(json['startDate'] as String),
    endDate: _day(json['endDate'] as String),
    createdBy: json['createdBy'] as String?,
  );

  final String id;
  final String userId;
  final String? userName;

  /// Calendar days, not instants: midnight UTC stands for "that day".
  final DateTime startDate;
  final DateTime endDate;
  final String? createdBy;
}

/// One window of the list. [canManage] is the server saying whether this
/// person may record or remove somebody else's — the screen offers exactly
/// that, never a button the door would refuse. [truncated] means the window
/// held more than one page: the screen says so rather than implying nobody
/// else is away.
class EeAbsencePage {
  const EeAbsencePage({
    this.absences = const [],
    this.truncated = false,
    this.canManage = false,
    this.today,
  });

  final List<EeAbsence> absences;
  final bool truncated;
  final bool canManage;

  /// Today in the TEAM's zone — the first day a new absence may cover by
  /// default, whatever zone this phone is in.
  final DateTime? today;
}

/// Who holds a unit's rota right now, with the cover an absence caused.
class EeOnCallNow {
  const EeOnCallNow({
    required this.unitId,
    required this.unitName,
    this.userId,
    this.userName,
    this.coveringFor,
    this.coveringForName,
    this.until,
  });

  factory EeOnCallNow.fromJson(Map<String, dynamic> json) => EeOnCallNow(
    unitId: json['unitId'] as String,
    unitName: json['unitName'] as String,
    userId: json['userId'] as String?,
    userName: json['userName'] as String?,
    coveringFor: json['coveringFor'] as String?,
    coveringForName: json['coveringForName'] as String?,
    until: json['until'] is String
        ? DateTime.tryParse(json['until'] as String)?.toLocal()
        : null,
  );

  final String unitId;
  final String unitName;

  /// Who is on call — null when everybody on the rota is away today.
  final String? userId;
  final String? userName;

  /// Whose turn it is, when that person is away and somebody covers it.
  final String? coveringFor;
  final String? coveringForName;
  final DateTime? until;

  bool get nobodyAvailable => userId == null && coveringFor != null;
}

class EeAbsencesApi {
  const EeAbsencesApi(this._dio);
  final Dio _dio;

  static const _base = '/api/v1/ee/team/absences';

  Future<EeAbsencePage> list() async {
    try {
      final res = await _dio.get<Map<String, dynamic>>(_base);
      final data = res.data ?? const <String, dynamic>{};
      return EeAbsencePage(
        absences: [
          for (final a in (data['absences'] as List?) ?? const [])
            EeAbsence.fromJson(a as Map<String, dynamic>),
        ],
        truncated: data['truncated'] == true,
        canManage: data['canManage'] == true,
        today: data['today'] is String ? _day(data['today'] as String) : null,
      );
    } on DioException catch (e) {
      throw asApiException(e);
    }
  }

  /// Records an absence. [userId] null means your own — the case that needs
  /// no permission.
  Future<EeAbsence> create({
    required DateTime startDate,
    required DateTime endDate,
    String? userId,
  }) async {
    try {
      final res = await _dio.post<Map<String, dynamic>>(
        _base,
        data: {
          'userId': ?userId,
          'startDate': dayText(startDate),
          'endDate': dayText(endDate),
        },
      );
      return EeAbsence.fromJson(res.data!);
    } on DioException catch (e) {
      throw asApiException(e);
    }
  }

  Future<void> delete(String absenceId) async {
    try {
      await _dio.delete<void>('$_base/$absenceId');
    } on DioException catch (e) {
      throw asApiException(e);
    }
  }

  /// The rotas of the units this person is in, as the server's arithmetic
  /// answers them now — the screen never works out a turn itself.
  Future<List<EeOnCallNow>> onCallMine() async {
    try {
      final res = await _dio.get<Map<String, dynamic>>(
        '/api/v1/ee/team/oncall/mine',
      );
      return [
        for (final u in (res.data?['units'] as List?) ?? const [])
          EeOnCallNow.fromJson(u as Map<String, dynamic>),
      ];
    } on DioException catch (e) {
      throw asApiException(e);
    }
  }
}

/// `YYYY-MM-DD` for a calendar day (its year, month and day, whatever zone
/// the DateTime carries).
String dayText(DateTime day) =>
    '${day.year.toString().padLeft(4, '0')}-'
    '${day.month.toString().padLeft(2, '0')}-'
    '${day.day.toString().padLeft(2, '0')}';

DateTime _day(String text) => DateTime.utc(
  int.parse(text.substring(0, 4)),
  int.parse(text.substring(5, 7)),
  int.parse(text.substring(8, 10)),
);
