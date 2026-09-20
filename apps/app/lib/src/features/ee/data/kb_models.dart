/// A knowledge-base article, as the screens read it (EE-195, EE-196).
class EeKbArticle {
  const EeKbArticle({
    required this.id,
    required this.title,
    required this.symptom,
    required this.status,
    this.environment,
    this.solution,
    this.serviceId,
    this.viewCount = 0,
    this.sourceTicketId,
    this.suggestedCount = 0,
    this.convertedCount = 0,
    this.deflectedCount = 0,
    this.createdBy,
    this.publishedBy,
  });

  final String id;
  final String title;

  /// What people SEE. The sentence somebody types when looking for this,
  /// which is why it leads the card under the title.
  final String symptom;

  /// `wip | draft | approved | published | retired`, the server's own word.
  /// Never mapped to a local enum: the set is the server's, and a replica
  /// that only knew four of five would render the fifth as nothing.
  final String status;
  final String? environment;

  /// Absent while an article is still a captured QUESTION — that is what
  /// `wip` means, not a draft somebody has not finished typing.
  final String? solution;
  final String? serviceId;
  final int viewCount;

  /// Which request taught the desk this, when one did.
  final String? sourceTicketId;
  final int suggestedCount;
  final int convertedCount;

  /// Shown, minus asked-anyway. Computed on the SERVER and carried, rather
  /// than subtracted here: two places doing the arithmetic is two answers the
  /// first time somebody changes the rule.
  final int deflectedCount;
  final String? createdBy;
  final String? publishedBy;

  bool get isPublished => status == 'published';
  bool get isWip => status == 'wip';

  factory EeKbArticle.fromJson(Map<String, dynamic> json) => EeKbArticle(
    id: json['id'] as String,
    title: json['title'] as String,
    symptom: json['symptom'] as String,
    status: json['status'] as String,
    environment: json['environment'] as String?,
    solution: json['solution'] as String?,
    serviceId: json['serviceId'] as String?,
    viewCount: (json['viewCount'] as num?)?.toInt() ?? 0,
    sourceTicketId: json['sourceTicketId'] as String?,
    suggestedCount: (json['suggestedCount'] as num?)?.toInt() ?? 0,
    convertedCount: (json['convertedCount'] as num?)?.toInt() ?? 0,
    deflectedCount: (json['deflectedCount'] as num?)?.toInt() ?? 0,
    createdBy: json['createdBy'] as String?,
    publishedBy: json['publishedBy'] as String?,
  );
}

/// The lifecycle, mirrored from `ee/server/modules/kb/state.js`.
///
/// Mirrored rather than fetched because a screen has to draw a status BEFORE
/// any request returns, and because the order below is the order the flow is
/// walked — which is what the detail screen's "what next" button reads. The
/// server is still the authority: an unknown value renders as itself rather
/// than being dropped.
const kEeKbStatuses = <String>[
  'wip',
  'draft',
  'approved',
  'published',
  'retired',
];

/// What a given status may become, and nothing else.
///
/// The second copy of a rule that also lives on the server, which is a cost
/// paid deliberately: without it the screen would offer every transition and
/// let the server refuse four of them, and a button that answers 409 is the
/// thing this repo tests for by name. The server remains the gate — this only
/// decides what to OFFER.
const kEeKbTransitions = <String, List<String>>{
  'wip': ['draft'],
  'draft': ['approved'],
  'approved': ['draft', 'published'],
  'published': ['draft', 'retired'],
  'retired': <String>[],
};

/// Entering or leaving `published` is the publisher's call — `kb.publish`.
bool eeKbNeedsPublish(String from, String to) =>
    from == 'published' || to == 'published';
