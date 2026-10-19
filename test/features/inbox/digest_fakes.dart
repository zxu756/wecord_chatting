// A digest repository for tests, and sample digests.
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:wecord/features/ai/ai_repository.dart';
import 'package:wecord/features/inbox/digest/digest_models.dart';
import 'package:wecord/features/inbox/digest/digest_repository.dart';


/// Digests and settings kept in memory, calls recorded.
class FakeDigestRepository implements DigestRepository {
  FakeDigestRepository({List<AiDigest>? digests, DigestSettings? settings})
    : digests = digests ?? [sampleDigest()],
      current = settings ?? sampleSettings();

  List<AiDigest> digests;
  DigestSettings current;

  final readCalls = <List<String>>[];
  final saved = <({bool? enabled, int? hour, int? minute, String? language})>[];
  final followCalls = <({String id, bool subscribed, String? language})>[];

  /// Thrown by every call when set.
  Object? error;

  /// Thrown by [setSubscription] when set (the server's 10 chat limit, say).
  Object? followError;

  @override
  Future<List<AiDigest>> list() async {
    if (error case final error?) {
      throw error;
    }
    return digests;
  }

  @override
  Future<void> markRead(List<String> ids) async {
    readCalls.add(ids);
    digests = [
      for (final digest in digests)
        if (ids.contains(digest.id))
          AiDigest(
            id: digest.id,
            localDate: digest.localDate,
            createdAt: digest.createdAt,
            items: digest.items,
            readAt: DateTime.now(),
          )
        else
          digest,
    ];
  }

  @override
  Future<DigestSettings> settings() async {
    if (error case final error?) {
      throw error;
    }
    return current;
  }

  @override
  Future<void> saveSettings({
    bool? enabled,
    int? hour,
    int? minute,
    String? language,
  }) async {
    if (error case final error?) {
      throw error;
    }
    saved.add((
      enabled: enabled,
      hour: hour,
      minute: minute,
      language: language,
    ));
    current = DigestSettings(
      enabled: enabled ?? current.enabled,
      hour: hour ?? current.hour,
      minute: hour == null ? current.minute : minute ?? 0,
      language: language ?? current.language,
      timeZone: current.timeZone,
      maxSubscriptions: current.maxSubscriptions,
      subscriptions: current.subscriptions,
    );
  }

  @override
  Future<int> setSubscription(
    String conversationId, {
    required bool subscribed,
    String? language,
  }) async {
    followCalls.add((
      id: conversationId,
      subscribed: subscribed,
      language: language,
    ));
    if (followError case final error?) {
      throw error;
    }
    final others = [
      for (final subscription in current.subscriptions)
        if (subscription.conversationId != conversationId) subscription,
    ];
    if (subscribed && others.length >= current.maxSubscriptions) {
      throw const DigestLimitReached();
    }
    current = DigestSettings(
      enabled: current.enabled,
      hour: current.hour,
      minute: current.minute,
      language: language ?? current.language,
      timeZone: current.timeZone,
      maxSubscriptions: current.maxSubscriptions,
      subscriptions: [
        ...others,
        if (subscribed)
          DigestSubscription(conversationId: conversationId, title: 'Chat'),
      ],
    );
    return current.subscriptions.length;
  }
}

/// Two chats: a group and a circle channel.
AiDigest sampleDigest({
  String id = 'digest-1',
  DateTime? readAt,
  List<DigestChatSummary>? items,
}) {
  final now = DateTime.now();
  return AiDigest(
    id: id,
    localDate: DateTime(now.year, now.month, now.day),
    createdAt: DateTime(now.year, now.month, now.day, 8),
    readAt: readAt,
    items:
        items ??
        const [
          DigestChatSummary(
            conversationId: 'group-1',
            title: 'Weekend climbers',
            summary:
                '- Bart asked who can book the 9am train on Friday\n'
                '- Grace will bring snacks; everyone packs a headlamp',
            messageCount: 12,
          ),
          DigestChatSummary(
            conversationId: 'conv-general',
            title: 'general',
            circleName: 'Hikers',
            summary: '- The meetup moved to 5pm on Saturday',
            messageCount: 1,
          ),
        ],
  );
}

DigestSettings sampleSettings({
  bool enabled = true,
  List<DigestSubscription>? subscriptions,
  int max = 10,
}) {
  return DigestSettings(
    enabled: enabled,
    hour: 8,
    minute: 0,
    timeZone: 'Asia/Shanghai',
    maxSubscriptions: max,
    subscriptions:
        subscriptions ??
        const [
          DigestSubscription(
            conversationId: 'group-1',
            title: 'Weekend climbers',
          ),
        ],
  );
}

List<Override> digestOverrides(
  FakeDigestRepository repository, {
  bool aiEnabled = true,
}) => [
  digestRepositoryProvider.overrideWithValue(repository),
  aiEnabledStoreProvider.overrideWithValue(InMemoryAiEnabledStore(aiEnabled)),
];
