import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:wecord/features/circles/circle_bot_repository.dart';
import 'package:wecord/features/circles/circle_bot_widgets.dart';
import 'package:wecord/features/circles/circle_rpc.dart';
import 'package:wecord/features/interactions/interactions_repository.dart';
import 'package:wecord/shared/models/circle.dart';
import 'package:wecord/shared/models/message_origin.dart';

import '../circles/announcement_channels_test.dart' show RecordingRpc;

Map<String, dynamic> _botJson() => {
  'id': 'bot-1',
  'circle_id': 'circle-1',
  'user_id': 'bot-user',
  'name': 'Helper',
  'username': 'bot_abc',
  'has_token': true,
  'is_member': true,
  'role_names': <String>[],
  'command_count': 1,
  'created_at': '2026-10-16T08:00:00Z',
  'last_used_at': null,
};

CircleDetail _detail() {
  return CircleDetail.fromJson({
    'circle': {
      'id': 'circle-1',
      'name': 'Study Hall',
      'member_count': 1,
      'channel_count': 1,
      'current_user_role': 'owner',
    },
    'members': const [],
    'channels': const [],
    'posts': const [],
    'roles': const [],
  });
}

const _secret =
    '0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef';

Future<RecordingRpc> _openCallback(
  WidgetTester tester, {
  required Map<String, Object? Function(Map<String, dynamic>)> responses,
}) async {
  final rpc = RecordingRpc({
    'list_circle_bots': (_) => [_botJson()],
    ...responses,
  });
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        circleRpcProvider.overrideWithValue(rpc.call),
        circleFunctionProvider.overrideWithValue(rpc.call),
      ],
      child: MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: CircleBotsSection(detail: _detail()),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(const ValueKey('circle-bot-menu-bot-1')));
  await tester.pumpAndSettle();
  await tester.tap(find.text('Callback address'));
  await tester.pumpAndSettle();
  return rpc;
}

