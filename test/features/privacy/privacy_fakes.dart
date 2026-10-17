import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:wecord/features/privacy/devices_repository.dart';

/// Devices signed in to the sample account: this Mac, a phone and a browser.
class FakeDevicesRepository implements DevicesRepository {
  FakeDevicesRepository([List<DeviceSession>? sessions])
    : sessions = sessions ?? sampleDeviceSessions();

  List<DeviceSession> sessions;

  @override
  Future<List<DeviceSession>> list() async => sessions;

  @override
  Future<void> registerCurrentDevice() async {}

  @override
  Future<void> signOutOthers() async {
    sessions = [
      for (final session in sessions)
        if (session.isCurrent) session,
    ];
  }

  @override
  Future<void> revoke(String sessionId) async {
    sessions = [
      for (final session in sessions)
        if (session.sessionId != sessionId) session,
    ];
  }
}

List<DeviceSession> sampleDeviceSessions() {
  final now = DateTime.now().toUtc();
  return [
    DeviceSession(
      sessionId: 'mac',
      deviceName: 'Ada\'s MacBook Pro',
      platform: 'macOS',
      appVersion: '0.1.0',
      userAgent: '',
      createdAt: now.subtract(const Duration(days: 30)),
      lastActiveAt: now,
      isCurrent: true,
    ),
    DeviceSession(
      sessionId: 'phone',
      deviceName: 'iPhone or iPad',
      platform: 'iOS',
      appVersion: '0.1.0',
      userAgent: '',
      createdAt: now.subtract(const Duration(days: 12)),
      lastActiveAt: now.subtract(const Duration(hours: 2)),
      isCurrent: false,
    ),
    DeviceSession(
      sessionId: 'web',
      deviceName: 'Chrome on Windows',
      platform: 'Web',
      appVersion: '0.1.0',
      userAgent: '',
      createdAt: now.subtract(const Duration(days: 40)),
      lastActiveAt: now.subtract(const Duration(days: 6)),
      isCurrent: false,
    ),
  ];
}

List<Override> deviceOverrides([FakeDevicesRepository? repository]) => [
  devicesRepositoryProvider.overrideWithValue(
    repository ?? FakeDevicesRepository(),
  ),
];
