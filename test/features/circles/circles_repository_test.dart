import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:wecord/features/chats/chats_repository.dart';
import 'package:wecord/features/circles/circles_repository.dart';
import 'package:wecord/shared/models/message.dart';
import 'package:wecord/shared/models/report_reason.dart';

void main() {
  test('listCircles maps list_circle_summaries rows', () async {
    final dataSource = FakeCirclesDataSource()
      ..rpcRows['list_circle_summaries'] = [
        {
          'id': 'circle-1',
          'name': 'Close Friends',
          'member_count': 3,
          'channel_count': 1,
          'current_user_role': 'owner',
        },
      ];
    final repository = SupabaseCirclesRepository.withDataSource(dataSource);

    final circles = await repository.listCircles();

    expect(circles.single.name, 'Close Friends');
    expect(circles.single.memberCount, 3);
    expect(circles.single.currentUserRole, 'owner');
    expect(dataSource.calls.single.functionName, 'list_circle_summaries');
    expect(dataSource.calls.single.params, isEmpty);
  });

  test('getCircleDetail maps get_circle_detail JSON payload', () async {
    final dataSource = FakeCirclesDataSource()
      ..rpcValue = {
        'circle': {
          'id': 'circle-1',
          'name': 'Close Friends',
          'member_count': 2,
          'channel_count': 1,
          'current_user_role': 'admin',
        },
        'members': [
          {'role': 'owner', 'profile': _profileRow(id: 'u1', name: 'Ada')},
        ],
        'channels': [
          {
            'id': 'channel-1',
            'circle_id': 'circle-1',
            'conversation_id': 'conversation-1',
            'name': 'General',
            'position': 0,
          },
        ],
        'posts': [
          {
            'id': 'post-1',
            'circle_id': 'circle-1',
            'author_id': 'u1',
            'body': 'Hello',
            'created_at': '2026-05-19T00:00:00Z',
            'updated_at': '2026-05-19T00:00:00Z',
            'author': _profileRow(id: 'u1', name: 'Ada'),
            'comments': [
              {
                'id': 'comment-1',
                'post_id': 'post-1',
                'author_id': 'u2',
                'body': 'Hi',
                'created_at': '2026-05-19T00:01:00Z',
                'updated_at': '2026-05-19T00:01:00Z',
                'author': _profileRow(id: 'u2', name: 'Grace'),
              },
            ],
            'like_count': 4,
            'comment_count': 1,
            'liked_by_current_user': true,
          },
        ],
      };
    final repository = SupabaseCirclesRepository.withDataSource(dataSource);

    final detail = await repository.getCircleDetail('circle-1');

    expect(detail.circle.name, 'Close Friends');
    expect(detail.members.single.profile.id, 'u1');
    expect(detail.channels.single.name, 'General');
    expect(detail.posts.single.comments.single.body, 'Hi');
    expect(dataSource.calls.single.functionName, 'get_circle_detail');
    expect(dataSource.calls.single.params, {'target_circle_id': 'circle-1'});
  });

  test('createCircle trims name and calls create_circle rpc', () async {
    final dataSource = FakeCirclesDataSource()..rpcValue = 'circle-1';
    final repository = SupabaseCirclesRepository.withDataSource(dataSource);

    final id = await repository.createCircle(
      name: ' Close Friends ',
      memberIds: ['u2'],
    );

    expect(id, 'circle-1');
    expect(dataSource.calls.single.functionName, 'create_circle');
    expect(dataSource.calls.single.params, {
      'circle_name': 'Close Friends',
      'member_ids': ['u2'],
    });
  });

  test(
    'createChannel trims name and calls create_circle_channel rpc',
    () async {
      final dataSource = FakeCirclesDataSource()..rpcValue = 'channel-1';
      final repository = SupabaseCirclesRepository.withDataSource(dataSource);

      final id = await repository.createChannel(
        circleId: 'circle-1',
        name: ' General ',
      );

      expect(id, 'channel-1');
      expect(dataSource.calls.single.functionName, 'create_circle_channel');
      expect(dataSource.calls.single.params, {
        'target_circle_id': 'circle-1',
        'channel_name': 'General',
      });
    },
  );

  test('inviteMembers calls invite_circle_members rpc', () async {
    final dataSource = FakeCirclesDataSource();
    final repository = SupabaseCirclesRepository.withDataSource(dataSource);

    await repository.inviteMembers(circleId: 'circle-1', memberIds: ['u2']);

    expect(dataSource.calls.single.functionName, 'invite_circle_members');
    expect(dataSource.calls.single.params, {
      'target_circle_id': 'circle-1',
      'member_ids': ['u2'],
    });
  });

  test('createPost trims body and sends image attachment map', () async {
    final dataSource = FakeCirclesDataSource()..rpcValue = 'post-1';
    final repository = SupabaseCirclesRepository.withDataSource(dataSource);
    const image = ImageAttachment(
      bucket: 'chat-media',
      path: 'circle-1/image.jpg',
      mimeType: 'image/jpeg',
      size: 3,
      width: 10,
      height: 20,
    );

    final id = await repository.createPost(
      circleId: 'circle-1',
      body: ' Hello ',
      image: image,
    );

    expect(id, 'post-1');
    expect(dataSource.calls.single.functionName, 'create_circle_post');
    expect(dataSource.calls.single.params, {
      'target_circle_id': 'circle-1',
      'body': 'Hello',
      'attachment': image.toJson(),
    });
  });

  test('createPost sends null attachment without image', () async {
    final dataSource = FakeCirclesDataSource()..rpcValue = 'post-1';
    final repository = SupabaseCirclesRepository.withDataSource(dataSource);

    await repository.createPost(circleId: 'circle-1', body: ' Hello ');

    expect(dataSource.calls.single.params['attachment'], isNull);
  });

  test('togglePostLike calls toggle_circle_post_like rpc', () async {
    final dataSource = FakeCirclesDataSource();
    final repository = SupabaseCirclesRepository.withDataSource(dataSource);

    await repository.togglePostLike(postId: 'post-1', liked: true);

    expect(dataSource.calls.single.functionName, 'toggle_circle_post_like');
    expect(dataSource.calls.single.params, {
      'target_post_id': 'post-1',
      'liked': true,
    });
  });

  test(
    'createComment trims body and calls create_circle_post_comment rpc',
    () async {
      final dataSource = FakeCirclesDataSource()..rpcValue = 'comment-1';
      final repository = SupabaseCirclesRepository.withDataSource(dataSource);

      final id = await repository.createComment(postId: 'post-1', body: ' Hi ');

      expect(id, 'comment-1');
      expect(
        dataSource.calls.single.functionName,
        'create_circle_post_comment',
      );
      expect(dataSource.calls.single.params, {
        'target_post_id': 'post-1',
        'body': 'Hi',
      });
    },
  );

  test('deletePost calls delete_circle_post rpc', () async {
    final dataSource = FakeCirclesDataSource();
    final repository = SupabaseCirclesRepository.withDataSource(dataSource);

    await repository.deletePost('post-1');

    expect(dataSource.calls.single.functionName, 'delete_circle_post');
    expect(dataSource.calls.single.params, {'target_post_id': 'post-1'});
  });

  test('reportPost serializes reason and details', () async {
    final dataSource = FakeCirclesDataSource();
    final repository = SupabaseCirclesRepository.withDataSource(dataSource);

    await repository.reportPost(
      postId: 'post-1',
      reason: ReportReason.spam,
      details: 'Looks automated',
    );

    expect(dataSource.calls.single.functionName, 'report_circle_post');
    expect(dataSource.calls.single.params, {
      'target_post_id': 'post-1',
      'report_reason': ReportReason.spam.toJson(),
      'report_details': 'Looks automated',
    });
  });

  test(
    'uploadPostImage uploads to chat-media and returns ImageAttachment',
    () async {
      final dataSource = FakeCirclesDataSource();
      final repository = SupabaseCirclesRepository.withDataSource(
        dataSource,
        storagePathSeed: () => 'seed',
      );
      final image = ChatImageUpload(
        bytes: Uint8List.fromList([1, 2, 3]),
        fileName: ' My Photo.JPG ',
        mimeType: 'image/jpeg',
        width: 100,
        height: 200,
      );

      final attachment = await repository.uploadPostImage(
        circleId: 'circle-1',
        image: image,
      );

      expect(dataSource.uploads.single.bucket, 'chat-media');
      expect(dataSource.uploads.single.path, 'circle-1/seed-my-photo.jpg');
      expect(dataSource.uploads.single.mimeType, 'image/jpeg');
      expect(attachment.toJson(), {
        'kind': 'image',
        'bucket': 'chat-media',
        'path': 'circle-1/seed-my-photo.jpg',
        'mime_type': 'image/jpeg',
        'size': 3,
        'width': 100,
        'height': 200,
      });
    },
  );

  test('createImageUrl signs image attachment URLs', () async {
    final dataSource = FakeCirclesDataSource()..signedUrl = 'signed-url';
    final repository = SupabaseCirclesRepository.withDataSource(dataSource);

    final url = await repository.createImageUrl(
      const ImageAttachment(
        bucket: 'chat-media',
        path: 'circle-1/image.jpg',
        mimeType: 'image/jpeg',
        size: 3,
      ),
    );

    expect(url, 'signed-url');
    expect(dataSource.signedUrlCalls.single, {
      'bucket': 'chat-media',
      'path': 'circle-1/image.jpg',
      'expiresIn': const Duration(hours: 1),
    });
  });
}

