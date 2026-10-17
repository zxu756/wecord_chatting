import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wecord/features/friend_tags/friend_tags_models.dart';

import '../../mobile/phone_test_support.dart';
import '../moments/moments_fakes.dart';

FakeFriendTagsRepository _tags({Set<String> starred = const {}}) =>
    FakeFriendTagsRepository(
      FriendTagsData(
        tags: const [
          FriendTag(id: 'tag-family', name: 'Family'),
          FriendTag(id: 'tag-work', name: 'Work'),
        ],
        members: const {
          'tag-family': {'user-2'},
          'tag-work': {'user-3', 'user-4'},
        },
        starred: starred,
      ),
    );

Future<PhoneWorld> open(
  WidgetTester tester,
  String location, {
  FakeFriendTagsRepository? tags,
  FakeMomentsRepository? moments,
  void Function(PhoneWorld world)? prepare,
}) async {
  usePhoneViewport(tester, notchedPhone);
  final world = PhoneWorld()
    ..extraOverrides = momentsOverrides(
      repository: moments ?? FakeMomentsRepository(),
      tags: tags,
    );
  prepare?.call(world);
  await world.open(tester, location);
  await settle(tester);
  return world;
}

Future<void> tapChip(WidgetTester tester, String key) async {
  final finder = find.byKey(ValueKey(key));
  await tester.ensureVisible(finder);
  await tester.pump();
  await tester.tap(finder);
  await settle(tester);
}

