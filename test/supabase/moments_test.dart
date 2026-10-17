import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'behaviour_runner.dart';

/// Schema checks for friend tags and stars (migration 202610180040) and
/// Moments (202610180041, 202610180042), plus the behaviour script, which
/// covers every visibility mode, tags in both lists, the visible range,
/// "don't let them see" and "hide their", the mutual friends rule for likes
/// and comments, the pictures in storage, blocking and unfriending.
void main() {
  late String tags;
  late String moments;
  late String feed;

  setUpAll(() {
    tags = File(
      'supabase/migrations/202610180040_friend_tags_and_stars.sql',
    ).readAsStringSync();
    moments = File(
      'supabase/migrations/202610180041_moments.sql',
    ).readAsStringSync();
    feed = File(
      'supabase/migrations/202610180042_moments_feed.sql',
    ).readAsStringSync();
  });

  group('friend tags and stars', () {
    test('every table is owner-only', () {
      for (final table in [
        'friend_tags',
        'friend_tag_members',
        'friend_stars',
      ]) {
        expect(tags, contains('alter table public.$table enable row level'));
        expect(
          tags,
          contains('revoke all on public.$table from anon, authenticated'),
        );
        expect(tags, contains('${table}_select_own'));
        expect(tags, contains('${table}_delete_own'));
      }
      expect(tags, isNot(contains('to anon')));
      expect(tags, isNot(contains('using (true)')));
    });

    test('only friends can be tagged or starred', () {
      expect(tags, contains('friend_tag_members_insert_own'));
      expect(tags, contains('friend_stars_insert_own'));
      expect(
        RegExp('from public.friendships f').allMatches(tags).length,
        greaterThanOrEqualTo(2),
      );
    });

    test('unfriending takes the friend out of tags and stars', () {
      expect(tags, contains('after delete on public.friendships'));
      expect(tags, contains('delete from public.friend_tag_members'));
      expect(tags, contains('delete from public.friend_stars'));
    });

    test('tag names are unique per owner, ignoring case', () {
      expect(tags, contains('(owner_id, lower(btrim(name)))'));
      expect(tags, contains('between 1 and 30'));
    });
  });

  group('moments', () {
    test('every table has row level security and no anonymous access', () {
      for (final table in [
        'moments_settings',
        'moments_friend_prefs',
        'moments_posts',
        'moments_likes',
        'moments_comments',
        'moments_notifications',
      ]) {
        expect(moments, contains('alter table public.$table enable row level'));
        expect(
          moments,
          contains('revoke all on public.$table from anon, authenticated'),
        );
      }
      expect(moments, isNot(contains('to anon')));
    });

    test('the audience of a post is not granted to anyone', () {
      final grant = RegExp(
        r'grant select \(([^)]*)\) on public\.moments_posts to authenticated;',
      ).firstMatch(moments);
      expect(grant, isNotNull);
      final columns = grant!.group(1)!;
      expect(columns, isNot(contains('audience')));
      for (final column in [
        'id',
        'author_id',
        'body',
        'photos',
        'created_at',
      ]) {
        expect(columns, contains(column));
      }
    });

    test('posts are made and removed through functions only', () {
      expect(moments, isNot(contains('grant insert on public.moments_posts')));
      expect(moments, isNot(contains('on public.moments_posts for insert')));
      expect(
        moments,
        contains('create or replace function public.create_moment('),
      );
      expect(
        moments,
        contains('create or replace function public.delete_moment('),
      );
    });

    test('the helpers that take a viewer are not callable by the app', () {
      for (final signature in [
        'moments_are_friends(uuid, uuid)',
        'moments_post_visible_to(uuid, public.moments_posts)',
        'moments_interaction_visible(uuid, uuid, uuid, uuid)',
      ]) {
        expect(
          moments,
          contains(
            'revoke execute on function public.$signature from public, anon, authenticated;',
          ),
        );
      }
      // The ones that start from the signed-in person are.
      for (final signature in [
        'moments_can_view(uuid)',
        'moments_can_see_interaction(uuid, uuid, uuid)',
        'moments_can_view_profile(uuid)',
        'moments_can_read_object(text)',
      ]) {
        expect(
          moments,
          contains(
            'grant execute on function public.$signature to authenticated;',
          ),
        );
      }
    });

    test('likes and comments follow the mutual friends rule', () {
      expect(moments, contains('moments_likes_select_visible'));
      expect(moments, contains('moments_comments_select_visible'));
      expect(
        moments,
        contains('public.moments_can_see_interaction(post_id, user_id, null)'),
      );
      expect(
        moments,
        contains(
          'public.moments_can_see_interaction(post_id, author_id, reply_to_user_id)',
        ),
      );
      expect(moments, contains('moments_comments_delete_own_or_poster'));
    });

    test('the pictures live in a private, small, image-only bucket', () {
      expect(moments, contains("'moments'"));
      expect(moments, contains('false,\n  5242880'));
      expect(
        moments,
        contains("array['image/jpeg', 'image/png', 'image/webp']"),
      );
      expect(moments, contains('moments_select_visible'));
      expect(moments, contains('moments_insert_owner'));
      expect(moments, contains('moments_delete_owner'));
      // Reading follows the post's rules, not the folder alone.
      expect(moments, contains('moments_post_visible_to(auth.uid(), p)'));
    });

    test('the visibility rules are all in the one function', () {
      for (final fragment in [
        "p.visibility = 'private'",
        'moments_are_friends(viewer, p.author_id)',
        'fp.hide_mine',
        "range_setting = 'six_months'",
        "range_setting = 'one_month'",
        "range_setting = 'three_days'",
        "p.visibility = 'only'",
        'return not in_audience',
        'm.tag_id = any (p.audience_tag_ids)',
      ]) {
        expect(moments, contains(fragment));
      }
    });

    test('blocking either way hides everything', () {
      expect(
        moments,
        contains('b.blocker_id = user_a and b.blocked_id = user_b'),
      );
      expect(
        moments,
        contains('b.blocker_id = user_b and b.blocked_id = user_a'),
      );
    });
  });

  group('reading', () {
    test('the feed is keyset paged and hides hidden friends', () {
      expect(feed, contains('(p.created_at, p.id) <'));
      expect(feed, contains('order by p.created_at desc, p.id desc'));
      expect(feed, contains('fp.hide_theirs'));
      expect(feed, contains('moments_post_visible_to(me, p)'));
      expect(feed, contains('least(coalesce(p_limit, 20), 50)'));
    });

    test('likes and comments in the feed pass the mutual friends rule', () {
      expect(
        feed,
        contains(
          'moments_interaction_visible(me, page.author_id, l.user_id, null)',
        ),
      );
      expect(feed, contains('page.author_id, c.author_id, c.reply_to_user_id'));
    });

    test('profile fields that follow the profile setting are never read', () {
      for (final source in [moments, feed]) {
        for (final column in ['bio', 'banner_url', 'pronouns']) {
          expect(
            RegExp('\\b(pr|p|cp|lp|rp)\\.$column\\b').hasMatch(source),
            isFalse,
            reason: '$column must not come from profiles here',
          );
        }
      }
    });

    test('every function is signed-in only', () {
      for (final name in [
        'moments_feed(integer, timestamptz, uuid, uuid, uuid)',
        'moments_unseen_summary()',
        'mark_moments_seen()',
        'get_moments_profile(uuid)',
        'list_moments_notifications(integer)',
        'mark_moments_notifications_read(uuid[])',
        'list_moments_friend_prefs()',
      ]) {
        expect(
          feed,
          contains(
            'revoke execute on function public.$name from public, anon;',
          ),
        );
        expect(
          feed,
          contains('grant execute on function public.$name to authenticated;'),
        );
      }
    });
  });

  behaviourTest(
    'moments and tags: every mode, the mutual rule, storage, blocking',
    'test/supabase/moments_behaviour.sql',
  );
}