class FakeCirclesDataSource implements CirclesDataSource {
  final rpcRows = <String, List<Map<String, dynamic>>>{};
  Object? rpcValue;
  String signedUrl = 'signed-url';
  final calls = <RpcCall>[];
  final uploads = <UploadCall>[];
  final signedUrlCalls = <Map<String, Object>>[];
  final changes = StreamController<void>.broadcast();

  @override
  Future<Object?> rpc(String functionName, Map<String, dynamic> params) async {
    calls.add(RpcCall(functionName: functionName, params: params));
    return rpcRows[functionName] ?? rpcValue;
  }

  @override
  Future<void> uploadBinary({
    required String bucket,
    required String path,
    required Uint8List bytes,
    required String mimeType,
  }) async {
    uploads.add(
      UploadCall(bucket: bucket, path: path, bytes: bytes, mimeType: mimeType),
    );
  }

  @override
  Future<String> createSignedUrl({
    required String bucket,
    required String path,
    required Duration expiresIn,
  }) async {
    signedUrlCalls.add({
      'bucket': bucket,
      'path': path,
      'expiresIn': expiresIn,
    });
    return signedUrl;
  }

  @override
  Stream<void> circleChanges(String circleId) => changes.stream;
}

class RpcCall {
  const RpcCall({required this.functionName, required this.params});

  final String functionName;
  final Map<String, dynamic> params;
}

class UploadCall {
  const UploadCall({
    required this.bucket,
    required this.path,
    required this.bytes,
    required this.mimeType,
  });

  final String bucket;
  final String path;
  final Uint8List bytes;
  final String mimeType;
}

Map<String, dynamic> _profileRow({required String id, required String name}) {
  return {
    'id': id,
    'username': name.toLowerCase(),
    'display_name': name,
    'avatar_url': null,
    'bio': '',
    'created_at': '2026-05-19T00:00:00Z',
    'updated_at': '2026-05-19T00:00:00Z',
  };
}
