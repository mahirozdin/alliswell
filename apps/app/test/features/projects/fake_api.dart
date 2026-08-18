import 'package:dio/dio.dart';

import '../auth/test_support.dart';

/// In-memory AllisWell API for project/task widget tests: serves /me plus
/// stateful projects/tasks/tags collections the way apps/api does — including
/// the sync protocol (`/sync/pull` + `/sync/push`) the local-first app speaks
/// since OPH-054.
class FakeApi {
  final String workspaceId = '01WSAAAAAAAAAAAAAAAAAAAAAA';
  final List<Map<String, dynamic>> projects = [];
  final List<Map<String, dynamic>> tasks = [];
  final List<Map<String, dynamic>> tags = [];
  final List<Map<String, dynamic>> folders = [];
  final List<Map<String, dynamic>> notes = [];

  /// OPH-199: the signed-in user's quick access rail. User-scoped on the real
  /// server (ADR-0018); the fake has one user, so the list IS the rail.
  final List<Map<String, dynamic>> quickLinks = [];
  final List<String> requests = [];

  /// Every mutation the client actually pushed, in order. Request paths alone
  /// cannot answer "was the delete written?" — the outbox pushes on its own
  /// schedule, so OPH-184's undo window needs the mutation, not the call.
  final List<Map<String, dynamic>> pushedMutations = [];

  // ── Attachments (Epic 14, OPH-154+) ──────────────────────────────────────
  /// Is STORAGE_S3_* configured on the fake server? Flip to false to test the
  /// honest not-configured surfaces (F6).
  bool storageConfigured = true;
  int storageMaxUploadBytes = 512 * 1024 * 1024;

  /// READY files (they sync). Uploading attempts live in [pendingUploads]
  /// until /complete, mirroring the server's invisible-until-verified rule.
  final List<Map<String, dynamic>> files = [];
  final Map<String, Map<String, dynamic>> pendingUploads = {};

  /// Optional per-file download URL the metadata endpoint answers. Default
  /// none → the app renders kind icons (no Image.network in tests).
  final Map<String, String> downloadUrls = {};

  /// Pending account deletion, as `GET /me` and the deletion endpoints report
  /// it. Null = nothing scheduled.
  String? deletionScheduledAt;

  /// Workspace revision + tombstones for the pull endpoint.
  int revision = 0;
  final List<Map<String, String>> deleted = [];
  int _seq = 0;

  void _bump() => revision += 1;

  Map<String, dynamic> seedNote({
    required String title,
    String plainText = '',
    bool isPinned = false,
    bool isArchived = false,
    String? projectId,
    List<Map<String, dynamic>>? contentDelta,
    String? contentFormat,
    String? contentMarkdown,
  }) {
    final note = _note({
      'title': title,
      'contentDelta':
          contentDelta ??
          [
            {'insert': '$plainText\n'},
          ],
      'contentFormat': contentFormat,
      'contentMarkdown': contentMarkdown,
      'projectId': projectId,
      'isPinned': isPinned,
    });
    note['isArchived'] = isArchived;
    notes.add(note);
    _bump();
    return note;
  }

  Map<String, dynamic> seedFile({
    required String name,
    required String targetType,
    required String targetId,
    String? folderId,
    String mime = 'application/octet-stream',
    int sizeBytes = 2048,
  }) {
    _seq += 1;
    final file = {
      'id': 'FDS$_seq'.padRight(26, '0'),
      'workspaceId': workspaceId,
      'targetType': targetType,
      'targetId': targetId,
      'folderId': folderId,
      'name': name,
      'mime': mime,
      'sizeBytes': sizeBytes,
      'status': 'ready',
      'uploadedBy': 'user-1',
      'revision': 1,
      'createdAt': '2026-07-18T10:00:00.000Z',
      'updatedAt': '2026-07-18T10:00:00.000Z',
    };
    files.add(file);
    _bump();
    return file;
  }

  Map<String, dynamic> seedFolder({required String name, String? parentId}) {
    _seq += 1;
    final folder = {
      'id': 'FDR$_seq'.padRight(26, '0'),
      'workspaceId': workspaceId,
      'parentId': parentId,
      'name': name,
      'revision': 1,
    };
    folders.add(folder);
    _bump();
    return folder;
  }

  Map<String, dynamic> seedQuickLink({
    required String kind,
    required String title,
    String? targetId,
    String? url,
    String? emoji,
    String? colorRgb,
  }) {
    _seq += 1;
    // padLeft, not padRight: 'QCK1'.padRight(26, '0') and 'QCK10'.padRight(26,
    // '0') are the SAME string, so ten-plus seeded rows silently collapsed
    // into fewer ids (found by the 50-shortcut limit test).
    final link = {
      'id': 'QCK${_seq.toString().padLeft(23, '0')}',
      'workspaceId': workspaceId,
      'userId': 'user-1',
      'kind': kind,
      'targetId': targetId,
      'url': url,
      'title': title,
      'emoji': emoji,
      'colorRgb': colorRgb,
      'sortOrder': quickLinks.length * 1024,
      'revision': 1,
    };
    quickLinks.add(link);
    _bump();
    return link;
  }

  Map<String, dynamic> seedTag({required String name}) {
    _seq += 1;
    final tag = {
      'id': 'TAG$_seq'.padRight(26, '0'),
      'workspaceId': workspaceId,
      'name': name,
      'slug': name.toLowerCase(),
      'colorRgb': '#64748B',
      'icon': null,
      'revision': 1,
    };
    tags.add(tag);
    _bump();
    return tag;
  }

  Map<String, dynamic> seedTask({
    required String title,
    String? description,
    String? projectId,
    String status = 'open',
    String priority = 'none',
    bool isUrgent = false,
    String? dueAt,
    String? remindAt,
    String? scheduledStartAt,
    String? scheduledEndAt,

    /// When a seeded task was finished. The server stamps this on the
    /// transition, so a `status: 'completed'` seed without it is a row that
    /// cannot exist in production — and OPH-185's day boundary reads it.
    String? completedAt,
    bool calendarMirrorEnabled = false,

    /// A subtask's parent. Real parent/child rows, exactly as the server
    /// stores them — the detail screen reads the relation, not a list field.
    String? parentTaskId,

    /// Per-task colour (OPH-195), and the series this row belongs to
    /// (OPH-205) — the repeat badge on a tile is `seriesId != null`.
    String? colorRgb,
    String? seriesId,
    String? occurrenceDate,
    List<String> tagIds = const [],
    List<Map<String, dynamic>> checklist = const [],
  }) {
    final task = _task({
      'title': title,
      'description': description,
      'projectId': projectId,
      'parentTaskId': parentTaskId,
      'status': status,
      'completedAt':
          completedAt ??
          (status == 'completed' ? '2026-07-14T12:00:00.000Z' : null),
      'priority': priority,
      'isUrgent': isUrgent,
      'dueAt': dueAt,
      'remindAt': remindAt ?? (isUrgent ? dueAt : null),
      'scheduledStartAt': scheduledStartAt,
      'scheduledEndAt': scheduledEndAt,
      'calendarMirrorEnabled': calendarMirrorEnabled,
      'colorRgb': colorRgb,
      'seriesId': seriesId,
      'occurrenceDate': occurrenceDate,
      'tagIds': tagIds,
      'checklist': checklist,
    });
    tasks.add(task);
    _bump();
    return task;
  }

