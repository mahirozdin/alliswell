/// AI data-transfer objects (OPH-220, Epic 20). The server owns the AI
/// connection state (per user, per workspace) — these mirror its serializers.
library;

/// The five providers, in the order the settings picker shows them.
const List<String> kAiProviders = [
  'anthropic',
  'openai',
  'gemini',
  'openrouter',
  'ollama',
];

/// Providers whose free tier trains on your data — the consent screen shows an
/// amber warning for these (AI.md §7).
const Set<String> kAiTrainsOnData = {'gemini'};

/// Whether AI surfaces exist at all, and what is connected. `configured` false
/// with `enabled` true = the honest "add a provider" state; `enabled` false (or
/// a 404 from the server) = the feature is withdrawn entirely.
class AiStatus {
  const AiStatus({
    required this.enabled,
    required this.configured,
    this.providers = const [],
    this.instanceProviders = const [],
  });

  final bool enabled;
  final bool configured;
  final List<String> providers;
  final List<String> instanceProviders;

  static const AiStatus disabled = AiStatus(enabled: false, configured: false);

  factory AiStatus.fromJson(Map<String, dynamic> json) => AiStatus(
    enabled: true,
    configured: (json['configured'] as bool?) ?? false,
    providers: ((json['providers'] as List?) ?? const []).cast<String>(),
    instanceProviders: ((json['instanceProviders'] as List?) ?? const [])
        .cast<String>(),
  );

  Map<String, dynamic> toJson() => {
    'enabled': enabled,
    'configured': configured,
    'providers': providers,
    'instanceProviders': instanceProviders,
  };
}

class AiConnection {
  const AiConnection({
    required this.id,
    required this.provider,
    required this.authMode,
    this.keyLast4,
    this.baseUrl,
    this.defaultChatModel,
    this.defaultFastModel,
    required this.status,
  });

  final String id;
  final String provider;
  final String authMode;
  final String? keyLast4;
  final String? baseUrl;
  final String? defaultChatModel;
  final String? defaultFastModel;
  final String status;

  bool get hasError => status == 'error';

  factory AiConnection.fromJson(Map<String, dynamic> json) => AiConnection(
    id: json['id'] as String,
    provider: json['provider'] as String,
    authMode: json['authMode'] as String,
    keyLast4: json['keyLast4'] as String?,
    baseUrl: json['baseUrl'] as String?,
    defaultChatModel: json['defaultChatModel'] as String?,
    defaultFastModel: json['defaultFastModel'] as String?,
    status: json['status'] as String,
  );
}

class AiModelOption {
  const AiModelOption({required this.id, required this.label});
  final String id;
  final String label;
  factory AiModelOption.fromJson(Map<String, dynamic> json) => AiModelOption(
    id: json['id'] as String,
    label: (json['label'] as String?) ?? json['id'] as String,
  );
}

class AiModelCatalog {
  const AiModelCatalog({
    required this.chat,
    required this.fast,
    this.defaultChat,
    this.defaultFast,
  });

  final List<AiModelOption> chat;
  final List<AiModelOption> fast;
  final String? defaultChat;
  final String? defaultFast;

  factory AiModelCatalog.fromJson(Map<String, dynamic> json) {
    List<AiModelOption> list(String key) =>
        (((json['models'] as Map?)?[key] as List?) ?? const [])
            .map((m) => AiModelOption.fromJson(m as Map<String, dynamic>))
            .toList();
    final defaults = (json['defaults'] as Map?) ?? const {};
    return AiModelCatalog(
      chat: list('chat'),
      fast: list('fast'),
      defaultChat: defaults['chat'] as String?,
      defaultFast: defaults['fast'] as String?,
    );
  }
}

/// One proposed task from `/ai/extract` (OPH-219's schema). `projectName` is
/// the user's words — resolution to a real project id is ours (project_match).
class AiProposalTask {
  const AiProposalTask({
    required this.title,
    this.description,
    this.projectName,
    this.dueAt,
    this.dueAtSource,
    this.reminderAt,
    this.priority,
    this.urgent = false,
    this.tags = const [],
    this.checklist = const [],
    this.ambiguities = const [],
  });

  final String title;
  final String? description;
  final String? projectName;
  final String? dueAt;
  final String? dueAtSource;
  final String? reminderAt;
  final String? priority;
  final bool urgent;
  final List<String> tags;
  final List<String> checklist;
  final List<String> ambiguities;

  factory AiProposalTask.fromJson(Map<String, dynamic> json) => AiProposalTask(
    title: json['title'] as String,
    description: json['description'] as String?,
    projectName: json['projectName'] as String?,
    dueAt: json['dueAt'] as String?,
    dueAtSource: json['dueAtSource'] as String?,
    reminderAt: json['reminderAt'] as String?,
    priority: json['priority'] as String?,
    urgent: (json['urgent'] as bool?) ?? false,
    tags: ((json['tags'] as List?) ?? const []).cast<String>(),
    checklist: ((json['checklist'] as List?) ?? const []).cast<String>(),
    ambiguities: ((json['ambiguities'] as List?) ?? const []).cast<String>(),
  );
}

class AiProposal {
  const AiProposal({
    required this.requestId,
    required this.actionId,
    required this.intent,
    this.answer,
    this.tasks = const [],
  });

  final String requestId;
  final String actionId;
  final String intent; // create_tasks | answer | none
  final String? answer;
  final List<AiProposalTask> tasks;

  factory AiProposal.fromJson(Map<String, dynamic> json) {
    final proposal = (json['proposal'] as Map<String, dynamic>?) ?? const {};
    return AiProposal(
      requestId: json['requestId'] as String,
      actionId: json['actionId'] as String,
      intent: proposal['intent'] as String? ?? 'none',
      answer: proposal['answer'] as String?,
      tasks: ((proposal['tasks'] as List?) ?? const [])
          .map((t) => AiProposalTask.fromJson(t as Map<String, dynamic>))
          .toList(),
    );
  }
}

class AiConnectionTest {
  const AiConnectionTest({
    required this.ok,
    this.code,
    this.message,
    this.latencyMs,
  });
  final bool ok;
  final String? code;
  final String? message;
  final int? latencyMs;
  factory AiConnectionTest.fromJson(Map<String, dynamic> json) =>
      AiConnectionTest(
        ok: (json['ok'] as bool?) ?? false,
        code: json['code'] as String?,
        message: json['message'] as String?,
        latencyMs: json['latencyMs'] as int?,
      );
}
