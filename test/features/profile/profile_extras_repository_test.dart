import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:wecord/features/profile/profile_extras_repository.dart';

void main() {
  ProfileExtrasRepository repository(FakeProfileExtrasDataSource dataSource) {
    return ProfileExtrasRepository(
      dataSource,
      currentUserId: () => 'user-1',
      storagePathSeed: () => '42',
    );
  }

  test('saves trimmed pronouns and clears blank ones', () async {
    final dataSource = FakeProfileExtrasDataSource();

    await repository(dataSource).updateProfileExtras(
      pronouns: ' they/them ',
      bannerUrl: 'profile-banners/user-1/42-sky.png',
    );
    await repository(
      dataSource,
    ).updateProfileExtras(pronouns: '  ', bannerUrl: null);

    expect(dataSource.calls.map((call) => call.name), [
      'update_profile_extras',
      'update_profile_extras',
    ]);
    expect(dataSource.calls.first.params, {
      'pronouns': 'they/them',
      'banner_url': 'profile-banners/user-1/42-sky.png',
    });
    expect(dataSource.calls.last.params, {
      'pronouns': null,
      'banner_url': null,
    });
  });

  test('banners upload to their own bucket under the user', () async {
    final dataSource = FakeProfileExtrasDataSource();

    final path = await repository(dataSource).uploadBanner(
      fileName: 'My Sky.PNG',
      mimeType: 'image/png',
      bytes: Uint8List.fromList([1, 2]),
    );

    expect(dataSource.uploads.single.bucket, 'profile-banners');
    expect(dataSource.uploads.single.path, 'user-1/42-my-sky.png');
    expect(path, 'profile-banners/user-1/42-my-sky.png');
  });

  test('circle avatars upload beside profile avatars and are set', () async {
    final dataSource = FakeProfileExtrasDataSource();
    final extras = repository(dataSource);

    final path = await extras.uploadCircleAvatar(
      circleId: 'circle-1',
      fileName: 'me.jpg',
      mimeType: 'image/jpeg',
      bytes: Uint8List.fromList([1]),
    );
    await extras.setCircleAvatar(circleId: 'circle-1', avatarUrl: path);
    await extras.setCircleAvatar(circleId: 'circle-1', avatarUrl: null);

    expect(dataSource.uploads.single.bucket, 'profile-avatars');
    expect(path, 'user-1/42-circle-circle-1-me.jpg');
    expect(dataSource.calls.first.params, {
      'target_circle_id': 'circle-1',
      'avatar_url': path,
    });
    expect(dataSource.calls.last.params['avatar_url'], isNull);
  });

  test('lists circle avatars by member', () async {
    final dataSource = FakeProfileExtrasDataSource()
      ..rpcResult = [
        {'user_id': 'user-2', 'avatar_url': 'user-2/1-circle.png'},
        {'user_id': 'user-3', 'avatar_url': ''},
      ];

    final avatars = await repository(
      dataSource,
    ).circleMemberAvatars('circle-1');

    expect(dataSource.calls.single.name, 'list_circle_member_avatars');
    expect(dataSource.calls.single.params, {'target_circle_id': 'circle-1'});
    expect(avatars, {'user-2': 'user-2/1-circle.png'});
  });

  test('uploads need a signed-in user', () {
    final extras = ProfileExtrasRepository(
      FakeProfileExtrasDataSource(),
      currentUserId: () => null,
    );

    expect(
      () => extras.uploadBanner(
        fileName: 'a.png',
        mimeType: 'image/png',
        bytes: Uint8List(0),
      ),
      throwsStateError,
    );
  });
}

class FakeProfileExtrasDataSource implements ProfileExtrasDataSource {
  Object? rpcResult;
  Object? rpcError;
  final calls = <({String name, Map<String, dynamic> params})>[];
  final uploads = <({String bucket, String path, String mimeType})>[];

  @override
  Future<Object?> rpc(String functionName, Map<String, dynamic> params) async {
    calls.add((name: functionName, params: params));
    if (rpcError case final error?) {
      throw error;
    }
    return rpcResult;
  }

  @override
  Future<void> uploadBinary({
    required String bucket,
    required String path,
    required Uint8List bytes,
    required String mimeType,
  }) async {
    uploads.add((bucket: bucket, path: path, mimeType: mimeType));
  }
}