  /// A recurrence series (OPH-205). Seeded rows reference it through
  /// [seedTask]'s `seriesId`; the app reads the rule from here to render the
  /// repeat summary ("Every month on the 31st") on a task's detail.
  final List<Map<String, dynamic>> taskSeries = [];

  Map<String, dynamic> seedSeries({
    required Map<String, dynamic> rule,
    required Map<String, dynamic> template,
    required String anchorAt,
    String timezone = 'Europe/Istanbul',
  }) {
    _seq += 1;
    final series = {
      'id': 'SRS${_seq.toString().padLeft(23, '0')}',
      'workspaceId': workspaceId,
      'rule': rule,
      'template': template,
      'timezone': timezone,
      'anchorAt': anchorAt,
      'revision': 1,
    };
    taskSeries.add(series);
    _bump();
    return series;
  }

  Map<String, dynamic> seedProject({
    required String name,
    String colorRgb = '#2563EB',
    String status = 'active',
    bool isFavorite = false,
    String? description,
  }) {
    final project = _project({
      'name': name,
      'colorRgb': colorRgb,
      'status': status,
      'isFavorite': isFavorite,
      'description': ?description,
    });
    projects.add(project);
    _bump();
    return project;
  }

  // ── Google Calendar integration (OPH-080) ────────────────────────────────
  // Mirrors apps/api/src/routes/integrations-google.js. Not part of the sync
  // protocol: calendar accounts are per-user server state.

  // ── Note versions (OPH-267/269, ADR-0031) — server-only history ──────────
  /// Rows in the server's version shape, newest first. Never synced: this is
  /// an online surface, and the fake mirrors that.
  final List<Map<String, dynamic>> noteVersions = [];

  /// What `…/diff` answers. The client only draws segments (ADR-0031 §8), so
  /// the fake supplies them the way the server would.
  List<Map<String, dynamic>> noteDiffSegments = [
    {'type': 'equal', 'value': 'ortak '},
    {'type': 'removed', 'value': 'eski'},
    {'type': 'added', 'value': 'yeni'},
  ];

  /// Restores the fake received, so a test can assert the MODE that was sent.
  final List<Map<String, String>> restoreCalls = [];

  int _versionSeq = 0;

  Map<String, dynamic> seedNoteVersion({
    required String noteId,
    String origin = 'edit',
    String? clientId,
    String markdown = 'gövde',
    DateTime? createdAt,
  }) {
    final row = {
      'id': 'VER${(_versionSeq++).toString().padLeft(23, '0')}',
      'noteId': noteId,
      'title': 'Not',
      'origin': origin,
      'clientId': clientId,
      'contentFormat': 'markdown',
      'contentMarkdown': markdown,
      'sizeBytes': markdown.length,
      'createdAt': (createdAt ?? DateTime.utc(2026, 8, 17, 9))
          .toIso8601String(),
    };
    noteVersions.add(row);
    return row;
  }

  ResponseBody? _noteVersionRoutes(
    String path,
    RequestOptions options,
    Map<String, dynamic>? body,
  ) {
    final list = RegExp(r'^/api/v1/notes/([^/]+)/versions$').firstMatch(path);
    if (list != null && options.method == 'GET') {
      final noteId = list.group(1);
      return jsonBody(200, {
        'items': [
          for (final v in noteVersions)
            if (v['noteId'] == noteId) v,
        ],
        'nextCursor': null,
      });
    }
    final diff = RegExp(
      r'^/api/v1/notes/([^/]+)/versions/([^/]+)/diff$',
    ).firstMatch(path);
    if (diff != null && options.method == 'GET') {
      return jsonBody(200, {'segments': noteDiffSegments, 'comparable': true});
    }
    final restore = RegExp(
      r'^/api/v1/notes/([^/]+)/versions/([^/]+)/restore$',
    ).firstMatch(path);
    if (restore != null && options.method == 'POST') {
      restoreCalls.add({
        'noteId': restore.group(1)!,
        'versionId': restore.group(2)!,
        'mode': (body?['mode'] as String?) ?? 'replace',
      });
      return jsonBody(200, {'id': restore.group(1), 'title': 'Not'});
    }
    final detail = RegExp(
      r'^/api/v1/notes/([^/]+)/versions/([^/]+)$',
    ).firstMatch(path);
    if (detail != null && options.method == 'GET') {
      final row = noteVersions.firstWhere(
        (v) => v['id'] == detail.group(2),
        orElse: () => <String, dynamic>{},
      );
      if (row.isEmpty) return jsonBody(404, {'code': 'NOTE_VERSION_NOT_FOUND'});
      return jsonBody(200, row);
    }
    return null;
  }

  // ── API keys (OPH-264/265, ADR-0032) — per-user server state, online only ─
  /// Rows in the server's `apiKeySchema` shape. The secret is NOT in here:
  /// like the real server, the fake hands it out once and forgets it.
  final List<Map<String, dynamic>> apiKeys = [];

  /// Every secret this fake ever minted, so a test can prove the one shown in
  /// the dialog is the one the server produced.
  final List<String> mintedApiKeys = [];

  int _apiKeySeq = 0;

  Map<String, dynamic> seedApiKey({
    String name = 'Home Assistant',
    String? expiresAt,
    String? lastUsedAt,
    String? revokedAt,
  }) {
    final row = {
      'id': 'APIKEY${(_apiKeySeq++).toString().padLeft(20, '0')}',
      'workspaceId': workspaceId,
      'name': name,
      'keyPrefix': 'awk_seeded$_apiKeySeq',
      'createdAt': '2026-08-01T09:00:00.000Z',
      'expiresAt': expiresAt,
      'lastUsedAt': lastUsedAt,
      'revokedAt': revokedAt,
    };
    apiKeys.add(row);
    return row;
  }

