import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Schema checks for public circles and discovery (202610160040-42).
void main() {
  String migration(String prefix) {
    final file = Directory('supabase/migrations')
        .listSync()
        .whereType<File>()
        .singleWhere(
          (file) => file.uri.pathSegments.last.startsWith(prefix),
          orElse: () => throw StateError('Missing migration $prefix'),
        );
    return file.readAsStringSync();
  }

  String function(String sql, String name) {
    return RegExp(
      'create or replace function public\\.$name\\([\\s\\S]*?\\n\\\$\\\$;',
    ).firstMatch(sql)!.group(0)!;
  }

  group('public circles', () {
    final sql = migration('202610160040');

    test('circles stay private by default and public ones need a category', () {
      expect(
        sql,
        contains(
          'add column if not exists is_public boolean not null default false',
        ),
      );
      expect(sql, contains('not is_public or discovery_category is not null'));
      expect(
        sql,
        contains('char_length(discovery_description) between 1 and 300'),
      );
      expect(sql, contains('cardinality(discovery_tags) <= 5'));
      for (final category in [
        'gaming',
        'music',
        'education',
        'science_tech',
        'entertainment',
        'art',
        'sports',
        'travel_outdoors',
        'food',
        'local',
        'other',
      ]) {
        expect(sql, contains("'$category'"));
      }
    });

    test('search has a tsvector and a trigram index over public circles', () {
      expect(sql, contains('create extension if not exists pg_trgm'));
      expect(sql, contains('using gin (discovery_search)'));
      expect(sql, contains('extensions.gin_trgm_ops'));
      expect(
        RegExp(r'create index[^;]*where is_public;').allMatches(sql).length,
        greaterThanOrEqualTo(2),
      );
    });

    test('only managers change discovery, and it is audited', () {
      final save = function(sql, 'set_circle_discovery');
      expect(save, contains('security definer'));
      expect(
        save,
        contains(
          "current_user_has_circle_permission(target_circle_id, 'manage_circle')",
        ),
      );
      expect(save, contains("'discovery_update'"));
      expect(save, contains('coalesce(c.discovery_listed_at, now())'));
      expect(sql, isNot(contains('to anon')));
    });
  });

  group('discovery', () {
    final sql = migration('202610160041');

    test(
      'listing and previews only show public circles, to signed-in users',
      () {
        final list = function(sql, 'list_discoverable_circles');
        expect(list, contains('security definer'));
        expect(list, contains('where c.is_public'));
        expect(list, contains("raise exception 'Authentication required'"));
        expect(
          list,
          contains('least(greatest(coalesce(page_size, 24), 1), 50)'),
        );
        // CJK text isn't segmented by full-text search: substring fallback.
        expect(list, contains('websearch_to_tsquery'));
        expect(list, contains(') like pattern'));
        // No owner, member list or other private columns.
        expect(list, isNot(contains('owner_id')));
        final preview = function(sql, 'discoverable_circle_preview');
        expect(preview, contains('and c.is_public'));
        expect(preview, contains("using errcode = 'P0002'"));
        expect(preview, isNot(contains('owner_id')));
        expect(preview, contains('r.is_default'));
      },
    );

    test('joining refuses banned users and is rate limited', () {
      final join = function(sql, 'join_public_circle');
      expect(join, contains('not circle.is_public'));
      expect(join, contains('public.circle_bans'));
      expect(join, contains("errcode = 'PB429'"));
      expect(join, contains(">= 10"));
      expect(
        sql,
        contains(
          'revoke all on public.circle_public_joins from anon, authenticated',
        ),
      );
      expect(
        sql,
        contains(
          'revoke all on public.presence_heartbeats from anon, authenticated',
        ),
      );
    });

    test('hidden users never count as online', () {
      final touch = function(sql, 'touch_presence');
      expect(touch, contains("'invisible'"));
      expect(touch, contains('show_online_status'));
      expect(touch, contains('delete from public.presence_heartbeats'));
    });
  });

  test('public circles can be reported with the safety reports table', () {
    final sql = migration('202610160042');
    expect(sql, contains('alter table public.reports'));
    expect(sql, contains('add column if not exists target_circle_id uuid'));
    final report = function(sql, 'report_circle');
    expect(report, contains('circle.is_public'));
    expect(report, contains("'Cannot report your own circle'"));
    expect(report, contains("errcode = 'PB429'"));
  });
}
