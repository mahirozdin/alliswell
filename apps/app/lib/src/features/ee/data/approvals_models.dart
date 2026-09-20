/// Approvals, client side (EE-184).
///
/// The model is deliberately thin because the SERVER'S answer is deliberately
/// thin: an approver may hold no access to the thing they are approving
/// (ADR-0007 §1 — seeing is unit membership, and the purchasing manager is not
/// in IT), so what arrives is a SUMMARY and never the record.
///
/// [EeApprovalTarget] being nullable is not defensive coding. A target really
/// can be gone — core deleted the task, the archive swept the request — and
/// the screen has to say so rather than render an empty row.
class EeApprovalTarget {
  const EeApprovalTarget({
    required this.kind,
    required this.title,
    required this.status,
    this.number,
  });

  factory EeApprovalTarget.fromJson(Map<String, dynamic> json) =>
      EeApprovalTarget(
        kind: json['kind'] as String,
        title: json['title'] as String,
        status: json['status'] as String,
        number: json['number'] as int?,
      );

  /// `ee_ticket` or `task` — what this is a decision about.
  final String kind;
  final String title;
  final String status;

  /// The request's own number (EE-167), null for anything that has none.
  final int? number;
}

class EeApproval {
  const EeApproval({
    required this.id,
    required this.targetType,
    required this.targetId,
    required this.status,
    required this.createdAt,
    this.approverUserId,
    this.approverRoleKey,
    this.requestReason,
    this.decisionReason,
    this.decidedBy,
    this.decidedAt,
    this.dueAt,
    this.target,
  });

  factory EeApproval.fromJson(Map<String, dynamic> json) => EeApproval(
    id: json['id'] as String,
    targetType: json['targetType'] as String,
    targetId: json['targetId'] as String,
    status: json['status'] as String,
    createdAt: DateTime.parse(json['createdAt'] as String).toLocal(),
    approverUserId: json['approverUserId'] as String?,
    approverRoleKey: json['approverRoleKey'] as String?,
    requestReason: json['requestReason'] as String?,
    decisionReason: json['decisionReason'] as String?,
    decidedBy: json['decidedBy'] as String?,
    decidedAt: json['decidedAt'] == null
        ? null
        : DateTime.parse(json['decidedAt'] as String).toLocal(),
    dueAt: json['dueAt'] == null
        ? null
        : DateTime.parse(json['dueAt'] as String).toLocal(),
    target: json['target'] == null
        ? null
        : EeApprovalTarget.fromJson(json['target'] as Map<String, dynamic>),
  );

  final String id;
  final String targetType;
  final String targetId;

  /// `pending`, `approved`, `rejected` or `expired`. The fourth is its own
  /// word on purpose: nobody decided anything, and a screen that drew it as a
  /// refusal would blame somebody for a silence.
  final String status;

  final DateTime createdAt;
  final String? approverUserId;
  final String? approverRoleKey;

  /// Why it was asked — the sentence the approver reads before deciding.
  final String? requestReason;

  /// Why it was answered. Required for BOTH answers by the server.
  final String? decisionReason;

  final String? decidedBy;
  final DateTime? decidedAt;

  /// When it lapses. Null is a legitimate choice, not a gap.
  final DateTime? dueAt;

  /// Null when the target is gone. See the file header.
  final EeApprovalTarget? target;

  bool get isPending => status == 'pending';
}
