import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wecord/features/accessibility/image_alt_sheet.dart';
import 'package:wecord/features/chats/chat_thread_screen.dart';
import 'package:wecord/features/chats/chats_screen.dart';
import 'package:wecord/features/chats/media_send/media_draft.dart';
import 'package:wecord/features/chats/media_send/media_picker.dart';
import 'package:wecord/features/chats/media_send/media_prepare.dart';
import 'package:wecord/features/chats/media_send/media_tray.dart';
import 'package:wecord/features/chats/media_send/media_tray_controller.dart';
import 'package:wecord/features/chats/media_send/outbox_media.dart';
import 'package:wecord/features/chats/message_semantics.dart';
import 'package:wecord/shared/models/conversation.dart';
import 'package:wecord/shared/models/message.dart';
import 'package:wecord/shared/theme/wecord_theme.dart';

import '../../mobile/phone_test_support.dart';
import '../chats/media_send/media_fakes.dart';

const _conversation = 'conversation-1';

ImageAttachment _image({String? alt}) => ImageAttachment(
  bucket: 'chat-images',
  path: 'conversation-1/sunset.jpg',
  mimeType: 'image/jpeg',
  size: 1000,
  width: 800,
  height: 600,
  alt: alt,
);

void main() {
  group('the description travels with the picture', () {
    test(
      'it is kept in the attachment, trimmed, and only when there is one',
      () {
        final json = _image(alt: '  A red kite over the sea  ').toJson();
        expect(json['alt'], 'A red kite over the sea');
        expect(_image().toJson().containsKey('alt'), isFalse);
        expect(_image(alt: '   ').toJson().containsKey('alt'), isFalse);
        expect(ImageAttachment.fromJson(json).alt, 'A red kite over the sea');
        // Older messages have none.
        expect(
          ImageAttachment.fromJson(_image().toJson()..remove('alt')).alt,
          isNull,
        );
      },
    );

    test('a very long one is cut at the limit', () {
      final long = 'a' * (maxImageAltLength + 50);
      expect(cleanImageAlt(long)!.length, maxImageAltLength);
      expect(cleanImageAlt(42), isNull);
    });

    test('a queued picture sends it; a view-once one never does', () {
      const media = OutboxMedia(
        kind: OutboxMediaKind.image,
        fileName: 'sunset.jpg',
        mimeType: 'image/jpeg',
        size: 1000,
        alt: 'A red kite over the sea',
      );
      expect(
        media.attachmentJson('conversation-1/c1-sunset.jpg')['alt'],
        'A red kite over the sea',
      );
      // It survives being kept in the queue and read back.
      expect(OutboxMedia.fromJson(media.toJson()).alt, media.alt);
      const none = OutboxMedia(
        kind: OutboxMediaKind.image,
        fileName: 'a.jpg',
        mimeType: 'image/jpeg',
        size: 1,
      );
      expect(none.toJson().containsKey('alt'), isFalse);
    });

    test('a screen reader says it instead of a guess from the file name', () {
      expect(
        messageImageDescription(
          'conversation-1/IMG_0042.jpg',
          'Bart',
          alt: 'Two kids on a seesaw',
        ),
        'Image: Two kids on a seesaw',
      );
      expect(
        messageImageDescription('conversation-1/IMG_0042.jpg', 'Bart'),
        'Image from Bart',
      );
    });
  });

  group('the tray', () {
    late ProviderContainer container;

    Future<void> pump(WidgetTester tester) async {
      container = ProviderContainer(
        overrides: [
          videoPosterReaderProvider.overrideWithValue((file) async => null),
        ],
      );
      addTearDown(container.dispose);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            theme: WeCordTheme.light(),
            home: Scaffold(
              body: Align(
                alignment: Alignment.bottomCenter,
                child: MediaTray(
                  conversationId: _conversation,
                  onSend: () async {},
                  onAddMore: (_) {},
                ),
              ),
            ),
          ),
        ),
      );
      await tester.runAsync(
        () => container.read(mediaTrayProvider(_conversation).notifier).add([
          testPhoto('a.jpg'),
        ]),
      );
      await tester.pump();
    }

    DraftAttachment draft() =>
        container.read(mediaTrayProvider(_conversation)).items.single;

    testWidgets('invites a description, takes one and shows it was written', (
      tester,
    ) async {
      await pump(tester);
      final row = find.byKey(const ValueKey('media-tray-describe'));
      final mark = find.byKey(ValueKey('media-tray-alt-${draft().id}'));
      expect(find.text('Describe picture'), findsOneWidget);
      expect(tester.widget<ImageAltBadge>(mark).described, isFalse);
      expect(
        find.byKey(const ValueKey('media-tray-describe-status')),
        findsNothing,
      );

      await tester.tap(row);
      await settle(tester);
      expect(find.text('Describe this picture'), findsOneWidget);
      await tester.enterText(
        find.byKey(ImageAltSheet.fieldKey(draft().id)),
        'A red kite over the sea',
      );
      await tester.tap(find.byKey(ImageAltSheet.saveKey));
      await settle(tester);

      expect(draft().alt, 'A red kite over the sea');
      expect(tester.widget<ImageAltBadge>(mark).described, isTrue);
      expect(find.text('Described'), findsOneWidget);

      // Changing it starts from what was written; an empty text takes it away.
      await tester.tap(row);
      await settle(tester);
      expect(find.text('A red kite over the sea'), findsOneWidget);
      await tester.enterText(
        find.byKey(ImageAltSheet.fieldKey(draft().id)),
        '',
      );
      await tester.tap(find.byKey(ImageAltSheet.saveKey));
      await settle(tester);
      expect(draft().alt, isNull);
    });

    testWidgets('backing out of the sheet changes nothing', (tester) async {
      await pump(tester);
      await tester.tap(find.byKey(const ValueKey('media-tray-describe')));
      await settle(tester);
      await tester.enterText(
        find.byKey(ImageAltSheet.fieldKey(draft().id)),
        'Never mind',
      );
      await tester.tapAt(const Offset(10, 10));
      await settle(tester);
      expect(find.text('Describe this picture'), findsNothing);
      expect(draft().alt, isNull);
    });

    testWidgets('several pictures are described in one sheet', (tester) async {
      await pump(tester);
      await tester.runAsync(
        () => container.read(mediaTrayProvider(_conversation).notifier).add([
          testPhoto('b.jpg'),
        ]),
      );
      await tester.pump();
      final items = container.read(mediaTrayProvider(_conversation)).items;
      expect(find.text('Describe pictures'), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('media-tray-describe')));
      await settle(tester);
      expect(find.text('Describe these pictures'), findsOneWidget);
      await tester.enterText(
        find.byKey(ImageAltSheet.fieldKey(items.last.id)),
        'The lake at dawn',
      );
      await tester.tap(find.byKey(ImageAltSheet.saveKey));
      await settle(tester);

      final after = container.read(mediaTrayProvider(_conversation)).items;
      expect(after.first.alt, isNull);
      expect(after.last.alt, 'The lake at dawn');
      expect(find.text('1 of 2 described'), findsOneWidget);
    });

    testWidgets('goes on to the outbox with the picture', (tester) async {
      await pump(tester);
      container
          .read(mediaTrayProvider(_conversation).notifier)
          .setAlt(draft().id, 'A red kite over the sea');
      final queued = await tester.runAsync(
        () => prepareDrafts(
          container.read(mediaTrayProvider(_conversation)).items,
          original: false,
        ),
      );
      expect(queued!.single.alt, 'A red kite over the sea');
    });
  });

  group('in a chat', () {
    Future<PhoneWorld> openChat(WidgetTester tester, {String? alt}) async {
      usePhoneViewport(tester, notchedPhone);
      final world = PhoneWorld();
      world.chats.messages = [
        phoneMessage(
          'm4',
          bart,
          '',
          minutesAgo: 5,
          type: MessageType.image,
          attachment: {
            'kind': 'image',
            'bucket': 'chat-images',
            'path': 'dm-1/photo.png',
            'mime_type': 'image/png',
            'size': 1024,
            'width': 1200,
            'height': 800,
            'alt': ?alt,
          },
        ),
      ];
      await world.open(
        tester,
        '${ChatsScreen.path}/dm-1',
        extra: ChatThreadRouteExtra(
          title: bart.displayName,
          type: ConversationType.direct,
        ),
      );
      await settle(tester);
      return world;
    }

    testWidgets('a described picture has an ALT mark that shows the text', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      final world = await openChat(tester, alt: 'A red kite over the sea');

      expect(find.byKey(const ValueKey('album-alt-m4')), findsOneWidget);
      expect(
        find.bySemanticsLabel(RegExp('A red kite over the sea')),
        findsWidgets,
      );

      await tester.tap(find.byKey(const ValueKey('album-alt-m4')));
      await settle(tester);
      expect(find.text('Picture description'), findsWidgets);
      expect(find.text('A red kite over the sea'), findsOneWidget);
      await tester.tap(find.text('Close'));
      await settle(tester);

      handle.dispose();
      await world.close(tester);
    });

    testWidgets('a picture without one has no mark', (tester) async {
      final world = await openChat(tester);
      expect(find.byKey(const ValueKey('album-alt-m4')), findsNothing);
      await world.close(tester);
    });
  });
}
