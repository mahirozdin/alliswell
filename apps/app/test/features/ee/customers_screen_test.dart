import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:alliswell/src/core/api_exception.dart';
import 'package:alliswell/src/features/ee/customers_providers.dart';
import 'package:alliswell/src/features/ee/data/customers_api.dart';
import 'package:alliswell/src/features/ee/providers.dart';
import 'package:alliswell/src/features/ee/ui/customers_screen.dart';
import 'package:alliswell/src/i18n/i18n.dart';
import 'package:alliswell/src/theme/theme.dart';

/// OPH-360 (UI-AUDIT #18) — the companies and their people.
///
/// The finding was that access, once given, could not be taken back from the
/// app: no list of a company's contacts, no switch, no archive. What is
/// pinned here is that each of those exists, that the two acts which shut
/// somebody out ASK first, that a member without `customers.manage` is
/// offered none of it, and that an older server — one without the EE-300
/// doors — is said to be older rather than drawn as an empty company.
class _FakeCustomersApi extends EeCustomersApi {
  _FakeCustomersApi() : super(Dio());

  List<EeCustomer> companies = const [
    EeCustomer(id: 'C1', name: 'Demir Çelik'),
    EeCustomer(id: 'C2', name: 'Eski Firma', archived: true),
  ];
  List<EeCustomerContact> people = const [
    EeCustomerContact(
      id: 'P1',
      email: 'ayse@demir.example',
      displayName: 'Ayşe Kaya',
    ),
    EeCustomerContact(id: 'P2', email: 'eski@demir.example', deactivated: true),
  ];
  Object? contactsError;
  Object? addError;
  final calls = <String>[];

  @override
  Future<List<EeCustomer>?> list() async => companies;

  @override
  Future<void> create(String name) async => calls.add('create $name');

  @override
  Future<void> update(
    String customerId, {
    String? name,
    bool? archived,
  }) async => calls.add('update $customerId name=$name archived=$archived');

  @override
  Future<EeCustomerContactsPage> contacts(
    String customerId, {
    String? cursor,
  }) async {
    if (contactsError != null) throw contactsError!;
    return EeCustomerContactsPage(contacts: people);
  }

  @override
  Future<String> addContact(
    String customerId, {
    required String email,
    String? displayName,
  }) async {
    calls.add('add $email');
    if (addError != null) throw addError!;
    return 'P9';
  }

  @override
  Future<EeCustomerInvite> invite(String customerUserId) async {
    calls.add('invite $customerUserId');
    return EeCustomerInvite(
      url: 'https://demo.alliswell.test/c/invite/TOKEN',
      expiresAt: DateTime(2026, 10, 14),
    );
  }

  @override
  Future<void> setDeactivated(
    String customerUserId, {
    required bool off,
  }) async => calls.add('${off ? 'deactivate' : 'reactivate'} $customerUserId');
}

late _FakeCustomersApi _api;

Future<void> _pump(
  WidgetTester tester, {
  bool may = true,
  Widget home = const EeCustomersScreen(),
}) async {
  tester.view.physicalSize = const Size(1170, 2532);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        eeCustomersApiProvider.overrideWithValue(_api),
        eeFeatureProvider.overrideWith((ref, name) => true),
        canProvider.overrideWith((ref, id) => may && id == 'customers.manage'),
      ],
      child: MaterialApp(theme: buildAwTheme(Brightness.light), home: home),
    ),
  );
  await tester.pumpAndSettle();
}

