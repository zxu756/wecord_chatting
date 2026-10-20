import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:wecord/features/chats/chat_thread_screen.dart'
    show chatConversationSummaryProvider;
import 'package:wecord/features/contacts/contacts_screen.dart'
    show friendsProvider;
import 'package:wecord/features/safety/scam_hint.dart';
import 'package:wecord/features/safety/scam_rules.dart';
import 'package:wecord/shared/l10n/l10n.dart';
import 'package:wecord/shared/models/conversation.dart';
import 'package:wecord/shared/models/message.dart';
import 'package:wecord/shared/models/profile.dart';
import 'package:wecord/shared/theme/wecord_theme.dart';

Profile person(String id) => Profile(
  id: id,
  username: 'user_$id',
  displayName: 'Person $id',
  bio: '',
  createdAt: DateTime.utc(2026),
  updatedAt: DateTime.utc(2026),
);

ChatMessage message(
  String body, {
  String sender = 'stranger',
  MessageType type = MessageType.text,
  MessageReviewState? reviewState,
  String? webhookId,
  DateTime? recalledAt,
}) => ChatMessage(
  id: 'message-1',
  conversationId: 'conversation-1',
  senderId: sender,
  type: type,
  body: body,
  createdAt: DateTime.utc(2026, 10, 20, 4),
  reviewState: reviewState,
  webhookId: webhookId,
  recalledAt: recalledAt,
  sender: person(sender),
);

ConversationSummary summary(ConversationType type, {bool noteToSelf = false}) =>
    ConversationSummary(
      id: 'conversation-1',
      type: type,
      unreadCount: 0,
      circleId: type == ConversationType.channel ? 'circle-1' : null,
      isNoteToSelf: noteToSelf,
    );

Widget app(
  ChatMessage message, {
  ConversationType type = ConversationType.group,
  List<Profile> friends = const [],
  Set<String> dismissed = const {},
  bool noteToSelf = false,
  bool friendsFail = false,
  ThemeData? theme,
  List<Override> overrides = const [],
}) {
  final signal = detectScamSignal(message.body) ?? ScamSignal.payment;
  return ProviderScope(
    overrides: [
      scamHintStoreProvider.overrideWithValue(InMemoryScamHintStore(dismissed)),
      friendsProvider.overrideWith(
        (ref) => friendsFail
            ? Future<List<Profile>>.error(Exception('offline'))
            : Future.value(friends),
      ),
      chatConversationSummaryProvider.overrideWith(
        (ref, id) async => summary(type, noteToSelf: noteToSelf),
      ),
      ...overrides,
    ],
    child: MaterialApp(
      theme: theme ?? WeCordTheme.light(),
      home: Scaffold(
        body: Center(
          child: ScamHintStrip(message: message, signal: signal),
        ),
      ),
    ),
  );
}

