import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wecord/features/notifications/notification_service_base.dart';
import 'package:wecord/features/notifications/web_local_notification_service.dart';
import 'package:wecord/features/notifications/web_notification_gateway_stub.dart'
    if (dart.library.html) 'package:wecord/features/notifications/web_notification_gateway_html.dart';

export 'package:wecord/features/notifications/notification_service_base.dart';

const _permissionRequestedKey = 'wecord.notifications.permission_requested';

final localNotificationServiceProvider = Provider<LocalNotificationService>((
  ref,
) {
  late final LocalNotificationService service;
  if (kIsWeb) {
    service = WebLocalNotificationService(
      gateway: createWebNotificationGateway(),
    );
  } else {
    service = FlutterLocalNotificationService();
  }
  ref.onDispose(service.dispose);
  return service;
});

class FlutterLocalNotificationService implements LocalNotificationService {
  FlutterLocalNotificationService({FlutterLocalNotificationsPlugin? plugin})
    : _plugin = plugin ?? FlutterLocalNotificationsPlugin();

  final FlutterLocalNotificationsPlugin _plugin;
  final _tapController = StreamController<String>.broadcast();
  Future<void>? _initialization;

  @override
  Future<NotificationPermissionStatus> permissionStatus() async {
    if (kIsWeb) {
      return NotificationPermissionStatus.unavailable;
    }
    await _ensureInitialized();
    final darwinStatus = await _darwinPermissionStatus();
    if (darwinStatus != null) {
      return darwinStatus;
    }
    final androidStatus = await _androidPermissionStatus();
    if (androidStatus != null) {
      return androidStatus;
    }
    return NotificationPermissionStatus.granted;
  }

  @override
  Future<NotificationPermissionStatus> requestPermission() async {
    if (kIsWeb) {
      return NotificationPermissionStatus.unavailable;
    }
    await _ensureInitialized();

    final ios = _plugin
        .resolvePlatformSpecificImplementation<
          IOSFlutterLocalNotificationsPlugin
        >();
    final iosGranted = await ios?.requestPermissions(
      alert: true,
      badge: true,
      sound: true,
    );
    if (iosGranted != null) {
      await _markPermissionRequested();
      return _statusFromGranted(iosGranted);
    }

    final macOS = _plugin
        .resolvePlatformSpecificImplementation<
          MacOSFlutterLocalNotificationsPlugin
        >();
    final macOSGranted = await macOS?.requestPermissions(
      alert: true,
      badge: true,
      sound: true,
    );
    if (macOSGranted != null) {
      await _markPermissionRequested();
      return _statusFromGranted(macOSGranted);
    }

    final android = _plugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >();
    final androidGranted = await android?.requestNotificationsPermission();
    if (androidGranted != null) {
      await _markPermissionRequested();
      return _statusFromGranted(androidGranted);
    }

    return NotificationPermissionStatus.granted;
  }

  @override
  Future<void> showMessageNotification({
    required String conversationId,
    required String title,
    required String body,
  }) async {
    if (kIsWeb) {
      return;
    }
    await _ensureInitialized();
    final status = await _permissionStatusForShow();
    if (status != NotificationPermissionStatus.granted) {
      return;
    }
    await _plugin.show(
      id: _notificationIdForConversation(conversationId),
      title: title,
      body: body,
      notificationDetails: const NotificationDetails(
        android: AndroidNotificationDetails(
          'wecord_messages',
          'Messages',
          channelDescription: 'Incoming WeCord message notifications',
          importance: Importance.high,
          priority: Priority.high,
        ),
        iOS: DarwinNotificationDetails(
          presentAlert: true,
          presentBadge: true,
          presentSound: true,
          presentBanner: true,
          presentList: true,
        ),
        macOS: DarwinNotificationDetails(
          presentAlert: true,
          presentBadge: true,
          presentSound: true,
          presentBanner: true,
          presentList: true,
        ),
      ),
      payload: conversationId,
    );
  }

  @override
  Stream<String> notificationTaps() => _tapController.stream;

  @override
  void dispose() {
    unawaited(_tapController.close());
  }

  Future<void> _ensureInitialized() {
    return _initialization ??= _plugin
        .initialize(
          settings: const InitializationSettings(
            android: AndroidInitializationSettings('@mipmap/ic_launcher'),
            iOS: DarwinInitializationSettings(
              requestAlertPermission: false,
              requestBadgePermission: false,
              requestSoundPermission: false,
            ),
            macOS: DarwinInitializationSettings(
              requestAlertPermission: false,
              requestBadgePermission: false,
              requestSoundPermission: false,
            ),
          ),
          onDidReceiveNotificationResponse: (response) {
            final payload = response.payload;
            if (payload != null && payload.isNotEmpty) {
              _tapController.add(payload);
            }
          },
        )
        .then((_) async {
          final launchDetails = await _plugin.getNotificationAppLaunchDetails();
          final payload = launchDetails?.notificationResponse?.payload;
          if (launchDetails?.didNotificationLaunchApp ?? false) {
            if (payload != null && payload.isNotEmpty) {
              _tapController.add(payload);
            }
          }
        });
  }

  Future<NotificationPermissionStatus?> _darwinPermissionStatus() async {
    final ios = _plugin
        .resolvePlatformSpecificImplementation<
          IOSFlutterLocalNotificationsPlugin
        >();
    final iosPermissions = await ios?.checkPermissions();
    if (iosPermissions != null) {
      return _statusFromDarwinPermissions(iosPermissions);
    }

    final macOS = _plugin
        .resolvePlatformSpecificImplementation<
          MacOSFlutterLocalNotificationsPlugin
        >();
    final macOSPermissions = await macOS?.checkPermissions();
    if (macOSPermissions != null) {
      return _statusFromDarwinPermissions(macOSPermissions);
    }
    return null;
  }

  Future<NotificationPermissionStatus?> _androidPermissionStatus() async {
    final android = _plugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >();
    final enabled = await android?.areNotificationsEnabled();
    return enabled == null ? null : _statusFromGranted(enabled);
  }

  Future<NotificationPermissionStatus> _permissionStatusForShow() async {
    final status = await permissionStatus();
    if (status == NotificationPermissionStatus.notRequested) {
      return requestPermission();
    }
    return status;
  }

  NotificationPermissionStatus _statusFromGranted(bool granted) {
    return granted
        ? NotificationPermissionStatus.granted
        : NotificationPermissionStatus.denied;
  }

  Future<NotificationPermissionStatus> _statusFromDarwinPermissions(
    NotificationsEnabledOptions permissions,
  ) async {
    if (permissions.isEnabled) {
      return NotificationPermissionStatus.granted;
    }
    return await _hasRequestedPermission()
        ? NotificationPermissionStatus.denied
        : NotificationPermissionStatus.notRequested;
  }

  Future<bool> _hasRequestedPermission() async {
    final preferences = await SharedPreferences.getInstance();
    return preferences.getBool(_permissionRequestedKey) ?? false;
  }

  Future<void> _markPermissionRequested() async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.setBool(_permissionRequestedKey, true);
  }

  int _notificationIdForConversation(String conversationId) {
    return conversationId.hashCode & 0x7fffffff;
  }
}