  ResponseBody? _apiKeysRoutes(
    String path,
    RequestOptions options,
    Map<String, dynamic>? body,
  ) {
    if (path == '/api/v1/workspaces/$workspaceId/api-keys') {
      if (options.method == 'GET') return jsonBody(200, {'items': apiKeys});
      if (options.method == 'POST') {
        final days = body?['expiresInDays'] as int?;
        final secret = 'awk_${'s' * 8}$_apiKeySeq${'x' * 30}';
        mintedApiKeys.add(secret);
        final row = {
          'id': 'APIKEY${(_apiKeySeq++).toString().padLeft(20, '0')}',
          'workspaceId': workspaceId,
          'name': body?['name'] as String? ?? '',
          'keyPrefix': secret.substring(0, 12),
          'createdAt': '2026-08-17T09:00:00.000Z',
          'expiresAt': days == null
              ? null
              : DateTime.utc(
                  2026,
                  8,
                  17,
                ).add(Duration(days: days)).toIso8601String(),
          'lastUsedAt': null,
          'revokedAt': null,
        };
        apiKeys.insert(0, row);
        // The secret rides along exactly once — the 201 body.
        return jsonBody(201, {...row, 'key': secret});
      }
    }
    final revoke = RegExp(
      r'^/api/v1/api-keys/([^/]+)/revoke$',
    ).firstMatch(path);
    if (revoke != null && options.method == 'POST') {
      final id = revoke.group(1);
      final row = apiKeys.firstWhere((k) => k['id'] == id);
      row['revokedAt'] ??= '2026-08-17T10:00:00.000Z';
      return jsonBody(200, row);
    }
    return null;
  }

  // ── Instance entitlements (/ee/status, EE-008) ────────────────────────────
  /// What `/api/v1/ee/status` answers. Defaults mirror a CE server: empty
  /// list, `state: none`, still a plain 200 (capability discovery is never an
  /// error). Set `eeStatusCode = 404` to play a server that predates the
  /// endpoint entirely.
  String eeState = 'none';
  List<String> eeFeatures = [];
  int? eeStatusCode;

  // ── AI (Epic 20) — per-user server state, like the calendar accounts ──────
  /// Is AI enabled on the server? Defaults OFF so the many existing feature
  /// flows are unperturbed by a second (AI) FAB; AI tests opt in with
  /// `..aiEnabled = true`. false = every /ai/* route 404s (surfaces withdrawn).
  bool aiEnabled = false;

  /// The caller's AI connections, in the server's connectionSchema shape.
  final List<Map<String, dynamic>> aiConnections = [];

  /// The next `/ai/extract` proposal (OPH-222) and the accepted-action log.
  Map<String, dynamic>? nextProposal;
  final List<Map<String, dynamic>> aiActionAccepts = [];

  /// OPH-243: how many times `/ai/extract` was asked. The AI-free share path
  /// must leave this at zero — "we didn't call the model" is an assertion, not
  /// a hope (the OPH-225 "sıfır AI" pattern).
  int aiExtractCalls = 0;

  /// Round 14: holds the `/ai/extract` answer back so a test can observe the
  /// optimistic ✨ state (instant row + enriching badge) before the proposal
  /// lands. Advance the fake clock past it with `tester.pump(delay)`.
  Duration? extractDelay;

  /// Round 15: force `/ai/extract` to fail with this HTTP status — the gate's
  /// degrade-to-chat path needs a provider that is down for extraction only.
  int? extractStatusCode;

  /// Result the `/ai/connections/:id/test` endpoint returns.
  Map<String, dynamic> aiTestResult = {'ok': true, 'latencyMs': 12};

  int _aiSeq = 0;

  Map<String, dynamic> seedAiConnection({
    required String provider,
    String authMode = 'api_key',
    String? keyLast4 = '1234',
    String? baseUrl,
    String status = 'active',
  }) {
    aiEnabled = true; // a connection means the server has AI on
    final row = {
      'id': 'AICONN${(_aiSeq++).toString().padLeft(20, '0')}',
      'workspaceId': workspaceId,
      'userId': 'user-1',
      'provider': provider,
      'authMode': authMode,
      'keyLast4': keyLast4,
      'baseUrl': baseUrl,
      'defaultChatModel': null,
      'defaultFastModel': null,
      'status': status,
    };
    aiConnections.add(row);
    return row;
  }

  /// Does the SERVER have an OAuth client? Flip to false to test the
  /// not-configured path — the integration is optional by design.
  bool googleConfigured = true;

  /// Connected accounts, in the server's `accountSchema` shape. Empty = not
  /// connected yet.
  final List<Map<String, dynamic>> googleAccounts = [];

  /// What `…/calendars` answers. Set to null to make it fail the way an
  /// expired refresh token does (502 CALENDAR_ACCOUNT_REAUTH_REQUIRED).
  List<Map<String, dynamic>>? googleCalendars = [
    {'id': 'primary', 'summary': 'Ana Takvim', 'primary': true},
    {'id': 'is-takvimi', 'summary': 'İş', 'primary': false},
  ];

  /// Every consent URL handed out, so tests can prove the hand-off happened.
  final List<String> googleConnectCalls = [];

  /// The user's own calendar events (OPH-083) — served through `/sync/pull`
  /// like any other entity, because that is exactly what they are.
  final List<Map<String, dynamic>> externalEvents = [];

  Map<String, dynamic> seedExternalEvent({
    required String summary,
    required String startsAt,
    required String endsAt,
    String? location,
    bool isAllDay = false,
    bool isBusy = true,
  }) {
    _seq += 1;
    final event = {
      'id': 'EVT$_seq'.padRight(26, '0'),
      'workspaceId': workspaceId,
      'summary': summary,
      'location': location,
      'startsAt': startsAt,
      'endsAt': endsAt,
      'isAllDay': isAllDay,
      'isBusy': isBusy,
      'htmlLink': 'https://calendar.google.com/event?eid=$_seq',
      'revision': 1,
    };
    externalEvents.add(event);
    _bump();
    return event;
  }

  Map<String, dynamic> seedGoogleAccount({
    String id = 'ACC1',
    String email = 'takvim@example.com',
    String status = 'active',
    String? defaultCalendarId,
    String? lastError,
  }) {
    final account = {
      'id': id.padRight(26, '0'),
      'provider': 'google',
      'providerAccountId': email,
      'status': status,
      'defaultCalendarId': defaultCalendarId,
      'lastSyncedAt': null,
      'lastError': lastError,
      'createdAt': '2026-07-15T10:00:00.000Z',
      'updatedAt': '2026-07-15T10:00:00.000Z',
    };
    googleAccounts.add(account);
    return account;
  }

