import 'package:drift/drift.dart' show DatabaseConnection;
import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:alliswell/src/features/ee/data/new_ticket_api.dart';
import 'package:alliswell/src/features/ee/new_ticket_providers.dart';
import 'package:alliswell/src/features/ee/ticket_drafts_providers.dart';
import 'package:alliswell/src/features/workspaces/workspaces.dart';
import 'package:alliswell/src/sync/db/database.dart';
import 'package:alliswell/src/sync/providers.dart';
import 'package:alliswell/src/sync/sync_api.dart';

/// EE-225 — the rules under the new-request form, and the courier.
///
/// The form's conditions are the SERVER's (`visibleFields` in the overlay's
/// `services.js`) and its required check is the PORTAL's
/// (`public-routes.js`). They are restated on the device because a form that
/// waited for a round trip to reveal the next question would not be a form —
/// so these cases are the server's own, one for one.
const _fields = [
  EeFormField(
    key: 'line',
    label: 'Hat',
    type: 'select',
    required: true,
    options: ['1', '2'],
  ),
  EeFormField(
    key: 'stopped',
    label: 'Durdu mu',
    type: 'checkbox',
    required: true,
  ),
  EeFormField(
    key: 'since',
    label: 'Ne zamandan beri',
    type: 'date',
    required: true,
    showIf: EeFormCondition(key: 'line', equals: '2'),
  ),
  EeFormField(key: 'note', label: 'Not', type: 'text'),
];

List<String> _keys(List<EeFormField> fields) => [for (final f in fields) f.key];

class _RecordingSyncApi implements SyncApi {
  final pushedFor = <String>[];
  final pulledFor = <String>[];

  @override
  Future<SyncPullPage> pull(
    String workspaceId, {
    required int sinceRevision,
    int? limit,
  }) async {
    pulledFor.add(workspaceId);
    return SyncPullPage(
      fromRevision: sinceRevision,
      toRevision: sinceRevision,
      hasMore: false,
      changes: const [],
    );
  }

  @override
  Future<SyncPushResponse> push({
    required String clientId,
    required String workspaceId,
    required int baseRevision,
    required List<SyncMutation> mutations,
  }) async {
    pushedFor.add(workspaceId);
    return SyncPushResponse(
      toRevision: baseRevision + mutations.length,
      results: [
        for (final (i, m) in mutations.indexed)
          SyncPushResult(
            clientMutationId: m.clientMutationId,
            status: 'applied',
            replayed: false,
            revision: baseRevision + i + 1,
          ),
      ],
    );
  }
}

