/// The team's outgoing endpoints, client side (EE-175/EE-176).
///
/// Like `EeTeamAiConnection`, this model is DELIBERATELY INCOMPLETE: there is
/// no field for the signing secret and there cannot be one, because no listing
/// carries it. [secretLast4] is the whole of what a screen may know about it
/// afterwards.
///
/// The secret does reach this app exactly once — as [EeWebhookMinted.secret],
/// returned by the two calls that mint one. It is a separate type on purpose:
/// a `String? secret` on this class would be a field somebody eventually tries
/// to read from a list item, and finding it null would look like a bug rather
/// than a promise.
class EeWebhook {
  const EeWebhook({
    required this.id,
    required this.url,
    required this.eventClasses,
    required this.enabled,
    required this.createdAt,
    this.secretLast4,
  });

  factory EeWebhook.fromJson(Map<String, dynamic> json) => EeWebhook(
    id: json['id'] as String,
    url: json['url'] as String,
    eventClasses: ((json['eventClasses'] as List<dynamic>?) ?? const [])
        .map((e) => e as String)
        .toList(growable: false),
    enabled: (json['enabled'] as bool?) ?? true,
    createdAt: DateTime.parse(json['createdAt'] as String).toLocal(),
    secretLast4: json['secretLast4'] as String?,
  );

  final String id;
  final String url;
  final List<String> eventClasses;

  /// Paused, not deleted. The ordinary move when an integration misbehaves at
  /// 02:00 is to stop calling it, not to lose how it was set up.
  final bool enabled;

  final DateTime createdAt;

  /// Four characters, or null for a row minted before one was recorded.
  final String? secretLast4;
}

/// The list AND the vocabulary, in one object because they arrive together.
///
/// [eventClasses] is what this product actually fires, sent as data rather
/// than typed out here: a screen offering a free text box for an event name
/// would invite a subscription to an event that never happens, and the symptom
/// is a call that never arrives — a silence nobody can debug.
class EeWebhooksData {
  const EeWebhooksData({required this.items, required this.eventClasses});

  factory EeWebhooksData.fromJson(Map<String, dynamic> json) => EeWebhooksData(
    items: ((json['items'] as List<dynamic>?) ?? const [])
        .map((e) => EeWebhook.fromJson(e as Map<String, dynamic>))
        .toList(growable: false),
    eventClasses: ((json['eventClasses'] as List<dynamic>?) ?? const [])
        .map((e) => e as String)
        .toList(growable: false),
  );

  final List<EeWebhook> items;
  final List<String> eventClasses;
}

/// An endpoint and the secret that exists in the clear for this one response.
class EeWebhookMinted {
  const EeWebhookMinted({required this.item, required this.secret});

  factory EeWebhookMinted.fromJson(Map<String, dynamic> json) =>
      EeWebhookMinted(
        item: EeWebhook.fromJson(json['item'] as Map<String, dynamic>),
        secret: json['secret'] as String?,
      );

  final EeWebhook item;

  /// Null when the call changed something other than the secret.
  final String? secret;
}

/// One attempt, in the shape EE-079 already uses for mail and push.
///
/// The body is not here, in this screen either: an admin chasing a failure
/// needs to know whether it arrived and why not, never to read what was sent.
class EeWebhookDelivery {
  const EeWebhookDelivery({
    required this.id,
    required this.eventClass,
    required this.status,
    required this.attempts,
    required this.createdAt,
    this.lastError,
    this.sentAt,
  });

  factory EeWebhookDelivery.fromJson(Map<String, dynamic> json) =>
      EeWebhookDelivery(
        id: json['id'] as String,
        eventClass: json['eventClass'] as String? ?? '',
        status: json['status'] as String? ?? 'queued',
        attempts: (json['attempts'] as num?)?.toInt() ?? 0,
        createdAt: DateTime.parse(json['createdAt'] as String).toLocal(),
        lastError: json['lastError'] as String?,
        sentAt: json['sentAt'] == null
            ? null
            : DateTime.parse(json['sentAt'] as String).toLocal(),
      );

  final String id;
  final String eventClass;

  /// `queued`, `sending`, `sent` or `dead` — the outbox's own states, because
  /// a webhook is a row in the same machine as a message.
  final String status;

  final int attempts;
  final DateTime createdAt;
  final String? lastError;
  final DateTime? sentAt;

  bool get failed => status == 'dead';
}
