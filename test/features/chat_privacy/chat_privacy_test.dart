import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wecord/features/ai/ai_repository.dart';
import 'package:wecord/features/chat_privacy/chat_privacy_notice.dart';
import 'package:wecord/features/chat_privacy/chat_privacy_repository.dart';
import 'package:wecord/features/chat_privacy/chat_privacy_ui.dart';
import 'package:wecord/features/chats/chats_screen.dart';
import 'package:wecord/features/chats/system_notice_text.dart';
import 'package:wecord/features/screen_capture/screen_capture_service.dart';
import 'package:wecord/features/screen_capture/screen_capture_status.dart';
import 'package:wecord/features/screen_capture/view_once_screenshots.dart';
import 'package:wecord/shared/l10n/l10n.dart';
import 'package:wecord/shared/models/conversation.dart';
import 'package:wecord/shared/models/message.dart';

import '../../mobile/phone_test_support.dart';
import 'chat_privacy_fakes.dart';

const _desktop = PhoneViewport(
  name: 'desktop',
  size: Size(1440, 900),
  devicePixelRatio: 1,
);

ChatMessage _system(String id, Map<String, dynamic> attachment, int minute) {
  return ChatMessage(
    id: id,
    conversationId: 'dm-1',
    senderId: 'user-2',
    type: MessageType.system,
    body: '',
    createdAt: DateTime.utc(2026, 10, 28, 9, minute),
    attachment: attachment,
  );
}

