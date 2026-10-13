import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:wecord/features/chats/chats_screen.dart';
import 'package:wecord/features/circles/circle_events_screen.dart';
import 'package:wecord/features/notifications/local_notification_service.dart';
import 'package:wecord/features/notifications/notification_coordinator.dart';
import 'package:wecord/features/presence/presence_repository.dart';
import 'package:wecord/shared/models/circle_event.dart';

class NotificationShellListener extends ConsumerStatefulWidget {
  const NotificationShellListener({required this.child, super.key});

  final Widget child;

  @override
  ConsumerState<NotificationShellListener> createState() =>
      _NotificationShellListenerState();
}

class _NotificationShellListenerState
    extends ConsumerState<NotificationShellListener> {
  StreamSubscription<String>? _tapSubscription;
  late final NotificationCoordinator _coordinator;

  /// Event reminders are fetched again when the app comes back, since
  /// interest may have changed elsewhere meanwhile.
  late final AppLifecycleListener _lifecycleListener;

  @override
  void initState() {
    super.initState();
    _coordinator = ref.read(notificationCoordinatorProvider);
    _tapSubscription = ref
        .read(localNotificationServiceProvider)
        .notificationTaps()
        .listen(_openConversation);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      unawaited(_coordinator.start());
    });
    _lifecycleListener = AppLifecycleListener(
      onResume: () => unawaited(_coordinator.refreshEventReminders()),
    );
  }

  @override
  void dispose() {
    _lifecycleListener.dispose();
    unawaited(_tapSubscription?.cancel());
    unawaited(_coordinator.dispose());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Stay on the app-wide presence channel while the shell is up, so
    // others see the current user online on every screen.
    ref.listen(onlineUserIdsProvider, (previous, next) {});
    return widget.child;
  }

  void _openConversation(String conversationId) {
    if (!mounted || conversationId.trim().isEmpty) {
      return;
    }
    // Event reminders open their event.
    if (parseCircleEventNotificationPayload(conversationId) case (
      :final circleId,
      :final eventId,
    )) {
      context.go(CircleEventsScreen.pathFor(circleId, eventId: eventId));
      return;
    }
    context.go('${ChatsScreen.path}/$conversationId');
  }
}
