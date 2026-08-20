import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:alliswell/src/features/ee/data/team_admin_api.dart';
import 'package:alliswell/src/features/ee/data/team_admin_models.dart';
import 'package:alliswell/src/features/ee/data/ee_models.dart';
import 'package:alliswell/src/features/ee/providers.dart';
import 'package:alliswell/src/features/ee/team_admin_providers.dart';
import 'package:alliswell/src/features/ee/ui/team_invites_screen.dart';
import 'package:alliswell/src/features/ee/ui/team_members_screen.dart';
import 'package:alliswell/src/i18n/i18n.dart';
import 'package:alliswell/src/theme/theme.dart';

/// EE-042 — the team-admin screens. What is pinned here is the behaviour that
/// would be easy to lose in a redesign: a deactivated member stays visible, a
/// removal explains itself before it happens, and the two halves of an
/// invitation are never offered together.

EeTeamMember member({
  String id = 'U1',
  String name = 'Cem Üye',
  String role = 'member',
  bool active = true,
}) => EeTeamMember(
  userId: id,
  role: role,
  active: active,
  email: '${id.toLowerCase()}@example.com',
  displayName: name,
  initials: 'CÜ',
  colorRgb: '#16A34A',
);

class FakeApi implements EeTeamAdminApi {
  FakeApi({
    EeSeats? seats,
    List<EeTeamMember>? members,
    List<EeInvite>? invites,
  }) : _seats = seats ?? const EeSeats(used: 3, max: 10),
       _members = members ?? [member()],
       _invites = invites ?? [];

  EeSeats _seats;
  List<EeTeamMember> _members;
  List<EeInvite> _invites;
  final List<String> calls = [];
  EeMintedInvite? nextMint;

  @override
  Future<EeTeamInfo?> info() async => const EeTeamInfo(
    id: 'T1',
    name: 'Acme',
    slug: 'acme',
    status: 'active',
    myRole: 'owner',
  );

  @override
  Future<EeTeamRoster> members() async =>
      EeTeamRoster(members: _members, seats: _seats);

  @override
  Future<void> setRole({required String userId, required String role}) async {
    calls.add('role:$userId:$role');
    _members = _members
        .map(
          (m) => m.userId == userId
              ? member(
                  id: m.userId,
                  name: m.displayName ?? '',
                  role: role,
                  active: m.active,
                )
              : m,
        )
        .toList();
  }

  @override
  Future<void> deactivate(String userId) async {
    calls.add('deactivate:$userId');
    _members = _members
        .map(
          (m) => m.userId == userId
              ? member(
                  id: m.userId,
                  name: m.displayName ?? '',
                  role: m.role,
                  active: false,
                )
              : m,
        )
        .toList();
    _seats = EeSeats(used: _seats.used - 1, max: _seats.max);
  }

  @override
  Future<void> reactivate(String userId) async {
    calls.add('reactivate:$userId');
  }

  @override
  Future<void> remove(String userId) async {
    calls.add('remove:$userId');
    _members = _members.where((m) => m.userId != userId).toList();
  }

  @override
  Future<List<EeInvite>> invites() async => _invites;

  @override
  Future<EeMintedInvite> invite({
    required String email,
    String role = 'member',
  }) async {
    calls.add('invite:$email:$role');
    final minted =
        nextMint ??
        EeMintedInvite(
          invite: EeInvite(
            id: 'I1',
            email: email,
            role: role,
            state: 'pending',
            expiresAt: '2026-08-21T00:00:00.000Z',
          ),
          token: 'TOKEN123456789012345',
          code: '420913',
          link: 'https://acme.example.com/join/TOKEN123456789012345',
          delivery: 'mail',
        );
    _invites = [minted.invite, ..._invites];
    return minted;
  }

  @override
  Future<void> revokeInvite(String inviteId) async {
    calls.add('revoke:$inviteId');
    _invites = _invites.where((i) => i.id != inviteId).toList();
  }
}

