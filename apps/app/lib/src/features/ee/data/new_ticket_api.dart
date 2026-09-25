import 'package:dio/dio.dart';

import '../../../core/api_exception.dart';

/// One shelf of the catalogue (EE-212) — for grouping, nothing more.
class EeCatalogCategory {
  const EeCatalogCategory({
    required this.id,
    required this.name,
    this.parentId,
    this.position = 0,
  });

  factory EeCatalogCategory.fromJson(Map<String, dynamic> json) =>
      EeCatalogCategory(
        id: json['id'] as String,
        name: json['name'] as String,
        parentId: json['parentId'] as String?,
        position: (json['position'] as num?)?.toInt() ?? 0,
      );

  final String id;
  final String name;
  final String? parentId;
  final int position;
}

/// "Show this field when that one was answered with that value" (EE-214).
class EeFormCondition {
  const EeFormCondition({required this.key, required this.equals});

  factory EeFormCondition.fromJson(Map<String, dynamic> json) =>
      EeFormCondition(
        key: json['key'] as String,
        equals: json['equals'] as String,
      );

  final String key;
  final String equals;
}

/// One question a service's form asks — the requester's view of it.
///
/// Not `EeServiceField`: that one is the ADMIN's model and writes the schema
/// back (EE-246 taught it to keep `help` and `showIf`, which it used to drop
/// on every save); this one only reads. The designer's preview converts one
/// into the other (`toFormField`), so both screens draw the same question.
class EeFormField {
  const EeFormField({
    required this.key,
    required this.label,
    required this.type,
    this.required = false,
    this.options = const [],
    this.help,
    this.showIf,
  });

  factory EeFormField.fromJson(Map<String, dynamic> json) => EeFormField(
    key: json['key'] as String,
    label: json['label'] as String,
    type: json['type'] as String,
    required: json['required'] == true,
    options: ((json['options'] as List?) ?? const []).cast<String>(),
    help: json['help'] as String?,
    showIf: json['showIf'] == null
        ? null
        : EeFormCondition.fromJson(json['showIf'] as Map<String, dynamic>),
  );

  final String key;
  final String label;

  /// text · number · date · checkbox · select — the server's closed list.
  final String type;
  final bool required;
  final List<String> options;
  final String? help;
  final EeFormCondition? showIf;
}

/// A unit that answers a service, named so a person can pick one.
class EeCatalogUnit {
  const EeCatalogUnit({required this.id, required this.name});

  factory EeCatalogUnit.fromJson(Map<String, dynamic> json) =>
      EeCatalogUnit(id: json['id'] as String, name: json['name'] as String);

  final String id;
  final String name;
}

/// What a person may ask this desk for (EE-225) — only what the door accepts.
class EeCatalogService {
  const EeCatalogService({
    required this.id,
    required this.name,
    this.description,
    this.categoryId,
    this.icon,
    this.formVersion = 0,
    this.fields = const [],
    this.units = const [],
    this.needsApproval = false,
  });

  factory EeCatalogService.fromJson(Map<String, dynamic> json) =>
      EeCatalogService(
        id: json['id'] as String,
        name: json['name'] as String,
        description: json['description'] as String?,
        categoryId: json['categoryId'] as String?,
        icon: json['icon'] as String?,
        formVersion: (json['formVersion'] as num?)?.toInt() ?? 0,
        fields: [
          for (final field
              in ((json['fields'] as List?) ?? const [])
                  .cast<Map<String, dynamic>>())
            EeFormField.fromJson(field),
        ],
        units: [
          for (final unit
              in ((json['units'] as List?) ?? const [])
                  .cast<Map<String, dynamic>>())
            EeCatalogUnit.fromJson(unit),
        ],
        needsApproval: json['needsApproval'] == true,
      );

  final String id;
  final String name;
  final String? description;
  final String? categoryId;

  /// The desk's icon token (EE-212) — the catalogue always sent it; the app
  /// read it from EE-228 on.
  final String? icon;

  /// The form version in force — what the answers are given against.
  final int formVersion;
  final List<EeFormField> fields;

  /// More than one: the person picks, because the door refuses to guess.
  final List<EeCatalogUnit> units;
  final bool needsApproval;
}