void main() {
  test('the repository reads, sets, rotates and clears the callback', () async {
    final rpc = RecordingRpc({
      'get_bot_callback': (_) => {
        'url': 'https://example.com/hook',
        'enabled': true,
        'consecutive_failures': 3,
        'last_status': 502,
        'last_error': 'http_502',
        'last_failure_at': '2026-10-28T09:00:00Z',
        'last_success_at': null,
      },
      'set_bot_callback': (_) => {
        'url': 'https://example.com/hook',
        'enabled': true,
        'secret': _secret,
      },
      'rotate_bot_callback_secret': (_) => {
        'url': 'https://example.com/hook',
        'enabled': true,
        'secret': 'f' * 64,
      },
      'clear_bot_callback': (_) => null,
    });
    final repository = CircleBotRepository(rpc.call, rpc.call);

    final read = await repository.getCallback('bot-1');
    expect(read.isSet, isTrue);
    expect(read.consecutiveFailures, 3);
    expect(read.lastStatus, 502);
    expect(read.lastError, 'http_502');
    expect(read.lastFailureAt, DateTime.utc(2026, 10, 28, 9));
    expect(read.secret, isNull);

    final set = await repository.setCallback(
      'bot-1',
      ' https://example.com/hook ',
    );
    expect(set.secret, _secret);
    expect(rpc.calls[1].$2, {
      'target_bot_id': 'bot-1',
      'callback_url': 'https://example.com/hook',
    });

    expect((await repository.rotateCallbackSecret('bot-1')).secret, 'f' * 64);
    await repository.clearCallback('bot-1');
    expect(rpc.calls.last.$1, 'clear_bot_callback');
    expect(const BotCallback().isSet, isFalse);
    expect(
      BotCallback.fromJson({'url': null, 'enabled': false}).isSet,
      isFalse,
    );
  });

  test('presses, statuses and private replies are read from the server', () {
    final receipt = InteractionReceipt.fromJson({
      'interaction_id': 'i1',
      'bot_name': 'Helper',
      'by_callback': true,
    });
    expect(receipt.interactionId, 'i1');
    expect(receipt.byCallback, isTrue);
    expect(
      InteractionStatus.fromJson({
        'status': 'answered',
        'response_kind': 'ack',
      }).state,
      InteractionState.answered,
    );
    expect(
      InteractionStatus.fromJson({'status': 'expired'}).state,
      InteractionState.expired,
    );
    expect(
      InteractionStatus.fromJson({'status': 'anything'}).state,
      InteractionState.pending,
    );
    final reply = EphemeralReply.maybeFromJson({
      'id': 'e1',
      'message_id': 'm1',
      'bot_name': 'Helper',
      'body': 'Psst',
      'components': [
        [
          {'type': 'button', 'id': 'go', 'label': 'Go'},
        ],
      ],
      'created_at': '2026-10-28T10:00:00Z',
    });
    expect(reply?.components?.rows.length, 1);
    expect(EphemeralReply.maybeFromJson({'id': 'x'}), isNull);
    expect(EphemeralReply.maybeFromJson('nope'), isNull);
  });

  testWidgets('a manager sets the address and sees the secret once', (
    tester,
  ) async {
    final rpc = await _openCallback(
      tester,
      responses: {
        'get_bot_callback': (_) => {'url': null, 'enabled': false},
        'set_bot_callback': (_) => {
          'url': 'https://example.com/hook',
          'enabled': true,
          'secret': _secret,
        },
      },
    );
    expect(find.text('Callback address'), findsWidgets);
    expect(find.byKey(const ValueKey('bot-callback-clear')), findsNothing);

    await tester.tap(find.byKey(const ValueKey('bot-callback-save')));
    await tester.pumpAndSettle();
    expect(find.text('The address must start with https://'), findsOneWidget);

    await tester.enterText(
      find.byKey(const ValueKey('bot-callback-field')),
      'http://example.com/hook',
    );
    await tester.tap(find.byKey(const ValueKey('bot-callback-save')));
    await tester.pumpAndSettle();
    expect(rpc.calls.where((c) => c.$1 == 'set_bot_callback'), isEmpty);

    await tester.enterText(
      find.byKey(const ValueKey('bot-callback-field')),
      'https://example.com/hook',
    );
    await tester.tap(find.byKey(const ValueKey('bot-callback-save')));
    await tester.pumpAndSettle();
    final set = rpc.calls.firstWhere((c) => c.$1 == 'set_bot_callback');
    expect(set.$2['callback_url'], 'https://example.com/hook');
    expect(find.text('Callback secret'), findsOneWidget);
    expect(find.text(_secret), findsOneWidget);
    await tester.tap(find.text('Done'));
    await tester.pumpAndSettle();
    expect(find.text(_secret), findsNothing);
  });

  testWidgets('the server refusing an address is explained', (tester) async {
    await _openCallback(
      tester,
      responses: {
        'get_bot_callback': (_) => {'url': null, 'enabled': false},
        'set_bot_callback': (_) => throw const PostgrestException(
          message: 'The address must be a website name',
          code: '22023',
        ),
      },
    );
    await tester.enterText(
      find.byKey(const ValueKey('bot-callback-field')),
      'https://127.0.0.1/hook',
    );
    await tester.tap(find.byKey(const ValueKey('bot-callback-save')));
    await tester.pumpAndSettle();
    expect(find.textContaining('cannot be used'), findsOneWidget);
    // The dialog stays so the address can be fixed.
    expect(find.byKey(const ValueKey('bot-callback-field')), findsOneWidget);
  });

  testWidgets(
    'a set callback shows how it is doing and can be reset or removed',
    (tester) async {
      final rpc = await _openCallback(
        tester,
        responses: {
          'get_bot_callback': (_) => {
            'url': 'https://example.com/hook',
            'enabled': false,
            'consecutive_failures': 20,
            'last_error': 'timeout',
          },
          'rotate_bot_callback_secret': (_) => {
            'url': 'https://example.com/hook',
            'enabled': false,
            'secret': 'f' * 64,
          },
          'clear_bot_callback': (_) => null,
        },
      );
      expect(find.textContaining('Paused'), findsOneWidget);
      expect(find.text('https://example.com/hook'), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('bot-callback-rotate')));
      await tester.pumpAndSettle();
      expect(find.text('New callback secret'), findsOneWidget);
      expect(find.text('f' * 64), findsOneWidget);
      await tester.tap(find.text('Done'));
      await tester.pumpAndSettle();
      expect(
        rpc.calls.map((c) => c.$1),
        contains('rotate_bot_callback_secret'),
      );

      await tester.tap(find.byKey(const ValueKey('circle-bot-menu-bot-1')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Callback address'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('bot-callback-clear')));
      await tester.pumpAndSettle();
      expect(rpc.calls.map((c) => c.$1), contains('clear_bot_callback'));
      expect(find.byKey(const ValueKey('bot-callback-field')), findsNothing);
    },
  );

  testWidgets('an answer to a press says who pressed what', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: InteractionOrigin(
            interaction: MessageInteraction(
              command: '',
              componentLabel: 'Approve',
              userName: 'Ann',
            ),
            foregroundColor: Colors.black,
          ),
        ),
      ),
    );
    expect(find.text('Ann pressed Approve'), findsOneWidget);
  });
}
