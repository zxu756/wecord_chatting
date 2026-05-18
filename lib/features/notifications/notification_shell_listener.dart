import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:wecord/features/chats/chats_screen.dart';
import 'package:wecord/features/notifications/local_notification_service.dart';
import 'package:wecord/features/notifications/notification_coordinator.dart';

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

  @override
  void initState() {
    super.initState();
    _tapSubscription = ref
        .read(localNotificationServiceProvider)
        .notificationTaps()
        .listen(_openConversation);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      unawaited(ref.read(notificationCoordinatorProvider).start());
    });
  }

  @override
  void dispose() {
    unawaited(_tapSubscription?.cancel());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;

  void _openConversation(String conversationId) {
    if (!mounted || conversationId.trim().isEmpty) {
      return;
    }
    context.go('${ChatsScreen.path}/$conversationId');
  }
}
