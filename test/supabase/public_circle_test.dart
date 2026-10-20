import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'behaviour_runner.dart';

/// Schema checks for the public circle web pages (C8: migrations
/// 202610260500 and 202610260510), plus the behaviour script that plays the
/// anon role the Worker uses against private, taken-down and invalid cases.
void main() {
  late String slug;
  late String card;

  setUpAll(() {
    slug = File(
      'supabase/migrations/202610260500_circle_slug.sql',
    ).readAsStringSync();
    card = File(
      'supabase/migrations/202610260510_public_circle_card.sql',
    ).readAsStringSync();
  });

  String body(String sql, String name) {
    final start = sql.indexOf('create or replace function public.$name(');
    expect(start, isNonNegative, reason: name);
    return sql.substring(start, sql.indexOf('\n\$\$;', start));
  }

  group('the short name', () {
    test('is lower case, 3 to 32 characters and unique', () {
      expect(slug, contains("slug ~ '^[a-z0-9][a-z0-9-]{1,30}[a-z0-9]\$'"));
      expect(slug, contains("slug !~ '--'"));
      expect(
        slug,
        contains('create unique index if not exists circles_slug_key'),
      );
    });

    test('is set by circle managers only, audited and rate limited', () {
      final set = body(slug, 'set_circle_slug');
      expect(set, contains("'manage_circle'"));
      expect(set, contains("'slug_update'"));
      expect(set, contains("errcode = 'PB429'"));
      expect(set, contains('security definer'));
      expect(set, contains('set search_path = public'));
      expect(
        slug,
        contains(
          'revoke execute on function public.set_circle_slug(uuid, text)',
        ),
      );
    });

    test('opening it in the app says nothing about private circles', () {
      final resolve = body(slug, 'resolve_circle_slug');
      expect(resolve, contains('disabled_at is not null'));
      expect(resolve, contains('not found.is_public'));
    });
  });

  group('what anon can read', () {
    test('only the two card functions are open to anon', () {
      expect(
        card,
        contains(
          'grant execute on function public.get_public_circle_card(text) to anon, authenticated;',
        ),
      );
      expect(
        card,
        contains(
          'grant execute on function public.get_public_invite_card(text) to anon, authenticated;',
        ),
      );
      expect(RegExp('to anon').allMatches(card).length, 2);
      for (final helper in [
        'public_circle_member_level(bigint)',
        'public_circle_card_json(public.circles)',
      ]) {
        expect(
          card,
          contains(
            'revoke execute on function public.$helper from public, anon, authenticated;',
          ),
        );
      }
    });

    test('both are read-only, definer functions with a fixed search path', () {
      for (final name in ['get_public_circle_card', 'get_public_invite_card']) {
        final function = body(card, name);
        expect(function, contains('stable'), reason: name);
        expect(function, contains('security definer'), reason: name);
        expect(function, contains('set search_path = public'), reason: name);
        expect(function, contains('c.is_public'), reason: name);
        expect(function, contains('c.disabled_at is null'), reason: name);
        expect(function, isNot(contains('insert into')), reason: name);
        expect(function, isNot(contains('update public')), reason: name);
      }
      expect(
        body(card, 'get_public_invite_card'),
        contains('circle_invite_invalid_reason(invite) is not null'),
      );
    });

    test('the card has no ids, member names or counts', () {
      final json = body(card, 'public_circle_card_json');
      expect(json, isNot(contains("'id'")));
      expect(json, isNot(contains('profiles')));
      expect(json, isNot(contains("'member_count'")));
      expect(json, contains('public_circle_member_level'));
    });
  });

  behaviourTest(
    'public circle pages: slug rules, anon card, take-downs and invalid invites',
    'test/supabase/public_circle_behaviour.sql',
  );
}
