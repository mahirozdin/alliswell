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
  });

  factory EeServiceField.fromJson(Map<String, dynamic> json) => EeServiceField(
    key: json['key'] as String,
    label: json['label'] as String,
    type: json['type'] as String,
    required: (json['required'] as bool?) ?? false,
    options: ((json['options'] as List?) ?? const []).cast<String>(),
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

  Map<String, dynamic> toJson() => {
    'key': key,
    'label': label,
    'type': type,
    if (required) 'required': true,
    // Only a select may carry options — the server rejects them anywhere else,
    // so sending an empty list on a text field would fail the save.
    if (type == 'select') 'options': options,
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
