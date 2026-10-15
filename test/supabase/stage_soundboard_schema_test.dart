import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Schema checks for stage channels and the soundboard.
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

  String functionBody(String sql, String name) {
    final match = RegExp(
      'create or replace function public\\.$name\\s*\\([\\s\\S]*?\\n\\\$\\\$;',
    ).allMatches(sql);
    expect(match, isNotEmpty, reason: 'Missing function $name');
    return match.last.group(0)!;
  }

  test('stage channels: kind, live stages and the stage role', () {
    final sql = migration('202610160018');

    // The kind constraint keeps whatever kinds it already allowed.
    expect(sql, contains('pg_get_constraintdef(c.oid)'));
    expect(sql, contains("array['text', 'voice', 'forum', 'stage']"));
    expect(
      functionBody(sql, 'create_circle_channel'),
      contains("channel_kind not in ('text', 'forum', 'voice', 'stage')"),
    );

    expect(sql, contains('create table if not exists public.stage_instances'));
    expect(
      sql,
      contains('alter table public.stage_instances enable row level security;'),
    );
    expect(
      sql,
      contains(
        'revoke insert, update, delete, truncate on public.stage_instances '
        'from authenticated;',
      ),
    );
    expect(
      sql,
      contains(
        'alter publication supabase_realtime add table public.stage_instances;',
      ),
    );
    for (final column in [
      'stage_speaker boolean not null default false',
      'stage_invited boolean not null default false',
      'hand_raised_at timestamptz',
    ]) {
      expect(sql, contains('add column if not exists $column'));
    }

    final moderator = functionBody(sql, 'is_current_user_stage_moderator');
    expect(moderator, contains("'mute_members'"));
    expect(moderator, contains("'move_members'"));
    for (final name in ['start_stage', 'end_stage', 'invite_stage_speaker']) {
      expect(
        functionBody(sql, name),
        contains('is_current_user_stage_moderator'),
        reason: name,
      );
    }
    expect(functionBody(sql, 'start_stage'), contains("'stage_start'"));
    expect(functionBody(sql, 'end_stage'), contains("'stage_end'"));
    expect(
      functionBody(sql, 'set_stage_audience'),
      contains('can_moderate_voice_member'),
    );

    final token = functionBody(sql, 'can_current_user_connect_voice');
    expect(token, contains("channel.kind not in ('voice', 'stage')"));
    expect(token, contains("'stage_speaker'"));
    final enforce = functionBody(sql, 'voice_enforcement_state');
    expect(enforce, contains('target_user_id = auth.uid()'));
    expect(enforce, contains("'stage_speaker'"));
    expect(
      functionBody(sql, 'join_voice_state'),
      contains("channel.kind = 'stage' and rejoining"),
    );

    for (final grant in [
      'list_stage_instances(uuid)',
      'start_stage(uuid, text)',
      'end_stage(uuid)',
      'set_stage_hand_raised(uuid, boolean)',
      'invite_stage_speaker(uuid, uuid)',
      'respond_stage_invite(uuid, boolean)',
      'set_stage_audience(uuid, uuid)',
    ]) {
      expect(
        sql,
        contains('grant execute on function public.$grant to authenticated;'),
      );
      expect(
        sql,
        contains('revoke execute on function public.$grant from anon;'),
      );
    }
    expect(
      sql,
      contains(
        'revoke execute on function '
        'public.is_current_user_stage_moderator(uuid) from authenticated;',
      ),
    );
  });

  test('livekit-token only lets stage speakers publish', () {
    final index = File(
      'supabase/functions/livekit-token/index.ts',
    ).readAsStringSync();
    expect(index, contains('canPublish: canPublishIn('));
    final token = File(
      'supabase/functions/livekit-token/token.ts',
    ).readAsStringSync();
    expect(token, contains('export function canPublishIn('));
    expect(token, contains('can_publish: canPublish,'));
  });
}
