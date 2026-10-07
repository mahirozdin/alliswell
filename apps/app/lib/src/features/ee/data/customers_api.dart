import 'package:dio/dio.dart';

import '../../../core/api_exception.dart';

/// A company the team serves (EE-209), as the admin screen reads it.
class EeCustomer {
  const EeCustomer({
    required this.id,
    required this.name,
    this.archived = false,
  });

  factory EeCustomer.fromJson(Map<String, dynamic> json) => EeCustomer(
    id: json['id'] as String,
    name: json['name'] as String,
    archived: json['archived'] == true,
  );

  final String id;
  final String name;

  /// Archived: its contacts can no longer sign in or open requests; its open
  /// requests stay on the desk (EE-300).
  final bool archived;
}

/// One person at a company who signs in to the company portal.
class EeCustomerContact {
  const EeCustomerContact({
    required this.id,
    required this.email,
    this.displayName,
    this.deactivated = false,
    this.invitePending = false,
    this.lastSeenAt,
  });

  factory EeCustomerContact.fromJson(Map<String, dynamic> json) =>
      EeCustomerContact(
        id: json['id'] as String,
        email: json['email'] as String,
        displayName: json['displayName'] as String?,
        deactivated: json['status'] == 'deactivated',
        invitePending: json['invitePending'] == true,
        lastSeenAt: json['lastSeenAt'] == null
            ? null
            : DateTime.parse(json['lastSeenAt'] as String).toLocal(),
      );

  final String id;
  final String email;
  final String? displayName;
  final bool deactivated;

  /// An invitation is out and unused — not "has a password", which only the
  /// sign-in door may answer.
  final bool invitePending;
  final DateTime? lastSeenAt;

  String get label => (displayName == null || displayName!.trim().isEmpty)
      ? email
      : displayName!;
}

/// One page of a company's contacts, and the cursor that continues it.
class EeCustomerContactsPage {
  const EeCustomerContactsPage({required this.contacts, this.nextCursor});

  final List<EeCustomerContact> contacts;
  final String? nextCursor;
}

/// The invitation link, which exists exactly once — the server keeps a
/// digest (the public-link rule).
class EeCustomerInvite {
  const EeCustomerInvite({required this.url, required this.expiresAt});

  final String url;
  final DateTime expiresAt;
}

/// The company doors (OPH-360, UI-AUDIT #18) — all behind `customers.manage`.
///
/// The four EE-300 added (contacts list, rename/archive, deactivate,
/// reactivate) do not exist on an older server: there the route is missing
/// and the answer is a CODELESS 404, which [isUnsupported] tells apart from a
/// coded `CUSTOMER_NOT_FOUND` (the company is gone).
class EeCustomersApi {
  const EeCustomersApi(this._dio);
  final Dio _dio;

  static const _base = '/api/v1/ee/team/customers';

  /// Null on 403/404: not this person's to manage, or no team here.
  Future<List<EeCustomer>?> list() async {
    try {
      final res = await _dio.get<Map<String, dynamic>>(_base);
      return [
        for (final row
            in ((res.data?['customers'] as List<dynamic>?) ?? const [])
                .whereType<Map<String, dynamic>>())
          EeCustomer.fromJson(row),
      ];
    } on DioException catch (e) {
      final code = e.response?.statusCode;
      if (code == 403 || code == 404) return null;
      throw asApiException(e);
    }
  }

  Future<void> create(String name) =>
      _run(() => _dio.post<Map<String, dynamic>>(_base, data: {'name': name}));

  Future<void> update(String customerId, {String? name, bool? archived}) =>
      _run(
        () => _dio.patch<Map<String, dynamic>>(
          '$_base/$customerId',
          data: {'name': ?name, 'archived': ?archived},
        ),
      );

  Future<EeCustomerContactsPage> contacts(
    String customerId, {
    String? cursor,
  }) async {
    try {
      final res = await _dio.get<Map<String, dynamic>>(
        '$_base/$customerId/users',
        queryParameters: {'limit': 50, 'cursor': ?cursor},
      );
      return EeCustomerContactsPage(
        contacts: [
          for (final row
              in ((res.data?['users'] as List<dynamic>?) ?? const [])
                  .whereType<Map<String, dynamic>>())
            EeCustomerContact.fromJson(row),
        ],
        nextCursor: res.data?['nextCursor'] as String?,
      );
    } on DioException catch (e) {
      throw asApiException(e);
    }
  }

  /// Adds a contact (no password: an invitation follows). A deactivated
  /// address answers 409 `CUSTOMER_USER_DEACTIVATED` with the contact's id,
  /// returned here as [EeContactDeactivated] so the screen can offer to
  /// reactivate rather than say "already exists".
  Future<String> addContact(
    String customerId, {
    required String email,
    String? displayName,
  }) async {
    try {
      final res = await _dio.post<Map<String, dynamic>>(
        '$_base/$customerId/users',
        data: {
          'email': email,
          if (displayName != null && displayName.isNotEmpty)
            'displayName': displayName,
        },
      );
      return res.data?['id'] as String;
    } on DioException catch (e) {
      final data = e.response?.data;
      if (data is Map &&
          data['code'] == 'CUSTOMER_USER_DEACTIVATED' &&
          data['customerUserId'] is String) {
        throw EeContactDeactivated(data['customerUserId'] as String);
      }
      throw asApiException(e);
    }
  }

  Future<EeCustomerInvite> invite(String customerUserId) async {
    try {
      final res = await _dio.post<Map<String, dynamic>>(
        '$_base/users/$customerUserId/invite',
      );
      return EeCustomerInvite(
        url: res.data?['url'] as String,
        expiresAt: DateTime.parse(res.data?['expiresAt'] as String).toLocal(),
      );
    } on DioException catch (e) {
      throw asApiException(e);
    }
  }

  Future<void> setDeactivated(String customerUserId, {required bool off}) =>
      _run(
        () => _dio.post<Map<String, dynamic>>(
          '$_base/users/$customerUserId/${off ? 'deactivate' : 'reactivate'}',
        ),
      );

  Future<void> _run(Future<Object?> Function() call) async {
    try {
      await call();
    } on DioException catch (e) {
      throw asApiException(e);
    }
  }
}

/// The address belongs to a contact that was switched off.
class EeContactDeactivated implements Exception {
  const EeContactDeactivated(this.customerUserId);
  final String customerUserId;
}

/// A codeless 404 — the route is not on this server (older than EE-300).
bool isUnsupported(Object? error) =>
    error is ApiException && error.code == 'HTTP_404';
