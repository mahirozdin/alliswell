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
  });

  factory EeService.fromJson(Map<String, dynamic> json) => EeService(
    id: json['id'] as String,
    name: json['name'] as String,
    description: json['description'] as String?,
    archived: (json['archived'] as bool?) ?? false,
    unitIds: ((json['unitIds'] as List?) ?? const []).cast<String>(),
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
