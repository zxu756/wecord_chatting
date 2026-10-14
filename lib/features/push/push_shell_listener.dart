import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:wecord/features/push/push_controller.dart';
import 'package:wecord/features/push/push_repository.dart';

/// While signed in: keeps this browser's push subscription saved for the
/// current account, and opens the chat when a push notification is clicked
/// with the app already open.
class PushShellListener extends ConsumerStatefulWidget {
  const PushShellListener({required this.child, super.key});

  final Widget child;

  @override
  ConsumerState<PushShellListener> createState() => _PushShellListenerState();
}

class _PushShellListenerState extends ConsumerState<PushShellListener> {
  StreamSubscription<String>? _openRequests;

  @override
  void initState() {
    super.initState();
    _openRequests = ref.read(pushGatewayProvider).openRequests.listen((path) {
      if (mounted) {
        GoRouter.maybeOf(context)?.go(path);
      }
    });
  }

  @override
  void dispose() {
    unawaited(_openRequests?.cancel());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Reading the status saves an existing subscription for this account.
    ref.watch(pushStatusProvider);
    return widget.child;
  }
}
