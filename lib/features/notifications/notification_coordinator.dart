import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wecord/features/auth/auth_repository.dart';
import 'package:wecord/features/chats/chats_repository.dart';
import 'package:wecord/features/chats/message_markdown.dart';
import 'package:wecord/features/circles/circles_repository.dart';
import 'package:wecord/features/notifications/local_notification_service.dart';
import 'package:wecord/features/notifications/notification_preferences_repository.dart';
import 'package:wecord/shared/l10n/l10n.dart';
import 'package:wecord/shared/models/circle_emoji.dart';
import 'package:wecord/shared/models/circle_event.dart';
import 'package:wecord/shared/models/circle_notification_settings.dart';
import 'package:wecord/shared/models/conversation.dart';
import 'package:wecord/shared/models/message.dart';
import 'package:wecord/shared/models/poll.dart';

final activeConversationIdProvider = StateProvider<String?>((ref) => null);

final notificationCoordinatorProvider = Provider<NotificationCoordinator>((
  ref,
) {
  final coordinator = NotificationCoordinator(
    authRepository: ref.watch(authRepositoryProvider),
    chatsRepository: ref.watch(chatsRepositoryProvider),
    circlesRepository: ref.watch(circlesRepositoryProvider),
    preferencesRepository: ref.watch(notificationPreferencesRepositoryProvider),
    notificationService: ref.watch(localNotificationServiceProvider),
    activeConversationId: () => ref.read(activeConversationIdProvider),
  );
  ref.onDispose(coordinator.dispose);
  return coordinator;
});

/// Notifies about new messages while the app runs (polling the
/// conversation list), and reminds the current user of events they are
/// interested in [CircleEvent.reminderLead] before they start.
class NotificationCoordinator {
  NotificationCoordinator({
    required AuthRepository authRepository,
    required ChatsRepository chatsRepository,
    CirclesRepository? circlesRepository,
    required NotificationPreferencesRepository preferencesRepository,
    required LocalNotificationService notificationService,
    required String? Function() activeConversationId,
    DateTime Function()? now,
    Stream<void>? pollTicks,
  }) : _authRepository = authRepository,
       _chatsRepository = chatsRepository,
       _circlesRepository = circlesRepository,
       _preferencesRepository = preferencesRepository,
       _notificationService = notificationService,
       _activeConversationId = activeConversationId,
       _now = now ?? DateTime.now,
       _pollTicks =
           pollTicks ?? Stream<void>.periodic(const Duration(seconds: 5));

  final AuthRepository _authRepository;
  final ChatsRepository _chatsRepository;
  final CirclesRepository? _circlesRepository;
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

  /// How often the upcoming event reminders are fetched again, besides
  /// [refreshEventReminders].
  static const eventReminderRefreshInterval = Duration(minutes: 5);

  var _eventReminders = const <CircleEventReminder>[];
  DateTime? _eventRemindersFetchedAt;
  var _fetchingEventReminders = false;
  var _checkingEventReminders = false;