  /// AI settings + extract + actions (Epic 20). Returns null when the path is
  /// not an AI route (fall through); a 404 for every /ai/* when disabled.
  Future<ResponseBody>? _ai(
    String path,
    RequestOptions options,
    Map<String, dynamic>? body,
  ) {
    if (!path.contains('/ai/')) return null;
    if (!aiEnabled) {
      return Future.value(
        jsonBody(404, {'code': 'AI_DISABLED', 'message': 'AI is off'}),
      );
    }
    final wsPrefix = '/api/v1/workspaces/$workspaceId/ai';

    if (path == '$wsPrefix/status' && options.method == 'GET') {
      return Future.value(
        jsonBody(200, {
          'configured': aiConnections.isNotEmpty,
          'providers': aiConnections.map((c) => c['provider']).toList(),
          'instanceProviders': const [],
        }),
      );
    }
    if (path == '$wsPrefix/connections' && options.method == 'GET') {
      return Future.value(jsonBody(200, {'items': aiConnections}));
    }
    if (path == '$wsPrefix/connections' && options.method == 'POST') {
      final provider = body?['provider'] as String;
      final apiKey = body?['apiKey'] as String?;
      final row = seedAiConnection(
        provider: provider,
        keyLast4: apiKey != null && apiKey.length >= 4
            ? apiKey.substring(apiKey.length - 4)
            : null,
        baseUrl: body?['baseUrl'] as String?,
      );
      return Future.value(jsonBody(201, row));
    }
    if (path == '$wsPrefix/models' && options.method == 'GET') {
      return Future.value(
        jsonBody(200, {
          'provider': 'anthropic',
          'source': 'catalog',
          'models': {
            'chat': [
              {'id': 'claude-sonnet-5', 'label': 'Claude Sonnet 5'},
            ],
            'fast': [
              {'id': 'claude-haiku-4-5-20251001', 'label': 'Claude Haiku 4.5'},
            ],
          },
          'defaults': {
            'chat': 'claude-sonnet-5',
            'fast': 'claude-haiku-4-5-20251001',
          },
        }),
      );
    }
    if (path == '$wsPrefix/extract' && options.method == 'POST') {
      aiExtractCalls++;
      if (extractStatusCode != null) {
        return Future.value(
          jsonBody(extractStatusCode!, {
            'statusCode': extractStatusCode,
            'code': 'AI_UPSTREAM_ERROR',
            'message': 'The AI provider failed',
          }),
        );
      }
      final proposal = nextProposal ?? {'intent': 'none', 'tasks': <dynamic>[]};
      final body = jsonBody(200, {
        'requestId': 'AIREQ${(_aiSeq++).toString().padLeft(21, '0')}',
        'actionId': 'AIACT${(_aiSeq++).toString().padLeft(21, '0')}',
        'repaired': false,
        'proposal': proposal,
      });
      final delay = extractDelay;
      if (delay == null) return Future.value(body);
      return Future.delayed(delay, () => body);
    }

    final test = RegExp(
      r'^/api/v1/ai/connections/([^/]+)/test$',
    ).firstMatch(path);
    if (test != null && options.method == 'POST') {
      return Future.value(jsonBody(200, aiTestResult));
    }
    final patch = RegExp(r'^/api/v1/ai/connections/([^/]+)$').firstMatch(path);
    if (patch != null && options.method == 'PATCH') {
      final row = aiConnections.firstWhere((c) => c['id'] == patch.group(1));
      if (body?['defaultChatModel'] != null) {
        row['defaultChatModel'] = body!['defaultChatModel'];
      }
      if (body?['defaultFastModel'] != null) {
        row['defaultFastModel'] = body!['defaultFastModel'];
      }
      return Future.value(jsonBody(200, row));
    }
    if (patch != null && options.method == 'DELETE') {
      aiConnections.removeWhere((c) => c['id'] == patch.group(1));
      return Future.value(emptyBody(204));
    }
    final decision = RegExp(
      r'^/api/v1/ai/actions/([^/]+)/decision$',
    ).firstMatch(path);
    if (decision != null && options.method == 'POST') {
      aiActionAccepts.add({'actionId': decision.group(1), ...?body});
      return Future.value(
        jsonBody(200, {'id': decision.group(1), 'accepted': body?['accepted']}),
      );
    }
    return Future.value(
      jsonBody(404, {
        'code': 'NOT_FOUND',
        'message': 'No fake AI route for $path',
      }),
    );
  }

  Future<ResponseBody>? _google(
    String path,
    RequestOptions options,
    Map<String, dynamic>? body,
  ) {
    final wsPrefix = '/api/v1/workspaces/$workspaceId/integrations/google';

    if (path == wsPrefix && options.method == 'GET') {
      return Future.value(
        jsonBody(200, {
          'configured': googleConfigured,
          'items': googleAccounts,
        }),
      );
    }

    if (path == '$wsPrefix/connect' && options.method == 'POST') {
      if (!googleConfigured) {
        return Future.value(
          jsonBody(503, {
            'code': 'GOOGLE_NOT_CONFIGURED',
            'message': 'Google Calendar is not configured on this server',
          }),
        );
      }
      const url = 'https://accounts.google.com/o/oauth2/v2/auth?state=signed';
      googleConnectCalls.add(url);
      return Future.value(jsonBody(200, {'authUrl': url}));
    }

    final calendars = RegExp(
      r'^/api/v1/integrations/google/accounts/([^/]+)/calendars$',
    ).firstMatch(path);
    if (calendars != null && options.method == 'GET') {
      if (googleCalendars == null) {
        return Future.value(
          jsonBody(502, {
            'code': 'CALENDAR_ACCOUNT_REAUTH_REQUIRED',
            'message': 'Google rejected the stored credentials — reconnect',
          }),
        );
      }
      return Future.value(jsonBody(200, {'items': googleCalendars}));
    }

    final account = RegExp(
      r'^/api/v1/integrations/google/accounts/([^/]+)$',
    ).firstMatch(path);
    if (account != null) {
      final id = account.group(1)!;
      final index = googleAccounts.indexWhere((a) => a['id'] == id);
      if (index < 0) {
        return Future.value(
          jsonBody(404, {
            'code': 'CALENDAR_ACCOUNT_NOT_FOUND',
            'message': 'Calendar account not found',
          }),
        );
      }
      if (options.method == 'PATCH') {
        googleAccounts[index] = {
          ...googleAccounts[index],
          'defaultCalendarId': body?['defaultCalendarId'],
        };
        return Future.value(jsonBody(200, googleAccounts[index]));
      }
      if (options.method == 'DELETE') {
        googleAccounts.removeAt(index);
        return Future.value(jsonBody(204, const <String, dynamic>{}));
      }
    }

    return null; // not a Google route — fall through to the rest
  }

  /// Make the server unreachable: every request answers 503. Flip mid-test to
  /// prove a failure path (OPH-171: a refresh that fails must SAY so).
  bool offline = false;

