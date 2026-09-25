import 'package:dio/dio.dart';

import '../../../core/api_exception.dart';

/// One of the desk's saved replies (EE-201), as the composer offers it (EE-223).
class EeCannedReply {
  const EeCannedReply({
    required this.id,
    required this.name,
    required this.text,
  });

  factory EeCannedReply.fromJson(Map<String, dynamic> json) => EeCannedReply(
    id: json['id'] as String,
    name: json['name'] as String,
    // The server's rendering against THIS request when it made one — the
    // `{{...}}` vocabulary is the server's (EE-201: "a vocabulary implemented
    // three times is three vocabularies") — and the raw text otherwise.
    text: (json['rendered'] as String?) ?? json['body'] as String,
  );

  final String id;
  final String name;

  /// What goes into the text box.
  final String text;
}

/// One answer a request was filed with (EE-213), as the detail endpoint
/// returns it (EE-242). The server's words: [label] is the question as it was
/// asked on the day, [value] the text the requester typed or picked.
class EeTicketAnswer {
  const EeTicketAnswer({
    required this.label,
    required this.type,
    required this.value,
  });

  factory EeTicketAnswer.fromJson(Map<String, dynamic> json) => EeTicketAnswer(
    label: json['label'] as String,
    type: json['type'] as String,
    value: json['value'] as String,
  );

  final String label;

  /// `text` | `number` | `date` | `checkbox` | `select`.
  final String type;
  final String value;
}

/// What the server says THIS caller may do to one request (EE-224).
///
/// Every field is the server's answer, read from the detail endpoint: the
/// moves come from the lifecycle map both of its doors read, filtered by the
/// caller's verbs and by the approval gate. Nothing here is worked out on the
/// device — "the client writes no second state machine" is E19's rule, and a
/// list of statuses typed out in the app would be exactly that.
class EeTicketActions {
  const EeTicketActions({
    required this.status,
    required this.priority,
    this.waitingReason,
    this.impact,
    this.urgency,
    this.priorityOverridden = false,
    this.allowedTransitions = const [],
    this.waitingReasons = const [],
    this.priorities = const [],
    this.approvalPending = false,
    this.canOverridePriority = false,
    this.canAssignOthers = false,
    this.canPauseSla = false,
    this.slaPausable = false,
    this.slaHeld = false,
    this.slaHoldReasons = const [],
    this.senderUnverified = false,
    this.unverifiedCommentIds = const {},
    this.requesterEmail,
    this.requesterDisplayName,
    this.answers = const [],
  });

  factory EeTicketActions.fromJson(Map<String, dynamic> json) {
    List<String> strings(Object? value) =>
        ((value as List<dynamic>?) ?? const []).cast<String>();
    final hold = (json['slaHold'] as Map<String, dynamic>?) ?? const {};
    return EeTicketActions(
      status: json['status'] as String,
      priority: json['priority'] as String,
      waitingReason: json['waitingReason'] as String?,
      impact: json['impact'] as String?,
      urgency: json['urgency'] as String?,
      priorityOverridden: json['priorityOverridden'] == true,
      allowedTransitions: strings(json['allowedTransitions']),
      waitingReasons: strings(json['waitingReasons']),
      priorities: strings(json['priorities']),
      approvalPending: json['approvalPending'] == true,
      canOverridePriority: json['canOverridePriority'] == true,
      canAssignOthers: json['canAssignOthers'] == true,
      canPauseSla: json['canPauseSla'] == true,
      slaPausable: json['slaPausable'] == true,
      slaHeld: hold['held'] == true,
      // One reason per held clock on the wire; the same reason twice is one
      // sentence on a screen.
      slaHoldReasons: {
        for (final row
            in ((hold['reasons'] as List<dynamic>?) ?? const [])
                .cast<Map<String, dynamic>>())
          row['reason'] as String,
      }.toList(growable: false),
      senderUnverified: json['senderUnverified'] == true,
      unverifiedCommentIds: strings(json['unverifiedCommentIds']).toSet(),
      requesterEmail: json['requesterEmail'] as String?,
      requesterDisplayName: json['requesterDisplayName'] as String?,
      answers: ((json['fields'] as List<dynamic>?) ?? const [])
          .cast<Map<String, dynamic>>()
          .map(EeTicketAnswer.fromJson)
          .toList(growable: false),
    );
  }