  /// Reminders already shown, by event and start time (a moved event
  /// reminds again).
  final _remindedEventKeys = <String>{};

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
      unawaited(_checkEventReminders());
    });

    await _ensureBaselineLoaded();
    await refreshEventReminders();
  }

  /// Fetches the events to remind about again: after the current user
  /// changes their interest or an event, and when the app comes back.
  Future<void> refreshEventReminders() async {
    final circlesRepository = _circlesRepository;
    if (circlesRepository == null || _disposed || _fetchingEventReminders) {
      return;
    }
    if (_authRepository.currentUser == null) {
      _eventReminders = const [];
      _remindedEventKeys.clear();
      return;
    }
    _fetchingEventReminders = true;
    try {
      _eventReminders = await circlesRepository.listMyEventReminders();
    } catch (_) {
      // Keep the last ones; the next refresh tries again.
    } finally {
      // Also after a failure, so a failing fetch is not retried every tick.
      _eventRemindersFetchedAt = _now();
      _fetchingEventReminders = false;
    }
    await _checkEventReminders();
  }

  Future<void> _checkEventReminders() async {
    if (_disposed ||
        _circlesRepository == null ||
        _checkingEventReminders ||
        _fetchingEventReminders ||
        _authRepository.currentUser == null) {
      return;
    }
    final now = _now();
    final fetchedAt = _eventRemindersFetchedAt;
    if (fetchedAt == null ||
        now.difference(fetchedAt) >= eventReminderRefreshInterval) {
      await refreshEventReminders();
      return;
    }
    final due = [
      for (final reminder in _eventReminders)
        if (!_remindedEventKeys.contains(_reminderKey(reminder)) &&
            !now.isBefore(
              reminder.startsAt.subtract(CircleEvent.reminderLead),
            ) &&
            now.isBefore(reminder.startsAt))
          reminder,
    ];
    if (due.isEmpty) {
      return;
    }
    _checkingEventReminders = true;
    try {
      final NotificationPreferences preferences;
      try {
        preferences = await _preferencesRepository.load();
      } catch (_) {
        return;
      }
      if (_disposed || !preferences.enabled) {
        return;
      }
      for (final reminder in due) {
        _remindedEventKeys.add(_reminderKey(reminder));
        if (reminder.notificationLevel == CircleNotificationLevel.none ||
            isCircleMutedAt(reminder.mutedUntil, now.toUtc())) {
          continue;
        }
        try {
          await _notificationService.showMessageNotification(
            conversationId: circleEventNotificationPayload(
              reminder.circleId,
              reminder.eventId,
            ),
            title: reminder.title,
            body: _eventReminderBody(reminder, now),
          );
        } catch (_) {
          continue;
        }
      }
    } finally {
      _checkingEventReminders = false;
    }
  }

  String _reminderKey(CircleEventReminder reminder) {
    return '${reminder.eventId}@${reminder.startsAt.toUtc().toIso8601String()}';
  }

  String _eventReminderBody(CircleEventReminder reminder, DateTime now) {
    final seconds = reminder.startsAt.difference(now).inSeconds;
    final minutes = (seconds / 60).ceil().clamp(1, 24 * 60);
    return [
      minutes == 1
          ? tr('Starts in 1 minute')
          : tr('Starts in {minutes} minutes', {'minutes': minutes}),
      if (reminder.circleName.trim().isNotEmpty) reminder.circleName.trim(),
      if (reminder.location case final location? when location.isNotEmpty)
        location,
    ].join(' · ');
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
    if (conversation.isMuted && !_mentionsCurrentUser(conversation)) {
      return false;
    }
    if (!_circleAllows(conversation)) {
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
    // Webhook messages are sent as the webhook's creator but are not
    // theirs, so they alert the creator too.
    if (conversation.lastMessageSenderId == currentUserId &&
        conversation.lastMessageWebhookName == null) {
      return false;
    }
    // System notices such as "X pinned a message." do not alert.
    if (conversation.lastMessageType == MessageType.system) {
      return false;
    }

    return true;
  }

  /// Circle channels follow the circle's notification settings: a muted
  /// circle stays silent, 'none' never notifies and 'mentions' only when
  /// the latest message mentions the current user.
  bool _circleAllows(ConversationSummary conversation) {
    if (conversation.circleId == null) {
      return true;
    }
    if (isCircleMutedAt(conversation.circleMutedUntil, _now().toUtc())) {
      return false;
    }
    return switch (conversation.circleNotificationLevel ??
        CircleNotificationLevel.all) {
      CircleNotificationLevel.all => true,
      CircleNotificationLevel.mentions => _mentionsCurrentUser(conversation),
      CircleNotificationLevel.none => false,
    };
  }

  bool _mentionsCurrentUser(ConversationSummary conversation) {
    final currentUserId = _authRepository.currentUser?.id;
    return currentUserId != null &&
        conversation.mentionedUserIds.contains(currentUserId);
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
      return tr('Conversation');
    }
    return title;
  }

  String _notificationBody(
    ConversationSummary conversation,
    NotificationPreferences preferences,
  ) {
    if (preferences.showPreviews) {
      final body = conversation.lastMessageBody?.trim();
      final preview = body == null
          ? null
          : switch (conversation.lastMessageType ?? MessageType.text) {
              MessageType.text => plainTextFromMarkdown(body).trim(),
              MessageType.poll => pollPreviewText(body),
              MessageType.sticker => stickerPreviewText(body),
              _ => body,
            };
      if (preview != null && preview.isNotEmpty) {
        return preview;
      }
    }
    return tr('New message');
  }

  Map<String, ConversationSummary> _indexById(
    List<ConversationSummary> conversations,
  ) {
    return {
      for (final conversation in conversations) conversation.id: conversation,
    };
  }
}
