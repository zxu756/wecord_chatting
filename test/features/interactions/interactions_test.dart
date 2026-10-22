import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wecord/features/chats/chats_screen.dart';
import 'package:wecord/features/chats/thread/registry/bubble_footer_registrations.dart';
import 'package:wecord/features/interactions/interactions_repository.dart';
import 'package:wecord/shared/models/conversation.dart';
import 'package:wecord/shared/models/message.dart';
import 'package:wecord/shared/models/message_components.dart';
import 'package:wecord/shared/models/message_origin.dart';

import '../../mobile/phone_test_support.dart';
import 'interactions_fakes.dart';

Future<FakeInteractionsRepository> _open(
  WidgetTester tester,
  PhoneWorld world, {
  Object? components,
  List<EphemeralReply> ephemeral = const [],
  List<InteractionStatus>? statuses,
  Duration limit = const Duration(seconds: 3),
  bool recalled = false,
}) async {
  final fake = FakeInteractionsRepository()..ephemeral = [...ephemeral];
  if (statuses != null) {
    fake.statuses = statuses;
  }
  world.chats.messages = [
    phoneMessage('m0', bart, 'Morning!', minutesAgo: 60),
    botMessage(
      'bm1',
      components: components ?? sampleComponentsJson(),
    ).copyWith(recalledAt: recalled ? DateTime.utc(2026, 10, 28) : null),
  ];
  world.extraOverrides = [
    interactionsRepositoryProvider.overrideWithValue(fake),
    interactionWaitProvider.overrideWithValue((
      limit: limit,
      every: const Duration(seconds: 1),
    )),
  ];
  await world.open(
    tester,
    '${ChatsScreen.path}/dm-1',
    extra: ChatThreadRouteExtra(
      title: bart.displayName,
      type: ConversationType.direct,
    ),
  );
  return fake;
}

