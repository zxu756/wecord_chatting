import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'behaviour_runner.dart';

/// Private Realtime channels (migration 202610190050) and the storage
/// bucket limits (202610190051): schema checks, plus the behaviour script,
/// which asks the policies on realtime.messages as members, outsiders,
/// ex-members, blocked people and signed-out callers.
void main() {
  late String realtime;
  late String storage;

  setUpAll(() {
    realtime = File(
      'supabase/migrations/202610190050_realtime_private.sql',
    ).readAsStringSync();
    storage = File(
      'supabase/migrations/202610190051_storage_limits.sql',
    ).readAsStringSync();
  });

  test('every policy is for signed-in people and names its extension', () {
    final policies = RegExp(
      r'create policy (\w+)\s+on realtime\.messages for (select|insert)\s+to authenticated',
    ).allMatches(realtime).toList();
    expect(policies.map((m) => m.group(1)).toSet(), {
      'chat_activity_receive',
      'chat_activity_send',
      'note_presence_receive',
      'note_presence_send',
      'online_users_receive',
      'online_users_send',
    });
    expect(
      RegExp(r'realtime\.messages\.extension (=|in)').allMatches(realtime),
      hasLength(6),
    );
    expect(realtime, isNot(contains('to anon')));
    expect(realtime, isNot(contains('to public')));
  });

  test('listening and sending are decided by the same rule', () {
    for (final name in ['chat_activity', 'note_presence', 'online_users']) {
      final receive = RegExp(
        'create policy ${name}_receive.*?;',
        dotAll: true,
      ).firstMatch(realtime)!.group(0)!;
      final send = RegExp(
        'create policy ${name}_send.*?;',
        dotAll: true,
      ).firstMatch(realtime)!.group(0)!;
      expect(
        receive.substring(receive.indexOf('using')),
        send
            .substring(send.indexOf('with check'))
            .replaceFirst('with check', 'using'),
        reason: name,
      );
    }
  });

  test('members, note viewers and blocks use the existing helpers', () {
    expect(realtime, contains('public.is_current_user_conversation_member('));
    expect(
      realtime,
      contains('public.is_current_user_blocked_in_conversation('),
    );
    expect(realtime, contains('public.can_current_user_view_note('));
  });

  test('every bucket people upload to gets a size limit', () {
    for (final bucket in [
      'chat-images',
      'chat-files',
      'voice-messages',
      'profile-avatars',
      'profile-banners',
    ]) {
      expect(storage, contains("'$bucket'"), reason: bucket);
    }
    expect(storage, contains('52428800'));
    expect(storage, contains('20971520'));
  });

  test('chat-files keeps any type, with its size cap', () {
    expect(
      storage,
      contains('''
set file_size_limit = 52428800,
    allowed_mime_types = null
where id = 'chat-files';'''),
    );
  });

  test('the picture and voice buckets take what the app sends', () {
    // maxChatFileBytes in chats_repository.dart is the chat-files ceiling.
    expect(storage, contains('52428800'));
    for (final type in [
      'image/jpeg',
      'image/png',
      'image/gif',
      'image/webp',
      'image/heic',
      'audio/wav',
    ]) {
      expect(storage, contains("'$type'"), reason: type);
    }
    expect(storage, isNot(contains('svg')));
  });

  behaviourTest(
    'realtime channels and bucket limits: who may listen and send, what '
        'uploads are accepted',
    'test/supabase/realtime_private_behaviour.sql',
  );
}
