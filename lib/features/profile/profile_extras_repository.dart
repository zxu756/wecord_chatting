import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:wecord/shared/api/supabase_providers.dart';

final profileExtrasRepositoryProvider = Provider<ProfileExtrasRepository>((
  ref,
) {
  try {
    final client = ref.watch(supabaseClientProvider);
    return ProfileExtrasRepository(
      SupabaseProfileExtrasDataSource(client),
      currentUserId: () => client.auth.currentUser?.id,
    );
  } on AssertionError {
    return ProfileExtrasRepository(
      const _UninitializedProfileExtrasDataSource(),
      currentUserId: () => null,
    );
  }
});

/// Each member's avatar in one circle, by user id, for members who set one
/// (see [ProfileExtrasRepository.circleMemberAvatars]).
final circleMemberAvatarsProvider = FutureProvider.autoDispose
    .family<Map<String, String>, String>((ref, circleId) async {
      try {
        return await ref
            .watch(profileExtrasRepositoryProvider)
            .circleMemberAvatars(circleId);
      } catch (_) {
        // Everyone shows their usual avatar.
        return const <String, String>{};
      }
    });

abstract interface class ProfileExtrasDataSource {
  Future<Object?> rpc(String functionName, Map<String, dynamic> params);

  Future<void> uploadBinary({
    required String bucket,
    required String path,
    required Uint8List bytes,
    required String mimeType,
  });
}

/// Banners, pronouns and per-circle avatars.
class ProfileExtrasRepository {
  const ProfileExtrasRepository(
    this._dataSource, {
    required this._currentUserId,
    this._storagePathSeed,
    this._storageOperationTimeout = const Duration(seconds: 30),
  });

  static const bannerBucket = 'profile-banners';
  static const avatarBucket = 'profile-avatars';

  final ProfileExtrasDataSource _dataSource;
  final String? Function() _currentUserId;
  final String Function()? _storagePathSeed;
  final Duration _storageOperationTimeout;

  /// Saves the current user's pronouns and banner; blank pronouns and a
  /// null banner clear them.
  Future<void> updateProfileExtras({
    required String? pronouns,
    required String? bannerUrl,
  }) async {
    final trimmed = pronouns?.trim() ?? '';
    await _dataSource.rpc('update_profile_extras', {
      'pronouns': trimmed.isEmpty ? null : trimmed,
      'banner_url': bannerUrl,
    });
  }

  /// Uploads a banner image; returns what to save as the banner
  /// (`profile-banners/<user>/<file>`).
  Future<String> uploadBanner({
    required String fileName,
    required String mimeType,
    required Uint8List bytes,
  }) async {
    final path = _uploadPath(fileName, fallbackName: 'banner.jpg');
    await _upload(bannerBucket, path, bytes, mimeType);
    return '$bannerBucket/$path';
  }

  /// Uploads an avatar for one circle; returns its stored path, in the
  /// same form as profile avatars.
  Future<String> uploadCircleAvatar({
    required String circleId,
    required String fileName,
    required String mimeType,
    required Uint8List bytes,
  }) async {
    final path = _uploadPath(
      'circle-$circleId-$fileName',
      fallbackName: 'avatar.jpg',
    );
    await _upload(avatarBucket, path, bytes, mimeType);
    return path;
  }

  /// Sets the current user's avatar in [circleId]; null goes back to their
  /// usual avatar.
  Future<void> setCircleAvatar({
    required String circleId,
    required String? avatarUrl,
  }) async {
    await _dataSource.rpc('set_circle_avatar', {
      'target_circle_id': circleId,
      'avatar_url': avatarUrl,
    });
  }

  Future<Map<String, String>> circleMemberAvatars(String circleId) async {
    final rows = await _dataSource.rpc('list_circle_member_avatars', {
      'target_circle_id': circleId,
    });
    return {
      for (final row in (rows as List).cast<Map<String, dynamic>>())
        if (row['avatar_url'] case final String avatarUrl
            when avatarUrl.isNotEmpty)
          row['user_id'] as String: avatarUrl,
    };
  }

  String _uploadPath(String fileName, {required String fallbackName}) {
    final userId = _currentUserId();
    if (userId == null) {
      throw StateError('A signed-in user is required to upload images.');
    }
    final seed =
        _storagePathSeed?.call() ??
        DateTime.now().toUtc().microsecondsSinceEpoch.toString();
    final sanitized = fileName
        .trim()
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9._-]+'), '-')
        .replaceAll(RegExp(r'-+'), '-')
        .replaceAll(RegExp(r'^[-.]+|[-.]+$'), '');
    return '$userId/$seed-${sanitized.isEmpty ? fallbackName : sanitized}';
  }

  Future<void> _upload(
    String bucket,
    String path,
    Uint8List bytes,
    String mimeType,
  ) {
    return _dataSource
        .uploadBinary(
          bucket: bucket,
          path: path,
          bytes: bytes,
          mimeType: mimeType,
        )
        .timeout(
          _storageOperationTimeout,
          onTimeout: () {
            throw TimeoutException(
              'Image upload timed out',
              _storageOperationTimeout,
            );
          },
        );
  }
}

class SupabaseProfileExtrasDataSource implements ProfileExtrasDataSource {
  const SupabaseProfileExtrasDataSource(this._client);

  final SupabaseClient _client;

  @override
  Future<Object?> rpc(String functionName, Map<String, dynamic> params) {
    return _client.rpc(functionName, params: params);
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
}

class _UninitializedProfileExtrasDataSource implements ProfileExtrasDataSource {
  const _UninitializedProfileExtrasDataSource();

  @override
  Future<Object?> rpc(String functionName, Map<String, dynamic> params) {
    throw StateError('Supabase must be initialized before saving profiles.');
  }

  @override
  Future<void> uploadBinary({
    required String bucket,
    required String path,
    required Uint8List bytes,
    required String mimeType,
  }) {
    throw StateError('Supabase must be initialized before uploading images.');
  }
}
