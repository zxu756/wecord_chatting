import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show ProviderException;
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:wecord/features/privacy/device_info.dart';
import 'package:wecord/shared/api/supabase_providers.dart';

/// One signed-in session of the current user.
class DeviceSession {
  const DeviceSession({
    required this.sessionId,
    required this.deviceName,
    required this.platform,
    required this.appVersion,
    required this.userAgent,
    required this.createdAt,
    required this.lastActiveAt,
    required this.isCurrent,
  });

  factory DeviceSession.fromJson(Map<String, dynamic> json) {
    return DeviceSession(
      sessionId: json['session_id'] as String,
      deviceName: json['device_name'] as String? ?? '',
      platform: json['platform'] as String? ?? '',
      appVersion: json['app_version'] as String? ?? '',
      userAgent: json['user_agent'] as String? ?? '',
      createdAt: DateTime.parse(json['created_at'] as String).toUtc(),
      lastActiveAt: DateTime.parse(json['last_active_at'] as String).toUtc(),
      isCurrent: json['is_current'] == true,
    );
  }

  final String sessionId;
  final String deviceName;
  final String platform;
  final String appVersion;
  final String userAgent;
  final DateTime createdAt;
  final DateTime lastActiveAt;
  final bool isCurrent;

  /// What to call it: the recorded name, else what the browser says, else
  /// the platform; empty when nothing is known (the list says "Unknown
  /// device").
  String get title {
    if (deviceName.isNotEmpty) {
      return deviceName;
    }
    final fromAgent = describeUserAgent(userAgent);
    return fromAgent.isNotEmpty ? fromAgent : platform;
  }
}

/// The user's sessions: listing, recording this device, signing others out.
abstract interface class DevicesRepository {
  Future<List<DeviceSession>> list();

  /// Tells the server what this session is (name, platform, version).
  Future<void> registerCurrentDevice();

  /// Signs out every session but this one.
  Future<void> signOutOthers();

  /// Signs out one other session.
  Future<void> revoke(String sessionId);
}

class SupabaseDevicesRepository implements DevicesRepository {
  const SupabaseDevicesRepository(this._client);

  final SupabaseClient _client;

  @override
  Future<List<DeviceSession>> list() async {
    final rows = await _client.rpc<List<dynamic>>('list_my_sessions');
    return [
      for (final row in rows)
        DeviceSession.fromJson(row as Map<String, dynamic>),
    ];
  }

  @override
  Future<void> registerCurrentDevice() async {
    if (_client.auth.currentSession == null) {
      return;
    }
    final device = currentDevice();
    await _client.rpc<void>(
      'register_device',
      params: {
        'device_name': device.name,
        'platform': device.platform,
        'app_version': device.appVersion,
      },
    );
  }

  @override
  Future<void> signOutOthers() {
    return _client.auth.signOut(scope: SignOutScope.others);
  }

  @override
  Future<void> revoke(String sessionId) async {
    final response = await _client.functions.invoke(
      'sessions',
      body: {'session_id': sessionId},
    );
    final data = response.data;
    if (data is Map && data['revoked'] == true) {
      return;
    }
    throw StateError('The device could not be signed out.');
  }
}

class _UninitializedDevicesRepository implements DevicesRepository {
  const _UninitializedDevicesRepository();

  @override
  Future<List<DeviceSession>> list() async => const [];

  @override
  Future<void> registerCurrentDevice() async {}

  @override
  Future<void> signOutOthers() {
    throw StateError('Supabase must be initialized before signing out.');
  }

  @override
  Future<void> revoke(String sessionId) {
    throw StateError('Supabase must be initialized before signing out.');
  }
}

final devicesRepositoryProvider = Provider<DevicesRepository>((ref) {
  try {
    return SupabaseDevicesRepository(ref.watch(supabaseClientProvider));
  } on ProviderException {
    return const _UninitializedDevicesRepository();
  }
});

/// The signed-in sessions, this device first.
final deviceSessionsProvider = FutureProvider.autoDispose<List<DeviceSession>>((
  ref,
) {
  return ref.watch(devicesRepositoryProvider).list();
});