Widget harness(FakeApi api, Widget child) => ProviderScope(
  overrides: [eeTeamAdminApiProvider.overrideWithValue(api)],
  child: MaterialApp(theme: buildAwTheme(Brightness.light), home: child),
);

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    AwI18n.instance.setActiveCached(const Locale('en'));
  });

  group('members', () {
    testWidgets(
      'the seat banner is always there, and says which problem it is',
      (tester) async {
        await tester.pumpWidget(
          harness(
            FakeApi(
              seats: const EeSeats(
                used: 12,
                max: 10,
                exceeded: true,
                canAdd: false,
              ),
            ),
            const EeTeamMembersScreen(),
          ),
        );
        await tester.pumpAndSettle();

        expect(find.byKey(const Key('team-seat-banner')), findsOneWidget);
        expect(find.text('12 of 10 seats used'), findsOneWidget);
        // "Over the plan" is a billing conversation; "cannot add one more" is a
        // blocked action. Telling somebody the wrong one wastes an afternoon.
        expect(find.textContaining('Nobody loses access'), findsOneWidget);
      },
    );

    testWidgets('a deactivated member stays on the list, dimmed and labelled', (
      tester,
    ) async {
      // Hiding them would make "where did Cem go?" unanswerable in the one
      // place built to answer it.
      await tester.pumpWidget(
        harness(
          FakeApi(members: [member(active: false)]),
          const EeTeamMembersScreen(),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Cem Üye'), findsOneWidget);
      expect(find.textContaining('deactivated'), findsOneWidget);
    });

    testWidgets('deactivating goes through and the roster is re-read', (
      tester,
    ) async {
      final api = FakeApi();
      await tester.pumpWidget(harness(api, const EeTeamMembersScreen()));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('member-menu-U1')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Deactivate'));
      await tester.pumpAndSettle();

      expect(api.calls, ['deactivate:U1']);
      // Re-read, not patched in place: the server may have adjusted the seat
      // count, and it did.
      expect(find.text('2 of 10 seats used'), findsOneWidget);
      expect(find.textContaining('deactivated'), findsOneWidget);
    });

    testWidgets(
      'removal explains itself before it happens, and can be refused',
      (tester) async {
        final api = FakeApi();
        await tester.pumpWidget(harness(api, const EeTeamMembersScreen()));
        await tester.pumpAndSettle();

        await tester.tap(find.byKey(const Key('member-menu-U1')));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Remove'));
        await tester.pumpAndSettle();

        // The sentence has to carry the two facts that matter: it is not
        // undoable, and there is a reversible option right next to it.
        expect(find.textContaining('needs a new invitation'), findsOneWidget);
        expect(find.textContaining('deactivate them instead'), findsOneWidget);

        await tester.tap(find.text('Cancel'));
        await tester.pumpAndSettle();
        expect(api.calls, isEmpty); // refused means nothing happened

        await tester.tap(find.byKey(const Key('member-menu-U1')));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Remove'));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('member-remove-confirm')));
        await tester.pumpAndSettle();
        expect(api.calls, ['remove:U1']);
      },
    );
  });

  group('invitations', () {
    testWidgets('an empty list says what to do, not just that it is empty', (
      tester,
    ) async {
      await tester.pumpWidget(harness(FakeApi(), const EeTeamInvitesScreen()));
      await tester.pumpAndSettle();
      expect(find.text('No invitations yet'), findsOneWidget);
      expect(find.textContaining('a link and a separate code'), findsOneWidget);
    });

    testWidgets('the link and the code are shown apart, and copied apart', (
      tester,
    ) async {
      final api = FakeApi();
      await tester.pumpWidget(harness(api, const EeTeamInvitesScreen()));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('invite-create')));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const Key('invite-email')),
        'yeni@example.com',
      );
      await tester.tap(find.byKey(const Key('invite-submit')));
      await tester.pumpAndSettle();

      expect(api.calls, ['invite:yeni@example.com:member']);
      expect(find.byKey(const Key('invite-credential')), findsOneWidget);
      expect(find.text('420913'), findsOneWidget);
      expect(find.textContaining('/join/TOKEN123456789012345'), findsOneWidget);

      // Two buttons, never one. A single "copy both" would put a working
      // credential on the clipboard and undo the reason there are two halves.
      expect(find.byKey(const Key('invite-copy-link')), findsOneWidget);
      expect(find.byKey(const Key('invite-copy-code')), findsOneWidget);
      expect(find.textContaining('different routes'), findsOneWidget);
    });

    testWidgets(
      'a server that sends no mail says so instead of implying delivery',
      (tester) async {
        final api = FakeApi()
          ..nextMint = EeMintedInvite(
            invite: const EeInvite(
              id: 'I2',
              email: 'yeni@example.com',
              role: 'member',
              state: 'pending',
              expiresAt: '2026-08-21T00:00:00.000Z',
            ),
            token: 'T',
            code: '000111',
            link: 'https://acme.example.com/join/T',
            delivery: 'manual',
          );
        await tester.pumpWidget(harness(api, const EeTeamInvitesScreen()));
        await tester.pumpAndSettle();

        await tester.tap(find.byKey(const Key('invite-create')));
        await tester.pumpAndSettle();
        await tester.enterText(
          find.byKey(const Key('invite-email')),
          'yeni@example.com',
        );
        await tester.tap(find.byKey(const Key('invite-submit')));
        await tester.pumpAndSettle();

        // On this instance the admin IS the delivery mechanism, and has to be
        // told rather than left waiting for an e-mail nobody will send.
        expect(find.textContaining('sends no e-mail'), findsOneWidget);
      },
    );

    testWidgets('a dead invitation cannot be revoked twice', (tester) async {
      final api = FakeApi(
        invites: [
          const EeInvite(
            id: 'I3',
            email: 'gitti@example.com',
            role: 'member',
            state: 'revoked',
            expiresAt: '2026-08-21T00:00:00.000Z',
          ),
        ],
      );
      await tester.pumpWidget(harness(api, const EeTeamInvitesScreen()));
      await tester.pumpAndSettle();

      expect(find.textContaining('cancelled'), findsOneWidget);
      expect(find.byKey(const Key('invite-revoke-I3')), findsNothing);
    });
  });

  group('the Settings group is gated on BOTH halves', () {
    /// Drives the provider the Settings index actually asks. The entitlement
    /// is awaited FIRST on purpose: on a cold start the team read runs before
    /// the status arrives and answers null, then re-runs when it does — so a
    /// test that skips the wait would pass for the wrong reason.
    Future<bool> gate({required bool entitled, required String? role}) async {
      final container = ProviderContainer(
        overrides: [
          eeStatusProvider.overrideWith(
            () => _FixedStatus(
              entitled
                  ? const EeStatus(state: 'active', features: ['teams'])
                  : EeStatus.none,
            ),
          ),
          eeTeamAdminApiProvider.overrideWithValue(_RoleApi(role)),
        ],
      );
      addTearDown(container.dispose);
      await container.read(eeStatusProvider.future);
      await container.read(eeTeamProvider.future);
      return container.read(eeTeamAdminProvider);
    }

    test('no entitlement, no group — whatever the role says', () async {
      // The house idiom: without the entitlement the endpoints do not exist,
      // so neither does the row that would lead to them.
      expect(await gate(entitled: false, role: 'owner'), isFalse);
    });

    test('entitled but only a member: still no group', () async {
      // A member who sees an admin group and meets a 403 behind it has been
      // told a small lie by their own app.
      expect(await gate(entitled: true, role: 'member'), isFalse);
    });

    test('entitled, but no team at this address: no group', () async {
      expect(await gate(entitled: true, role: null), isFalse);
    });

    test('entitled and an admin: the group exists', () async {
      expect(await gate(entitled: true, role: 'admin'), isTrue);
      expect(await gate(entitled: true, role: 'owner'), isTrue);
    });
  });
}

class _FixedStatus extends EeStatusController {
  _FixedStatus(this._status);
  final EeStatus _status;
  @override
  Future<EeStatus> build() async => _status;
}

/// Answers one question — what role does the caller hold — and refuses the
/// rest, so a gate test cannot accidentally depend on anything else.
class _RoleApi extends FakeApi {
  _RoleApi(this._role);
  final String? _role;

  @override
  Future<EeTeamInfo?> info() async => _role == null
      ? null
      : EeTeamInfo(
          id: 'T1',
          name: 'Acme',
          slug: 'acme',
          status: 'active',
          myRole: _role,
        );
}
