import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:wecord/features/settings/settings_repository.dart';

void main() {
  test('updateProfile calls scoped profile RPC', () async {
    final dataSource = FakeSettingsDataSource();
    final repository = SupabaseSettingsRepository.withDataSource(
      dataSource,
      currentUserId: () => 'user-1',
    );

    await repository.updateProfile(
      displayName: 'Ada',
      bio: 'Math notes',
      avatarUrl: 'avatars/user-1.png',
    );

    expect(dataSource.rpcCalls, [
      const RpcCall(
        functionName: 'update_current_user_profile',
        params: {
          'display_name': 'Ada',
          'bio': 'Math notes',
          'avatar_url': 'avatars/user-1.png',
        },
      ),
    ]);
  });

  test('uploadAvatar stores the file under the current user folder', () async {
    final dataSource = FakeSettingsDataSource();
    final repository = SupabaseSettingsRepository.withDataSource(
      dataSource,
      currentUserId: () => 'user-1',
      storagePathSeed: () => 'seed-1',
    );

    final path = await repository.uploadAvatar(
      fileName: ' My Avatar.PNG ',
      mimeType: 'image/png',
      bytes: Uint8List.fromList([1, 2, 3]),
    );

    expect(path, 'user-1/seed-1-my-avatar.png');
    expect(dataSource.uploads, [
      UploadedAvatar(
        bucket: 'profile-avatars',
        path: 'user-1/seed-1-my-avatar.png',
        bytes: Uint8List.fromList([1, 2, 3]),
        mimeType: 'image/png',
      ),
    ]);
  });

  test('createAvatarUrl signs private avatar paths', () async {
    final dataSource = FakeSettingsDataSource();
    final repository = SupabaseSettingsRepository.withDataSource(
      dataSource,
      currentUserId: () => 'user-1',
    );

    final url = await repository.createAvatarUrl('user-1/avatar.png');

    expect(url, 'https://signed.example.com/user-1/avatar.png');
    expect(dataSource.signedUrls, [
      const SignedUrlCall(
        bucket: 'profile-avatars',
        path: 'user-1/avatar.png',
        expiresIn: Duration(hours: 1),
      ),
    ]);
  });

  test('createAvatarUrl returns public avatar URLs without signing', () async {
    final dataSource = FakeSettingsDataSource();
    final repository = SupabaseSettingsRepository.withDataSource(
      dataSource,
      currentUserId: () => 'user-1',
    );

    final url = await repository.createAvatarUrl(
      'https://example.com/avatar.png',
    );

    expect(url, 'https://example.com/avatar.png');
    expect(dataSource.signedUrls, isEmpty);
  });
}

class FakeSettingsDataSource implements SettingsDataSource {
  final rpcCalls = <RpcCall>[];
  final uploads = <UploadedAvatar>[];
  final signedUrls = <SignedUrlCall>[];

  @override
  Future<Map<String, dynamic>> currentProfile(String currentUserId) {
    throw UnimplementedError();
  }

  @override
  Future<void> rpc(String functionName, Map<String, dynamic> params) async {
    rpcCalls.add(RpcCall(functionName: functionName, params: params));
  }

  @override
  Future<void> uploadBinary({
    required String bucket,
    required String path,
    required Uint8List bytes,
    required String mimeType,
  }) async {
    uploads.add(
      UploadedAvatar(
        bucket: bucket,
        path: path,
        bytes: bytes,
        mimeType: mimeType,
      ),
    );
  }

  @override
  Future<String> createSignedUrl({
    required String bucket,
    required String path,
    required Duration expiresIn,
  }) async {
    signedUrls.add(
      SignedUrlCall(bucket: bucket, path: path, expiresIn: expiresIn),
    );
    return 'https://signed.example.com/$path';
  }
}

class RpcCall {
  const RpcCall({required this.functionName, required this.params});

  final String functionName;
  final Map<String, dynamic> params;

  @override
  bool operator ==(Object other) {
    return other is RpcCall &&
        other.functionName == functionName &&
        _mapsEqual(other.params, params);
  }

  @override
  int get hashCode => Object.hash(functionName, Object.hashAll(params.entries));
}

class UploadedAvatar {
  const UploadedAvatar({
    required this.bucket,
    required this.path,
    required this.bytes,
    required this.mimeType,
  });

  final String bucket;
  final String path;
  final Uint8List bytes;
  final String mimeType;

  @override
  bool operator ==(Object other) {
    return other is UploadedAvatar &&
        other.bucket == bucket &&
        other.path == path &&
        _listsEqual(other.bytes, bytes) &&
        other.mimeType == mimeType;
  }

  @override
  int get hashCode =>
      Object.hash(bucket, path, Object.hashAll(bytes), mimeType);
}

class SignedUrlCall {
  const SignedUrlCall({
    required this.bucket,
    required this.path,
    required this.expiresIn,
  });

  final String bucket;
  final String path;
  final Duration expiresIn;

  @override
  bool operator ==(Object other) {
    return other is SignedUrlCall &&
        other.bucket == bucket &&
        other.path == path &&
        other.expiresIn == expiresIn;
  }

  @override
  int get hashCode => Object.hash(bucket, path, expiresIn);
}

bool _mapsEqual(Map<String, dynamic> left, Map<String, dynamic> right) {
  if (left.length != right.length) {
    return false;
  }
  for (final entry in left.entries) {
    if (right[entry.key] != entry.value) {
      return false;
    }
  }
  return true;
}

bool _listsEqual(List<int> left, List<int> right) {
  if (left.length != right.length) {
    return false;
  }
  for (var index = 0; index < left.length; index += 1) {
    if (left[index] != right[index]) {
      return false;
    }
  }
  return true;
}