void main() {
  tearDown(() => AppStrings.isChinese = false);

  group('the setting', () {
    test('open until the server says otherwise', () {
      expect(ChatPrivacy.open.restricted, isFalse);
      expect(ChatPrivacy.open.requestedByUser('user-1'), isFalse);
    });

    test('knows who asked, and when only the other person did', () {
      const mine = ChatPrivacy(restricted: true, requestedBy: {'user-1'});
      const theirs = ChatPrivacy(restricted: true, requestedBy: {'user-2'});
      expect(mine.requestedByUser('user-1'), isTrue);
      expect(mine.onlyOthersAsked('user-1'), isFalse);
      expect(theirs.onlyOthersAsked('user-1'), isTrue);
      expect(ChatPrivacy.open.onlyOthersAsked('user-1'), isFalse);
      expect(mine.requestedByUser(null), isFalse);
    });

    test('compares by what it holds', () {
      expect(
        const ChatPrivacy(restricted: true, requestedBy: {'a'}),
        const ChatPrivacy(restricted: true, requestedBy: {'a'}),
      );
      expect(
        const ChatPrivacy(restricted: true, requestedBy: {'a'}),
        isNot(const ChatPrivacy(restricted: true, requestedBy: {'b'})),
      );
    });

    test('is read through the provider', () async {
      final repository = FakeChatPrivacyRepository(
        chats: {
          'c1': const ChatPrivacy(restricted: true, requestedBy: {'user-2'}),
        },
      );
      final container = ProviderContainer(
        overrides: [
          chatPrivacyRepositoryProvider.overrideWithValue(repository),
        ],
      );
      addTearDown(container.dispose);
      container.listen(restrictSharingProvider('c1'), (_, _) {});
      container.listen(restrictSharingProvider('other'), (_, _) {});
      await container.read(chatPrivacyProvider('c1').future);
      await container.read(chatPrivacyProvider('other').future);
      expect(container.read(restrictSharingProvider('c1')), isTrue);
      expect(container.read(restrictSharingProvider('other')), isFalse);
    });
  });

  group('the chat lines', () {
    test('read as the server wrote them, in the reader\'s language', () {
      final on = ChatNotice.maybeFromAttachment({
        'kind': 'chat_privacy',
        'enabled': true,
        'actor_name': 'Ada',
      })!;
      expect(on.text, 'Ada turned on advanced chat privacy');
      final off = ChatNotice.maybeFromAttachment({
        'kind': 'chat_privacy',
        'enabled': false,
        'actor_name': 'Ada',
      })!;
      expect(off.text, 'Ada turned off advanced chat privacy');
      final shot = ChatNotice.maybeFromAttachment({
        'kind': 'screenshot',
        'event': 'screenshot',
        'media': 'photo',
        'actor_name': 'Bob',
      })!;
      expect(shot.text, 'Bob took a screenshot of a view-once photo');
      final video = ChatNotice.maybeFromAttachment({
        'kind': 'screenshot',
        'event': 'screenshot',
        'media': 'video',
        'actor_name': 'Bob',
      })!;
      expect(video.text, 'Bob took a screenshot of a view-once video');
      final recording = ChatNotice.maybeFromAttachment({
        'kind': 'screenshot',
        'event': 'recording',
        'media': 'photo',
        'actor_name': 'Bob',
      })!;
      expect(
        recording.text,
        'Bob was recording the screen while a view-once photo was open',
      );
      AppStrings.isChinese = true;
      expect(on.text, 'Ada 开启了高级聊天隐私');
      expect(shot.text, 'Bob 对阅后即焚的照片截了屏');
      expect(recording.text, 'Bob 在打开阅后即焚照片时正在录屏');
    });

    test('ignore other system lines, and name a missing actor', () {
      expect(ChatNotice.maybeFromAttachment(null), isNull);
      expect(ChatNotice.maybeFromAttachment({'kind': 'call'}), isNull);
      expect(
        ChatNotice.maybeFromAttachment({
          'kind': 'chat_privacy',
          'enabled': true,
        })!.text,
        'Someone turned on advanced chat privacy',
      );
    });

    test('the list preview reads the server\'s English body in Chinese', () {
      expect(
        systemNoticeText('Ada turned on advanced chat privacy.'),
        'Ada turned on advanced chat privacy.',
      );
      AppStrings.isChinese = true;
      expect(
        systemNoticeText('Ada turned on advanced chat privacy.'),
        'Ada 开启了高级聊天隐私',
      );
      expect(
        systemNoticeText('Ada turned off advanced chat privacy.'),
        'Ada 关闭了高级聊天隐私',
      );
      expect(
        systemNoticeText('Bob took a screenshot of a view-once video.'),
        'Bob 对阅后即焚的视频截了屏',
      );
      expect(
        systemNoticeText(
          'Bob was recording the screen while a view-once photo was open.',
        ),
        'Bob 在打开阅后即焚照片时正在录屏',
      );
    });

    test('the newest change of the setting is found', () {
      expect(latestPrivacyNoticeId(null), isNull);
      expect(latestPrivacyNoticeId(const []), isNull);
      final messages = [
        _system('a', {'kind': 'chat_privacy', 'enabled': true}, 1),
        _system('b', {'kind': 'screenshot'}, 5),
        _system('c', {'kind': 'chat_privacy', 'enabled': false}, 3),
      ];
      expect(latestPrivacyNoticeId(messages), 'c');
    });
  });

  group('screenshot signals', () {
    test('the native names map to events, unknown ones are dropped', () {
      expect(
        parseScreenCaptureEvent('screenshot'),
        ScreenCaptureEvent.screenshot,
      );
      expect(
        parseScreenCaptureEvent('recording_started'),
        ScreenCaptureEvent.recordingStarted,
      );
      expect(
        parseScreenCaptureEvent('recording_stopped'),
        ScreenCaptureEvent.recordingStopped,
      );
      expect(parseScreenCaptureEvent('airplay'), isNull);
      expect(parseScreenCaptureEvent(null), isNull);
    });

    test('a device without a signal says so and sends nothing', () async {
      const service = UnsupportedScreenCaptureService();
      expect(service.detects, isFalse);
      expect(await service.isRecording(), isFalse);
      expect(await service.events.toList(), isEmpty);
    });

    test('tests on other platforms get the unsupported service', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      expect(container.read(screenCaptureDetectsProvider), isFalse);
    });

    test('the words never promise what the device cannot do', () {
      final yes = screenCaptureStatusText(detects: true);
      final no = screenCaptureStatusText(detects: false);
      expect(yes, contains('best effort'));
      expect(yes, contains('not a promise'));
      expect(no, contains('cannot tell'));
      expect(no, contains('Only iPhone and iPad can'));
      expect(screenCaptureSenderNote(), contains('not proof'));
    });

    test('the sender\'s status names what was reported', () {
      ViewOnceCaptureReport report(ViewOnceCaptureKind kind, String user) =>
          ViewOnceCaptureReport(
            userId: user,
            kind: kind,
            reportedAt: DateTime.utc(2026, 10, 28),
          );
      expect(viewOnceCaptureNote(const []), isNull);
      expect(
        viewOnceCaptureNote([report(ViewOnceCaptureKind.screenshot, 'a')]),
        'Screenshot taken',
      );
      expect(
        viewOnceCaptureNote([
          report(ViewOnceCaptureKind.screenshot, 'a'),
          report(ViewOnceCaptureKind.screenshot, 'b'),
        ]),
        'Screenshots taken',
      );
      expect(
        viewOnceCaptureNote([report(ViewOnceCaptureKind.recording, 'a')]),
        'Screen recorded',
      );
    });
  });

  group('in the chat', () {
    Future<PhoneWorld> openDirect(
      WidgetTester tester, {
      required FakeChatPrivacyRepository privacy,
    }) async {
      usePhoneViewport(tester, _desktop);
      final world = PhoneWorld();
      world.chats.messages = [
        phoneMessage('m1', bart, 'Morning everyone', minutesAgo: 5),
      ];
      world.extraOverrides = [
        chatPrivacyRepositoryProvider.overrideWithValue(privacy),
        aiAvailableProvider.overrideWith((ref, circleId) => true),
      ];
      await world.open(
        tester,
        '${ChatsScreen.path}/dm-1',
        extra: ChatThreadRouteExtra(
          title: bart.displayName,
          type: ConversationType.direct,
        ),
      );
      return world;
    }

    void wideTest(String name, Future<void> Function(WidgetTester) body) {
      testWidgets(name, (tester) async {
        debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
        try {
          await body(tester);
        } finally {
          debugDefaultTargetPlatformOverride = null;
        }
      });
    }

    final banner = find.byKey(const ValueKey('chat-privacy-banner'));

    wideTest('a restricted chat shows the banner and drops the menu entries', (
      tester,
    ) async {
      await openDirect(
        tester,
        privacy: FakeChatPrivacyRepository(
          chats: {
            'dm-1': const ChatPrivacy(
              restricted: true,
              requestedBy: {'user-2'},
            ),
          },
        ),
      );
      expect(banner, findsOneWidget);
      expect(find.text('Advanced chat privacy is on'), findsOneWidget);
      expect(find.textContaining('cannot stop screenshots'), findsOneWidget);

      await tester.tap(
        find.text('Morning everyone'),
        buttons: kSecondaryButton,
      );
      await tester.pumpAndSettle();
      // What the person may still do with a message.
      expect(find.text('Reply'), findsOneWidget);
      // What takes it out of the chat is gone.
      for (final gone in ['Forward', 'Copy', 'Save for later', 'Translate']) {
        expect(find.text(gone), findsNothing, reason: gone);
      }
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();

      // AI entry points are gone from the header and the "+" menu.
      await tester.tap(find.byKey(const ValueKey('chat-header-more')));
      await tester.pumpAndSettle();
      expect(find.text('Summarize'), findsNothing);
      expect(find.text('Advanced chat privacy'), findsOneWidget);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('composer-attach-button')));
      await tester.pumpAndSettle();
      expect(find.text('Ask WeCord AI'), findsNothing);
    });

    wideTest('an open chat keeps its menu and has no banner', (tester) async {
      await openDirect(tester, privacy: FakeChatPrivacyRepository());
      expect(banner, findsNothing);
      await tester.tap(
        find.text('Morning everyone'),
        buttons: kSecondaryButton,
      );
      await tester.pumpAndSettle();
      expect(find.text('Forward'), findsOneWidget);
      expect(find.text('Copy'), findsOneWidget);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      // The same entries the restricted chat loses are there.
      await tester.tap(find.byKey(const ValueKey('chat-header-more')));
      await tester.pumpAndSettle();
      expect(find.text('Summarize'), findsOneWidget);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('composer-attach-button')));
      await tester.pumpAndSettle();
      expect(find.text('Ask WeCord AI'), findsOneWidget);
    });

    wideTest('the sheet turns it on and the banner follows', (tester) async {
      final privacy = FakeChatPrivacyRepository();
      await openDirect(tester, privacy: privacy);
      await tester.tap(find.byKey(const ValueKey('chat-header-more')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Advanced chat privacy'));
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('chat-privacy-explainer')),
        findsOneWidget,
      );
      // It says what it cannot do, plainly.
      expect(find.textContaining('cannot stop screenshots'), findsWidgets);
      await tester.tap(find.byKey(const ValueKey('chat-privacy-toggle')));
      await tester.pumpAndSettle();
      expect(privacy.changes, [('dm-1', true)]);
      expect(find.text('Sharing is restricted'), findsOneWidget);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(banner, findsOneWidget);
    });
  });

  group('the sheet', () {
    Future<void> open(
      WidgetTester tester,
      FakeChatPrivacyRepository privacy, {
      required bool isGroup,
      required bool canChange,
    }) async {
      usePhoneViewport(tester, notchedPhone);
      final world = PhoneWorld();
      world.extraOverrides = [
        chatPrivacyRepositoryProvider.overrideWithValue(privacy),
      ];
      await pumpStandalone(
        tester,
        world,
        const Scaffold(body: SizedBox.expand()),
      );
      final context = tester.element(find.byType(Scaffold));
      showChatPrivacySheet(
        context,
        conversationId: isGroup ? 'group-1' : 'dm-1',
        isGroup: isGroup,
        canChange: canChange,
      );
      await settle(tester);
    }

    testWidgets('a group member who is not an admin only reads it', (
      tester,
    ) async {
      final privacy = FakeChatPrivacyRepository();
      await open(tester, privacy, isGroup: true, canChange: false);
      expect(
        find.text('Only group owners and admins can change this.'),
        findsOneWidget,
      );
      await tester.tap(find.byKey(const ValueKey('chat-privacy-toggle')));
      await settle(tester);
      expect(privacy.changes, isEmpty);
    });

    testWidgets('a group admin turns it on and off', (tester) async {
      final privacy = FakeChatPrivacyRepository();
      await open(tester, privacy, isGroup: true, canChange: true);
      await tester.tap(find.byKey(const ValueKey('chat-privacy-toggle')));
      await settle(tester);
      await tester.tap(find.byKey(const ValueKey('chat-privacy-toggle')));
      await settle(tester);
      expect(privacy.changes, [('group-1', true), ('group-1', false)]);
    });

    testWidgets('a failed change says so and leaves it as it was', (
      tester,
    ) async {
      final privacy = FakeChatPrivacyRepository()..failure = StateError('x');
      await open(tester, privacy, isGroup: false, canChange: true);
      await tester.tap(find.byKey(const ValueKey('chat-privacy-toggle')));
      await settle(tester);
      expect(
        find.text('Could not change it. Check your connection and try again.'),
        findsOneWidget,
      );
      expect(privacy.chats, isEmpty);
    });

    testWidgets('in a direct chat both of you can hold it on', (tester) async {
      final privacy = FakeChatPrivacyRepository(
        chats: {
          'dm-1': const ChatPrivacy(restricted: true, requestedBy: {'user-2'}),
        },
      );
      await open(tester, privacy, isGroup: false, canChange: true);
      expect(
        find.textContaining('The other person turned this on'),
        findsOneWidget,
      );
      await tester.tap(find.byKey(const ValueKey('chat-privacy-toggle')));
      await settle(tester);
      expect(find.textContaining('You both turned this on'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('chat-privacy-toggle')));
      await settle(tester);
      // Mine is off; the chat is still restricted because they asked.
      expect(privacy.chats['dm-1']!.restricted, isTrue);
      expect(
        find.textContaining('The other person turned this on'),
        findsOneWidget,
      );
    });
  });

  group('Settings', () {
    testWidgets('explains what it does and cannot do, for this device', (
      tester,
    ) async {
      usePhoneViewport(tester, notchedPhone);
      final world = PhoneWorld();
      await pumpStandalone(tester, world, const ChatPrivacyScreen());
      expect(find.text('What this does'), findsOneWidget);
      expect(find.text('What it cannot do'), findsOneWidget);
      // Tests run on a platform without the signal: the card says so.
      expect(
        find.text('Screenshot alerts do not work on this device'),
        findsOneWidget,
      );
    });

    testWidgets('says alerts work on a phone that can tell', (tester) async {
      usePhoneViewport(tester, notchedPhone);
      final world = PhoneWorld();
      world.extraOverrides = [
        screenCaptureServiceProvider.overrideWithValue(FakeScreenCapture()),
      ];
      await pumpStandalone(tester, world, const ChatPrivacyScreen());
      expect(
        find.text('Screenshot alerts work on this device'),
        findsOneWidget,
      );
      expect(find.textContaining('best effort'), findsOneWidget);
    });
  });
}
