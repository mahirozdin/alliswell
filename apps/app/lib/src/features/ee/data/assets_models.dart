/// The equipment register, as the screens read it (EE-191, EE-192, EE-194).
class EeAsset {
  const EeAsset({
    required this.id,
    required this.tag,
    required this.name,
    required this.type,
    required this.status,
    this.serialNo,
    this.manufacturer,
    this.model,
    this.location,
    this.supplier,
    this.warrantyUntil,
    this.calibrationDue,
    this.purchasedAt,
    this.purchaseCostMinor,
    this.currency,
    this.notes,
    this.ownerUserId,
  });

  final String id;

  /// The number painted on the machine. Leads everywhere it is shown.
  final String tag;
  final String name;
  final String type;

  /// `in_stock | in_use | maintenance | faulty | retired`.
  final String status;
  final String? serialNo;
  final String? manufacturer;
  final String? model;
  final String? location;
  final String? supplier;

  /// `YYYY-MM-DD`, never an instant — a warranty ends on a day, and turning
  /// it into a timestamp moves it by one east of UTC (EE-191's measurement).
  final String? warrantyUntil;
  final String? calibrationDue;
  final String? purchasedAt;
  final int? purchaseCostMinor;
  final String? currency;
  final String? notes;
  final String? ownerUserId;

  factory EeAsset.fromJson(Map<String, dynamic> json) => EeAsset(
    id: json['id'] as String,
    tag: json['tag'] as String,
    name: json['name'] as String,
    type: json['type'] as String,
    status: json['status'] as String,
    serialNo: json['serialNo'] as String?,
    manufacturer: json['manufacturer'] as String?,
    model: json['model'] as String?,
    location: json['location'] as String?,
    supplier: json['supplier'] as String?,
    warrantyUntil: json['warrantyUntil'] as String?,
    calibrationDue: json['calibrationDue'] as String?,
    purchasedAt: json['purchasedAt'] as String?,
    purchaseCostMinor: (json['purchaseCostMinor'] as num?)?.toInt(),
    currency: json['currency'] as String?,
    notes: json['notes'] as String?,
    ownerUserId: json['ownerUserId'] as String?,
  );
}

/// One request in a machine's history (EE-192).
class EeAssetTicket {
  const EeAssetTicket({
    required this.id,
    required this.subject,
    required this.status,
    required this.priority,
    required this.createdAt,
    required this.archived,
    this.number,
    this.terminalAt,
  });

  final String id;
  final int? number;
  final String subject;
  final String status;
  final String priority;
  final DateTime createdAt;
  final DateTime? terminalAt;

  /// A FACT the screen draws, not an accident of a join. Most of a machine's
  /// history is archived, which is the whole reason this list exists.
  final bool archived;

  factory EeAssetTicket.fromJson(Map<String, dynamic> json) => EeAssetTicket(
    id: json['id'] as String,
    number: (json['number'] as num?)?.toInt(),
    subject: json['subject'] as String,
    status: json['status'] as String,
    priority: json['priority'] as String,
    createdAt: DateTime.parse(json['createdAt'] as String),
    terminalAt: json['terminalAt'] == null
        ? null
        : DateTime.parse(json['terminalAt'] as String),
    archived: json['archived'] as bool? ?? false,
  );
}

/// The numbers that say a machine should be replaced (EE-192).
class EeAssetStats {
  const EeAssetStats({
    required this.months,
    required this.ticketCount,
    required this.openTicketCount,
    required this.openMinutes,
    this.purchaseCostMinor,
    this.currency,
  });

  final int months;
  final int ticketCount;
  final int openTicketCount;

  /// How long requests about it stayed OPEN — not how long it was stopped.
  /// Nobody records the second thing yet, and the label says so.
  final int openMinutes;
  final int? purchaseCostMinor;
  final String? currency;

  factory EeAssetStats.fromJson(Map<String, dynamic> json) => EeAssetStats(
    months: (json['months'] as num?)?.toInt() ?? 12,
    ticketCount: (json['ticketCount'] as num?)?.toInt() ?? 0,
    openTicketCount: (json['openTicketCount'] as num?)?.toInt() ?? 0,
    openMinutes: (json['openMinutes'] as num?)?.toInt() ?? 0,
    purchaseCostMinor: (json['purchaseCostMinor'] as num?)?.toInt(),
    currency: json['currency'] as String?,
  );
}

/// A machine's card: what it is, and what keeps happening to it.
class EeAssetHistory {
  const EeAssetHistory({required this.stats, this.tickets = const []});

  final List<EeAssetTicket> tickets;
  final EeAssetStats stats;
}

/// The type vocabulary: the built-in keys plus whatever the team wrote down.
class EeAssetTypes {
  const EeAssetTypes({this.builtIn = const [], this.team = const {}});

  final List<String> builtIn;

  /// key → label, the team's own.
  final Map<String, String> team;

  List<String> get all => [...builtIn, ...team.keys];

  factory EeAssetTypes.fromJson(Map<String, dynamic> json) => EeAssetTypes(
    builtIn: ((json['builtIn'] as List<dynamic>?) ?? const [])
        .cast<String>()
        .toList(growable: false),
    team: {
      for (final row in (json['team'] as List<dynamic>?) ?? const [])
        (row as Map<String, dynamic>)['key'] as String: row['label'] as String,
    },
  );
}
