import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wecord/features/location/live_location_map_screen.dart';
import 'package:wecord/features/location/live_location_sharer.dart';
import 'package:wecord/features/location/live_location_start_sheet.dart';
import 'package:wecord/features/location/location_picker_screen.dart';
import 'package:wecord/features/location/location_repository.dart';
import 'package:wecord/features/location/location_service.dart';
import 'package:wecord/shared/l10n/l10n.dart';

void _say(
  ScaffoldMessengerState? messenger,
  String message, {
  SnackBarAction? action,
}) {
  messenger?.showSnackBar(
    SnackBar(
      content: Text(message),
      action: action,
      duration: const Duration(seconds: 4),
    ),
  );
}

/// The chat's "Location" action: pick a place on the map and send it as a
/// card.
Future<void> sendLocationFlow(
  BuildContext context,
  WidgetRef ref, {
  required String conversationId,
}) async {
  final repository = ref.read(locationRepositoryProvider);
  final messenger = ScaffoldMessenger.maybeOf(context);
  final place = await showLocationPicker(context);
  if (place == null || !context.mounted) {
    return;
  }
  try {
    await repository.sendLocation(conversationId, place);
  } on Object {
    _say(messenger, tr("Couldn't send the location. Try again."));
  }
}

/// The chat's "Share live location" action: asks for consent (how long,
/// precise or approximate), starts sharing and opens the map.
Future<void> shareLiveLocationFlow(
  BuildContext context,
  WidgetRef ref, {
  required String conversationId,
  bool openMap = true,
}) async {
  final sharer = ref.read(liveLocationSharerProvider.notifier);
  final service = ref.read(locationServiceProvider);
  final messenger = ScaffoldMessenger.maybeOf(context);
  final choice = await showLiveLocationConsent(context);
  if (choice == null || !context.mounted) {
    return;
  }
  try {
    await sharer.start(
      conversationId: conversationId,
      duration: choice.duration,
      precise: choice.precise,
    );
  } on LocationNotAllowed catch (error) {
    _say(
      messenger,
      switch (error.access) {
        LocationAccess.deniedForever => tr(
          'Location is off for WeCord. Turn it on in Settings to share it.',
        ),
        LocationAccess.serviceOff => tr(
          'Location services are off on this device.',
        ),
        _ => tr('WeCord needs your location to share it.'),
      },
      action: error.access == LocationAccess.deniedForever
          ? SnackBarAction(
              label: tr('Open settings'),
              onPressed: () => unawaited(service.openSettings()),
            )
          : null,
    );
    return;
  } on LocationRefused {
    _say(messenger, tr("Couldn't start sharing here."));
    return;
  } on Object {
    _say(messenger, tr("Couldn't start sharing. Try again."));
    return;
  }
  if (openMap && context.mounted) {
    await showLiveLocationMap(context, conversationId: conversationId);
  }
}
