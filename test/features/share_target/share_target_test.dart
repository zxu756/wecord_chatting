import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wecord/features/chats/chats_screen.dart';
import 'package:wecord/features/note_to_self/note_to_self.dart';
import 'package:wecord/features/share_target/protocol_links.dart';
import 'package:wecord/features/share_target/share_target_screen.dart';
import 'package:wecord/features/share_target/shared_content.dart';
import 'package:wecord/features/voice_input/speech_results.dart';
import 'package:wecord/shared/l10n/l10n.dart';

import '../../mobile/phone_test_support.dart';
import 'share_fakes.dart';

const _qr = 'abcdefgh23456789';
const _invite = 'AbCdEfGh12';
const _call = 'abcdefghij12';

void main() {
  group('what a share says', () {
    test('title, text and link each go on their own line', () {
      expect(
        sharedMessageText(
          title: 'A page',
          text: 'Worth a look',
          url: 'https://example.com/a',
        ),
        'A page\nWorth a look\nhttps://example.com/a',
      );
    });

    test('a link the text already holds is not said twice', () {
      expect(
        sharedMessageText(
          title: 'A page',
          text: 'A page https://example.com/a',
          url: 'https://example.com/a',
        ),
        'A page https://example.com/a',
      );
      expect(sharedMessageText(title: 'Same', text: 'Same', url: ''), 'Same');
    });

    test('a link with a title is the title, then the link', () {
      expect(
        sharedMessageText(title: 'Docs', url: 'https://example.com'),
        'Docs\nhttps://example.com',
      );
    });

    test('nothing at all is no message', () {
      expect(sharedMessageText(title: ' ', text: '', url: '\n'), isNull);
      expect(const SharedContent().isEmpty, isTrue);
      expect(const SharedContent(text: 'x').isEmpty, isFalse);
      expect(SharedContent(files: [sharedFile('a.pdf')]).isEmpty, isFalse);
    });
  });

  group('web+wecord: links', () {
    test('open the four kinds of link WeCord already has', () {
      expect(
        protocolLinkLocation('web+wecord:invite/$_invite'),
        '/invite/${_invite.toLowerCase()}',
      );
      expect(protocolLinkLocation('web+wecord:call/$_call'), '/call/$_call');
      expect(protocolLinkLocation('web+wecord:u/$_qr'), '/u/$_qr');
      expect(protocolLinkLocation('web+wecord:g/$_qr'), '/g/$_qr');
    });

    test('accept the slashes and case people type', () {
      expect(protocolLinkLocation('web+wecord://u/$_qr'), '/u/$_qr');
      expect(
        protocolLinkLocation('  WEB+WECORD:U/${_qr.toUpperCase()}  '),
        '/u/$_qr',
      );
      expect(protocolLinkLocation('web+wecord:u/$_qr?x=1#y'), '/u/$_qr');
    });

    test('open nothing else', () {
      for (final link in [
        '',
        'web+wecord:',
        'web+wecord:settings',
        'web+wecord:admin/console',
        'web+wecord:invite/short',
        'web+wecord:u/nope',
        'web+wecord:u/$_qr/extra',
        'web+other:u/$_qr',
        'https://example.com/u/$_qr',
        'javascript:alert(1)',
      ]) {
        expect(protocolLinkLocation(link), isNull, reason: link);
      }
    });

    test('are found from the address the browser opens', () {
      final encoded = Uri.encodeQueryComponent('web+wecord:u/$_qr');
      expect(
        protocolLinkLocationFor(
          Uri.parse('https://wecord.test/open?uri=$encoded'),
        ),
        '/u/$_qr',
      );
      expect(
        protocolLinkLocationFor(
          Uri.parse('https://wecord.test/open/?uri=$encoded'),
        ),
        '/u/$_qr',
      );
      // Not the handler's address, or a bad link, or a route of its own.
      expect(
        protocolLinkLocationFor(Uri.parse('https://wecord.test/')),
        isNull,
      );
      expect(
        protocolLinkLocationFor(
          Uri.parse('https://wecord.test/other?uri=$encoded'),
        ),
        isNull,
      );
      expect(
        protocolLinkLocationFor(
          Uri.parse('https://wecord.test/open?uri=web%2Bwecord%3Aoops'),
        ),
        isNull,
      );
      expect(
        protocolLinkLocationFor(Uri.parse('https://wecord.test/open')),
        isNull,
      );
      expect(
        protocolLinkLocationFor(
          Uri.parse('https://wecord.test/open?uri=$encoded#/chats/x'),
        ),
        isNull,
      );
    });
  });

  group('Chrome on Android repeating a growing phrase', () {
    test('keeps only the longest update of a phrase', () {
      expect(
        joinSpeechResults([
          'hello',
          'hello how',
          'hello how are you',
        ], cumulative: true),
        'hello how are you',
      );
    });

    test('keeps separate phrases that follow each other', () {
      expect(
        joinSpeechResults([
          'hello there',
          ' how are you',
          ' how are you today',
        ], cumulative: true),
        'hello there how are you today',
      );
    });

    test('Chinese has no spaces to tell phrases apart, and needs none', () {
      expect(joinSpeechResults(['你', '你好', '你好吗'], cumulative: true), '你好吗');
    });

    test('other browsers number each phrase, so nothing is dropped', () {
      // "yes" then "yes sir" are two phrases there, not one growing one.
      expect(
        joinSpeechResults(['Yes', ' yes sir'], cumulative: false),
        'Yes yes sir',
      );
      expect(
        joinSpeechResults(['hello', ' world'], cumulative: false),
        'hello world',
      );
    });

    test('skips empty results and trims the whole', () {
      expect(joinSpeechResults(['', ' ', ' a '], cumulative: true), 'a');
      expect(joinSpeechResults(const [], cumulative: true), '');
    });

    test('spots a browser on Android by its user agent', () {
      expect(
        isAndroidBrowser(
          'Mozilla/5.0 (Linux; Android 14; Pixel 8) AppleWebKit/537.36 '
          '(KHTML, like Gecko) Chrome/130.0.0.0 Mobile Safari/537.36',
        ),
        isTrue,
      );
      expect(
        isAndroidBrowser(
          'Mozilla/5.0 (iPhone; CPU iPhone OS 18_4 like Mac OS X) '
          'AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.4 Mobile/15E148',
        ),
        isFalse,
      );
      expect(
        isAndroidBrowser(
          'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) Chrome/130.0.0.0',
        ),
        isFalse,
      );
    });
  });

  group('the share page', () {
    tearDown(() => AppStrings.isChinese = false);

    Future<(PhoneWorld, FakeShareTargetGateway, FakeShareNoteToSelf)> open(
      WidgetTester tester,
      SharedContent? content,
    ) async {
      usePhoneViewport(tester, notchedPhone);
      final gateway = FakeShareTargetGateway(content);
      final notes = FakeShareNoteToSelf();
      final world = PhoneWorld()
        ..extraOverrides = shareOverrides(gateway, notes: notes);
      await world.open(tester, ShareTargetScreen.path);
      return (world, gateway, notes);
    }

    final shared = SharedContent(
      title: 'A page',
      url: 'https://example.com/a',
      files: [sharedFile('menu.pdf')],
    );

    testWidgets('shows what was shared and the chats, note to self first', (
      tester,
    ) async {
      final (world, _, _) = await open(tester, shared);

      expect(find.text('Share to WeCord'), findsOneWidget);
      expect(
        find.textContaining('A page\nhttps://example.com/a'),
        findsOneWidget,
      );
      expect(find.text('menu.pdf'), findsOneWidget);
      final rows = find.byWidgetPredicate(
        (widget) =>
            widget.key is ValueKey<String> &&
            (widget.key! as ValueKey<String>).value.startsWith('share-target-'),
      );
      expect(rows, findsWidgets);
      expect(
        (tester.widget(rows.first).key! as ValueKey<String>).value,
        'share-target-$noteToSelfPlaceholderId',
      );
      // Not circle channels.
      expect(
        find.byKey(const ValueKey('share-target-conv-general')),
        findsNothing,
      );
      await world.close(tester);
    });

    testWidgets(
      'sending to a chat sends the text and the file, then opens it',
      (tester) async {
        final (world, gateway, _) = await open(tester, shared);

        await tester.tap(find.byKey(const ValueKey('share-target-dm-1')));
        await settle(tester);

        expect(world.chats.sentMessages.single.conversationId, 'dm-1');
        expect(
          world.chats.sentMessages.single.body,
          'A page\nhttps://example.com/a',
        );
        expect(world.chats.sentFiles.single.conversationId, 'dm-1');
        expect(world.chats.sentFiles.single.fileName, 'menu.pdf');
        expect(world.chats.sentFiles.single.mimeType, 'application/pdf');
        expect(gateway.cleared, 1);
        expect(
          world.router.routerDelegate.currentConfiguration.uri.path,
          '${ChatsScreen.path}/dm-1',
        );
        await world.close(tester);
      },
    );

    testWidgets('the note to self is made first when it does not exist yet', (
      tester,
    ) async {
      final (world, _, notes) = await open(
        tester,
        const SharedContent(text: 'Look later'),
      );

      await tester.tap(
        find.byKey(ValueKey('share-target-$noteToSelfPlaceholderId')),
      );
      await settle(tester);

      expect(notes.ensured, 1);
      expect(world.chats.sentMessages.single.conversationId, 'note-1');
      expect(world.chats.sentMessages.single.body, 'Look later');
      expect(
        world.router.routerDelegate.currentConfiguration.uri.path,
        '${ChatsScreen.path}/note-1',
      );
      await world.close(tester);
    });

    testWidgets('a refused send says so and keeps the share', (tester) async {
      final (world, gateway, _) = await open(tester, shared);
      world.chats.sendError = StateError('down');

      await tester.tap(find.byKey(const ValueKey('share-target-dm-1')));
      await settle(tester);

      expect(find.text('Could not send. Try again.'), findsOneWidget);
      expect(gateway.cleared, 0);
      expect(
        world.router.routerDelegate.currentConfiguration.uri.path,
        ShareTargetScreen.path,
      );
      // Still there to try another chat.
      expect(find.byKey(const ValueKey('share-target-dm-2')), findsOneWidget);
      await world.close(tester);
    });

    testWidgets('searching narrows the chats', (tester) async {
      final (world, _, _) = await open(tester, shared);

      await tester.enterText(
        find.byKey(const ValueKey('share-search')),
        'weekend',
      );
      await settle(tester);

      expect(
        find.byKey(const ValueKey('share-target-group-1')),
        findsOneWidget,
      );
      expect(find.byKey(const ValueKey('share-target-dm-1')), findsNothing);
      await world.close(tester);
    });

    testWidgets('says when files were left out', (tester) async {
      final (world, _, _) = await open(
        tester,
        const SharedContent(text: 'x', skippedFiles: 3),
      );
      expect(find.byKey(const ValueKey('share-skipped')), findsOneWidget);
      await world.close(tester);
    });

    testWidgets('with nothing waiting it says so and goes back', (
      tester,
    ) async {
      final (world, _, _) = await open(tester, null);

      expect(find.text('Nothing to share'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('share-done')));
      await settle(tester);
      expect(
        world.router.routerDelegate.currentConfiguration.uri.path,
        '/home',
      );
      await world.close(tester);
    });

    testWidgets('discarding forgets the share', (tester) async {
      final (world, gateway, _) = await open(tester, shared);

      await tester.tap(find.byKey(const ValueKey('share-discard')));
      await settle(tester);

      expect(gateway.cleared, 1);
      expect(
        world.router.routerDelegate.currentConfiguration.uri.path,
        '/home',
      );
      await world.close(tester);
    });

    testWidgets('speaks Chinese', (tester) async {
      usePhoneViewport(tester, notchedPhone);
      AppStrings.isChinese = true;
      await pumpStandalone(
        tester,
        PhoneWorld(),
        const ShareTargetScreen(),
        extraOverrides: shareOverrides(FakeShareTargetGateway(shared)),
      );

      expect(find.text('分享到 WeCord'), findsOneWidget);
      expect(find.text('发送到'), findsOneWidget);
      expect(find.text('放弃'), findsOneWidget);
    });
  });

  group('sending a share', () {
    testWidgets('pictures go as pictures with their size, the rest as files', (
      tester,
    ) async {
      final world = PhoneWorld();
      await tester.runAsync(() async {
        await sendSharedContent(
          world.chats,
          'dm-1',
          SharedContent(
            files: [
              sharedFile('dot.png', mimeType: 'image/png', bytes: tinyPng),
              sharedFile('notes.txt', mimeType: 'text/plain'),
              sharedFile('mystery', mimeType: ''),
            ],
          ),
        );
      });
      final picture = world.chats.sentImages.single.image;
      expect(picture.fileName, 'dot.png');
      expect(picture.mimeType, 'image/png');
      expect((picture.width, picture.height), (1, 1));
      expect(world.chats.sentFiles.map((f) => f.fileName), [
        'notes.txt',
        'mystery',
      ]);
      expect(world.chats.sentFiles.last.mimeType, 'application/octet-stream');
      expect(world.chats.sentMessages, isEmpty);
    });

    testWidgets('a picture that cannot be decoded goes as a file', (
      tester,
    ) async {
      final world = PhoneWorld();
      await tester.runAsync(() async {
        await sendSharedContent(
          world.chats,
          'dm-1',
          SharedContent(
            files: [
              sharedFile('broken.png', mimeType: 'image/png', bytes: [1, 2, 3]),
            ],
          ),
        );
      });
      expect(world.chats.sentImages, isEmpty);
      expect(world.chats.sentFiles.single.fileName, 'broken.png');
    });
  });
}
