import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wecord/features/auth/auth_repository.dart';
import 'package:wecord/features/chats/chats_repository.dart';
import 'package:wecord/features/notifications/local_notification_service.dart';
import 'package:wecord/features/notifications/notification_preferences_repository.dart';
import 'package:wecord/shared/models/conversation.dart';

final activeConversationIdProvider = StateProvider<String?>((ref) => null);

final notificationCoordinatorProvider = Provider<NotificationCoordinator>((
  ref,
) {
  final coordinator = NotificationCoordinator(
    authRepository: ref.watch(authRepositoryProvider),
    chatsRepository: ref.watch(chatsRepositoryProvider),
    preferencesRepository: ref.watch(notificationPreferencesRepositoryProvider),
    notificationService: ref.watch(localNotificationServiceProvider),
    activeConversationId: () => ref.read(activeConversationIdProvider),
  );
  ref.onDispose(coordinator.dispose);
  return coordinator;
});

class NotificationCoordinator {
  NotificationCoordinator({
    required AuthRepository authRepository,
    required ChatsRepository chatsRepository,
    required NotificationPreferencesRepository preferencesRepository,
    required LocalNotificationService notificationService,
    required String? Function() activeConversationId,
    DateTime Function()? now,
    Stream<void>? pollTicks,
  }) : _authRepository = authRepository,
       _chatsRepository = chatsRepository,
       _preferencesRepository = preferencesRepository,
       _notificationService = notificationService,
       _activeConversationId = activeConversationId,
       _now = now ?? DateTime.now,
       _pollTicks =
           pollTicks ?? Stream<void>.periodic(const Duration(seconds: 5));

  final AuthRepository _authRepository;
  final ChatsRepository _chatsRepository;
  final NotificationPreferencesRepository _preferencesRepository;
  final LocalNotificationService _notificationService;
  final String? Function() _activeConversationId;
  final DateTime Function() _now;
  final Stream<void> _pollTicks;

  StreamSubscription<void>? _subscription;
  StreamSubscription<void>? _pollSubscription;
  Map<String, ConversationSummary> _previousById = {};
  Future<void>? _baselineLoad;
  var _started = false;
  var _disposed = false;
  var _baselineLoaded = false;
  var _baselineLoadFailed = false;
  var _eventQueuedWhileBaselineLoading = false;
  var _processingReload = false;
  var _reloadQueued = false;
  late DateTime _startedAt;

  Future<void> start() async {
    if (_started || _disposed) {
      return;
    }
    _started = true;
    _startedAt = _now().toUtc();

    _subscription = _chatsRepository.conversationChanges().listen((_) {
      _queueReload();
    });
    _pollSubscription = _pollTicks.listen((_) {
      _queueReload();
    });

    await _ensureBaselineLoaded();
  }

  Future<void> dispose() async {
    _disposed = true;
    final pollSubscription = _pollSubscription;
    final subscription = _subscription;
    _subscription = null;
    _pollSubscription = null;
    await pollSubscription?.cancel();
    await subscription?.cancel();
  }

  void _queueReload() {
    if (_disposed) {
      return;
    }
    if (!_baselineLoaded && _baselineLoad != null) {
      _eventQueuedWhileBaselineLoading = true;
    }
    _reloadQueued = true;
    if (_processingReload) {
      return;
    }
    unawaited(_drainReloadQueue());
  }

  Future<void> _drainReloadQueue() async {
    if (_processingReload) {
      return;
    }
    _processingReload = true;
    try {
      while (_reloadQueued && !_disposed) {
        _reloadQueued = false;
        await _reloadAndNotify();
      }
    } finally {
      _processingReload = false;
    }
  }

