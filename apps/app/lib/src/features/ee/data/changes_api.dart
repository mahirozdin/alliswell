import 'package:dio/dio.dart';

import '../../../core/api_exception.dart';
import 'changes_models.dart';

/// The change client (EE-186's REST, read and written by EE-269's screens).
///
/// The LIST is not here: the list is the device's copy (the replica EE-186
/// sends and nothing read until EE-269). What is here is what a replica row
/// cannot carry — services, the source request, the signatures, the calendar
/// — and the one write the screens make, raising a change.
///
/// Status moves are absent on purpose. The server has no "moves this person
/// may make" answer for a change (a ticket has one), and a phone that copied
/// the type-keyed map to offer them would be a second state machine (§0.0/6).
class EeChangesApi {
  const EeChangesApi(this._dio);
  final Dio _dio;

  static const _base = '/api/v1/ee/team/changes';

  /// The server's own copy of one change. Failures travel: the detail draws
  /// "needs a connection" and "not here" differently.
  Future<EeChange> get(String id) async {
    try {
      final res = await _dio.get<Map<String, dynamic>>('$_base/$id');
      return EeChange.fromJson(res.data ?? const {});
    } on DioException catch (e) {
      throw asApiException(e);
    }
  }

  /// EE-279 — the changes raised from one request, for its detail.
  ///
  /// A 403 or 404 is an empty answer: this is an addition to a screen that
  /// already works, and "no team here" is nothing to draw, not an error.
  Future<List<EeChange>> raisedFrom(String ticketId) async {
    try {
      final res = await _dio.get<Map<String, dynamic>>(
        _base,
        queryParameters: {'ticketId': ticketId},
      );
      return [
        for (final row in (res.data?['changes'] as List<dynamic>? ?? const []))
          EeChange.fromJson(row as Map<String, dynamic>),
      ];
    } on DioException catch (e) {
      final code = e.response?.statusCode;
      if (code == 403 || code == 404) return const [];
      throw asApiException(e);
    }
  }

  /// Who was asked to sign, and whether THIS person may answer (EE-269).
  Future<List<EeChangeApproval>> approvals(String id) async {
    try {
      final res = await _dio.get<Map<String, dynamic>>('$_base/$id/approvals');
      return [
        for (final row
            in (res.data?['approvals'] as List<dynamic>? ?? const []))
          EeChangeApproval.fromJson(row as Map<String, dynamic>),
      ];
    } on DioException catch (e) {
      throw asApiException(e);
    }
  }

  /// The machines it touches. Reading them takes `assets.view`; without it
  /// the section is simply not drawn, which a 403 turned into [] says.
  Future<List<EeChangeAsset>> assets(String id) async {
    try {
      final res = await _dio.get<Map<String, dynamic>>('$_base/$id/assets');
      return [
        for (final row in (res.data?['assets'] as List<dynamic>? ?? const []))
          EeChangeAsset.fromJson(row as Map<String, dynamic>),
      ];
    } on DioException catch (e) {
      if (e.response?.statusCode == 403) return const [];
      throw asApiException(e);
    }
  }

  /// What the calendar says about [change]'s own window (EE-187's read,
  /// asked for one window). The clashes are the server's — computed against
  /// every unit's changes, which this device does not hold — and so is the
  /// list of freezes the window overlaps.
  Future<EeChangeConflicts> conflicts(EeChange change) async {
    if (!change.hasWindow) return const EeChangeConflicts();
    try {
      final res = await _dio.get<Map<String, dynamic>>(
        '$_base/calendar',
        queryParameters: {
          'from': change.windowStart!.toUtc().toIso8601String(),
          'to': change.windowEnd!.toUtc().toIso8601String(),
        },
      );
      final data = res.data ?? const {};
      Map<String, dynamic>? self;
      for (final row in (data['changes'] as List<dynamic>? ?? const [])) {
        final map = row as Map<String, dynamic>;
        if (map['id'] == change.id) self = map;
      }
      return EeChangeConflicts(
        clashes: [
          for (final c in (self?['clashes'] as List<dynamic>? ?? const []))
            EeChangeClash.fromJson(c as Map<String, dynamic>),
        ],
        freezes: [
          for (final f in (data['freezes'] as List<dynamic>? ?? const []))
            EeChangeFreeze.fromJson(f as Map<String, dynamic>),
        ],
      );
    } on DioException catch (e) {
      throw asApiException(e);
    }
  }

  /// Raises one (EE-269, `changes.create`). Exactly one of [sourceTicketId]
  /// and [workspaceId] is sent: a change raised from a request is filed in
  /// that request's desk, any other in the desk on screen (EE-279) — never in
  /// whichever of the caller's desks happens to sort first.
  Future<EeChange> create({
    required String title,
    required String type,
    required String risk,
    required String impact,
    required String rollbackPlan,
    String? description,
    DateTime? windowStart,
    DateTime? windowEnd,
    List<String> serviceIds = const [],
    String? sourceTicketId,
    String? workspaceId,
  }) async {
    try {
      final res = await _dio.post<Map<String, dynamic>>(
        _base,
        data: {
          'title': title,
          'type': type,
          'risk': risk,
          'impact': impact,
          'rollbackPlan': rollbackPlan,
          if (description != null && description.isNotEmpty)
            'description': description,
          if (windowStart != null)
            'windowStart': windowStart.toUtc().toIso8601String(),
          if (windowEnd != null)
            'windowEnd': windowEnd.toUtc().toIso8601String(),
          if (serviceIds.isNotEmpty) 'serviceIds': serviceIds,
          'sourceTicketId': ?sourceTicketId,
          if (sourceTicketId == null) 'workspaceId': ?workspaceId,
        },
      );
      return EeChange.fromJson(res.data ?? const {});
    } on DioException catch (e) {
      throw asApiException(e);
    }
  }
}
