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

  test('soundboard: sounds, storage, plays and the cooldown', () {
    final sql = migration('202610160019');

    expect(sql, contains('create table if not exists public.circle_sounds'));
    expect(
      sql,
      contains("check (mime_type in ('audio/mpeg', 'audio/ogg', 'audio/wav'))"),
    );
    expect(sql, contains('duration_ms between 1 and 5000'));
    expect(
      sql,
      contains(
        'revoke insert, update, delete, truncate on public.circle_sounds '
        'from authenticated;',
      ),
    );

    // The bucket: private, 512 KB, audio only, managed like emoji.
    expect(sql, contains("'circle-sounds',\n  false,\n  524288,"));
    for (final policy in [
      'circle_sounds_storage_select_member',
      'circle_sounds_storage_insert_manager',
      'circle_sounds_storage_delete_manager',
    ]) {
      expect(sql, contains('create policy $policy'));
    }
    expect(sql, contains(r'\.(mp3|ogg|wav)$'));

    final create = functionBody(sql, 'create_circle_sound');
    expect(create, contains("'manage_emojis'"));
    expect(create, contains("o.bucket_id = 'circle-sounds'"));
    expect(create, contains('>= 24'));
    expect(create, contains("'sound_create'"));
    expect(
      functionBody(sql, 'delete_circle_sound'),
      contains("'sound_delete'"),
    );

    expect(sql, contains('create table if not exists public.soundboard_plays'));
    expect(
      sql,
      contains(
        'alter publication supabase_realtime add table public.soundboard_plays;',
      ),
    );
    expect(
      functionBody(sql, 'soundboard_cooldown'),
      contains("interval '2 seconds'"),
    );
    final play = functionBody(sql, 'play_soundboard_sound');
    expect(play, contains("'connect_voice'"));
    expect(play, contains('state.server_mute'));
    expect(
      play,
      contains("channel.kind = 'stage' and not state.stage_speaker"),
    );
    expect(play, contains('pg_advisory_xact_lock'));
    expect(play, contains("format('soundboard_cooldown_ms=%s'"));

    for (final grant in [
      'create_circle_sound(uuid, text, text, text, text, integer)',
      'delete_circle_sound(uuid)',
      'list_circle_sounds(uuid)',
      'play_soundboard_sound(uuid, uuid)',
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
  });

  test('account deletion removes the soundboard clips of its circles', () {
    final sql = migration('202610160026');
    final prepare = functionBody(sql, 'prepare_account_deletion');
    expect(
      prepare,
      contains(
        "where o.bucket_id in ('circle-emojis', 'chat-media', 'circle-sounds');",
      ),
    );
    expect(
      prepare,
      contains('returns table (bucket_id text, object_path text)'),
    );
    expect(
      prepare,
      contains("'Transfer the circles you own to another member first'"),
    );
    expect(
      sql,
      contains(
        'grant execute on function public.prepare_account_deletion() '
        'to authenticated;',
      ),
    );
    // The Edge Function removes whatever buckets it is handed.
    final function = File(
      'supabase/functions/delete-account/index.ts',
    ).readAsStringSync();
    expect(function, contains('admin.storage.from(bucket).remove('));
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
