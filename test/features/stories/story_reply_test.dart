import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wecord/features/chats/chats_screen.dart';
import 'package:wecord/features/chats/message_semantics.dart';
import 'package:wecord/features/stories/stories_models.dart';
import 'package:wecord/shared/models/conversation.dart';
import 'package:wecord/shared/models/message.dart';
import 'package:wecord/shared/models/profile.dart';

import '../../mobile/phone_test_support.dart';
import 'stories_fakes.dart';

Map<String, dynamic> _attachment({String id = 'story-1', String? kind}) => {
  'kind': 'story_ref',
  'story_id': id,
  'owner_id': 'user-2',
  'media_kind': kind ?? 'photo',
};

void main() {
  group('model', () {
    test('a reply points at a daily and its owner', () {
      final ref = StoryRef.maybeFromAttachment(_attachment(kind: 'video'))!;
      expect(ref.storyId, 'story-1');
      expect(ref.ownerId, 'user-2');
      expect(ref.kind, StoryMediaKind.video);
      expect(
        StoryRef.maybeFromAttachment(_attachment())!.kind,
        StoryMediaKind.photo,
      );
    });

    test('malformed references are not references', () {
      expect(StoryRef.maybeFromAttachment(null), isNull);
      expect(StoryRef.maybeFromAttachment({'kind': 'note'}), isNull);
      expect(
        StoryRef.maybeFromAttachment({'kind': 'story_ref', 'story_id': 's'}),
        isNull,
      );
      expect(
        StoryRef.maybeFromAttachment({
          'kind': 'story_ref',
          'story_id': '',
          'owner_id': 'u',
        }),
        isNull,
      );
    });

    test('a deleted reply is no reference, nor is a voice message', () {
      final reply = phoneMessage(
        'm1',
        bart,
        'Love it',
        minutesAgo: 3,
        attachment: _attachment(),
      );
      expect(reply.storyRef, isNotNull);
      expect(reply.copyWith(recalledAt: DateTime.utc(2026)).storyRef, isNull);
    });

    test('a screen reader hears it is a reply to a daily', () {
      final reply = phoneMessage(
        'm1',
        bart,
        'Love it',
        minutesAgo: 3,
        attachment: _attachment(),
      );
      expect(
        messageSpokenContent(reply, senderName: 'Bart'),
        'Reply to a daily: Love it',
      );
    });
  });

  group('in a chat', () {
    late PhoneWorld world;
    late FakeStoriesRepository stories;

    setUp(() {
      stories = FakeStoriesRepository();
      world = PhoneWorld();
      world.extraOverrides = storiesOverrides(repository: stories);
    });

    Future<void> openDirect(WidgetTester tester) async {
      usePhoneViewport(tester, notchedPhone);
      await world.open(
        tester,
        '${ChatsScreen.path}/dm-1',
        extra: ChatThreadRouteExtra(
          title: bart.displayName,
          type: ConversationType.direct,
        ),
      );
    }

    ChatMessage reply({
      required Profile from,
      String body = 'Love this one',
      String storyId = 'story-1',
    }) {
      return phoneMessage(
        'reply-1',
        from,
        body,
        minutesAgo: 3,
        attachment: _attachment(id: storyId),
      );
    }

    testWidgets('a reply to my daily shows its thumbnail and the words', (
      tester,
    ) async {
      stories.refs['story-1'] = const StoryRefInfo(
        storyId: 'story-1',
        authorId: 'user-1',
        kind: StoryMediaKind.photo,
        thumbPath: 'user-1/story-1-t.jpg',
      );
      world.chats.messages = [reply(from: bart)];
      await openDirect(tester);

      expect(find.text('Love this one'), findsOneWidget);
      expect(find.text('Replied to your daily'), findsOneWidget);
      expect(find.text('Photo'), findsOneWidget);
      expect(find.byKey(const ValueKey('story-reply-story-1')), findsOneWidget);
      await world.close(tester);
    });

    testWidgets('my own reply says I replied', (tester) async {
      stories.refs['story-1'] = const StoryRefInfo(
        storyId: 'story-1',
        authorId: 'user-2',
        kind: StoryMediaKind.video,
        thumbPath: 'user-2/story-1-t.jpg',
      );
      world.chats.messages = [reply(from: me)];
      await openDirect(tester);

      expect(find.text('You replied to a daily'), findsOneWidget);
      await world.close(tester);
    });

    testWidgets('once the daily has ended the card says so', (tester) async {
      world.chats.messages = [reply(from: bart)];
      await openDirect(tester);

      expect(find.text('Love this one'), findsOneWidget);
      expect(find.text('This daily has ended'), findsOneWidget);
      expect(find.byIcon(Icons.hourglass_empty_rounded), findsOneWidget);
      await world.close(tester);
    });

    testWidgets('a message without a story has no card', (tester) async {
      world.chats.messages = [
        phoneMessage('plain-1', bart, 'Just a message', minutesAgo: 3),
      ];
      await openDirect(tester);
      expect(find.byKey(const ValueKey('story-reply-story-1')), findsNothing);
      await world.close(tester);
    });
  });
}