const _company = EeCustomer(id: 'C1', name: 'Demir Çelik');

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    AwI18n.instance.setActiveCached(const Locale('en'));
    _api = _FakeCustomersApi();
  });

  group('the companies', () {
    testWidgets('UI-AUDIT #18: companies are listed, archived ones last and '
        'marked in words', (tester) async {
      await _pump(tester);
      expect(find.byKey(const Key('customer-C1')), findsOneWidget);
      expect(find.byKey(const Key('customer-C2')), findsOneWidget);
      expect(find.textContaining('archived'), findsOneWidget);
      expect(
        tester.getTopLeft(find.byKey(const Key('customer-C1'))).dy,
        lessThan(tester.getTopLeft(find.byKey(const Key('customer-C2'))).dy),
      );
    });

    testWidgets('UI-AUDIT #18: archiving asks first and says what stays', (
      tester,
    ) async {
      await _pump(tester);
      await tester.tap(find.byKey(const Key('customer-menu-C1')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Archive'));
      await tester.pumpAndSettle();
      expect(_api.calls, isEmpty);
      expect(find.textContaining('open requests stay'), findsOneWidget);
      await tester.tap(find.byKey(const Key('customer-archive-confirm')));
      await tester.pumpAndSettle();
      expect(_api.calls, ['update C1 name=null archived=true']);
    });

    testWidgets('UI-AUDIT #18: restoring does not ask', (tester) async {
      await _pump(tester);
      await tester.tap(find.byKey(const Key('customer-menu-C2')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Restore'));
      await tester.pumpAndSettle();
      expect(_api.calls, ['update C2 name=null archived=false']);
    });

    testWidgets('UI-AUDIT #18: a company can be added and renamed', (
      tester,
    ) async {
      await _pump(tester);
      await tester.tap(find.byKey(const Key('customer-new')));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const Key('customer-name')),
        'Yeni A.Ş.',
      );
      await tester.pump();
      await tester.tap(find.byKey(const Key('customer-name-save')));
      await tester.pumpAndSettle();
      expect(_api.calls, ['create Yeni A.Ş.']);
      expect(find.byType(AlertDialog), findsNothing);
      await tester.tap(find.byKey(const Key('customer-menu-C1')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Rename'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const Key('customer-rename')),
        'Demir Çelik A.Ş.',
      );
      await tester.pump();
      await tester.tap(find.byKey(const Key('customer-name-save')));
      await tester.pumpAndSettle();
      expect(_api.calls, [
        'create Yeni A.Ş.',
        'update C1 name=Demir Çelik A.Ş. archived=null',
      ]);
    });

    testWidgets('UI-AUDIT #18: without customers.manage nothing is offered', (
      tester,
    ) async {
      await _pump(tester, may: false);
      expect(find.byKey(const Key('customer-new')), findsNothing);
      expect(find.byKey(const Key('customer-menu-C1')), findsNothing);
    });
  });

  group('a company\'s people', () {
    testWidgets('UI-AUDIT #18: each contact says whether they can sign in', (
      tester,
    ) async {
      await _pump(
        tester,
        home: const EeCustomerContactsScreen(customer: _company),
      );
      expect(find.text('Ayşe Kaya'), findsOneWidget);
      expect(find.textContaining('Active'), findsOneWidget);
      expect(find.textContaining('Switched off'), findsOneWidget);
    });

    testWidgets(
      'UI-AUDIT #18: switching somebody off asks first, says their sessions end, then does it',
      (tester) async {
        await _pump(
          tester,
          home: const EeCustomerContactsScreen(customer: _company),
        );
        await tester.tap(find.byKey(const Key('contact-menu-P1')));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Switch off'));
        await tester.pumpAndSettle();
        expect(_api.calls, isEmpty);
        expect(find.textContaining('every session'), findsOneWidget);
        await tester.tap(find.byKey(const Key('contact-deactivate-confirm')));
        await tester.pumpAndSettle();
        expect(_api.calls, ['deactivate P1']);
      },
    );

    testWidgets('UI-AUDIT #18: switching back on does not ask', (tester) async {
      await _pump(
        tester,
        home: const EeCustomerContactsScreen(customer: _company),
      );
      await tester.tap(find.byKey(const Key('contact-menu-P2')));
      await tester.pumpAndSettle();
      // A switched-off contact is not invited.
      expect(find.text('Send invitation'), findsNothing);
      await tester.tap(find.text('Switch back on'));
      await tester.pumpAndSettle();
      expect(_api.calls, ['reactivate P2']);
    });

    testWidgets(
      'UI-AUDIT #18: adding someone sends the invitation and shows its link once',
      (tester) async {
        await _pump(
          tester,
          home: const EeCustomerContactsScreen(customer: _company),
        );
        await tester.tap(find.byKey(const Key('contact-new')));
        await tester.pumpAndSettle();
        await tester.enterText(
          find.byKey(const Key('contact-email')),
          'yeni@demir.example',
        );
        await tester.pump();
        await tester.tap(find.byKey(const Key('contact-add-confirm')));
        await tester.pumpAndSettle();
        expect(_api.calls, ['add yeni@demir.example', 'invite P9']);
        expect(find.byKey(const Key('contact-invite-once')), findsOneWidget);
        expect(find.textContaining('/c/invite/TOKEN'), findsOneWidget);
        await tester.tap(find.text('Done'));
        await tester.pumpAndSettle();
      },
    );

    testWidgets(
      'UI-AUDIT #18: re-adding a switched-off address offers the switch, not "already exists"',
      (tester) async {
        _api.addError = const EeContactDeactivated('P2');
        await _pump(
          tester,
          home: const EeCustomerContactsScreen(customer: _company),
        );
        await tester.tap(find.byKey(const Key('contact-new')));
        await tester.pumpAndSettle();
        await tester.enterText(
          find.byKey(const Key('contact-email')),
          'eski@demir.example',
        );
        await tester.pump();
        await tester.tap(find.byKey(const Key('contact-add-confirm')));
        await tester.pumpAndSettle();
        expect(find.textContaining('switched off here'), findsOneWidget);
        await tester.tap(find.text('Switch back on'));
        await tester.pumpAndSettle();
        expect(_api.calls, ['add eski@demir.example', 'reactivate P2']);
      },
    );

    testWidgets('an archived company takes nobody new', (tester) async {
      await _pump(
        tester,
        home: const EeCustomerContactsScreen(
          customer: EeCustomer(id: 'C2', name: 'Eski Firma', archived: true),
        ),
      );
      expect(find.byKey(const Key('contact-new')), findsNothing);
      expect(find.byKey(const Key('customer-archived-note')), findsOneWidget);
    });

    testWidgets(
      'UI-AUDIT #18: an older server without the contact doors says so',
      (tester) async {
        _api.contactsError = const ApiException(
          'HTTP_404',
          'Unexpected server response',
          statusCode: 404,
        );
        await _pump(
          tester,
          home: const EeCustomerContactsScreen(customer: _company),
        );
        expect(find.byKey(const Key('contacts-unsupported')), findsOneWidget);
        expect(find.byKey(const Key('contact-new')), findsNothing);
      },
    );

    testWidgets('a coded refusal is an error with a retry, not "unsupported"', (
      tester,
    ) async {
      _api.contactsError = const ApiException(
        'CUSTOMER_NOT_FOUND',
        'Not found',
        statusCode: 404,
      );
      await _pump(
        tester,
        home: const EeCustomerContactsScreen(customer: _company),
      );
      expect(find.byKey(const Key('contacts-unsupported')), findsNothing);
      expect(find.text('common.retry'.tr()), findsOneWidget);
    });

    testWidgets('a member without the verb sees the people and no controls', (
      tester,
    ) async {
      await _pump(
        tester,
        may: false,
        home: const EeCustomerContactsScreen(customer: _company),
      );
      expect(find.text('Ayşe Kaya'), findsOneWidget);
      expect(find.byKey(const Key('contact-menu-P1')), findsNothing);
      expect(find.byKey(const Key('contact-new')), findsNothing);
    });
  });
}
