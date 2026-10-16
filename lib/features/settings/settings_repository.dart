import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show ProviderException;
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:wecord/shared/api/signed_url_refresh.dart';
import 'package:wecord/shared/api/supabase_providers.dart';
import 'package:wecord/shared/models/profile.dart';

final settingsRepositoryProvider = Provider<SettingsRepository>((ref) {
  try {
    return SupabaseSettingsRepository(ref.watch(supabaseClientProvider));
  } on ProviderException {
    return const _UninitializedSettingsRepository();
  }
});

final avatarDisplayUrlProvider = FutureProvider.autoDispose
    .family<String?, String?>((ref, avatarUrl) {
      if (avatarUrl == null || avatarUrl.trim().isEmpty) {
        return Future.value();
      }
      final uri = Uri.tryParse(avatarUrl);
      if (uri != null && (uri.scheme == 'http' || uri.scheme == 'https')) {
        return Future.value(avatarUrl);
      }
      return ref.watch(settingsRepositoryProvider).createAvatarUrl(avatarUrl);
    });

/// Signs a stored avatar again after its image failed to load (the signed
/// URL may have expired), at most once every few minutes per avatar.
void refreshAvatarDisplayUrl(WidgetRef ref, String? avatarUrl) {
  if (avatarUrl == null || avatarUrl.trim().isEmpty) {
    return;
  }
  final uri = Uri.tryParse(avatarUrl);
  if (uri != null && (uri.scheme == 'http' || uri.scheme == 'https')) {
    return;
  }
  refreshSignedUrlSoon('avatar:$avatarUrl', () {
    try {
      ref.invalidate(avatarDisplayUrlProvider(avatarUrl));
    } catch (_) {
      // The widget is gone; the next one to show the avatar signs it.
    }
  });
}

abstract interface class SettingsRepository {
  Future<Profile> currentProfile();

  Future<void> updateProfile({
    required String displayName,
    required String bio,
    required String? avatarUrl,
  });

  Future<String> uploadAvatar({
    required String fileName,
    required String mimeType,
    required Uint8List bytes,
  });

  Future<String> createAvatarUrl(String avatarPath);

  Future<List<Profile>> listBlockedUsers();

  Future<void> unblockUser(String userId);

  /// Sets the current user's status; blank [emoji] and [text] clear it. A
  /// null [expiresAt] keeps it until changed.
  Future<void> setCustomStatus({
    String? emoji,
    String? text,
    DateTime? expiresAt,
  });
}

abstract interface class SettingsDataSource {
  Future<Map<String, dynamic>> currentProfile(String currentUserId);

  Future<List<Map<String, dynamic>>> listBlockedUsers(String currentUserId);

  Future<void> rpc(String functionName, Map<String, dynamic> params);

  Future<void> uploadBinary({
    required String bucket,
    required String path,
    required Uint8List bytes,
    required String mimeType,
  });

  Future<String> createSignedUrl({
    required String bucket,
    required String path,
    required Duration expiresIn,
  });
}

class SupabaseSettingsRepository implements SettingsRepository {
  SupabaseSettingsRepository(SupabaseClient client)
    : this.withDataSource(
        SupabaseSettingsDataSource(client),
        currentUserId: () => client.auth.currentUser?.id,
      );

  const SupabaseSettingsRepository.withDataSource(
    this._dataSource, {
    required this._currentUserId,
    this._storagePathSeed,
    this._storageOperationTimeout = const Duration(seconds: 30),
  });

  final SettingsDataSource _dataSource;
  final String? Function() _currentUserId;
  final String Function()? _storagePathSeed;
  final Duration _storageOperationTimeout;

  @override
  Future<Profile> currentProfile() async {
    final row = await _dataSource.currentProfile(_requireCurrentUserId());
    return Profile.fromJson(row);
  }

  @override
  Future<List<Profile>> listBlockedUsers() async {
    final rows = await _dataSource.listBlockedUsers(_requireCurrentUserId());
    return rows
        .map((row) => Profile.fromJson(row['blocked'] as Map<String, dynamic>))
        .toList(growable: false);
  }

  @override
  Future<void> unblockUser(String userId) async {
    await _dataSource.rpc('unblock_user', {'target_user_id': userId});
  }

  @override
  Future<void> setCustomStatus({
    String? emoji,
    String? text,
    DateTime? expiresAt,
  }) async {
    final trimmedEmoji = emoji?.trim() ?? '';
    final trimmedText = text?.trim() ?? '';
    final clearing = trimmedEmoji.isEmpty && trimmedText.isEmpty;
    await _dataSource.rpc('set_custom_status', {
      'emoji': trimmedEmoji.isEmpty ? null : trimmedEmoji,
      'text': trimmedText.isEmpty ? null : trimmedText,
      'expires_at': clearing ? null : expiresAt?.toUtc().toIso8601String(),
    });
  }

  @override
  Future<void> updateProfile({
    required String displayName,
    required String bio,
    required String? avatarUrl,
  }) async {
    await _dataSource.rpc('update_current_user_profile', {
      'display_name': displayName,
      'bio': bio,
      'avatar_url': avatarUrl,
    });
  }

