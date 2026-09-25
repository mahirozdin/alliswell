import '../../../sync/db/database.dart';

/// A problem record (EE-188, screens EE-270).
///
/// The device's copy ([EeProblem.fromRecord]) carries the whole record — the
/// symptom people see, the workaround, the root cause and the permanent
/// action — because the workaround is the one sentence an agent must be able
/// to read with no signal. The server's answer ([EeProblem.fromJson]) stands
/// in for a record this device does not hold; [fromServer] says which.
class EeProblem {
  const EeProblem({
    required this.id,
    required this.workspaceId,
    required this.title,
    required this.symptom,
    required this.status,
    this.workaround,
    this.rootCause,
    this.permanentAction,
    this.resolvedAt,
    this.createdAt,
    this.updatedAt,
    this.fromServer = false,
  });

  factory EeProblem.fromRecord(ProblemRecord row) => EeProblem(
    id: row.id,
    workspaceId: row.workspaceId,
    title: row.title,
    symptom: row.symptom,
    status: row.status,
    workaround: row.workaround,
    rootCause: row.rootCause,
    permanentAction: row.permanentAction,
    resolvedAt: row.resolvedAt?.toLocal(),
    createdAt: row.createdAt?.toLocal(),
    updatedAt: row.updatedAt?.toLocal(),
  );

  factory EeProblem.fromJson(Map<String, dynamic> json) => EeProblem(
    id: json['id'] as String,
    workspaceId: json['workspaceId'] as String,
    title: json['title'] as String,
    symptom: json['symptom'] as String,
    status: json['status'] as String,
    workaround: json['workaround'] as String?,
    rootCause: json['rootCause'] as String?,
    permanentAction: json['permanentAction'] as String?,
    resolvedAt: _date(json['resolvedAt']),
    createdAt: _date(json['createdAt']),
    updatedAt: _date(json['updatedAt']),
    fromServer: true,
  );

  final String id;
  final String workspaceId;
  final String title;

  /// What people SEE — the field somebody matches against when they wonder
  /// whether this is that thing again.
  final String symptom;

  /// `investigating | known_error | resolved | closed`, the server's word.
  final String status;

  /// What to do until it is fixed. Null until somebody has something useful
  /// to say (an empty string would read as "we looked and there is nothing").
  final String? workaround;
  final String? rootCause;
  final String? permanentAction;
  final DateTime? resolvedAt;
  final DateTime? createdAt;
  final DateTime? updatedAt;
  final bool fromServer;

  /// A known error is a problem whose cause is known and whose fix is not in
  /// yet — the server's own definition (`problems/state.js` `isKnownError`),
  /// read off the status it sent rather than re-derived.
  bool get isKnownError => status == 'known_error';

  bool get hasWorkaround => workaround != null && workaround!.trim().isNotEmpty;
}

/// A request a problem explains (EE-270's read of EE-189's link).
class EeProblemTicket {
  const EeProblemTicket({
    required this.id,
    required this.workspaceId,
    required this.subject,
    required this.status,
    required this.priority,
    this.number,
  });

  factory EeProblemTicket.fromJson(Map<String, dynamic> json) =>
      EeProblemTicket(
        id: json['id'] as String,
        workspaceId: json['workspaceId'] as String,
        subject: json['subject'] as String,
        status: json['status'] as String,
        priority: json['priority'] as String,
        number: (json['number'] as num?)?.toInt(),
      );

  final String id;
  final String workspaceId;
  final String subject;
  final String status;
  final String priority;
  final int? number;
}

/// The requests a problem explains, as this person may see them: those in
/// desks they work in by subject, the rest as a count.
class EeProblemTickets {
  const EeProblemTickets({
    this.tickets = const [],
    this.count = 0,
    this.elsewhere = 0,
  });

  factory EeProblemTickets.fromJson(Map<String, dynamic> json) =>
      EeProblemTickets(
        tickets: [
          for (final row in (json['tickets'] as List<dynamic>? ?? const []))
            EeProblemTicket.fromJson(row as Map<String, dynamic>),
        ],
        count: (json['count'] as num?)?.toInt() ?? 0,
        elsewhere: (json['elsewhere'] as num?)?.toInt() ?? 0,
      );

  final List<EeProblemTicket> tickets;

  /// How many this person can see — more than [tickets] when the list was
  /// cut at the server's cap.
  final int count;

  /// Linked requests in desks this person does not work in.
  final int elsewhere;
}

/// What the detail reads from the server each time it opens.
class EeProblemLive {
  const EeProblemLive({required this.problem, required this.tickets});

  final EeProblem problem;
  final EeProblemTickets tickets;
}

/// Where a known-error record raised from a request comes from (EE-280).
class EeProblemSource {
  const EeProblemSource({
    required this.ticketId,
    required this.subject,
    this.number,
  });

  final String ticketId;
  final String subject;
  final int? number;
}

DateTime? _date(Object? value) =>
    value == null ? null : DateTime.parse(value as String).toLocal();