  Future<void> _reloadAndNotify() async {
    if (_disposed) {
      return;
    }
    DateTime? startupNotificationCutoff;

    if (_authRepository.currentUser == null) {
      _previousById = {};
      _baselineLoaded = false;
      return;
    }

    if (!_baselineLoaded) {
      final baselineHadFailed = _baselineLoadFailed;
      final shouldNotifyAfterBaseline =
          _eventQueuedWhileBaselineLoading && !baselineHadFailed;
      await _ensureBaselineLoaded();
      if (!_baselineLoaded) {
        return;
      }
      if (baselineHadFailed) {
        _baselineLoadFailed = false;
        _eventQueuedWhileBaselineLoading = false;
        return;
      }
      if (shouldNotifyAfterBaseline) {
        _previousById = {};
        startupNotificationCutoff = _startedAt;
        _eventQueuedWhileBaselineLoading = false;
      }
    }

    final List<ConversationSummary> conversations;
    try {
      conversations = await _chatsRepository.listConversations();
    } catch (_) {
      return;
    }
    if (_disposed) {
      return;
    }

    final previousById = _previousById;
    _previousById = _indexById(conversations);

    final NotificationPreferences preferences;
    try {
      preferences = await _preferencesRepository.load();
    } catch (_) {
      return;
    }
    if (_disposed) {
      return;
    }

    if (!preferences.enabled) {
      return;
    }

    for (final conversation in conversations) {
      if (!_shouldNotify(
        conversation,
        previousById[conversation.id],
        startupNotificationCutoff: startupNotificationCutoff,
      )) {
        continue;
      }
      try {
        await _notificationService.showMessageNotification(
          conversationId: conversation.id,
          title: _notificationTitle(conversation),
          body: _notificationBody(conversation, preferences),
        );
      } catch (_) {
        continue;
      }
    }
  }

  bool _shouldNotify(
    ConversationSummary conversation,
    ConversationSummary? previous, {
    DateTime? startupNotificationCutoff,
  }) {
    if (conversation.id == _activeConversationId()) {
      return false;
    }
    if (conversation.unreadCount <= 0) {
      return false;
    }

    final lastMessageAt = conversation.lastMessageAt;
    if (lastMessageAt == null) {
      return false;
    }
    if (previous == null &&
        startupNotificationCutoff != null &&
        !lastMessageAt.isAfter(startupNotificationCutoff)) {
      return false;
    }

    final previousLastMessageAt = previous?.lastMessageAt;
    if (previousLastMessageAt != null &&
        !lastMessageAt.isAfter(previousLastMessageAt)) {
      return false;
    }

    final currentUserId = _authRepository.currentUser?.id;
    if (currentUserId == null) {
      return false;
    }
    if (conversation.lastMessageSenderId == currentUserId) {
      return false;
    }

    return true;
  }

  Future<void> _ensureBaselineLoaded() {
    if (_baselineLoaded || _disposed || _authRepository.currentUser == null) {
      return Future<void>.value();
    }
    return _baselineLoad ??= _loadBaselineWithoutNotifying().whenComplete(() {
      _baselineLoad = null;
    });
  }

  Future<void> _loadBaselineWithoutNotifying() async {
    try {
      final conversations = await _chatsRepository.listConversations();
      if (!_disposed) {
        _previousById = _indexById(conversations);
        _baselineLoaded = true;
        _baselineLoadFailed = false;
      }
    } catch (_) {
      _baselineLoadFailed = true;
      return;
    }
  }

  String _notificationTitle(ConversationSummary conversation) {
    final title = conversation.title?.trim();
    if (title == null || title.isEmpty) {
      return 'Conversation';
    }
    return title;
  }

  String _notificationBody(
    ConversationSummary conversation,
    NotificationPreferences preferences,
  ) {
    if (preferences.showPreviews) {
      final preview = conversation.lastMessageBody?.trim();
      if (preview != null && preview.isNotEmpty) {
        return preview;
      }
    }
    return 'New message';
  }

  Map<String, ConversationSummary> _indexById(
    List<ConversationSummary> conversations,
  ) {
    return {
      for (final conversation in conversations) conversation.id: conversation,
    };
  }
}