  @override
  Future<String> uploadAvatar({
    required String fileName,
    required String mimeType,
    required Uint8List bytes,
  }) async {
    const bucket = 'profile-avatars';
    final path =
        '${_requireCurrentUserId()}/${_nextStoragePathSeed()}-${_safeFileName(fileName)}';
    await _withStorageTimeout(
      _dataSource.uploadBinary(
        bucket: bucket,
        path: path,
        bytes: bytes,
        mimeType: mimeType,
      ),
    );
    return path;
  }

  @override
  Future<String> createAvatarUrl(String avatarPath) {
    final uri = Uri.tryParse(avatarPath);
    if (uri != null && (uri.scheme == 'http' || uri.scheme == 'https')) {
      return Future.value(avatarPath);
    }
    final storagePath = _avatarStoragePath(avatarPath);
    return _withStorageTimeout(
      _dataSource.createSignedUrl(
        bucket: storagePath.bucket,
        path: storagePath.path,
        expiresIn: const Duration(hours: 1),
      ),
    );
  }

  String _requireCurrentUserId() {
    final userId = _currentUserId();
    if (userId == null) {
      throw StateError('A signed-in user is required for settings.');
    }
    return userId;
  }

  String _nextStoragePathSeed() {
    return _storagePathSeed?.call() ??
        DateTime.now().toUtc().microsecondsSinceEpoch.toString();
  }

  Future<T> _withStorageTimeout<T>(Future<T> operation) {
    return operation.timeout(
      _storageOperationTimeout,
      onTimeout: () {
        throw TimeoutException(
          'Avatar storage request timed out',
          _storageOperationTimeout,
        );
      },
    );
  }

  String _safeFileName(String fileName) {
    final normalized = fileName.trim().toLowerCase();
    final sanitized = normalized
        .replaceAll(RegExp(r'[^a-z0-9._-]+'), '-')
        .replaceAll(RegExp(r'-+'), '-')
        .replaceAll(RegExp(r'^[-.]+|[-.]+$'), '');
    return sanitized.isEmpty ? 'avatar.jpg' : sanitized;
  }

  _AvatarStoragePath _avatarStoragePath(String avatarPath) {
    for (final bucket in [
      'profile-avatars',
      'group-avatars',
      'profile-banners',
    ]) {
      final prefix = '$bucket/';
      if (avatarPath.startsWith(prefix)) {
        return _AvatarStoragePath(
          bucket: bucket,
          path: avatarPath.substring(prefix.length),
        );
      }
    }
    return _AvatarStoragePath(bucket: 'profile-avatars', path: avatarPath);
  }
}

class _AvatarStoragePath {
  const _AvatarStoragePath({required this.bucket, required this.path});

  final String bucket;
  final String path;
}

class SupabaseSettingsDataSource implements SettingsDataSource {
  const SupabaseSettingsDataSource(this._client);

  final SupabaseClient _client;

  @override
  Future<Map<String, dynamic>> currentProfile(String currentUserId) async {
    final row = await _client
        .from('profiles')
        .select('*,custom_status')
        .eq('id', currentUserId)
        .single();
    return row;
  }

  @override
  Future<List<Map<String, dynamic>>> listBlockedUsers(
    String currentUserId,
  ) async {
    final rows = await _client
        .from('blocks')
        .select('blocked:profiles!blocks_blocked_id_fkey(*)')
        .eq('blocker_id', currentUserId)
        .order('created_at');
    return rows;
  }

  @override
  Future<void> rpc(String functionName, Map<String, dynamic> params) async {
    await _client.rpc(functionName, params: params);
  }

  @override
  Future<void> uploadBinary({
    required String bucket,
    required String path,
    required Uint8List bytes,
    required String mimeType,
  }) async {
    await _client.storage
        .from(bucket)
        .uploadBinary(
          path,
          bytes,
          fileOptions: FileOptions(contentType: mimeType, upsert: false),
        );
  }

  @override
  Future<String> createSignedUrl({
    required String bucket,
    required String path,
    required Duration expiresIn,
  }) {
    return _client.storage
        .from(bucket)
        .createSignedUrl(path, expiresIn.inSeconds);
  }
}

class _UninitializedSettingsRepository implements SettingsRepository {
  const _UninitializedSettingsRepository();

  @override
  Future<Profile> currentProfile() {
    throw StateError('Supabase must be initialized before loading settings.');
  }

  @override
  Future<List<Profile>> listBlockedUsers() {
    throw StateError('Supabase must be initialized before loading settings.');
  }

  @override
  Future<void> unblockUser(String userId) {
    throw StateError('Supabase must be initialized before updating blocks.');
  }

  @override
  Future<void> setCustomStatus({
    String? emoji,
    String? text,
    DateTime? expiresAt,
  }) {
    throw StateError('Supabase must be initialized before setting a status.');
  }

  @override
  Future<void> updateProfile({
    required String displayName,
    required String bio,
    required String? avatarUrl,
  }) {
    throw StateError('Supabase must be initialized before updating profiles.');
  }

  @override
  Future<String> uploadAvatar({
    required String fileName,
    required String mimeType,
    required Uint8List bytes,
  }) {
    throw StateError('Supabase must be initialized before uploading avatars.');
  }

  @override
  Future<String> createAvatarUrl(String avatarPath) {
    throw StateError('Supabase must be initialized before loading avatars.');
  }
}