  Future<ResponseBody> handle(
    RequestOptions options,
    Map<String, dynamic>? body,
  ) async {
    final path = options.uri.path;
    requests.add('${options.method} $path');
    if (offline) {
      return jsonBody(503, {
        'code': 'SERVER_UNREACHABLE',
        'message': 'The fake server is offline',
      });
    }

    // Account deletion (App Store 5.1.1(v) / Google Play): schedule + undo.
    if (path == '/api/v1/me' && options.method == 'DELETE') {
      deletionScheduledAt ??= DateTime.utc(2026, 8, 1, 12).toIso8601String();
      return jsonBody(200, {
        'deletionScheduledAt': deletionScheduledAt,
        'graceDays': 3,
      });
    }
    if (path == '/api/v1/me/deletion/cancel' && options.method == 'POST') {
      deletionScheduledAt = null;
      return jsonBody(200, {'deletionScheduledAt': null, 'graceDays': 3});
    }

    if (path == '/api/v1/me') {
      return jsonBody(200, {
        'user': {
          'id': 'user-1',
          'email': 'mahir@example.com',
          'displayName': 'Mahir',
          'timezone': 'Europe/Istanbul',
          'locale': 'tr-TR',
          'createdAt': '2026-07-14T00:00:00.000Z',
          'deletionScheduledAt': deletionScheduledAt,
        },
        'workspaces': [
          {
            'id': workspaceId,
            'name': "Mahir's Space",
            'slug': 'mahir-s-space',
            'colorRgb': '#2563EB',
            'icon': null,
            'role': 'owner',
          },
        ],
      });
    }

    if (path == '/api/v1/ee/status' && options.method == 'GET') {
      if (eeStatusCode != null) {
        return jsonBody(eeStatusCode!, {
          'code': 'NOT_FOUND',
          'message': 'Not found',
        });
      }
      return jsonBody(200, {
        'state': eeState,
        'features': eeFeatures,
        'expiresAt': null,
        'overlay': 'disabled',
      });
    }

    if (path == '/api/v1/sync/pull') return _syncPull(options);
    if (path == '/api/v1/sync/push' && options.method == 'POST') {
      return _syncPush(body ?? const {});
    }

    final apiKeysRes = _apiKeysRoutes(path, options, body);
    if (apiKeysRes != null) return apiKeysRes;

    final versionsRes = _noteVersionRoutes(path, options, body);
    if (versionsRes != null) return versionsRes;

    final ai = _ai(path, options, body);
    if (ai != null) return ai;

    final google = _google(path, options, body);
    if (google != null) return google;

    final filesRes = _files(path, options, body);
    if (filesRes != null) return filesRes;

    if (path == '/api/v1/workspaces/$workspaceId/projects') {
      if (options.method == 'GET') return jsonBody(200, {'items': projects});
      if (options.method == 'POST') {
        final project = _project(body ?? const {});
        projects.add(project);
        return jsonBody(201, project);
      }
    }

    if (path == '/api/v1/workspaces/$workspaceId/tags' &&
        options.method == 'GET') {
      return jsonBody(200, {'items': tags});
    }

    if (path == '/api/v1/workspaces/$workspaceId/notes') {
      if (options.method == 'GET') {
        final params = options.uri.queryParameters;
        var items = params['archived'] != null
            ? notes
                  .where(
                    (n) =>
                        (n['isArchived'] == true) ==
                        (params['archived'] == 'true'),
                  )
                  .toList()
            : notes.where((n) => n['isArchived'] != true).toList();
        if (params['pinned'] == 'true') {
          items = items.where((n) => n['isPinned'] == true).toList();
        }
        final q = params['q']?.toLowerCase();
        if (q != null && q.isNotEmpty) {
          items = items
              .where(
                (n) => ('${n['title']} ${n['plainText']}')
                    .toLowerCase()
                    .contains(q),
              )
              .toList();
        }
        return jsonBody(200, {'items': items, 'nextCursor': null});
      }
      if (options.method == 'POST') {
        final note = _note(body ?? const {});
        notes.add(note);
        return jsonBody(201, note);
      }
    }

    final projectNotes = RegExp(
      r'^/api/v1/projects/([^/]+)/notes$',
    ).firstMatch(path);
    if (projectNotes != null && options.method == 'GET') {
      final items = notes
          .where((n) => n['projectId'] == projectNotes.group(1))
          .toList();
      return jsonBody(200, {'items': items, 'nextCursor': null});
    }

    final singleNote = RegExp(r'^/api/v1/notes/([^/]+)$').firstMatch(path);
    if (singleNote != null) {
      final index = notes.indexWhere((n) => n['id'] == singleNote.group(1));
      if (index < 0) return _notFound('NOTE_NOT_FOUND');
      switch (options.method) {
        case 'GET':
          return jsonBody(200, notes[index]);
        case 'PATCH':
          notes[index] = {
            ...notes[index],
            ...?body,
            'revision': (notes[index]['revision'] as int) + 1,
          };
          return jsonBody(200, notes[index]);
        case 'DELETE':
          notes.removeAt(index);
          return ResponseBody.fromString('', 204);
      }
    }

    if (path == '/api/v1/workspaces/$workspaceId/tasks') {
      if (options.method == 'GET') {
        return jsonBody(200, {
          'items': _filteredTasks(options.uri.queryParametersAll),
          'nextCursor': null,
        });
      }
      if (options.method == 'POST') {
        final task = _task(body ?? const {});
        tasks.add(task);
        return jsonBody(201, task);
      }
    }

    final taskAction = RegExp(
      r'^/api/v1/tasks/([^/]+)/(complete|reopen|snooze|tags|checklist)(?:/([^/]+))?$',
    ).firstMatch(path);
    if (taskAction != null) {
      return _handleTaskAction(
        options.method,
        taskAction.group(1)!,
        taskAction.group(2)!,
        taskAction.group(3),
        body,
      );
    }

    final singleTask = RegExp(r'^/api/v1/tasks/([^/]+)$').firstMatch(path);
    if (singleTask != null) {
      final index = tasks.indexWhere((t) => t['id'] == singleTask.group(1));
      if (index < 0) return _notFound('TASK_NOT_FOUND');
      switch (options.method) {
        case 'GET':
          return jsonBody(200, tasks[index]);
        case 'PATCH':
          tasks[index] = {
            ...tasks[index],
            ...?body,
            'revision': (tasks[index]['revision'] as int) + 1,
          };
          if (body?['status'] == 'completed') {
            tasks[index]['completedAt'] = '2026-07-14T12:00:00.000Z';
          }
          return jsonBody(200, tasks[index]);
        case 'DELETE':
          tasks.removeAt(index);
          return ResponseBody.fromString('', 204);
      }
    }

    final single = RegExp(r'^/api/v1/projects/([^/]+)$').firstMatch(path);
    if (single != null) {
      final index = projects.indexWhere((p) => p['id'] == single.group(1));
      if (index < 0) {
        return jsonBody(404, {
          'statusCode': 404,
          'code': 'PROJECT_NOT_FOUND',
          'error': 'Not Found',
          'message': 'Project not found',
        });
      }
      switch (options.method) {
        case 'GET':
          return jsonBody(200, projects[index]);
        case 'PATCH':
          projects[index] = {
            ...projects[index],
            ...?body,
            'revision': (projects[index]['revision'] as int) + 1,
          };
          return jsonBody(200, projects[index]);
        case 'DELETE':
          projects.removeAt(index);
          return ResponseBody.fromString('', 204);
      }
    }

    return jsonBody(404, {
      'statusCode': 404,
      'code': 'NOT_FOUND',
      'error': 'Not Found',
      'message': 'No fake route for $path',
    });
  }

