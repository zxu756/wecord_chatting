import 'package:flutter_test/flutter_test.dart';
import 'package:wecord/features/friend_tags/friend_tags_models.dart';
import 'package:wecord/shared/models/profile.dart';

Profile _friend(String id, String name) => Profile(
  id: id,
  username: id,
  displayName: name,
  bio: '',
  createdAt: DateTime.utc(2026),
  updatedAt: DateTime.utc(2026),
);

void main() {
  group('checkFriendTagName', () {
    const family = FriendTag(id: 't1', name: 'Family');

    test('accepts a tidy name', () {
      expect(checkFriendTagName('Work', [family]), isNull);
      expect(checkFriendTagName('  Work  ', [family]), isNull);
    });

    test('refuses an empty name and one that is only spaces', () {
      expect(checkFriendTagName('', const []), FriendTagNameProblem.empty);
      expect(checkFriendTagName('   ', const []), FriendTagNameProblem.empty);
    });

    test('refuses a name over 30 characters, after trimming', () {
      expect(
        checkFriendTagName('x' * 31, const []),
        FriendTagNameProblem.tooLong,
      );
      expect(checkFriendTagName('  ${'x' * 30}  ', const []), isNull);
    });

    test('refuses a name already used, ignoring case and spaces', () {
      expect(
        checkFriendTagName(' family ', [family]),
        FriendTagNameProblem.taken,
      );
      expect(
        checkFriendTagName('FAMILY', [family]),
        FriendTagNameProblem.taken,
      );
    });

    test('a renamed tag may keep its own name (it is not "other" then)', () {
      expect(checkFriendTagName('Family', const []), isNull);
    });
  });

  group('FriendTagsData', () {
    final ada = _friend('ada', 'Ada');
    final bob = _friend('bob', 'Bob');
    final cy = _friend('cy', 'Cy');
    const family = FriendTag(id: 't1', name: 'Family');
    const work = FriendTag(id: 't2', name: 'Work');
    const data = FriendTagsData(
      tags: [family, work],
      members: {
        't1': {'ada', 'bob'},
        't2': {'bob'},
      },
      starred: {'cy'},
    );

    test('lists the tags of a friend in tag order', () {
      expect(data.tagsOf('bob'), [family, work]);
      expect(data.tagsOf('ada'), [family]);
      expect(data.tagsOf('cy'), isEmpty);
    });

    test('starred friends come first and keep their order', () {
      expect(data.starredFirst([ada, bob, cy]).map((friend) => friend.id), [
        'cy',
        'ada',
        'bob',
      ]);
    });

    test('filters friends by tag', () {
      expect(data.inTag([ada, bob, cy], 't2').map((f) => f.id), ['bob']);
      expect(data.inTag([ada, bob, cy], 'gone'), isEmpty);
    });

    test('finds a tag by id', () {
      expect(data.tagById('t2'), work);
      expect(data.tagById('nope'), isNull);
    });
  });
}
