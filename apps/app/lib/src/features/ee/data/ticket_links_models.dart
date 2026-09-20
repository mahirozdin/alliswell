/// What one request has to do with everything else (EE-189, EE-190).
class EeTicketLink {
  const EeTicketLink({
    required this.id,
    required this.ticketId,
    required this.type,
    this.relatedTicketId,
    this.problemId,
  });

  final String id;
  final String ticketId;

  /// `related` | `duplicate_of` | `child_of` | `problem_of`.
  final String type;
  final String? relatedTicketId;
  final String? problemId;

  factory EeTicketLink.fromJson(Map<String, dynamic> json) => EeTicketLink(
    id: json['id'] as String,
    ticketId: json['ticketId'] as String,
    type: json['type'] as String,
    relatedTicketId: json['relatedTicketId'] as String?,
    problemId: json['problemId'] as String?,
  );
}

/// A problem the request is an instance of, and the thing to say meanwhile.
class EeLinkedProblem {
  const EeLinkedProblem({
    required this.id,
    required this.title,
    required this.status,
    required this.hasUsableWorkaround,
    this.workaround,
  });

  final String id;
  final String title;
  final String status;

  /// The field this whole record exists to put in front of somebody.
  final String? workaround;

  /// Answered by the server rather than derived here: "known error AND a
  /// workaround that is not blank" is a rule, and a rule computed twice is a
  /// rule that can be computed differently.
  final bool hasUsableWorkaround;

  factory EeLinkedProblem.fromJson(Map<String, dynamic> json) =>
      EeLinkedProblem(
        id: json['id'] as String,
        title: json['title'] as String,
        status: json['status'] as String,
        workaround: json['workaround'] as String?,
        hasUsableWorkaround: json['hasUsableWorkaround'] as bool? ?? false,
      );
}

/// Everything the detail screen shows below the conversation.
///
/// One object rather than three providers, because the three arrive from two
/// calls and a screen that renders them independently flickers through three
/// half-states on every refresh.
class EeTicketRelations {
  const EeTicketRelations({
    this.links = const [],
    this.problems = const [],
    this.taskIds = const [],
    this.waitingReason,
  });

  final List<EeTicketLink> links;
  final List<EeLinkedProblem> problems;

  /// The work this request caused (ADR-0011 §5). Ids only — the titles come
  /// from the device's own copy, which already has every task in the unit.
  final List<String> taskIds;

  /// Null unless the request is parked (EE-190).
  final String? waitingReason;
}