  List<Map<String, dynamic>> _filteredTasks(Map<String, List<String>> query) {
    final statuses = query['status'];
    final projectId = query['projectId']?.first;
    final dueFrom = query['dueFrom']?.first;
    final dueTo = query['dueTo']?.first;
    return tasks.where((t) {
      if (statuses != null && !statuses.contains(t['status'])) return false;
      if (projectId != null && t['projectId'] != projectId) return false;
      final due = t['dueAt'] as String?;
      if (dueFrom != null && (due == null || due.compareTo(dueFrom) < 0)) {
        return false;
      }
      if (dueTo != null && (due == null || due.compareTo(dueTo) > 0)) {
        return false;
      }
      return true;
    }).toList();
  }

  Future<ResponseBody> _handleTaskAction(
    String method,
    String taskId,
    String action,
    String? itemId,
    Map<String, dynamic>? body,
  ) async {
    final index = tasks.indexWhere((t) => t['id'] == taskId);
    if (index < 0) return _notFound('TASK_NOT_FOUND');
    final task = tasks[index];

    switch (action) {
      case 'complete':
        task['status'] = 'completed';
        task['completedAt'] = '2026-07-14T12:00:00.000Z';
        return jsonBody(200, task);
      case 'reopen':
        task['status'] = 'open';
        task['completedAt'] = null;
        return jsonBody(200, task);
      case 'snooze':
        task['snoozedUntil'] =
            body?['snoozeUntil'] ?? '2026-07-15T06:00:00.000Z';
        return jsonBody(200, task);
      case 'tags':
        task['tagIds'] = (body?['tagIds'] as List?)?.cast<String>() ?? [];
        return jsonBody(200, task);
      case 'checklist':
        final checklist = (task['checklist'] as List)
            .cast<Map<String, dynamic>>();
        if (method == 'POST') {
          _seq += 1;
          final item = {
            'id': 'CHK$_seq'.padRight(26, '0'),
            'taskId': taskId,
            'title': body?['title'],
            'isDone': false,
            'sortOrder': checklist.length,
            'revision': 1,
          };
          checklist.add(item);
          return jsonBody(201, item);
        }
        final itemIndex = checklist.indexWhere((i) => i['id'] == itemId);
        if (itemIndex < 0) return _notFound('CHECKLIST_ITEM_NOT_FOUND');
        if (method == 'PATCH') {
          checklist[itemIndex] = {...checklist[itemIndex], ...?body};
          return jsonBody(200, checklist[itemIndex]);
        }
        if (method == 'DELETE') {
          checklist.removeAt(itemIndex);
          return ResponseBody.fromString('', 204);
        }
    }
    return _notFound('NOT_FOUND');
  }

  // ── Sync protocol (OPH-054c): full-state snapshots + tombstones ───────────

  Future<ResponseBody> _syncPull(RequestOptions options) async {
    final since = int.parse(options.uri.queryParameters['sinceRevision']!);
    final changes = <Map<String, dynamic>>[];
    if (since < revision) {
      void snapshot(String type, Map<String, dynamic> data) {
        changes.add({
          'revision': revision,
          'entityType': type,
          'entityId': data['id'],
          'operation': 'update',
          'data': data,
        });
      }

      for (final p in projects) {
        snapshot('project', p);
      }
      for (final t in tags) {
        snapshot('tag', t);
      }
      for (final f in folders) {
        snapshot('folder', f);
      }
      for (final q in quickLinks) {
        snapshot('quick_link', q);
      }
      // Before the tasks: a row whose seriesId resolves to nothing renders as
      // a repeat badge with no rule behind it.
      for (final s in taskSeries) {
        snapshot('task_series', s);
      }
      for (final t in tasks) {
        snapshot('task', t);
        for (final item in (t['checklist'] as List? ?? const [])) {
          snapshot('checklist_item', {
            ...(item as Map).cast<String, dynamic>(),
            'taskId': t['id'],
          });
        }
      }
      for (final n in notes) {
        snapshot('note', {'links': const [], ...n});
      }
      // OPH-083: the user's own calendar events ride the same pull — read-only,
      // so the fake has no push route for them (mirroring the server's
      // ENTITIES registry, which simply does not list the type).
      for (final e in externalEvents) {
        snapshot('external_event', e);
      }
      // Epic 14: attachment metadata is pull-only, exactly like the events —
      // no push route exists for 'file' (the server refuses them too).
      for (final f in files) {
        snapshot('file', f);
      }
      for (final d in deleted) {
        changes.add({
          'revision': revision,
          'entityType': d['entityType'],
          'entityId': d['entityId'],
          'operation': 'delete',
          'data': null,
        });
      }
    }
    return jsonBody(200, {
      'workspaceId': workspaceId,
      'fromRevision': since,
      'toRevision': since > revision ? since : revision,
      'hasMore': false,
      'changes': changes,
    });
  }

  Future<ResponseBody> _syncPush(Map<String, dynamic> body) async {
    final mutations = ((body['mutations'] as List?) ?? const [])
        .cast<Map<String, dynamic>>();
    final results = <Map<String, dynamic>>[];
    for (final m in mutations) {
      pushedMutations.add(m);
      _bump();
      _applyMutation(m);
      results.add({
        'clientMutationId': m['clientMutationId'],
        'status': 'applied',
        'revision': revision,
        'errorCode': null,
        'replayed': false,
        'discardedFields': const <String>[],
      });
    }
    return jsonBody(200, {
      'workspaceId': workspaceId,
      'toRevision': revision,
      'results': results,
    });
  }