  /// EE-278: the service form's answers, in the form's order. The replica
  /// keeps none (they are the server's, EE-213), so the detail reads them
  /// here — the endpoint has returned them since EE-242, and until EE-278 no
  /// screen did.
  final List<EeTicketAnswer> answers;

  /// EE-258: who asked, in the server's words. The replica keeps them from
  /// v33 on; a request this device pulled before that has neither until the
  /// server next sends it, and the detail reads these instead.
  final String? requesterEmail;
  final String? requesterDisplayName;

  /// EE-254 (D17.2): this request arrived as mail claiming a colleague's
  /// address that could not be checked, so it was filed as an outside sender
  /// under the address it claimed. The server's word, read with the actions:
  /// the replica has no column for it.
  final bool senderUnverified;

  /// …and the replies that did the same, by id — the conversation itself is
  /// drawn from the replica.
  final Set<String> unverifiedCommentIds;

  final String status;
  final String priority;

  /// Why it is parked — null unless [status] is `waiting` (EE-190).
  final String? waitingReason;

  /// The matrix inputs (EE-183); both null on a request filed without them.
  final String? impact;
  final String? urgency;

  /// True when somebody allowed to has taken the priority out of the
  /// matrix's hands; a later impact correction then leaves it alone.
  final bool priorityOverridden;

  /// Where this caller may move it from here — possibly nothing.
  final List<String> allowedTransitions;

  /// Why a request may be parked, in the server's words and order.
  final List<String> waitingReasons;

  /// The priority tiers, in the server's order.
  final List<String> priorities;

  /// A signature is pending (EE-184): the reason [allowedTransitions] may be
  /// down to cancelling alone, which a screen has to say out loud.
  final bool approvalPending;

  final bool canOverridePriority;

  /// `tickets.assign`: putting the request on somebody else, or taking it
  /// off them. Taking it yourself needs nothing (EE-086's rule).
  final bool canAssignOthers;
  final bool canPauseSla;

  /// A pause would stop something: a running promise nobody holds yet.
  final bool slaPausable;

  /// Something holds the promise — a person's pause, or an approval's.
  final bool slaHeld;
  final List<String> slaHoldReasons;

  /// Whether this request's priority comes from the matrix at all.
  bool get usesMatrix => impact != null && urgency != null;
}

/// The desk's impact × urgency table (EE-183), as the server hands it out.
///
/// The rows and columns are read from the table itself, so a screen draws
/// exactly the inputs the server would accept. [derive] is a LOOKUP for the
/// preview line, not a rule: the server derives again on save, from its own
/// copy, and what it answers is what the request gets.
class EePriorityMatrix {
  const EePriorityMatrix({required this.cells, this.customised = false});

  factory EePriorityMatrix.fromJson(Map<String, dynamic> json) {
    final raw = (json['matrix'] as Map<String, dynamic>?) ?? const {};
    return EePriorityMatrix(
      cells: {
        for (final row in raw.entries)
          row.key: {
            for (final cell in (row.value as Map<String, dynamic>).entries)
              cell.key: cell.value as String,
          },
      },
      customised: json['customised'] == true,
    );
  }

  final Map<String, Map<String, String>> cells;

  /// False means the desk derives from the shipped table, not that there is
  /// no table (EE-183).
  final bool customised;

  List<String> get impacts => cells.keys.toList(growable: false);
  List<String> get urgencies => cells.isEmpty
      ? const []
      : cells.values.first.keys.toList(growable: false);

  String? derive(String? impact, String? urgency) =>
      impact == null || urgency == null ? null : cells[impact]?[urgency];
}