void main() {
  group('reading components', () {
    test('a server row becomes rows of buttons, links and lists', () {
      final components = MessageComponents.maybeFromJson(
        sampleComponentsJson(),
      )!;
      expect(components.rows.length, 3);
      final first = components.rows[0];
      expect(first[0], isA<ButtonComponent>());
      expect((first[0] as ButtonComponent).style, ComponentButtonStyle.primary);
      expect((first[1] as ButtonComponent).style, ComponentButtonStyle.danger);
      expect((first[2] as LinkComponent).uri.host, 'example.com');
      final select = components.rows[1].single as SelectComponent;
      expect(select.options.map((o) => o.value), ['ridge', 'lake', 'forest']);
      expect(select.options.first.description, 'Hard');
      expect(select.multiple, isFalse);
      final form = (components.rows[2].single as ButtonComponent).modal!;
      expect(form.title, 'Your note');
      expect(form.fields.map((f) => f.id), ['text', 'name']);
      expect(form.fields.first.paragraph, isTrue);
      expect(form.fields.first.maxLength, 50);
      expect(form.fields.last.required, isFalse);
    });

    test('nothing is drawn for no components or the wrong shape', () {
      expect(MessageComponents.maybeFromJson(null), isNull);
      expect(MessageComponents.maybeFromJson(<Object?>[]), isNull);
      expect(MessageComponents.maybeFromJson('x'), isNull);
      expect(MessageComponents.maybeFromJson({'rows': []}), isNull);
      expect(MessageComponents.maybeFromJson([<Object?>[]]), isNull);
      expect(MessageComponents.maybeFromJson(['x', 5, null]), isNull);
    });

    test(
      'links to scripts, plain http, addresses and inner names are dropped',
      () {
        for (final url in [
          'javascript:alert(1)',
          'JavaScript:alert(1)',
          'data:text/html,hi',
          'http://example.com/',
          'ftp://example.com/',
          'file:///etc/passwd',
          'https://127.0.0.1/',
          'https://10.0.0.5/admin',
          'https://169.254.169.254/latest',
          'https://localhost/',
          'https://[::1]/',
          'https://example.com:8443/',
          'https://user:pw@example.com/',
          'https://paypal.com@evil.example/',
          'https://printer.local/',
          'https://intranet.internal/',
          'https://example.com/a b',
          'https://example.com/"onmouseover=x',
          'https://example.com\\@evil.example/',
          'https://example',
          'https://0x7f.1/',
          'https://2130706433/',
          '',
          ' https://example.com/',
        ]) {
          expect(safeComponentUri(url), isNull, reason: url);
        }
        for (final url in [
          'https://example.com',
          'https://sub.example.co.uk:443/a/b?c=d#e',
          'https://Example.COM/x',
        ]) {
          expect(safeComponentUri(url), isNotNull, reason: url);
        }
        final parsed = MessageComponents.maybeFromJson([
          [
            {'type': 'link', 'label': 'Bad', 'url': 'javascript:alert(1)'},
            {'type': 'link', 'label': 'Good', 'url': 'https://example.com/ok'},
          ],
        ])!;
        expect(parsed.rows.single.length, 1);
        expect((parsed.rows.single.single as LinkComponent).label, 'Good');
      },
    );

    test('limits hold even when the server does not keep them', () {
      final rows = [
        for (var r = 0; r < 8; r++)
          [
            for (var i = 0; i < 8; i++)
              {'type': 'button', 'id': 'b$r$i', 'label': 'B'},
          ],
      ];
      final components = MessageComponents.maybeFromJson(rows)!;
      expect(components.rows.length, ComponentLimits.maxRows);
      expect(
        components.rows.every((row) => row.length == ComponentLimits.maxPerRow),
        isTrue,
      );
      // A label that is too long is not drawn.
      expect(
        MessageComponents.maybeFromJson([
          [
            {'type': 'button', 'id': 'a', 'label': 'x' * 41},
          ],
        ]),
        isNull,
      );
      // 26 options keep 25; a list shares no row.
      final big = MessageComponents.maybeFromJson([
        [
          {
            'type': 'select',
            'id': 's',
            'options': [
              for (var i = 0; i < 26; i++) {'label': 'o$i', 'value': 'v$i'},
            ],
          },
          {'type': 'button', 'id': 'b', 'label': 'B'},
        ],
      ])!;
      expect(big.rows.single.single, isA<SelectComponent>());
      expect(
        (big.rows.single.single as SelectComponent).options.length,
        ComponentLimits.maxOptions,
      );
    });

    test('text is cleaned of controls and direction tricks', () {
      final components = MessageComponents.maybeFromJson([
        [
          {'type': 'button', 'id': 'a', 'label': ' Go\u202e now\u200b '},
          {'type': 'button', 'id': 'a b', 'label': 'bad id'},
          {'type': 'button', 'id': 'dup', 'label': 'One'},
        ],
      ])!;
      expect((components.rows.single.first as ButtonComponent).label, 'Go now');
      // An id with a space is not an id the server would accept.
      expect(components.rows.single.length, 2);
      expect(cleanComponentText('  hi  ', max: 5), 'hi');
      expect(cleanComponentText('a\nb', max: 5), 'ab');
      expect(cleanComponentText('abcdef', max: 5), isNull);
      expect(cleanComponentText(5, max: 5), isNull);
      expect(cleanComponentText('', max: 5), isNull);
      expect(cleanComponentText('', max: 5, allowEmpty: true), '');
    });

    test('a list keeps min and max within its options', () {
      final select =
          MessageComponents.maybeFromJson([
                [
                  {
                    'type': 'select',
                    'id': 's',
                    'options': [
                      {'label': 'A', 'value': 'a', 'default': true},
                      {'label': 'B', 'value': 'b'},
                    ],
                    'min_values': 5,
                    'max_values': 9,
                  },
                ],
              ])!.rows.single.single
              as SelectComponent;
      expect(select.maxValues, 2);
      expect(select.minValues, 2);
      expect(select.multiple, isTrue);
      expect(select.defaults, ['a']);
    });

    test('messages carry components and keep them when copied', () {
      final message = ChatMessage.fromJson({
        'id': 'm1',
        'conversation_id': 'c1',
        'sender_id': 'bot-user',
        'type': 'text',
        'body': 'Pick one',
        'created_at': '2026-10-28T10:00:00Z',
        'components': sampleComponentsJson(),
      });
      expect(message.components?.rows.length, 3);
      expect(message.copyWith(body: 'x').components?.rows.length, 3);
      expect(message.copyWith(components: null).components, isNull);
      expect(
        ChatMessage.fromJson({
          'id': 'm2',
          'conversation_id': 'c1',
          'sender_id': 'u',
          'type': 'text',
          'body': 'hi',
          'created_at': '2026-10-28T10:00:00Z',
        }).components,
        isNull,
      );
    });

    test('an answer to a press names the button', () {
      final interaction = MessageInteraction.maybeFromJson({
        'interaction_id': 'i1',
        'command': '',
        'component_label': 'Approve',
        'user_id': 'u1',
        'user_name': 'Ann',
      });
      expect(interaction?.componentLabel, 'Approve');
      expect(interaction?.command, '');
      expect(MessageInteraction.maybeFromJson({'command': ''}), isNull);
      expect(
        MessageInteraction.maybeFromJson({'command': 'ping'})?.componentLabel,
        isNull,
      );
    });
  });

  group('in the chat', () {
    testWidgets('a bot message shows its buttons, link and list', (
      tester,
    ) async {
      final world = PhoneWorld();
      await _open(tester, world);
      expect(find.text('Pick one'), findsOneWidget);
      expect(find.byKey(const ValueKey('component-approve')), findsOneWidget);
      expect(find.text('Approve'), findsOneWidget);
      expect(find.text('Reject'), findsOneWidget);
      expect(find.text('Docs'), findsOneWidget);
      expect(find.text('Pick a trail'), findsOneWidget);
      expect(find.text('Add a note'), findsOneWidget);
      // Ordinary messages have none.
      expect(find.byKey(const ValueKey('message-components')), findsOneWidget);
      await world.close(tester);
    });

    test('the registry draws them inside the bubble', () {
      expect(
        bubbleFooterExtensions.map((entry) => entry.id),
        containsAll(['bot-components', 'bot-private-replies']),
      );
    });

    testWidgets('texts are plain text: markup in a label stays markup', (
      tester,
    ) async {
      final world = PhoneWorld();
      await _open(
        tester,
        world,
        components: [
          [
            {'type': 'button', 'id': 'a', 'label': '**bold** <b>x</b> :smile:'},
            {
              'type': 'button',
              'id': 'b',
              'label': '[link](https://evil.example)',
            },
          ],
        ],
      );
      expect(find.text('**bold** <b>x</b> :smile:'), findsOneWidget);
      expect(find.text('[link](https://evil.example)'), findsOneWidget);
      await world.close(tester);
    });

    testWidgets('a button sends the press and waits for the bot', (
      tester,
    ) async {
      final world = PhoneWorld();
      final fake = await _open(tester, world);
      await tester.tap(find.byKey(const ValueKey('component-approve')));
      await settle(tester);
      expect(fake.presses.single.messageId, 'bm1');
      expect(fake.presses.single.componentId, 'approve');
      expect(fake.presses.single.values, isNull);
      expect(find.byKey(const ValueKey('component-status')), findsOneWidget);
      expect(find.textContaining('Sent to Helper'), findsOneWidget);
      await tester.pump(const Duration(seconds: 5));
      await world.close(tester);
    });

    testWidgets('the note goes when the bot has answered', (tester) async {
      final world = PhoneWorld();
      final fake = await _open(
        tester,
        world,
        statuses: const [
          InteractionStatus(InteractionState.pending),
          InteractionStatus(InteractionState.answered, responseKind: 'message'),
        ],
      );
      await tester.tap(find.byKey(const ValueKey('component-approve')));
      await tester.pump();
      await tester.pump();
      expect(find.byKey(const ValueKey('component-status')), findsOneWidget);
      await tester.pump(const Duration(seconds: 1));
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      await tester.pump();
      expect(fake.statusCalls, 2);
      expect(find.byKey(const ValueKey('component-status')), findsNothing);
      await world.close(tester);
    });

    testWidgets('an ack says it is done', (tester) async {
      final world = PhoneWorld();
      await _open(
        tester,
        world,
        statuses: const [
          InteractionStatus(InteractionState.answered, responseKind: 'ack'),
        ],
      );
      await tester.tap(find.byKey(const ValueKey('component-approve')));
      await tester.pump();
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      await tester.pump();
      expect(find.text('Done.'), findsOneWidget);
      await world.close(tester);
    });

    testWidgets('a bot that does not answer is called out after a while', (
      tester,
    ) async {
      final world = PhoneWorld();
      await _open(tester, world, limit: const Duration(seconds: 3));
      await tester.tap(find.byKey(const ValueKey('component-approve')));
      await tester.pump();
      await tester.pump();
      for (var i = 0; i < 4; i++) {
        await tester.pump(const Duration(seconds: 1));
        await tester.pump();
      }
      expect(find.text('Helper did not answer.'), findsOneWidget);
      await world.close(tester);
    });

    testWidgets('a press the server refuses says why', (tester) async {
      final world = PhoneWorld();
      final fake = await _open(tester, world);
      for (final (failure, text) in [
        (InteractionFailure.tooFast, 'Too fast. Wait a moment and try again.'),
        (InteractionFailure.notAllowed, 'You cannot use this bot.'),
        (InteractionFailure.gone, 'This message is no longer available.'),
        (InteractionFailure.invalid, 'That answer is not valid. Check it.'),
        (InteractionFailure.other, 'Could not reach the bot. Try again.'),
      ]) {
        fake.failWith = InteractionException(failure);
        await tester.tap(find.byKey(const ValueKey('component-reject')));
        await settle(tester);
        expect(find.text(text), findsOneWidget, reason: '$failure');
      }
      expect(fake.presses, isEmpty);
      await world.close(tester);
    });

    testWidgets('a disabled button does nothing', (tester) async {
      final world = PhoneWorld();
      final fake = await _open(
        tester,
        world,
        components: [
          [
            {'type': 'button', 'id': 'off', 'label': 'Off', 'disabled': true},
          ],
        ],
      );
      await tester.tap(find.byKey(const ValueKey('component-off')));
      await settle(tester);
      expect(fake.presses, isEmpty);
      await world.close(tester);
    });

    testWidgets('a single list sends the choice at once', (tester) async {
      final world = PhoneWorld();
      final fake = await _open(tester, world);
      await tester.tap(find.byKey(const ValueKey('component-pick')));
      await settle(tester);
      expect(find.text('Ridge'), findsOneWidget);
      expect(find.text('Hard'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('component-option-lake')));
      await settle(tester);
      expect(fake.presses.single.componentId, 'pick');
      expect(fake.presses.single.values, ['lake']);
      await tester.pump(const Duration(seconds: 5));
      await world.close(tester);
    });

    testWidgets('a multiple list sends when enough is chosen', (tester) async {
      final world = PhoneWorld();
      final fake = await _open(
        tester,
        world,
        components: [
          [
            {
              'type': 'select',
              'id': 'many',
              'placeholder': 'Pick two or three',
              'options': [
                {'label': 'A', 'value': 'a'},
                {'label': 'B', 'value': 'b'},
                {'label': 'C', 'value': 'c'},
                {'label': 'D', 'value': 'd'},
              ],
              'min_values': 2,
              'max_values': 3,
            },
          ],
        ],
      );
      await tester.tap(find.byKey(const ValueKey('component-many')));
      await settle(tester);
      Finder send() => find.byKey(const ValueKey('component-options-send'));
      await tester.tap(find.byKey(const ValueKey('component-option-a')));
      await settle(tester);
      await tester.tap(send());
      await settle(tester);
      expect(fake.presses, isEmpty, reason: 'one is not enough');
      await tester.tap(find.byKey(const ValueKey('component-option-b')));
      await tester.tap(find.byKey(const ValueKey('component-option-c')));
      await tester.tap(find.byKey(const ValueKey('component-option-d')));
      await settle(tester);
      await tester.tap(send());
      await settle(tester);
      expect(fake.presses.single.values, ['a', 'b', 'c']);
      await tester.pump(const Duration(seconds: 5));
      await world.close(tester);
    });

    testWidgets('a button with a form asks first', (tester) async {
      final world = PhoneWorld();
      final fake = await _open(tester, world);
      await tester.tap(find.byKey(const ValueKey('component-note')));
      await settle(tester);
      expect(find.text('Your note'), findsOneWidget);
      expect(
        find.text('This goes to the bot, which can read it.'),
        findsOneWidget,
      );
      // The required field cannot be left empty.
      await tester.tap(find.byKey(const ValueKey('component-form-send')));
      await settle(tester);
      expect(find.text('This field is required.'), findsOneWidget);
      expect(fake.presses, isEmpty);
      await tester.enterText(
        find.byKey(const ValueKey('component-field-text')),
        '  hello bot  ',
      );
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('component-form-send')));
      await settle(tester);
      expect(fake.presses.single.componentId, 'note');
      expect(fake.presses.single.values, {'text': 'hello bot', 'name': ''});
      await tester.pump(const Duration(seconds: 5));
      await world.close(tester);
    });

    testWidgets('a link asks before it opens and shows where it goes', (
      tester,
    ) async {
      final world = PhoneWorld();
      await _open(tester, world);
      await tester.tap(find.text('Docs'));
      await settle(tester);
      expect(find.text('Open this link?'), findsOneWidget);
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('component-link-target')),
          matching: find.text('example.com'),
        ),
        findsOneWidget,
      );
      expect(find.text('https://example.com/docs'), findsOneWidget);
      await tester.tap(find.text('Cancel'));
      await settle(tester);
      expect(world.openedLinks, isEmpty);
      await tester.tap(find.text('Docs'));
      await settle(tester);
      await tester.tap(find.byKey(const ValueKey('component-link-open')));
      await settle(tester);
      expect(world.openedLinks.single.toString(), 'https://example.com/docs');
      await world.close(tester);
    });

    testWidgets('a deleted message shows no buttons', (tester) async {
      final world = PhoneWorld();
      await _open(tester, world, recalled: true);
      expect(find.byKey(const ValueKey('message-components')), findsNothing);
      expect(find.text('Approve'), findsNothing);
      await world.close(tester);
    });

    testWidgets('private replies show under the message, only for it', (
      tester,
    ) async {
      final world = PhoneWorld();
      final fake = await _open(
        tester,
        world,
        ephemeral: [
          EphemeralReply(
            id: 'e1',
            messageId: 'bm1',
            botName: 'Helper',
            body: 'Only for **you**',
            createdAt: DateTime.utc(2026, 10, 28, 10),
            components: MessageComponents.maybeFromJson([
              [
                {'type': 'button', 'id': 'secret', 'label': 'Secret action'},
              ],
            ]),
          ),
          EphemeralReply(
            id: 'e2',
            messageId: 'someone-else',
            botName: 'Helper',
            body: 'About another message',
            createdAt: DateTime.utc(2026, 10, 28, 10, 1),
          ),
        ],
      );
      expect(find.text('Only you can see this'), findsOneWidget);
      expect(find.byKey(const ValueKey('private-reply-e1')), findsOneWidget);
      expect(find.byKey(const ValueKey('private-reply-e2')), findsNothing);
      expect(find.text('Secret action'), findsOneWidget);
      // A press on its button goes to the private reply, not the message.
      await tester.tap(find.byKey(const ValueKey('component-secret')));
      await settle(tester);
      expect(fake.presses.single.messageId, 'e1');
      await tester.pump(const Duration(seconds: 5));
      // Dismissing removes it.
      await tester.tap(find.byKey(const ValueKey('private-reply-dismiss-e1')));
      await settle(tester);
      expect(fake.dismissed, ['e1']);
      expect(find.byKey(const ValueKey('private-reply-e1')), findsNothing);
      await world.close(tester);
    });

    testWidgets('a new private reply appears when the server says so', (
      tester,
    ) async {
      final world = PhoneWorld();
      final fake = await _open(tester, world);
      expect(find.byKey(const ValueKey('private-reply-e9')), findsNothing);
      fake.ephemeral = [
        EphemeralReply(
          id: 'e9',
          messageId: 'bm1',
          botName: 'Helper',
          body: 'Psst',
          createdAt: DateTime.utc(2026, 10, 28, 10),
        ),
      ];
      fake.changed();
      await settle(tester);
      expect(find.byKey(const ValueKey('private-reply-e9')), findsOneWidget);
      expect(find.text('Psst'), findsOneWidget);
      await world.close(tester);
    });
  });
}
