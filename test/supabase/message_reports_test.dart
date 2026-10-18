import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'behaviour_runner.dart';

/// Schema checks for message reports (migrations 202610220110 and
/// 202610220120) and the terms acceptance (202610220130), plus the behaviour
/// script: the attacks that must fail (reading reports and snapshots as the
/// reporter, the reported person, an outsider and a circle owner; reporting
/// your own message, a message you cannot see, too often) and the walk
/// through reporting and handling in a circle and in the admin console.
void main() {
  late String reports;
  late String admin;
  late String terms;

  setUpAll(() {
    reports = File(
      'supabase/migrations/202610220110_message_reports.sql',
    ).readAsStringSync();
    admin = File(
      'supabase/migrations/202610220120_message_reports_admin.sql',
    ).readAsStringSync();
    terms = File(
      'supabase/migrations/202610220130_terms_acceptance.sql',
    ).readAsStringSync();
  });

  group('message_reports', () {
    test('is closed to the API except plain columns for the people involved', () {
      expect(
        reports,
        contains('alter table public.message_reports enable row level security'),
      );
      expect(
        reports,
        contains(
          'revoke all on public.message_reports from public, anon, authenticated',
        ),
      );
      // Column-level select: the content is only in the functions.
      final grant = reports.substring(
        reports.indexOf('grant select ('),
        reports.indexOf('on public.message_reports to authenticated'),
      );
      for (final column in ['snapshot', 'context', 'details', 'reported_user_id']) {
        expect(grant, isNot(contains(column)), reason: column);
      }
      expect(reports, isNot(contains('grant insert')));
      expect(reports, isNot(contains('grant update')));
      expect(reports, isNot(contains('grant delete')));
    });

    test('the reported person is left out of every handler policy', () {
      expect(
        RegExp('reported_user_id is distinct from auth.uid\\(\\)')
            .allMatches(reports)
            .length,
        greaterThanOrEqualTo(3),
      );
      expect(
        RegExp('reported_user_id is distinct from auth.uid\\(\\)')
            .allMatches(admin)
            .length,
        greaterThanOrEqualTo(3),
      );
    });

    test('a report is of one of three states with a reason from the list', () {
      expect(reports, contains("status in ('open', 'actioned', 'dismissed')"));
      expect(
        reports,
        contains(
          "reason in ('spam', 'harassment', 'impersonation', 'unsafe_content', 'other')",
        ),
      );
    });

    test('view-once media and storage paths are never copied', () {
      expect(reports, contains("attachment->>'view_once' = 'true'"));
      final keys = reports.substring(
        reports.indexOf("e.key in ("),
        reports.indexOf("and jsonb_typeof(e.value)"),
      );
      expect(keys, isNot(contains("'path'")));
      expect(keys, isNot(contains("'bucket'")));
    });

    test('the retention rides on the existing daily job', () {
      expect(reports, contains('interval \'90 days\''));
      expect(reports, contains('perform public.purge_old_message_report_data()'));
      expect(reports, isNot(contains('cron.schedule')));
    });

    test('the functions are security definer with a fixed search path', () {
      for (final name in [
        'report_message',
        'list_circle_message_reports',
        'resolve_message_report',
      ]) {
        final start = reports.indexOf('create or replace function public.$name(');
        expect(start, isNonNegative, reason: name);
        final text = reports.substring(start, reports.indexOf('\n\$\$;', start));
        expect(text, contains('security definer'), reason: name);
        expect(text, contains('set search_path = public'), reason: name);
      }
      for (final name in [
        'admin_list_message_reports',
        'admin_get_message_report',
        'admin_resolve_message_report',
      ]) {
        final start = admin.indexOf('create or replace function public.$name(');
        expect(start, isNonNegative, reason: name);
        final text = admin.substring(start, admin.indexOf('\n\$\$;', start));
        expect(text, contains('security definer'), reason: name);
        expect(text, contains('admin_require('), reason: name);
      }
    });

    test('internal helpers are not callable by clients', () {
      for (final name in [
        'report_attachment_meta(jsonb)',
        'report_can_see_message(public.messages)',
        'report_message_snapshot(public.messages)',
        'report_message_context(public.messages)',
        'purge_old_message_report_data()',
      ]) {
        expect(
          reports,
          contains('revoke execute on function public.$name'),
          reason: name,
        );
        expect(
          reports,
          isNot(contains('grant execute on function public.$name')),
          reason: name,
        );
      }
      expect(
        admin,
        contains('revoke execute on function public.admin_erase_message(uuid)'),
      );
      expect(admin, isNot(contains('grant execute on function public.admin_erase_message')));
    });

    test('moderator actions reuse the circle functions that check permissions', () {
      expect(reports, contains('public.recall_message('));
      expect(reports, contains('public.timeout_circle_member('));
      expect(reports, contains('public.ban_circle_member('));
      expect(reports, contains('public.write_circle_audit('));
    });
  });

  group('the admin side', () {
    test('writes the admin audit log and handles only direct chats and groups', () {
      expect(admin, contains("admin_write_audit(\n    'resolve_message_report'"));
      expect(admin, contains('circle_id is null'));
    });
  });

  group('terms acceptance', () {
    test('the profile columns are private and stamped by the server', () {
      expect(terms, contains('accepted_terms_at timestamptz'));
      expect(terms, contains('age_confirmed_at timestamptz'));
      expect(terms, contains('new.accepted_terms_at := now()'));
      expect(terms, contains('before insert on public.profiles'));
      expect(terms, isNot(contains('grant select')));
    });
  });

  behaviourTest(
    'message reports: attacks, circle moderation, admin queue, retention, terms',
    'test/supabase/message_reports_behaviour.sql',
    // The script drops and rebuilds the schema from every migration.
    rebuildsSchema: true,
  );
}