/// Writing on a request from the app (EE-223).
///
/// ONLINE, by decision (E19): a request is server-canonical, and a reply that
/// waited in a queue would reach the requester whenever the phone next found a
/// signal, in an order nobody chose. So a failure travels back intact — the
/// composer keeps the text and says why — and nothing is retried behind the
/// person's back.
/// One request's answer inside a batch (EE-171, EE-227).
class EeBulkRow {
  const EeBulkRow({required this.ticketId, required this.changed, this.reason});

  factory EeBulkRow.fromJson(Map<String, dynamic> json) => EeBulkRow(
    ticketId: json['ticketId'] as String,
    changed: json['changed'] == true,
    reason: json['reason'] as String?,
  );

  final String ticketId;
  final bool changed;

  /// The code the single door would have answered with, or `NO_CHANGE` /
  /// `NOT_FOUND` — null when the row moved.
  final String? reason;
}

/// A batch's whole answer: every row accounted for, so a screen can say
/// "12 of 15 moved, and why the other three did not".
class EeBulkResult {
  const EeBulkResult({
    required this.changed,
    required this.skipped,
    required this.rows,
  });

  factory EeBulkResult.fromJson(Map<String, dynamic> json) => EeBulkResult(
    changed: (json['changed'] as num?)?.toInt() ?? 0,
    skipped: (json['skipped'] as num?)?.toInt() ?? 0,
    rows: [
      for (final row
          in ((json['results'] as List<dynamic>?) ?? const [])
              .cast<Map<String, dynamic>>())
        EeBulkRow.fromJson(row),
    ],
  );

  final int changed;
  final int skipped;
  final List<EeBulkRow> rows;
}

class EeTicketWriteApi {
  const EeTicketWriteApi(this._dio);
  final Dio _dio;

  static const _tickets = '/api/v1/ee/team/tickets';

  /// A reply (the requester reads it) or an internal note (only the unit
  /// does). The rest is the server's: who may mark a note internal, what is
  /// mailed, what reaches a linked child request (EE-182, EE-189).
  Future<void> comment(
    String ticketId, {
    required String body,
    required bool internal,
  }) async {
    try {
      await _dio.post<Map<String, dynamic>>(
        '$_tickets/$ticketId/comments',
        data: {'body': body, 'internal': internal},
      );
    } on DioException catch (error) {
      throw asApiException(error);
    }
  }

  /// The desk's saved replies, rendered against [ticketId]. Archived ones are
  /// not offered: the desk retired that wording. A 403/404 is "none" — the
  /// composer then has no list to open, rather than an error to explain.
  Future<List<EeCannedReply>> cannedReplies(String ticketId) async {
    try {
      final response = await _dio.get<Map<String, dynamic>>(
        '/api/v1/ee/team/canned-replies',
        queryParameters: {'ticketId': ticketId},
      );
      final rows = (response.data?['replies'] as List<dynamic>?) ?? const [];
      return [
        for (final row in rows.cast<Map<String, dynamic>>())
          if (row['archived'] != true) EeCannedReply.fromJson(row),
      ];
    } on DioException catch (error) {
      final code = error.response?.statusCode;
      if (code == 403 || code == 404) return const [];
      throw asApiException(error);
    }
  }

  /// EE-224 — what this caller may do to the request, read fresh.
  ///
  /// A 403/404 is "nothing": a request this person cannot reach offers no
  /// actions, rather than an error to explain on a screen that already
  /// shows the device's copy of it.
  Future<EeTicketActions?> actions(String ticketId) async {
    try {
      final response = await _dio.get<Map<String, dynamic>>(
        '$_tickets/$ticketId',
      );
      final data = response.data;
      return data == null ? null : EeTicketActions.fromJson(data);
    } on DioException catch (error) {
      final code = error.response?.statusCode;
      if (code == 403 || code == 404) return null;
      throw asApiException(error);
    }
  }

