import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// What a phone tells the app about its own screen (roadmap G7).
enum ScreenCaptureEvent {
  /// The person took a screenshot (the system says so after the fact).
  screenshot,

  /// The screen started being recorded, mirrored or cast.
  recordingStarted,

  /// The recording, mirroring or casting ended.
  recordingStopped,
}

/// The device's screenshot and screen recording signals.
///
/// Only iOS and iPadOS give an app these two signals
/// (`UIApplication.userDidTakeScreenshotNotification` and
/// `UIScreen.isCaptured`). Android can only block capture, not report it;
/// macOS and the web have no signal at all. A device without one says so
/// ([detects] is false) and nothing in the app pretends otherwise.
abstract interface class ScreenCaptureService {
  /// Whether this device can tell the app about screenshots and recordings.
  bool get detects;

  /// Whether the screen is being recorded, mirrored or cast right now.
  Future<bool> isRecording();

  /// Screenshots and recordings, as they happen.
  Stream<ScreenCaptureEvent> get events;
}

/// iOS: a small native plugin (ios/Runner/ScreenCapturePlugin.swift).
class IosScreenCaptureService implements ScreenCaptureService {
  IosScreenCaptureService({MethodChannel? methods, EventChannel? eventChannel})
    : _methods = methods ?? const MethodChannel(channelName),
      _events = eventChannel ?? const EventChannel(eventChannelName);

  static const channelName = 'wecord/screen_capture';
  static const eventChannelName = 'wecord/screen_capture/events';

  final MethodChannel _methods;
  final EventChannel _events;

  @override
  bool get detects => true;

  @override
  Future<bool> isRecording() async {
    try {
      return await _methods.invokeMethod<bool>('isCaptured') ?? false;
    } on PlatformException {
      return false;
    } on MissingPluginException {
      return false;
    }
  }

  @override
  Stream<ScreenCaptureEvent> get events => _events
      .receiveBroadcastStream()
      .map<ScreenCaptureEvent?>(parseScreenCaptureEvent)
      .where((event) => event != null)
      .cast<ScreenCaptureEvent>();
}

/// The event name the native side sends, or null for one this app does not
/// know (a newer native build).
@visibleForTesting
ScreenCaptureEvent? parseScreenCaptureEvent(Object? raw) {
  return switch (raw) {
    'screenshot' => ScreenCaptureEvent.screenshot,
    'recording_started' => ScreenCaptureEvent.recordingStarted,
    'recording_stopped' => ScreenCaptureEvent.recordingStopped,
    _ => null,
  };
}

/// Everything else (Android, macOS, the web): no signal, no events.
class UnsupportedScreenCaptureService implements ScreenCaptureService {
  const UnsupportedScreenCaptureService();

  @override
  bool get detects => false;

  @override
  Future<bool> isRecording() async => false;

  @override
  Stream<ScreenCaptureEvent> get events => const Stream.empty();
}

/// The service for this device. Tests override it.
final screenCaptureServiceProvider = Provider<ScreenCaptureService>((ref) {
  if (!kIsWeb && defaultTargetPlatform == TargetPlatform.iOS) {
    return IosScreenCaptureService();
  }
  return const UnsupportedScreenCaptureService();
});

/// Whether this device can tell about screenshots and recordings.
final screenCaptureDetectsProvider = Provider<bool>(
  (ref) => ref.watch(screenCaptureServiceProvider).detects,
);