  void _applyMutation(Map<String, dynamic> m) {
    final entityId = m['entityId'] as String;
    final operation = m['operation'] as String;
    final patch = ((m['patch'] as Map?) ?? const {}).cast<String, dynamic>();

    List<Map<String, dynamic>>? collection = switch (m['entityType']) {
      'project' => projects,
      'task' => tasks,
      'note' => notes,
      'tag' => tags,
      'folder' => folders,
      _ => null,
    };

    switch (m['entityType']) {
      case 'checklist_item':
        _applyChecklistMutation(entityId, operation, patch);
      case 'quick_link':
        _applyQuickLinkMutation(entityId, operation, patch);
      case 'project' || 'task' || 'note' || 'tag' || 'folder':
        final index = collection!.indexWhere((e) => e['id'] == entityId);
        if (operation == 'create') {
          if (index >= 0) return;
          collection.add(switch (m['entityType']) {
            'project' => _project({...patch, 'id': entityId}),
            'folder' => {
              'id': entityId,
              'workspaceId': workspaceId,
              'parentId': patch['parentId'],
              'name': patch['name'],
              'revision': 1,
            },
            'task' => _task({...patch, 'id': entityId}),
            'note' => {
              'links': const [],
              ..._note({...patch, 'id': entityId}),
            },
            _ => {
              'id': entityId,
              'workspaceId': workspaceId,
              'name': patch['name'],
              'slug': (patch['name'] as String).toLowerCase(),
              'colorRgb': patch['colorRgb'] ?? '#64748B',
              'icon': null,
              'revision': 1,
            },
          });
        } else if (operation == 'update' && index >= 0) {
          final merged = {...collection[index], ...patch};
          merged['revision'] = (collection[index]['revision'] as int) + 1;
          if (m['entityType'] == 'task' && patch.containsKey('status')) {
            merged['completedAt'] = patch['status'] == 'completed'
                ? '2026-07-14T12:00:00.000Z'
                : null;
          }
          if (m['entityType'] == 'note' && patch.containsKey('contentDelta')) {
            final plain = ((patch['contentDelta'] as List?) ?? const [])
                .map((op) => (op as Map)['insert'])
                .whereType<String>()
                .join()
                .replaceAll(RegExp(r'\s+'), ' ')
                .trim();
            merged['plainText'] = plain;
            merged['snippet'] = plain;
          }
          collection[index] = merged;
        } else if (operation == 'delete' && index >= 0) {
          collection.removeAt(index);
          deleted.add({
            'entityType': m['entityType'] as String,
            'entityId': entityId,
          });
        }
    }
  }

  /// Quick links (OPH-197/203): create, patch, delete, and the whole-rail
  /// reorder that arrives as an ordinary `update` carrying `orderedIds`.
  void _applyQuickLinkMutation(
    String entityId,
    String operation,
    Map<String, dynamic> patch,
  ) {
    final index = quickLinks.indexWhere((q) => q['id'] == entityId);
    if (operation == 'create') {
      if (index >= 0) return;
      quickLinks.add({
        'id': entityId,
        'workspaceId': workspaceId,
        'userId': 'user-1',
        'kind': patch['kind'],
        'targetId': patch['targetId'],
        'url': patch['url'],
        'title': patch['title'],
        'emoji': patch['emoji'],
        'colorRgb': patch['colorRgb'],
        'sortOrder': quickLinks.length * 1024,
        'revision': 1,
      });
      return;
    }
    if (operation == 'delete') {
      if (index < 0) return;
      quickLinks.removeAt(index);
      deleted.add({'entityType': 'quick_link', 'entityId': entityId});
      return;
    }
    if (operation != 'update') return;
    if (patch['orderedIds'] case final List<dynamic> ordered) {
      for (final (position, id) in ordered.indexed) {
        final row = quickLinks.firstWhere(
          (q) => q['id'] == id,
          orElse: () => <String, dynamic>{},
        );
        if (row.isEmpty) continue;
        row['sortOrder'] = position * 1024;
        row['revision'] = (row['revision'] as int) + 1;
      }
      quickLinks.sort(
        (a, b) => (a['sortOrder'] as int).compareTo(b['sortOrder'] as int),
      );
      return;
    }
    if (index < 0) return;
    quickLinks[index] = {
      ...quickLinks[index],
      ...patch,
      'revision': (quickLinks[index]['revision'] as int) + 1,
    };
  }

  void _applyChecklistMutation(
    String entityId,
    String operation,
    Map<String, dynamic> patch,
  ) {
    if (operation == 'create') {
      final task = tasks.firstWhere(
        (t) => t['id'] == patch['taskId'],
        orElse: () => const {},
      );
      if (task.isEmpty) return;
      (task['checklist'] as List).add({
        'id': entityId,
        'taskId': patch['taskId'],
        'title': patch['title'],
        'isDone': false,
        'sortOrder': patch['sortOrder'] ?? 0,
        'revision': 1,
      });
      return;
    }
    for (final task in tasks) {
      final checklist = ((task['checklist'] as List?) ?? const [])
          .cast<Map<String, dynamic>>();
      final index = checklist.indexWhere((i) => i['id'] == entityId);
      if (index < 0) continue;
      if (operation == 'update') {
        checklist[index] = {...checklist[index], ...patch};
      } else {
        checklist.removeAt(index);
        deleted.add({'entityType': 'checklist_item', 'entityId': entityId});
      }
      return;
    }
  }

  // ── Attachments (Epic 14) — mirrors apps/api/src/routes/files.js ────────

