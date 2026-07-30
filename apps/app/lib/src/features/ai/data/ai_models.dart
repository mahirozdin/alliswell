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