  /// The desk's matrix (EE-183); null when it cannot be read.
  Future<EePriorityMatrix?> priorityMatrix() async {
    try {
      final response = await _dio.get<Map<String, dynamic>>(
        '/api/v1/ee/team/priority-matrix',
      );
      final data = response.data;
      return data == null ? null : EePriorityMatrix.fromJson(data);
    } on DioException catch (error) {
      final code = error.response?.statusCode;
      if (code == 403 || code == 404) return null;
      throw asApiException(error);
    }
  }

  /// Moves the request. `waiting` owes a [waitingReason] (EE-190); the
  /// server refuses a move it does not list, whatever a screen offered.
  Future<void> setStatus(
    String ticketId,
    String status, {
    String? waitingReason,
  }) => _write(
    () => _dio.post<Map<String, dynamic>>(
      '$_tickets/$ticketId/status',
      data: {'status': status, 'waitingReason': ?waitingReason},
    ),
  );

  /// A priority named directly. Against the matrix it is an override and
  /// needs its own verb; agreeing with the matrix hands the request back to
  /// it (EE-183) — both decided by the server, which answers with the
  /// priority the request now has.
  Future<String?> setPriority(String ticketId, String priority) =>
      _edit(ticketId, {'priority': priority});

  /// The matrix inputs. The server derives the priority from them — unless
  /// somebody took it out of the matrix's hands — and answers with it.
  Future<String?> setMatrixInputs(
    String ticketId, {
    required String impact,
    required String urgency,
  }) => _edit(ticketId, {'impact': impact, 'urgency': urgency});

  Future<String?> _edit(String ticketId, Map<String, Object> patch) async {
    try {
      final response = await _dio.patch<Map<String, dynamic>>(
        '$_tickets/$ticketId',
        data: patch,
      );
      return response.data?['priority'] as String?;
    } on DioException catch (error) {
      throw asApiException(error);
    }
  }

  /// Stops the promise without moving the request (EE-190).
  Future<void> pauseSla(String ticketId, String reason) => _write(
    () => _dio.post<Map<String, dynamic>>(
      '$_tickets/$ticketId/sla/pause',
      data: {'reason': reason},
    ),
  );

  Future<void> resumeSla(String ticketId) => _write(
    () => _dio.post<Map<String, dynamic>>('$_tickets/$ticketId/sla/resume'),
  );

  /// Puts [userId] on the request and answers the assignment's id — the one
  /// a later release names. Already on it is the same state, not an error.
  Future<String> assign(String ticketId, String userId) async {
    try {
      final response = await _dio.post<Map<String, dynamic>>(
        '$_tickets/$ticketId/assignments',
        data: {'userId': userId},
      );
      return (response.data ?? const <String, dynamic>{})['id'] as String;
    } on DioException catch (error) {
      throw asApiException(error);
    }
  }

  /// EE-227 — one action on many requests (`POST /tickets/bulk`, EE-171).
  ///
  /// Every row walks the single door's checks on the server and answers for
  /// itself; a missing verb refuses the whole batch (403), which arrives here
  /// as the thrown error it is.
  Future<EeBulkResult> bulk(
    List<String> ticketIds,
    Map<String, Object> action,
  ) async {
    try {
      final response = await _dio.post<Map<String, dynamic>>(
        '$_tickets/bulk',
        data: {'ticketIds': ticketIds, 'action': action},
      );
      return EeBulkResult.fromJson(response.data ?? const <String, dynamic>{});
    } on DioException catch (error) {
      throw asApiException(error);
    }
  }

  /// Takes an assignment off the request. Released already is the same state.
  Future<void> release(String ticketId, String assignmentId) => _write(
    () => _dio.delete<void>('$_tickets/$ticketId/assignments/$assignmentId'),
  );

  Future<void> _write(Future<Object?> Function() call) async {
    try {
      await call();
    } on DioException catch (error) {
      throw asApiException(error);
    }
  }
}
