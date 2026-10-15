import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wecord/features/chats/chats_repository.dart';
import 'package:wecord/features/chats/image_picker_service.dart';
import 'package:wecord/features/profile/circle_avatar_sheet.dart';
import 'package:wecord/features/profile/profile_extras_repository.dart';
import 'package:wecord/shared/models/circle.dart';
import 'package:wecord/shared/models/profile.dart';

import 'profile_extras_repository_test.dart';

void main() {
  final member = CircleMember(
    role: 'member',
    isCurrentUser: true,
    profile: Profile(
      id: 'user-1',
      username: 'ada',
      displayName: 'Ada',
      bio: '',
      createdAt: DateTime.utc(2026),
      updatedAt: DateTime.utc(2026),
    ),
  );

  Widget app(
    FakeProfileExtrasDataSource dataSource, {
    ImagePickerService? picker,
  }) {
    return ProviderScope(
      overrides: [
        profileExtrasRepositoryProvider.overrideWithValue(
          ProfileExtrasRepository(
            dataSource,
            currentUserId: () => 'user-1',
            storagePathSeed: () => '9',
          ),
        ),
        if (picker != null)
          imagePickerServiceProvider.overrideWithValue(picker),
      ],
      child: MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => showCircleAvatarSheet(
                context,
                circleId: 'circle-1',
                member: member,
              ),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
  }

  testWidgets('uploads and sets an avatar for one circle', (tester) async {
    final dataSource = FakeProfileExtrasDataSource()..rpcResult = [];
    await tester.pumpWidget(app(dataSource, picker: _Picker()));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    expect(find.text('Circle avatar'), findsOneWidget);
    // Nothing to go back to yet.
    expect(find.byKey(const ValueKey('remove-circle-avatar')), findsNothing);

    await tester.tap(find.byKey(const ValueKey('upload-circle-avatar')));
    await tester.pumpAndSettle();

    expect(dataSource.uploads.single.bucket, 'profile-avatars');
    expect(
      dataSource.calls
          .where((call) => call.name == 'set_circle_avatar')
          .single
          .params,
      {
        'target_circle_id': 'circle-1',
        'avatar_url': 'user-1/9-circle-circle-1-me.png',
      },
    );
    expect(find.text('Circle avatar'), findsNothing);
  });

  testWidgets('goes back to the usual avatar', (tester) async {
    final dataSource = FakeProfileExtrasDataSource()
      ..rpcResult = [
        {'user_id': 'user-1', 'avatar_url': 'user-1/1-circle.png'},
      ];
    await tester.pumpWidget(app(dataSource));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('remove-circle-avatar')));
    await tester.pumpAndSettle();

    final set = dataSource.calls
        .where((call) => call.name == 'set_circle_avatar')
        .single;
    expect(set.params['avatar_url'], isNull);
  });
}

class _Picker implements ImagePickerService {
  @override
  Future<ChatImageUpload?> pickImage() async => ChatImageUpload(
    fileName: 'me.png',
    mimeType: 'image/png',
    bytes: Uint8List.fromList([1]),
  );
}