class EeCatalog {
  const EeCatalog({this.categories = const [], this.services = const []});

  factory EeCatalog.fromJson(Map<String, dynamic> json) => EeCatalog(
    categories: [
      for (final row
          in ((json['categories'] as List?) ?? const [])
              .cast<Map<String, dynamic>>())
        EeCatalogCategory.fromJson(row),
    ],
    services: [
      for (final row
          in ((json['services'] as List?) ?? const [])
              .cast<Map<String, dynamic>>())
        EeCatalogService.fromJson(row),
    ],
  );

  final List<EeCatalogCategory> categories;
  final List<EeCatalogService> services;
}

/// Which of a form's fields the answers so far make visible (EE-214).
///
/// The SERVER's rule, restated because a form that reacts as somebody types
/// has to evaluate it on the device: `visibleFields` in the overlay's
/// `services.js` — a field whose condition names an unanswered question is
/// hidden, and values compare as strings. The server keeps the last word: it
/// stores only what the service's schema names.
List<EeFormField> visibleFormFields(
  List<EeFormField> fields,
  Map<String, Object?> answers,
) => [
  for (final field in fields)
    if (field.showIf == null ||
        '${answers[field.showIf!.key] ?? ''}' == field.showIf!.equals)
      field,
];

/// The visible required fields still unanswered — what stops a send.
///
/// The portal's own check, restated (`public-routes.js`): a required field
/// is missing when its answer is empty, and a checkbox never is — unticked is
/// an answer.
List<EeFormField> missingRequiredFields(
  List<EeFormField> fields,
  Map<String, Object?> answers,
) => [
  for (final field in visibleFormFields(fields, answers))
    if (field.required &&
        field.type != 'checkbox' &&
        _blank(answers[field.key]))
      field,
];

bool _blank(Object? value) => value == null || '$value'.trim().isEmpty;

/// Filing a request from the app (EE-225) — online, through the one door
/// every other surface uses (`POST /tickets`). Offline, the screen writes a
/// draft instead (EE-216); nothing here queues.
class EeNewTicketApi {
  const EeNewTicketApi(this._dio);
  final Dio _dio;

  /// The catalogue, or null when this person has none to read (not on a
  /// team, not licensed) — a missing surface, not an error to explain.
  Future<EeCatalog?> catalog() async {
    try {
      final response = await _dio.get<Map<String, dynamic>>(
        '/api/v1/ee/team/catalog',
      );
      final data = response.data;
      return data == null ? null : EeCatalog.fromJson(data);
    } on DioException catch (error) {
      final code = error.response?.statusCode;
      if (code == 403 || code == 404) return null;
      throw asApiException(error);
    }
  }

  /// Files the request and answers its id and number (EE-167: the number is
  /// what a person reads out on the phone). The caller sends only the answers
  /// to VISIBLE fields: a hidden field's old value is not something the
  /// person meant to say.
  Future<({String id, int? number})> create({
    required String serviceId,
    required String subject,
    String? body,
    String? unitId,
    Map<String, Object?> fields = const {},
    String? requesterName,
    String? requesterEmail,
    List<String> openedArticleIds = const [],
    String? assetId,
  }) async {
    try {
      final response = await _dio.post<Map<String, dynamic>>(
        '/api/v1/ee/team/tickets',
        data: {
          'serviceId': serviceId,
          'subject': subject,
          'body': ?body,
          'unitId': ?unitId,
          if (fields.isNotEmpty) 'fields': fields,
          'requesterName': ?requesterName,
          'requesterEmail': ?requesterEmail,
          // EE-226: answers read before asking anyway — the server counts
          // them as suggested AND converted, so reading did not deflect.
          if (openedArticleIds.isNotEmpty) 'openedArticleIds': openedArticleIds,
          // EE-271: the machine it is about, linked by the server in the
          // request's own transaction.
          'assetId': ?assetId,
        },
      );
      final data = response.data ?? const <String, dynamic>{};
      return (
        id: data['id'] as String,
        number: (data['number'] as num?)?.toInt(),
      );
    } on DioException catch (error) {
      throw asApiException(error);
    }
  }
}