void main() {
  group('the Tags page', () {
    testWidgets('says when there are no tags yet', (tester) async {
      await open(tester, '/tags', tags: FakeFriendTagsRepository());
      expect(find.byKey(const ValueKey('tags-empty')), findsOneWidget);
      expect(find.text('No tags yet'), findsOneWidget);
    });

    testWidgets('lists the tags with how many friends are in them', (
      tester,
    ) async {
      await open(tester, '/tags', tags: _tags());
      expect(find.text('Family'), findsOneWidget);
      expect(find.text('1 friend'), findsOneWidget);
      expect(find.text('Work'), findsOneWidget);
      expect(find.text('2 friends'), findsOneWidget);
    });

    testWidgets('makes a tag with friends in it', (tester) async {
      final tags = FakeFriendTagsRepository();
      await open(tester, '/tags', tags: tags);

      await tester.tap(find.byKey(const ValueKey('tags-new')));
      await settle(tester);
      await tester.enterText(
        find.byKey(const ValueKey('tag-name-field')),
        '  Climbing ',
      );
      await tester.tap(find.byKey(const ValueKey('tag-friend-user-2')));
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('tag-friend-user-4')));
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('tag-save')));
      await settle(tester);

      expect(tags.calls, ['create:Climbing', 'members:tag-1:user-2,user-4']);
      expect(find.text('Climbing'), findsOneWidget);
      expect(find.text('2 friends'), findsOneWidget);
    });

    testWidgets('refuses an empty name, a taken one and a long one', (
      tester,
    ) async {
      final tags = _tags();
      await open(tester, '/tags', tags: tags);
      await tester.tap(find.byKey(const ValueKey('tags-new')));
      await settle(tester);

      await tester.tap(find.byKey(const ValueKey('tag-save')));
      await settle(tester);
      expect(find.text('Give the tag a name.'), findsOneWidget);

      await tester.enterText(
        find.byKey(const ValueKey('tag-name-field')),
        ' family ',
      );
      await tester.tap(find.byKey(const ValueKey('tag-save')));
      await settle(tester);
      expect(
        find.text('You already have a tag with that name.'),
        findsOneWidget,
      );

      await tester.enterText(
        find.byKey(const ValueKey('tag-name-field')),
        'x' * 31,
      );
      await tester.tap(find.byKey(const ValueKey('tag-save')));
      await settle(tester);
      expect(
        find.text('Tag names can have up to 30 characters.'),
        findsOneWidget,
      );
      expect(tags.calls, isEmpty);
    });

    testWidgets('renames a tag and changes who is in it', (tester) async {
      final tags = _tags();
      await open(tester, '/tags', tags: tags);

      await tester.tap(find.byKey(const ValueKey('tag-row-tag-work')));
      await settle(tester);
      await tester.enterText(
        find.byKey(const ValueKey('tag-name-field')),
        'Colleagues',
      );
      await tester.tap(find.byKey(const ValueKey('tag-friend-user-3')));
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('tag-friend-user-2')));
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('tag-save')));
      await settle(tester);

      expect(tags.calls, [
        'rename:tag-work:Colleagues',
        'members:tag-work:user-2,user-4',
      ]);
      expect(find.text('Colleagues'), findsOneWidget);
      expect(find.text('Work'), findsNothing);
    });

    testWidgets('deletes a tag after asking', (tester) async {
      final tags = _tags();
      await open(tester, '/tags', tags: tags);

      await tester.tap(find.byKey(const ValueKey('tag-row-tag-family')));
      await settle(tester);
      await tester.tap(find.byKey(const ValueKey('tag-delete')));
      await settle(tester);
      expect(find.text('Delete tag?'), findsOneWidget);
      await tester.tap(find.text('Cancel'));
      await settle(tester);
      expect(tags.calls, isEmpty);

      await tester.tap(find.byKey(const ValueKey('tag-delete')));
      await settle(tester);
      await tester.tap(find.byKey(const ValueKey('tag-delete-confirm')));
      await settle(tester);
      expect(tags.calls, ['delete:tag-family']);
      expect(find.text('Family'), findsNothing);
    });

    testWidgets('a failed save says so and keeps the sheet', (tester) async {
      final tags = _tags()..failNext = Exception('offline');
      await open(tester, '/tags', tags: tags);
      await tester.tap(find.byKey(const ValueKey('tags-new')));
      await settle(tester);
      await tester.enterText(
        find.byKey(const ValueKey('tag-name-field')),
        'Neighbours',
      );
      await tester.tap(find.byKey(const ValueKey('tag-save')));
      await settle(tester);
      expect(find.byKey(const ValueKey('tag-error')), findsOneWidget);
      expect(find.byKey(const ValueKey('tag-name-field')), findsOneWidget);
    });
  });

  group('the friends list', () {
    testWidgets('starred friends come first, under a Starred header', (
      tester,
    ) async {
      await open(tester, '/contacts', tags: _tags(starred: {'user-4'}));

      expect(find.text('Starred'), findsOneWidget);
      expect(find.text('Other friends'), findsOneWidget);
      // Linus (starred) is above Bart, who is above nobody starred.
      expect(
        tester.getTopLeft(find.byKey(const ValueKey('friend-user-4'))).dy,
        lessThan(
          tester.getTopLeft(find.byKey(const ValueKey('friend-user-2'))).dy,
        ),
      );
    });

    testWidgets('without stars there is no Starred header', (tester) async {
      await open(tester, '/contacts', tags: _tags());
      expect(find.text('Starred'), findsNothing);
      expect(find.text('Other friends'), findsNothing);
    });

    testWidgets('stars and unstars a friend from the list', (tester) async {
      final tags = _tags();
      await open(tester, '/contacts', tags: tags);

      await tester.tap(find.byKey(const ValueKey('friend-star-user-3')));
      await settle(tester);
      expect(tags.calls, ['star:user-3']);
      expect(find.text('Starred'), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('friend-star-user-3')));
      await settle(tester);
      expect(tags.calls.last, 'unstar:user-3');
      expect(find.text('Starred'), findsNothing);
    });

    testWidgets('a tag chip narrows the list to its friends', (tester) async {
      await open(tester, '/contacts', tags: _tags());

      await tapChip(tester, 'friends-filter-tag-tag-work');
      expect(find.byKey(const ValueKey('friend-user-3')), findsOneWidget);
      expect(find.byKey(const ValueKey('friend-user-4')), findsOneWidget);
      expect(find.byKey(const ValueKey('friend-user-2')), findsNothing);

      // Tapping it again, or All, brings everyone back.
      await tapChip(tester, 'friends-filter-tag-tag-work');
      expect(find.byKey(const ValueKey('friend-user-2')), findsOneWidget);

      await tapChip(tester, 'friends-filter-tag-tag-family');
      expect(find.byKey(const ValueKey('friend-user-3')), findsNothing);
      await tapChip(tester, 'friends-filter-all');
      expect(find.byKey(const ValueKey('friend-user-3')), findsOneWidget);
    });

    testWidgets('the Tags button opens the Tags page', (tester) async {
      final world = await open(tester, '/contacts', tags: _tags());
      await tester.tap(find.byKey(const ValueKey('contacts-tags')));
      await settle(tester);
      expect(world.router.state.uri.path, '/tags');
    });
  });

  group('a friend\'s profile', () {
    testWidgets('has the star, the tags and Moments', (tester) async {
      final tags = _tags();
      final world = await open(tester, '/profile/user-2', tags: tags);

      expect(
        find.byKey(const ValueKey('profile-friend-extras')),
        findsOneWidget,
      );
      expect(find.text('Family'), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('profile-star')));
      await settle(tester);
      expect(tags.calls, ['star:user-2']);

      await tester.tap(find.byKey(const ValueKey('profile-moments')));
      await settle(tester);
      expect(world.router.state.uri.path, '/moments/of/user-2');
    });

    testWidgets('switches tags on and off, and makes a new one', (
      tester,
    ) async {
      final tags = _tags();
      await open(tester, '/profile/user-2', tags: tags);

      await tester.tap(find.byKey(const ValueKey('profile-tags')));
      await settle(tester);
      await tester.tap(find.byKey(const ValueKey('picker-tag-tag-work')));
      await settle(tester);
      expect(tags.calls, ['members:tag-work:user-2,user-3,user-4']);

      await tester.tap(find.byKey(const ValueKey('picker-tag-tag-family')));
      await settle(tester);
      expect(tags.calls.last, 'members:tag-family:');

      await tester.enterText(
        find.byKey(const ValueKey('picker-new-tag-field')),
        'Hiking',
      );
      await tester.tap(find.byKey(const ValueKey('picker-new-tag-add')));
      await settle(tester);
      expect(tags.calls.sublist(tags.calls.length - 2), [
        'create:Hiking',
        'members:tag-1:user-2',
      ]);
      expect(find.byKey(const ValueKey('picker-tag-tag-1')), findsOneWidget);
    });

    testWidgets('a stranger\'s profile has none of it', (tester) async {
      await open(
        tester,
        '/profile/user-9',
        tags: _tags(),
        prepare: (world) {
          final json = Map<String, dynamic>.from(
            (world.profileData.rpcResult! as List).first as Map,
          );
          world.profileData.rpcResult = [
            {...json, 'relationship_status': 'none'},
          ];
        },
      );
      expect(find.byKey(const ValueKey('profile-friend-extras')), findsNothing);
    });
  });
}