void main() {
  group('the rules', () {
    test('notice asking for money', () {
      for (final text in [
        '加我微信，先转账 500 手续费',
        '请把保证金打款到这个账户',
        'Please send me the money by Western Union',
        'Venmo me 20 for the ticket',
        'Pay the processing fee first',
      ]) {
        expect(detectScamSignal(text), ScamSignal.payment, reason: text);
      }
    });

    test('notice asking for a verification code', () {
      for (final text in [
        '把验证码发给我',
        '请告诉我你收到的短信验证码',
        'Send me the verification code you just got',
        'what is your one-time code? read it to me',
      ]) {
        expect(detectScamSignal(text), ScamSignal.code, reason: text);
      }
    });

    test('notice prizes, easy returns, gift cards and fake support', () {
      expect(detectScamSignal('恭喜你中奖了，点击领取'), ScamSignal.prize);
      expect(
        detectScamSignal('You have won a free giveaway!'),
        ScamSignal.prize,
      );
      expect(detectScamSignal('跟着老师带单，稳赚不赔'), ScamSignal.investment);
      expect(
        detectScamSignal('Guaranteed returns, no risk'),
        ScamSignal.investment,
      );
      expect(detectScamSignal('买两张 Steam gift card 发我'), ScamSignal.giftCard);
      expect(detectScamSignal('您的账号异常，官方客服联系您'), ScamSignal.impersonation);
      expect(
        detectScamSignal('Your account has been suspended'),
        ScamSignal.impersonation,
      );
    });

    test('money outranks the rest', () {
      expect(
        detectScamSignal('You won! Send me the money to claim'),
        ScamSignal.payment,
      );
    });

    test('an ordinary link is not a signal, a suspicious one is', () {
      expect(detectScamSignal('docs here https://github.com/flutter'), isNull);
      expect(detectScamSignal('see example.com/page'), isNull);
      expect(
        detectScamSignal('look https://paypal-login.com/verify'),
        ScamSignal.link,
      );
      expect(detectScamSignal('go to http://203.0.113.9/'), ScamSignal.link);
      expect(
        detectScamSignal('short https://bit.ly/abc, ok?'),
        ScamSignal.link,
      );
    });

    test('ordinary talk is not a signal', () {
      for (final text in [
        '',
        '   ',
        'lunch at noon?',
        '今天晚上一起吃饭吗',
        'the code is on GitHub, check the repo',
        'I sent you the files',
      ]) {
        expect(detectScamSignal(text), isNull, reason: text);
      }
    });

    test('only text from someone else, not held, bot or deleted', () {
      final text = message('把验证码发给我');
      expect(scamSignalFor(text, isOwn: false), ScamSignal.code);
      expect(scamSignalFor(text, isOwn: true), isNull);
      expect(
        scamSignalFor(
          message('把验证码发给我', reviewState: MessageReviewState.checking),
          isOwn: false,
        ),
        isNull,
      );
      expect(
        scamSignalFor(message('把验证码发给我', webhookId: 'hook'), isOwn: false),
        isNull,
      );
      expect(
        scamSignalFor(
          message('把验证码发给我', recalledAt: DateTime.utc(2026)),
          isOwn: false,
        ),
        isNull,
      );
      expect(
        scamSignalFor(
          message('把验证码发给我', type: MessageType.image),
          isOwn: false,
        ),
        isNull,
      );
    });
  });

  group('the strip', () {
    testWidgets('warns about a stranger in a group', (tester) async {
      await tester.pumpWidget(app(message('把验证码发给我')));
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey('scam-hint')), findsOneWidget);
      expect(
        find.text("Watch out for scams: they aren't your friend"),
        findsOneWidget,
      );
      expect(
        find.text("They're asking for a verification code. Never share one."),
        findsOneWidget,
      );
    });

    testWidgets('warns in a circle channel too', (tester) async {
      await tester.pumpWidget(
        app(message('Send me the money'), type: ConversationType.channel),
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('scam-hint')), findsOneWidget);
    });

    testWidgets('says nothing about a friend', (tester) async {
      await tester.pumpWidget(
        app(message('Send me the money'), friends: [person('stranger')]),
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('scam-hint')), findsNothing);
    });

    testWidgets('says nothing in a direct chat or the file helper', (
      tester,
    ) async {
      await tester.pumpWidget(
        app(message('Send me the money'), type: ConversationType.direct),
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('scam-hint')), findsNothing);

      await tester.pumpWidget(
        app(message('Send me the money'), noteToSelf: true),
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('scam-hint')), findsNothing);
    });

    testWidgets('says nothing until it knows who the friends are', (
      tester,
    ) async {
      await tester.pumpWidget(
        app(message('Send me the money'), friendsFail: true),
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('scam-hint')), findsNothing);
    });

    testWidgets('hiding it hides it for that person, and is remembered', (
      tester,
    ) async {
      await tester.pumpWidget(app(message('Send me the money')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('scam-hint-dismiss')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('scam-hint')), findsNothing);

      final container = ProviderScope.containerOf(
        tester.element(find.byType(Scaffold)),
      );
      expect(container.read(scamHintDismissedProvider), {'stranger'});
      expect(await container.read(scamHintStoreProvider).load(), {'stranger'});
    });

    testWidgets('a person hidden before stays hidden', (tester) async {
      await tester.pumpWidget(
        app(message('Send me the money'), dismissed: {'stranger'}),
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('scam-hint')), findsNothing);
    });

    testWidgets('a different stranger is still warned about', (tester) async {
      await tester.pumpWidget(
        app(
          message('Send me the money', sender: 'other'),
          dismissed: {'stranger'},
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('scam-hint')), findsOneWidget);
    });

    testWidgets('offers to report the message', (tester) async {
      await tester.pumpWidget(app(message('Send me the money')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('scam-hint-report')));
      await tester.pumpAndSettle();
      expect(find.text('Report message'), findsOneWidget);
    });

    testWidgets('reads in Chinese, in dark mode too', (tester) async {
      AppStrings.isChinese = true;
      addTearDown(() => AppStrings.isChinese = false);
      await tester.pumpWidget(
        app(message('Send me the money'), theme: WeCordTheme.dark()),
      );
      await tester.pumpAndSettle();
      expect(find.text('谨防诈骗：对方不是你的好友'), findsOneWidget);
      expect(find.text('举报这条消息'), findsOneWidget);
    });

    test('remembers at most a couple of hundred people', () {
      final container = ProviderContainer(
        overrides: [
          scamHintStoreProvider.overrideWithValue(InMemoryScamHintStore()),
        ],
      );
      addTearDown(container.dispose);
      final notifier = container.read(scamHintDismissedProvider.notifier);
      for (var i = 0; i < maxDismissedSenders + 5; i++) {
        notifier.dismiss('user-$i');
      }
      final kept = container.read(scamHintDismissedProvider);
      expect(kept.length, maxDismissedSenders);
      expect(kept.contains('user-0'), isFalse);
      expect(kept.contains('user-${maxDismissedSenders + 4}'), isTrue);
    });
  });
}