  Future<ResponseBody>? _files(
    String path,
    RequestOptions options,
    Map<String, dynamic>? body,
  ) {
    if (path == '/api/v1/workspaces/$workspaceId/files/usage' &&
        options.method == 'GET') {
      var total = 0;
      for (final f in files) {
        total += (f['sizeBytes'] as num).toInt();
      }
      return Future.value(
        jsonBody(200, {'totalBytes': total, 'fileCount': files.length}),
      );
    }

    if (path == '/api/v1/storage' && options.method == 'GET') {
      return Future.value(
        jsonBody(200, {
          'configured': storageConfigured,
          'maxUploadBytes': storageMaxUploadBytes,
          'presignTtlSec': 3600,
        }),
      );
    }

    if (path == '/api/v1/workspaces/$workspaceId/files' &&
        options.method == 'POST') {
      if (!storageConfigured) {
        return Future.value(
          jsonBody(503, {
            'statusCode': 503,
            'code': 'STORAGE_NOT_CONFIGURED',
            'error': 'Service Unavailable',
            'message': 'storage off',
          }),
        );
      }
      _seq += 1;
      final id = 'FDS$_seq'.padRight(26, '0');
      final mime = (body?['mime'] as String?) ?? 'application/octet-stream';
      final file = {
        'id': id,
        'workspaceId': workspaceId,
        'targetType': body?['targetType'],
        'targetId': body?['targetId'],
        'folderId': body?['folderId'],
        'name': body?['name'],
        'mime': mime,
        'sizeBytes': body?['sizeBytes'],
        'status': 'uploading',
        'uploadedBy': 'user-1',
        'revision': 0,
        'createdAt': '2026-07-18T10:00:00.000Z',
        'updatedAt': '2026-07-18T10:00:00.000Z',
      };
      pendingUploads[id] = file;
      return Future.value(
        jsonBody(201, {
          'file': file,
          'upload': {
            'method': 'PUT',
            'url': 'https://fake-store/put/$id',
            'headers': {'content-type': mime},
            'expiresAt': '2030-01-01T00:00:00.000Z',
          },
        }),
      );
    }

    final complete = RegExp(
      r'^/api/v1/files/([^/]+)/complete$',
    ).firstMatch(path);
    if (complete != null && options.method == 'POST') {
      final id = complete.group(1)!;
      final pending = pendingUploads.remove(id);
      if (pending == null) return _notFound('FILE_NOT_FOUND');
      pending['status'] = 'ready';
      pending['revision'] = revision + 1;
      files.add(pending);
      _bump();
      return Future.value(jsonBody(200, {'file': pending}));
    }

    final byId = RegExp(r'^/api/v1/files/([^/]+)$').firstMatch(path);
    if (byId != null) {
      final id = byId.group(1)!;
      final index = files.indexWhere((f) => f['id'] == id);
      switch (options.method) {
        case 'GET':
          if (index < 0) return _notFound('FILE_NOT_FOUND');
          return Future.value(
            jsonBody(200, {
              'file': files[index],
              'downloadUrl': downloadUrls[id],
              'downloadExpiresAt': downloadUrls.containsKey(id)
                  ? '2030-01-01T00:00:00.000Z'
                  : null,
            }),
          );
        case 'PATCH':
          if (index < 0) return _notFound('FILE_NOT_FOUND');
          if (body?.containsKey('name') ?? false) {
            files[index]['name'] = body?['name'];
          }
          // OPH-170: move between folders (workspace files).
          if (body?.containsKey('folderId') ?? false) {
            files[index]['folderId'] = body?['folderId'];
          }
          files[index]['revision'] = revision + 1;
          _bump();
          return Future.value(jsonBody(200, {'file': files[index]}));
        case 'DELETE':
          if (index >= 0) {
            files.removeAt(index);
            deleted.add({'entityType': 'file', 'entityId': id});
            _bump();
          } else {
            pendingUploads.remove(id);
          }
          return Future.value(ResponseBody.fromString('', 204));
      }
    }
    return null;
  }

  Future<ResponseBody> _notFound(String code) async => jsonBody(404, {
    'statusCode': 404,
    'code': code,
    'error': 'Not Found',
    'message': code,
  });

  Map<String, dynamic> _task(Map<String, dynamic> body) {
    _seq += 1;
    return {
      'id': (body['id'] as String?) ?? 'TSK$_seq'.padRight(26, '0'),
      'workspaceId': workspaceId,
      'projectId': body['projectId'],
      'parentTaskId': body['parentTaskId'],
      'title': body['title'] ?? 'Untitled',
      'description': body['description'],
      'status': body['status'] ?? 'open',
      'priority': body['priority'] ?? 'none',
      'colorRgb': body['colorRgb'],
      // OPH-205: server-owned. Clients read them; a non-null seriesId is what
      // puts the repeat badge on a tile.
      'seriesId': body['seriesId'],
      'occurrenceDate': body['occurrenceDate'],
      'startAt': null,
      'dueAt': body['dueAt'],
      'scheduledStartAt': body['scheduledStartAt'],
      'scheduledEndAt': body['scheduledEndAt'],
      'remindAt': body['remindAt'],
      'snoozedUntil': null,
      'timezone': 'Europe/Istanbul',
      'isUrgent': body['isUrgent'] ?? false,
      'requiresAcknowledgement': body['isUrgent'] ?? false,
      // OPH-081: mirrors routes/tasks.js — snapshots carry it, push accepts it.
      'calendarMirrorEnabled': body['calendarMirrorEnabled'] ?? false,
      'repeatRule': null,
      'estimatedMinutes': null,
      'actualMinutes': null,
      'sortOrder': 0,
      'completedAt': body['completedAt'],
      'revision': 1,
      'createdAt': '2026-07-14T10:00:00.000Z',
      'updatedAt': '2026-07-14T10:00:00.000Z',
      'tagIds': (body['tagIds'] as List?)?.cast<String>() ?? <String>[],
      'checklist':
          (body['checklist'] as List?)?.cast<Map<String, dynamic>>() ??
          <Map<String, dynamic>>[],
    };
  }

  Map<String, dynamic> _note(Map<String, dynamic> body) {
    _seq += 1;
    final delta = (body['contentDelta'] as List?)?.cast<Map<String, dynamic>>();
    final plain = (delta ?? const [])
        .map((op) => op['insert'])
        .whereType<String>()
        .join()
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    return {
      'id': (body['id'] as String?) ?? 'NOT$_seq'.padRight(26, '0'),
      'workspaceId': workspaceId,
      'projectId': body['projectId'],
      'createdFromTaskId': null,
      'title': body['title'] ?? 'Untitled',
      'snippet': plain,
      'plainText': plain,
      'contentDelta': delta,
      'contentMarkdown': body['contentMarkdown'],
      'contentFormat': body['contentFormat'] ?? 'delta',
      'isPinned': body['isPinned'] ?? false,
      'isArchived': false,
      'links': <Map<String, dynamic>>[],
      'revision': 1,
      'createdAt': '2026-07-14T10:00:00.000Z',
      'updatedAt': '2026-07-14T10:00:00.000Z',
    };
  }

  Map<String, dynamic> _project(Map<String, dynamic> body) {
    _seq += 1;
    return {
      'id': (body['id'] as String?) ?? 'PRJ$_seq'.padRight(26, '0'),
      'workspaceId': workspaceId,
      'name': body['name'] ?? 'Untitled',
      'description': body['description'],
      'colorRgb': body['colorRgb'] ?? '#2563EB',
      'icon': null,
      'status': body['status'] ?? 'active',
      'startAt': null,
      'dueAt': null,
      'sortOrder': 0,
      'isFavorite': body['isFavorite'] ?? false,
      'revision': 1,
      'createdAt': '2026-07-14T10:00:00.000Z',
      'updatedAt': '2026-07-14T10:00:00.000Z',
    };
  }
}
