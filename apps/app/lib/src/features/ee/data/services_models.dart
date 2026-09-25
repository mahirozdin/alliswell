import 'new_ticket_api.dart' show EeFormCondition, EeFormField;

/// The service catalogue, client side (EE-082).
///
/// A service is "what can I ask this company for"; `unitIds` is "and who
/// answers it". The client models the pair together because the screen's most
/// important state is the one where the second is EMPTY: a service routed
/// nowhere accepts no request at all, and that is invisible unless the row
/// says so.
class EeService {
  const EeService({
    required this.id,
    required this.name,
    this.description,
    this.archived = false,
    this.unitIds = const [],
    this.formFields = const [],
    this.categoryId,
    this.icon,
    this.approvalMode = 'none',
    this.approverRoleKey,
    this.approverUserIds = const [],
    this.formVersion = 0,
    this.processType = 'request',
  });

  factory EeService.fromJson(Map<String, dynamic> json) => EeService(
    id: json['id'] as String,
    name: json['name'] as String,
    description: json['description'] as String?,
    archived: (json['archived'] as bool?) ?? false,
    unitIds: ((json['unitIds'] as List?) ?? const []).cast<String>(),
    categoryId: json['categoryId'] as String?,
    icon: json['icon'] as String?,
    approvalMode: (json['approvalMode'] as String?) ?? 'none',
    approverRoleKey: json['approverRoleKey'] as String?,
    approverUserIds: ((json['approverUserIds'] as List?) ?? const [])
        .cast<String>(),
    formVersion: (json['formVersion'] as num?)?.toInt() ?? 0,
    processType: (json['processType'] as String?) ?? 'request',
    formFields:
        (((json['formSchema'] as Map<String, dynamic>?)?['fields'] as List?) ??
                const [])
            .map((f) => EeServiceField.fromJson(f as Map<String, dynamic>))
            .toList(),
  );

  final String id;
  final String name;
  final String? description;
  final bool archived;

  /// Which units answer it. Plural because madde 8 says plural: "elektrik
  /// arızası" is answered by maintenance on the shop floor and by facilities
  /// in the office building.
  final List<String> unitIds;

  /// The extra questions this service's form asks. Flattened out of the
  /// server's `formSchema.fields` because the wrapper object carries nothing
  /// else — reproducing it here would be a level of nesting no widget needs.
  final List<EeServiceField> formFields;

  /// The shelf it sits on (EE-212, EE-228); null is the catalogue's root.
  final String? categoryId;

  /// A token from the server's closed set (`kServiceIconTokens`), or null.
  final String? icon;

  /// EE-185's rule: `none | manager | role | users` — the server's words.
  final String approvalMode;

  /// A role name or custom-role id: the approver for `role`, the FALLBACK
  /// for `manager` (a portal submission has no manager to ask).
  final String? approverRoleKey;

  /// The named people, for `users`.
  final List<String> approverUserIds;

  /// The form version in force (EE-214): every publish is the next number,
  /// and a request answered against an older one keeps it. 0 = never set.
  final int formVersion;

  /// EE-268: `incident | request` — the kind of work a request filed here is.
  /// A request copies it when it is opened; changing it moves no past work.
  final String processType;

  /// The state worth drawing loudly: live, but reaching nobody.
  bool get unroutable => !archived && unitIds.isEmpty;

  Map<String, dynamic>? get formSchemaJson => formFields.isEmpty
      ? null
      : {'fields': formFields.map((f) => f.toJson()).toList()};
}

/// One custom field on a service's request form.
///
/// The type list is closed and mirrors the server's, deliberately: the server
/// refuses anything else, so a client that offered a sixth type would be
/// drawing a control whose save always fails.
class EeServiceField {
  const EeServiceField({
    required this.key,
    required this.label,
    required this.type,
    this.required = false,
    this.options = const [],
    this.help,
    this.showIf,
  });

  // EE-246: `help` and `showIf` (EE-214) are READ — and written back below.
  // Until then this model knew five properties of seven, so an admin who
  // touched a form in the app stripped every help text and every condition
  // on save, silently, from every field.
  factory EeServiceField.fromJson(Map<String, dynamic> json) => EeServiceField(
    key: json['key'] as String,
    label: json['label'] as String,
    type: json['type'] as String,
    required: (json['required'] as bool?) ?? false,
    options: ((json['options'] as List?) ?? const []).cast<String>(),
    help: json['help'] as String?,
    showIf: json['showIf'] == null
        ? null
        : EeFormCondition.fromJson(json['showIf'] as Map<String, dynamic>),
  );

  static const List<String> types = [
    'text',
    'number',
    'date',
    'checkbox',
    'select',
  ];

  final String key;
  final String label;
  final String type;
  final bool required;
  final List<String> options;

  /// The sentence under the label (EE-214, at most 200 characters).
  final String? help;

  /// Shown only when an EARLIER field was answered with a value (EE-214).
  final EeFormCondition? showIf;

  EeServiceField copyWith({
    String? label,
    String? type,
    bool? required,
    List<String>? options,
    String? help,
    bool clearHelp = false,
    EeFormCondition? showIf,
    bool clearShowIf = false,
  }) => EeServiceField(
    key: key,
    label: label ?? this.label,
    type: type ?? this.type,
    required: required ?? this.required,
    options: options ?? this.options,
    help: clearHelp ? null : (help ?? this.help),
    showIf: clearShowIf ? null : (showIf ?? this.showIf),
  );

  /// The same question as the person filing reads it — what the designer's
  /// preview draws (EE-229), through the request form's own renderer.
  EeFormField toFormField() => EeFormField(
    key: key,
    label: label,
    type: type,
    required: required,
    options: options,
    help: help,
    showIf: showIf,
  );

  Map<String, dynamic> toJson() => {
    'key': key,
    'label': label,
    'type': type,
    if (required) 'required': true,
    // Only a select may carry options — the server rejects them anywhere else,
    // so sending an empty list on a text field would fail the save.
    if (type == 'select') 'options': options,
    if (help != null && help!.trim().isNotEmpty) 'help': help!.trim(),
    if (showIf != null)
      'showIf': {'key': showIf!.key, 'equals': showIf!.equals},
  };
}

/// EE-185 — the approval modes, in the server's words and order.
///
/// Mirrored for the same reason `EeServiceField.types` is: the server
/// refuses anything else, so a sheet offering a fifth mode would offer a
/// save that always fails.
const kServiceApprovalModes = ['none', 'manager', 'role', 'users'];

/// A shelf of the catalogue (EE-212): two levels, never three.
class EeServiceCategory {
  const EeServiceCategory({
    required this.id,
    required this.name,
    this.parentId,
    this.icon,
    this.position = 0,
  });

  factory EeServiceCategory.fromJson(Map<String, dynamic> json) =>
      EeServiceCategory(
        id: json['id'] as String,
        name: json['name'] as String,
        parentId: json['parentId'] as String?,
        icon: json['icon'] as String?,
        position: (json['position'] as num?)?.toInt() ?? 0,
      );

  final String id;
  final String name;

  /// Null for a top shelf; a top shelf's id for a sub-shelf.
  final String? parentId;
  final String? icon;
  final int position;

  bool get isRoot => parentId == null;
}
