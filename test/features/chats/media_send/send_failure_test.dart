import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart' show PostgrestException;
import 'package:wecord/features/chats/chats_repository.dart';
import 'package:wecord/features/chats/media_send/media_upload.dart';
import 'package:wecord/features/chats/media_send/outbox_media.dart';
import 'package:wecord/features/chats/media_send/send_failure.dart';
import 'package:wecord/features/chats/offline/outbox.dart';
import 'package:wecord/features/chats/pending_message.dart';
import 'package:wecord/shared/l10n/l10n.dart';
import 'package:wecord/shared/theme/wecord_theme.dart';

OutboxEntry _failed(Object? error, {bool media = true}) {
  return OutboxEntry(
    clientId: 'c1',
    conversationId: 'conversation-1',
    body: '',
    createdAt: DateTime.utc(2026, 10, 17),
    state: OutboxState.failed,
    error: error,
    media: media
        ? const OutboxMedia(
            kind: OutboxMediaKind.image,
            fileName: 'a.jpg',
            mimeType: 'image/jpeg',
            size: 10,
            groupId: 'g',
          )
        : null,
  );
}

PostgrestException _postgrest(String code, String message) =>
    PostgrestException(message: message, code: code);

void main() {
  tearDown(() => AppStrings.isChinese = false);

  group('sendFailureReason', () {
    test('slowmode says how long, as text sends do', () {
      expect(
        sendFailureReason(const SlowmodeException(8)),
        'Slowmode is enabled. Try again in 8 seconds.',
      );
    });

    test('AutoMod gives its reason, or says it blocked the message', () {
      expect(
        sendFailureReason(const AutoModBlockedException('No links here')),
        'AutoMod blocked your message: No links here',
      );
      expect(
        sendFailureReason(const AutoModBlockedException()),
        'AutoMod blocked your message.',
      );
    });

    test('the circle rules, the size limit and a missing file', () {
      expect(
        sendFailureReason(const CircleRulesNotAcceptedException()),
        'Accept the circle rules to start chatting.',
      );
      expect(
        sendFailureReason(const ChatFileTooLargeException()),
        'Files can be up to 50 MB.',
      );
      expect(
        sendFailureReason(const UploadException(413, 'big')),
        'Files can be up to 50 MB.',
      );
      expect(
        sendFailureReason(PendingMediaMissingException()),
        'The file to send is no longer there.',
      );
    });

    test('a refusal to send is a timeout while the member is timed out', () {
      final now = DateTime.utc(2026, 10, 17, 12);
      final error = _postgrest(
        '42501',
        'You do not have permission to send messages in this channel',
      );
      expect(
        sendFailureReason(error, now: now),
        "You don't have permission to send messages in this channel",
      );
      final reason = sendFailureReason(
        error,
        timedOutUntil: now.add(const Duration(hours: 2)),
        now: now,
      );
      expect(reason, startsWith("You're timed out until "));
      expect(reason, endsWith('You can read, but not send messages or react.'));
      // A timeout that ended is just a missing permission.
      expect(
        sendFailureReason(
          error,
          timedOutUntil: now.subtract(const Duration(hours: 1)),
          now: now,
        ),
        "You don't have permission to send messages in this channel",
      );
    });

    test('reads in Chinese', () {
      AppStrings.isChinese = true;
      expect(
        sendFailureReason(const CircleRulesNotAcceptedException()),
        isNot('Accept the circle rules to start chatting.'),
      );
      expect(sendFailureReason(PendingMediaMissingException()), '要发送的文件已不存在。');
    });

    test('is null when nobody said why', () {
      expect(sendFailureReason(null), isNull);
      expect(sendFailureReason(http.ClientException('offline')), isNull);
      expect(sendFailureReason(TimeoutException('slow')), isNull);
      expect(sendFailureReason(const UploadCancelledException()), isNull);
    });
  });

  group('isRetryableFailure', () {
    test('network trouble and slowmode can be tried again', () {
      expect(isRetryableFailure(null), isTrue);
      expect(isRetryableFailure(http.ClientException('offline')), isTrue);
      expect(isRetryableFailure(const UploadException(503, 'busy')), isTrue);
      expect(isRetryableFailure(const SlowmodeException(3)), isTrue);
    });

    test('what the server refused outright is edited and sent anew', () {
      expect(isRetryableFailure(const AutoModBlockedException('x')), isFalse);
      expect(
        isRetryableFailure(const CircleRulesNotAcceptedException()),
        isFalse,
      );
      expect(isRetryableFailure(const ChatFileTooLargeException()), isFalse);
      expect(isRetryableFailure(const UploadException(413, 'big')), isFalse);
      expect(isRetryableFailure(PendingMediaMissingException()), isFalse);
      expect(isRetryableFailure(_postgrest('42501', 'no permission')), isFalse);
    });
  });

  group('the failed status under a bubble', () {
    Future<void> pump(
      WidgetTester tester,
      OutboxEntry entry, {
      String? reason,
      VoidCallback? onEditResend,
      List<String>? log,
    }) {
      return tester.pumpWidget(
        MaterialApp(
          theme: WeCordTheme.light(),
          home: Scaffold(
            body: PendingMessageFrame(
              entry: entry,
              reason: reason,
              onRetry: () => log?.add('retry'),
              onDiscard: () => log?.add('discard'),
              onEditResend: onEditResend ?? () => log?.add('edit'),
              child: const SizedBox(width: 100, height: 40),
            ),
          ),
        ),
      );
    }

    testWidgets('keeps the old line when nobody said why', (tester) async {
      await pump(tester, _failed(null));
      expect(find.text('Failed — tap to retry'), findsOneWidget);
      expect(find.text('Discard'), findsNothing);
    });

    testWidgets('a refusal shows its reason with Edit and resend', (
      tester,
    ) async {
      final log = <String>[];
      await pump(
        tester,
        _failed(const AutoModBlockedException('No links')),
        reason: 'AutoMod blocked your message: No links',
        log: log,
      );
      expect(
        find.text('AutoMod blocked your message: No links'),
        findsOneWidget,
      );
      expect(find.text('Retry'), findsNothing);
      await tester.tap(find.text('Edit and resend'));
      await tester.tap(find.text('Discard'));
      expect(log, ['edit', 'discard']);
    });

    testWidgets('slowmode shows its reason with Retry', (tester) async {
      final log = <String>[];
      await pump(
        tester,
        _failed(const SlowmodeException(5)),
        reason: 'Slowmode is enabled. Try again in 5 seconds.',
        log: log,
      );
      expect(find.text('Edit and resend'), findsNothing);
      await tester.tap(find.text('Retry'));
      expect(log, ['retry']);
    });

    testWidgets('a text message keeps Retry whatever the reason', (
      tester,
    ) async {
      await pump(
        tester,
        _failed(const AutoModBlockedException(), media: false),
        reason: 'AutoMod blocked your message.',
      );
      expect(find.text('Edit and resend'), findsNothing);
      expect(find.text('Retry'), findsOneWidget);
    });
  });
}
