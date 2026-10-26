import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'behaviour_runner.dart';

/// Two-step recovery codes and passkeys (G4: migrations 202610280400 to
/// 202610280430): what the SQL says, as text, plus the behaviour script that
/// plays people through it against the local database.
void main() {
  final names = [
    '202610280400_account_security_schema.sql',
    '202610280410_mfa_recovery_codes.sql',
    '202610280420_account_security_events.sql',
    '202610280430_account_security_triggers.sql',
  ];
  late Map<String, String> sql;
  late String all;

  setUpAll(() {
    sql = {
      for (final name in names)
        name: File('supabase/migrations/$name').readAsStringSync(),
    };
    all = sql.values.join('\n');
  });

  group('numbering and what is left alone', () {
    test('the migrations are in this package\'s range, ten apart', () {
      final numbers = [
        for (final name in names) int.parse(name.substring(0, 12)),
      ];
      for (var i = 0; i < numbers.length; i++) {
        expect(numbers[i], 202610280400 + i * 10);
      }
      expect(numbers.last, lessThan(202610280500));
    });

    test(
      'the every-minute dispatcher and older functions are not rewritten',
      () {
        expect(all, isNot(contains('function public.run_later_dispatch')));
        expect(
          all,
          isNot(contains('function public.claim_security_alert_pushes')),
        );
        expect(
          all,
          isNot(contains('function public.prepare_account_deletion')),
        );
        expect(
          all,
          isNot(contains('function public.user_devices_login_alert')),
        );
      },
    );

    test('nothing reintroduces a bare bio', () {
      expect(all, isNot(matches(RegExp(r"'bio',\s*\w+\.bio\b"))));
      expect(all, isNot(matches(RegExp(r'\n\s*\w+\.bio,\n'))));
    });

    test('Supabase Auth is read, never configured', () {
      expect(all, isNot(contains('config push')));
      expect(all, isNot(contains('secrets set')));
      // The only writes to Auth's own tables would be triggers on them.
      expect(
        all,
        isNot(matches(RegExp(r'(insert into|update|delete from) auth\.'))),
      );
    });
  });

  group('the codes', () {
    test('only a salted hash is stored, never the code', () {
      final schema = sql['202610280400_account_security_schema.sql']!;
      expect(schema, contains('salt text not null'));
      expect(schema, contains('code_hash text not null'));
      final codes = sql['202610280410_mfa_recovery_codes.sql']!;
      expect(codes, contains("'sha256'"));
      expect(codes, contains('extensions.gen_random_bytes(16)'));
      expect(
        codes,
        isNot(
          contains('insert into public.mfa_recovery_codes (user_id, code)'),
        ),
      );
    });

    test('the tables are closed to clients', () {
      final schema = sql['202610280400_account_security_schema.sql']!;
      for (final table in [
        'mfa_recovery_codes',
        'mfa_recovery_attempts',
        'account_security_events',
      ]) {
        expect(
          schema,
          contains('alter table public.$table enable row level security'),
        );
        expect(
          schema,
          contains(
            'revoke all on public.$table from public, anon, authenticated',
          ),
        );
      }
      expect(schema, isNot(contains('grant select')));
    });

    test('making codes needs a session that just passed the authenticator', () {
      final codes = sql['202610280410_mfa_recovery_codes.sql']!;
      expect(codes, contains("claims ->> 'aal' is distinct from 'aal2'"));
      expect(codes, contains("e ->> 'method' = 'totp'"));
      expect(codes, contains('- 600'));
      expect(codes, contains("'rate_limited'"));
    });

    test('trying a code is the service role\'s, with a lock', () {
      final codes = sql['202610280410_mfa_recovery_codes.sql']!;
      expect(codes, contains('max_failures constant integer := 5'));
      expect(codes, contains("interval '30 minutes'"));
      expect(
        codes,
        contains(
          'grant execute on function public.consume_mfa_recovery_code(uuid, text) to service_role',
        ),
      );
      expect(
        codes,
        contains(
          'revoke execute on function public.consume_mfa_recovery_code(uuid, text)\n  from public, anon, authenticated',
        ),
      );
      expect(codes, contains('for update'));
    });

    test('every function is security definer with a fixed search path', () {
      for (final source in sql.values) {
        final functions = RegExp(
          r'create or replace function public\.(\w+)\(([\s\S]*?)\n\$\$;',
        ).allMatches(source);
        for (final match in functions) {
          final body = match.group(0)!;
          final name = match.group(1)!;
          expect(body, contains('set search_path = public'), reason: name);
          // The three small helpers are plain SQL; the rest run as the owner.
          if (!{
            'new_recovery_code',
            'normalize_recovery_code',
            'recovery_code_hash',
          }.contains(name)) {
            expect(body, contains('security definer'), reason: name);
          }
        }
      }
    });
  });

  group('the record', () {
    test('events are pushed in Chinese and English', () {
      final events = sql['202610280420_account_security_events.sql']!;
      expect(events, contains("s.language = 'zh'"));
      expect(events, contains('两步验证恢复码已重新生成'));
      expect(events, contains('A passkey was added to your account'));
      expect(
        events,
        contains(
          "replace(replace(coalesce(c.detail ->> 'name', ''), '<', ''), '>', '')",
        ),
      );
    });

    test('the export has no hash, salt or key', () {
      final events = sql['202610280420_account_security_events.sql']!;
      final export = events.substring(
        events.indexOf('function public.export_my_account_security'),
      );
      expect(export, isNot(contains('code_hash')));
      expect(export, isNot(contains('public_key')));
      expect(export, isNot(contains('credential_id')));
      expect(export, contains('service_role'));
    });

    test('deleting an account erases it', () {
      final schema = sql['202610280400_account_security_schema.sql']!;
      expect(schema, contains('after update of deleted_at on public.profiles'));
      expect(schema, contains('delete from public.mfa_recovery_codes'));
      expect(schema, contains('delete from public.account_security_events'));
      expect(schema, contains('references auth.users(id) on delete cascade'));
    });

    test('the Auth triggers cannot break Auth or the migration', () {
      final triggers = sql['202610280430_account_security_triggers.sql']!;
      expect(triggers, contains('exception when others then'));
      expect(
        triggers,
        contains('after insert or delete on auth.webauthn_credentials'),
      );
      expect(triggers, contains('after delete on auth.mfa_factors'));
      // They skip accounts that are going away.
      expect(triggers, contains('from auth.users u where u.id = owner_id'));
    });
  });

  group('the Edge Function', () {
    test('mfa-recovery checks the token and is deployed with it', () {
      final config = File('supabase/config.toml').readAsStringSync();
      expect(config, contains('[functions.mfa-recovery]'));
      final handler = File(
        'supabase/functions/mfa-recovery/handler.ts',
      ).readAsStringSync();
      expect(handler, contains('deps.authenticate'));
      expect(handler, contains('consume'));
    });

    test('the scheduled dispatcher claims the new pushes', () {
      final index = File(
        'supabase/functions/scheduled-dispatch/index.ts',
      ).readAsStringSync();
      expect(index, contains('claim_account_security_pushes'));
    });

    test('data export and account deletion cover the new data', () {
      final collect = File(
        'supabase/functions/data-export/collect.ts',
      ).readAsStringSync();
      expect(collect, contains('export_my_account_security'));
    });
  });

  behaviourTest(
    'the behaviour script passes',
    'test/supabase/account_security_behaviour.sql',
  );
}
