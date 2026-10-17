import 'package:flutter_test/flutter_test.dart';
import 'package:wecord/features/moments/moment_composer_screen.dart';
import 'package:wecord/features/moments/moments_models.dart';
import 'package:wecord/shared/l10n/l10n.dart';

void main() {
  tearDown(() => AppStrings.isChinese = false);

  group('MomentAudience', () {
    test('everyone and private need no lists', () {
      expect(MomentAudience.everyone.isComplete, isTrue);
      expect(
        const MomentAudience(visibility: MomentVisibility.private).isComplete,
        isTrue,
      );
    });

    test('only and except need a friend or a tag', () {
      for (final visibility in [
        MomentVisibility.only,
        MomentVisibility.except,
      ]) {
        expect(MomentAudience(visibility: visibility).isComplete, isFalse);
        expect(
          MomentAudience(
            visibility: visibility,
            friendIds: const {'a'},
          ).isComplete,
          isTrue,
        );
        expect(
          MomentAudience(
            visibility: visibility,
            tagIds: const {'t'},
          ).isComplete,
          isTrue,
        );
      }
    });

    test('compares by value, whatever the order', () {
      expect(
        const MomentAudience(
          visibility: MomentVisibility.only,
          friendIds: {'a', 'b'},
        ),
        const MomentAudience(
          visibility: MomentVisibility.only,
          friendIds: {'b', 'a'},
        ),
      );
      expect(
        MomentAudience.everyone,
        isNot(const MomentAudience(visibility: MomentVisibility.private)),
      );
    });

    test('speaks the audience', () {
      expect(momentAudienceLabel(MomentAudience.everyone), 'Friends');
      expect(
        momentAudienceLabel(
          const MomentAudience(visibility: MomentVisibility.private),
        ),
        'Only me',
      );
      expect(
        momentAudienceLabel(
          const MomentAudience(
            visibility: MomentVisibility.only,
            friendIds: {'a'},
            tagIds: {'t'},
          ),
          tagNames: ['Family'],
          friendNames: ['Bob'],
        ),
        'Only: Family, Bob',
      );
      expect(
        momentAudienceLabel(
          const MomentAudience(
            visibility: MomentVisibility.except,
            friendIds: {'a', 'b'},
            tagIds: {'t'},
          ),
          tagNames: ['Work'],
          friendNames: ['Bob', 'Cy'],
        ),
        'Not: Work, Bob and 1 more',
      );
      expect(
        momentAudienceLabel(
          const MomentAudience(visibility: MomentVisibility.only),
        ),
        'Only share with…',
      );
    });

    test('speaks it in Chinese', () {
      AppStrings.isChinese = true;
      expect(momentAudienceLabel(MomentAudience.everyone), '好友');
      expect(
        momentAudienceLabel(
          const MomentAudience(visibility: MomentVisibility.private),
        ),
        '仅自己可见',
      );
    });
  });

  group('wire names', () {
    test('visibility and range round trip, unknown falls back', () {
      for (final visibility in MomentVisibility.values) {
        expect(MomentVisibility.fromWire(visibility.wire), visibility);
      }
      expect(MomentVisibility.fromWire('wat'), MomentVisibility.friends);
      for (final range in MomentsRange.values) {
        expect(MomentsRange.fromWire(range.wire), range);
      }
      expect(MomentsRange.fromWire(null), MomentsRange.all);
      expect(MomentsRange.sixMonths.wire, 'six_months');
      expect(MomentsRange.oneMonth.wire, 'one_month');
      expect(MomentsRange.threeDays.wire, 'three_days');
    });

    test('ranges have words', () {
      expect(MomentsRange.all.label, 'All');
      expect(MomentsRange.threeDays.label, 'Last 3 days');
      AppStrings.isChinese = true;
      expect(MomentsRange.threeDays.label, '最近三天');
    });
  });

  test('a post reads from the feed row', () {
    final post = MomentPost.fromJson({
      'id': 'p1',
      'author_id': 'u2',
      'author_name': 'Bob',
      'author_avatar_url': null,
      'body': 'Hello',
      'kind': 'photos',
      'photos': [
        {'path': 'u2/p1-0.jpg', 'thumb': 'u2/p1-0-t.jpg', 'w': 800, 'h': 600},
      ],
      'link_url': null,
      'link_title': null,
      'location': 'Lisbon',
      'visibility': 'only',
      'created_at': '2026-10-18T10:00:00+00:00',
      'like_count': 2,
      'liked_by_me': true,
      'likes': [
        {'user_id': 'u1', 'name': 'Ada', 'avatar_url': null},
        {'user_id': 'u3', 'name': 'Cy', 'avatar_url': null},
      ],
      'comment_count': 1,
      'comments': [
        {
          'id': 'c1',
          'user_id': 'u3',
          'name': 'Cy',
          'avatar_url': null,
          'body': 'Nice',
          'created_at': '2026-10-18T10:05:00+00:00',
          'reply_to_comment_id': null,
          'reply_to_user_id': 'u1',
          'reply_to_name': 'Ada',
        },
      ],
    });
    expect(post.kind, MomentKind.photos);
    expect(post.photos.single.thumb, 'u2/p1-0-t.jpg');
    expect(post.photos.single.aspectRatio, closeTo(4 / 3, 0.001));
    expect(post.visibility, MomentVisibility.only);
    expect(post.likedByMe, isTrue);
    expect(post.likes.map((like) => like.name), ['Ada', 'Cy']);
    expect(post.comments.single.isReply, isTrue);
    expect(post.comments.single.replyToName, 'Ada');
    expect(post.createdAt, DateTime.utc(2026, 10, 18, 10));
  });

  test('a post with nothing but text has empty lists', () {
    final post = MomentPost.fromJson({
      'id': 'p2',
      'author_id': 'u2',
      'author_name': 'Bob',
      'body': 'Just words',
      'kind': 'text',
      'photos': [],
      'visibility': 'friends',
      'created_at': '2026-10-18T10:00:00Z',
      'likes': [],
      'comments': [],
    });
    expect(post.photos, isEmpty);
    expect(post.likeCount, 0);
    expect(post.comments, isEmpty);
    expect(post.linkUrl, isNull);
  });

  test('a notification reads from the inbox row', () {
    final notification = MomentNotification.fromJson({
      'id': 'n1',
      'kind': 'reply',
      'post_id': 'p1',
      'comment_id': 'c1',
      'actor_id': 'u3',
      'actor_name': 'Cy',
      'actor_avatar_url': null,
      'snippet': 'Agreed',
      'post_excerpt': 'Hello',
      'post_thumb': null,
      'created_at': '2026-10-18T10:00:00Z',
      'is_unread': true,
    });
    expect(notification.kind, MomentNotificationKind.reply);
    expect(notification.isUnread, isTrue);
    expect(notification.snippet, 'Agreed');
  });

  group('isMomentLink', () {
    test('accepts web addresses', () {
      expect(isMomentLink('https://example.com/a?b=1'), isTrue);
      expect(isMomentLink('  http://example.com '), isTrue);
    });

    test('refuses everything else', () {
      expect(isMomentLink('javascript:alert(1)'), isFalse);
      expect(isMomentLink('example.com'), isFalse);
      expect(isMomentLink('ftp://example.com'), isFalse);
      expect(isMomentLink('https://'), isFalse);
      expect(isMomentLink(''), isFalse);
    });
  });
}