void main() {
  group('which questions show', () {
    test('a condition on an unanswered question hides the field', () {
      expect(_keys(visibleFormFields(_fields, const {})), [
        'line',
        'stopped',
        'note',
      ]);
    });

    test('the answer it names reveals it — compared as a string', () {
      expect(_keys(visibleFormFields(_fields, const {'line': '2'})), [
        'line',
        'stopped',
        'since',
        'note',
      ]);
      expect(
        _keys(visibleFormFields(_fields, const {'line': '1'})),
        isNot(contains('since')),
      );
    });
  });

  group('what stops a send', () {
    test('an empty required answer does; an unticked checkbox never does', () {
      expect(_keys(missingRequiredFields(_fields, const {})), ['line']);
      expect(
        _keys(missingRequiredFields(_fields, const {'line': '1'})),
        isEmpty,
        reason: '"stopped" is a checkbox: unticked is an answer',
      );
    });

    test('a hidden required field is not missing; a revealed one is', () {
      expect(_keys(missingRequiredFields(_fields, const {'line': '2'})), [
        'since',
      ]);
      expect(
        _keys(
          missingRequiredFields(_fields, const {'line': '2', 'since': ' '}),
        ),
        ['since'],
        reason: 'blank is empty',
      );
      expect(
        missingRequiredFields(_fields, const {
          'line': '2',
          'since': '2026-09-24',
        }),
        isEmpty,
      );
    });
  });

  test(
    'the catalogue parses the server shape, conditions and units included',
    () {
      final catalog = EeCatalog.fromJson({
        'categories': [
          {'id': 'C1', 'parentId': null, 'name': 'Arızalar', 'position': 0},
        ],
        'services': [
          {
            'id': 'S1',
            'name': 'Pres arızası',
            'description': null,
            'categoryId': 'C1',
            'formVersion': 3,
            'fields': [
              {
                'key': 'since',
                'label': 'Ne zamandan beri',
                'type': 'date',
                'required': false,
                'options': <String>[],
                'help': 'Yaklaşık yeter',
                'showIf': {'key': 'line', 'equals': '2'},
              },
            ],
            'units': [
              {'id': 'U1', 'name': 'Bakım'},
              {'id': 'U2', 'name': 'Tesis'},
            ],
            'needsApproval': true,
          },
        ],
      });
      final service = catalog.services.single;
      expect(service.formVersion, 3);
      expect(service.fields.single.showIf?.equals, '2');
      expect(service.fields.single.help, 'Yaklaşık yeter');
      expect([for (final u in service.units) u.name], ['Bakım', 'Tesis']);
      expect(service.needsApproval, isTrue);
      expect(catalog.categories.single.name, 'Arızalar');
    },
  );

  group('the courier', () {
    late AwDatabase db;
    late _RecordingSyncApi api;

    ProviderContainer containerFor({required String current}) {
      final container = ProviderContainer(
        overrides: [
          databaseProvider.overrideWithValue(db),
          syncApiProvider.overrideWithValue(api),
          syncPullIntervalProvider.overrideWithValue(null),
          syncDebounceProvider.overrideWithValue(Duration.zero),
          workspacesProvider.overrideWith(
            (ref) async => const [
              WorkspaceSummary(
                id: 'W-OWN',
                name: 'Barış',
                slug: 'baris',
                colorRgb: '#2563EB',
                role: 'owner',
              ),
              WorkspaceSummary(
                id: 'W-UNIT',
                name: 'Bakım',
                slug: 'bakim',
                colorRgb: '#2563EB',
                role: 'member',
              ),
            ],
          ),
          selectedWorkspaceIdProvider.overrideWith(() => _Selected(current)),
        ],
      );
      addTearDown(container.dispose);
      return container;
    }

    setUp(() {
      db = AwDatabase(DatabaseConnection(NativeDatabase.memory()));
      api = _RecordingSyncApi();
    });
    tearDown(() => db.close());

    test(
      "the person's own space is where drafts go — the owner workspace",
      () async {
        final container = containerFor(current: 'W-UNIT');
        await container.read(workspacesProvider.future);
        expect(container.read(draftWorkspaceIdProvider), 'W-OWN');
      },
    );

    test(
      'a draft written away from the workspace on screen is carried anyway',
      () async {
        final container = containerFor(current: 'W-UNIT');
        final sub = container.listen(draftCourierProvider, (_, _) {});
        addTearDown(sub.close);
        await container.read(workspacesProvider.future);
        expect(
          container.read(draftCourierProvider),
          isNull,
          reason: 'nothing waiting',
        );

        await TicketDraftStore(
          db,
        ).write(workspaceId: 'W-OWN', subject: 'Kompresör gece durdu');
        // The outbox stream reaches the courier; the courier's engine pushes.
        for (var i = 0; i < 20 && api.pushedFor.isEmpty; i++) {
          await Future<void>.delayed(const Duration(milliseconds: 10));
        }
        expect(api.pushedFor, contains('W-OWN'));
        expect(api.pushedFor, isNot(contains('W-UNIT')));
        expect(await db.select(db.pendingMutations).get(), isEmpty);
        // …and with nothing left to carry, it stands down.
        for (
          var i = 0;
          i < 20 && container.read(draftCourierProvider) != null;
          i++
        ) {
          await Future<void>.delayed(const Duration(milliseconds: 10));
        }
        expect(container.read(draftCourierProvider), isNull);
      },
    );

    test(
      'on its own space the ordinary engine carries it — no second engine',
      () async {
        final container = containerFor(current: 'W-OWN');
        final sub = container.listen(draftCourierProvider, (_, _) {});
        addTearDown(sub.close);
        await container.read(workspacesProvider.future);
        await TicketDraftStore(
          db,
        ).write(workspaceId: 'W-OWN', subject: 'Durdu');
        await Future<void>.delayed(const Duration(milliseconds: 50));
        expect(container.read(draftCourierProvider), isNull);
        expect(
          api.pushedFor,
          isEmpty,
          reason: 'the main engine is not in this test',
        );
      },
    );
  });
}

class _Selected extends SelectedWorkspace {
  _Selected(this._id);
  final String _id;

  @override
  String? build() => _id;
}
