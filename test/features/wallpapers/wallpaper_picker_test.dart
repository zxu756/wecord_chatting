import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wecord/features/chats/chats_repository.dart';
import 'package:wecord/features/chats/chats_screen.dart';
import 'package:wecord/features/wallpapers/wallpaper_backdrop.dart';
import 'package:wecord/features/wallpapers/wallpaper_controller.dart';
import 'package:wecord/features/wallpapers/wallpaper_model.dart';
import 'package:wecord/features/wallpapers/wallpaper_store.dart';
import 'package:wecord/shared/l10n/l10n.dart';
import 'package:wecord/shared/models/conversation.dart';
import 'package:wecord/shared/theme/wecord_theme.dart';
import 'package:wecord/shared/ui/ui.dart';

import '../../mobile/phone_test_support.dart';
import 'wallpaper_fakes.dart';

const _dawn = ChatWallpaper.preset('dawn');
const _sand = ChatWallpaper.preset('sand');
const _backdrop = ValueKey('chat-wallpaper');

Future<WallpaperTestStores> _openChat(
  WidgetTester tester,
  PhoneWorld world, {
  WallpaperSettings? settings,
}) async {
  final stores = WallpaperTestStores();
  if (settings != null) {
    stores.repository.settings = settings;
    stores.cache.values['user-1'] = settings;
  }
  world.extraOverrides = stores.overrides;
  await world.open(
    tester,
    '${ChatsScreen.path}/dm-1',
    extra: ChatThreadRouteExtra(
      title: bart.displayName,
      type: ConversationType.direct,
    ),
  );
  await settleWithImages(tester);
  return stores;
}

Future<void> _openWallpaperFromMenu(WidgetTester tester) async {
  await tester.tap(find.byTooltip(tr('More')));
  await settle(tester);
  await tester.tap(find.text('Wallpaper'));
  await settleWithImages(tester);
}

/// A bubble drawn over a wallpaper: solid, with the thin edge shadow.
Finder _wallpaperBubbles(Color fill) => find.byWidgetPredicate((widget) {
  if (widget is! Container) {
    return false;
  }
  final decoration = widget.decoration;
  return decoration is BoxDecoration &&
      decoration.color == fill &&
      decoration.boxShadow != null &&
      decoration.borderRadius != null;
});

void main() {
  late PhoneWorld world;

  setUp(() {
    world = PhoneWorld();
  });

  testWidgets('a chat has a Wallpaper entry in its More menu', (tester) async {
    usePhoneViewport(tester, notchedPhone);
    await _openChat(tester, world);
    await tester.tap(find.byTooltip(tr('More')));
    await settle(tester);
    expect(find.text('Wallpaper'), findsOneWidget);
    await world.close(tester);
  });

  testWidgets('the picker shows two sample bubbles, the choices and a note', (
    tester,
  ) async {
    usePhoneViewport(tester, notchedPhone);
    await _openChat(tester, world);
    await _openWallpaperFromMenu(tester);

    expect(find.text('Chat wallpaper'), findsOneWidget);
    expect(find.text('Only for this chat. Only you see it.'), findsOneWidget);
    expect(find.text('Hey! Are we still on for Friday?'), findsOneWidget);
    expect(find.text('Yes, see you there!'), findsOneWidget);
    expect(find.byKey(const ValueKey('wallpaper-none')), findsOneWidget);
    expect(find.byKey(const ValueKey('wallpaper-dawn')), findsOneWidget);
    expect(find.byKey(const ValueKey('wallpaper-photo')), findsOneWidget);
    // Nothing is changed yet: Apply waits.
    expect(
      tester
          .widget<WeCordButton>(find.byKey(const ValueKey('wallpaper-apply')))
          .onPressed,
      isNull,
    );
    await world.close(tester);
  });

  testWidgets('choosing a built-in and applying sets it for this chat only', (
    tester,
  ) async {
    usePhoneViewport(tester, notchedPhone);
    final stores = await _openChat(tester, world);
    expect(find.byKey(_backdrop), findsNothing);
    await _openWallpaperFromMenu(tester);

    await tester.tap(find.byKey(const ValueKey('wallpaper-dawn')));
    await settleWithImages(tester);
    await tester.tap(find.byKey(const ValueKey('wallpaper-apply')));
    await settleWithImages(tester);

    expect(stores.repository.saves, [('dm-1', _dawn)]);
    expect(stores.repository.settings.defaultWallpaper, isNull);
    // The sheet closed and the chat paints it, bubbles on solid surfaces.
    expect(find.text('Chat wallpaper'), findsNothing);
    expect(find.byKey(_backdrop), findsOneWidget);
    expect(_wallpaperBubbles(WeCordTokens.light.colors.panel), findsWidgets);
    await world.close(tester);
  });

  testWidgets('cancel changes nothing', (tester) async {
    usePhoneViewport(tester, notchedPhone);
    final stores = await _openChat(tester, world);
    await _openWallpaperFromMenu(tester);
    await tester.tap(find.byKey(const ValueKey('wallpaper-sand')));
    await settleWithImages(tester);
    await tester.tap(find.byKey(const ValueKey('wallpaper-cancel')));
    await settleWithImages(tester);

    expect(stores.repository.saves, isEmpty);
    expect(find.byKey(_backdrop), findsNothing);
    await world.close(tester);
  });

  testWidgets(
    'a chat\'s own wallpaper beats the default; Use default clears it',
    (tester) async {
      usePhoneViewport(tester, notchedPhone);
      final stores = await _openChat(
        tester,
        world,
        settings: const WallpaperSettings(
          defaultWallpaper: _dawn,
          chats: {'dm-1': _sand},
        ),
      );
      expect(find.byKey(_backdrop), findsOneWidget);
      final container = ProviderScope.containerOf(
        tester.element(find.byKey(_backdrop)),
      );
      expect(container.read(chatWallpaperProvider('dm-1')), _sand);
      expect(container.read(chatWallpaperProvider('other')), _dawn);

      await _openWallpaperFromMenu(tester);
      // The chat's own choice is selected, and Use default is offered.
      expect(
        find.byKey(const ValueKey('wallpaper-use-default')),
        findsOneWidget,
      );
      await tester.tap(find.byKey(const ValueKey('wallpaper-use-default')));
      await settleWithImages(tester);

      expect(stores.repository.clears, ['dm-1']);
      expect(container.read(chatWallpaperProvider('dm-1')), _dawn);
      // The default's wallpaper still shows.
      expect(find.byKey(_backdrop), findsOneWidget);
      await world.close(tester);
    },
  );

  testWidgets('a chat without its own wallpaper offers no Use default', (
    tester,
  ) async {
    usePhoneViewport(tester, notchedPhone);
    await _openChat(
      tester,
      world,
      settings: const WallpaperSettings(defaultWallpaper: _dawn),
    );
    await _openWallpaperFromMenu(tester);
    expect(find.byKey(const ValueKey('wallpaper-use-default')), findsNothing);
    await world.close(tester);
  });

  testWidgets('None for one chat opts it out of the default', (tester) async {
    usePhoneViewport(tester, notchedPhone);
    final stores = await _openChat(
      tester,
      world,
      settings: const WallpaperSettings(defaultWallpaper: _dawn),
    );
    expect(find.byKey(_backdrop), findsOneWidget);
    await _openWallpaperFromMenu(tester);
    await tester.tap(find.byKey(const ValueKey('wallpaper-none')));
    await settleWithImages(tester);
    await tester.tap(find.byKey(const ValueKey('wallpaper-apply')));
    await settleWithImages(tester);

    expect(stores.repository.saves.single.$1, 'dm-1');
    expect(stores.repository.saves.single.$2.isNone, isTrue);
    expect(find.byKey(_backdrop), findsNothing);
    await world.close(tester);
  });

  testWidgets('a failed save keeps the sheet open and says so', (tester) async {
    usePhoneViewport(tester, notchedPhone);
    final stores = await _openChat(tester, world);
    stores.repository.failWrites = StateError('offline');
    await _openWallpaperFromMenu(tester);
    await tester.tap(find.byKey(const ValueKey('wallpaper-sand')));
    await settleWithImages(tester);
    await tester.tap(find.byKey(const ValueKey('wallpaper-apply')));
    await settleWithImages(tester);

    expect(
      find.text("Couldn't change the wallpaper. Try again."),
      findsOneWidget,
    );
    expect(find.text('Chat wallpaper'), findsOneWidget);
    expect(find.byKey(_backdrop), findsNothing);
    await world.close(tester);
  });

  testWidgets('a photo: pick it, dim and blur it, apply', (tester) async {
    usePhoneViewport(tester, notchedPhone);
    final stores = await _openChat(tester, world);
    world.imagePicker.nextImage = ChatImageUpload(
      bytes: samplePhotoBytes(width: 1200, height: 1600),
      fileName: 'beach.heic',
      mimeType: 'image/heic',
    );
    await _openWallpaperFromMenu(tester);
    // The photo controls only show for a photo.
    expect(find.byKey(const ValueKey('wallpaper-dim')), findsNothing);

    await tester.tap(find.byKey(const ValueKey('wallpaper-photo')));
    await settleWithImages(tester);
    expect(world.imagePicker.pickCalls, 1);
    await tester.drag(find.byType(ListView).last, const Offset(0, -600));
    await settleWithImages(tester);
    expect(find.text('Dim in dark mode'), findsOneWidget);
    expect(find.text('Blur'), findsOneWidget);

    await tester.ensureVisible(find.byKey(const ValueKey('wallpaper-blur')));
    await settleWithImages(tester);
    await tester.tap(find.byKey(const ValueKey('wallpaper-blur')));
    await settleWithImages(tester);
    await tester.drag(
      find.byKey(const ValueKey('wallpaper-dim')),
      const Offset(80, 0),
    );
    await settleWithImages(tester);
    await tester.tap(find.byKey(const ValueKey('wallpaper-apply')));
    await settleWithImages(tester);

    expect(stores.repository.uploads, 1);
    final (chat, saved) = stores.repository.saves.single;
    expect(chat, 'dm-1');
    expect(saved.isPhoto, isTrue);
    expect(saved.blur, isTrue);
    expect(saved.dim, greaterThan(defaultPhotoDim));
    expect(saved.photoPath, stores.repository.bucket.keys.single);
    // The upload is a scaled-down JPEG, not the original.
    expect(stores.repository.bucket.values.single.length, lessThan(300000));
    expect(find.byKey(_backdrop), findsOneWidget);
    await world.close(tester);
  });

  testWidgets('a file that is not a picture is turned down', (tester) async {
    usePhoneViewport(tester, notchedPhone);
    final stores = await _openChat(tester, world);
    world.imagePicker.nextImage = ChatImageUpload(
      bytes: Uint8List.fromList([1, 2, 3, 4]),
      fileName: 'notes.jpg',
      mimeType: 'image/jpeg',
    );
    await _openWallpaperFromMenu(tester);
    await tester.tap(find.byKey(const ValueKey('wallpaper-photo')));
    await settleWithImages(tester);

    expect(
      find.text('Could not use that picture. Try another.'),
      findsOneWidget,
    );
    expect(stores.repository.uploads, 0);
    await world.close(tester);
  });

  testWidgets('wallpapers are painted once behind the list, not per message', (
    tester,
  ) async {
    usePhoneViewport(tester, notchedPhone);
    await _openChat(
      tester,
      world,
      settings: const WallpaperSettings(defaultWallpaper: _dawn),
    );
    // One backdrop in its own repaint boundary, however many messages.
    expect(find.byKey(_backdrop), findsOneWidget);
    expect(
      find.descendant(
        of: find.byKey(_backdrop),
        matching: find.byType(CustomPaint),
      ),
      findsWidgets,
    );
    expect(find.byType(ChatWallpaperBackdrop), findsOneWidget);
    await world.close(tester);
  });

  group('readability fallbacks', () {
    Widget probe({
      required WallpaperTestStores stores,
      bool highContrastTheme = false,
      bool glass = true,
      bool platformHighContrast = false,
    }) {
      return ProviderScope(
        overrides: [
          ...stores.overrides,
          wallpaperUserIdProvider.overrideWithValue('user-1'),
        ],
        child: MaterialApp(
          theme: WeCordTheme.light(highContrast: highContrastTheme),
          home: MediaQuery(
            data: MediaQueryData(highContrast: platformHighContrast),
            child: WeCordAppearance(
              glassEffects: glass,
              child: ChatWallpaperHost(
                conversationId: 'a',
                child: Builder(
                  builder: (context) => Stack(
                    children: [
                      const Positioned.fill(child: ChatWallpaperBackdrop()),
                      Center(
                        child: Text(
                          ChatWallpaperScope.activeOf(context)
                              ? 'wallpaper on'
                              : 'wallpaper off',
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      );
    }

    WallpaperTestStores stores0([ChatWallpaper? wallpaper]) {
      final settings = WallpaperSettings(defaultWallpaper: wallpaper ?? _dawn);
      return WallpaperTestStores(
        repository: FakeWallpaperRepository(settings),
        cache: InMemoryWallpaperSettingsStore({'user-1': settings}),
      );
    }

    testWidgets('a preset shows normally', (tester) async {
      await tester.pumpWidget(probe(stores: stores0()));
      await tester.pump(const Duration(milliseconds: 50));
      await tester.pump(const Duration(milliseconds: 50));
      expect(find.text('wallpaper on'), findsOneWidget);
      expect(find.byKey(_backdrop), findsOneWidget);
    });

    testWidgets('high contrast falls back to the plain background', (
      tester,
    ) async {
      await tester.pumpWidget(
        probe(stores: stores0(), platformHighContrast: true),
      );
      await tester.pump(const Duration(milliseconds: 50));
      await tester.pump(const Duration(milliseconds: 50));
      expect(find.text('wallpaper off'), findsOneWidget);
      expect(find.byKey(_backdrop), findsNothing);
    });

    testWidgets('the high contrast theme does too', (tester) async {
      await tester.pumpWidget(
        probe(stores: stores0(), highContrastTheme: true),
      );
      await tester.pump(const Duration(milliseconds: 50));
      await tester.pump(const Duration(milliseconds: 50));
      expect(find.text('wallpaper off'), findsOneWidget);
      expect(find.byKey(_backdrop), findsNothing);
    });

    testWidgets('so does turning Glass effects off (reduced transparency)', (
      tester,
    ) async {
      await tester.pumpWidget(probe(stores: stores0(), glass: false));
      await tester.pump(const Duration(milliseconds: 50));
      await tester.pump(const Duration(milliseconds: 50));
      expect(find.text('wallpaper off'), findsOneWidget);
      expect(find.byKey(_backdrop), findsNothing);
    });

    testWidgets('a wallpaper from a newer version shows the plain background', (
      tester,
    ) async {
      await tester.pumpWidget(
        probe(stores: stores0(const ChatWallpaper.preset('from-the-future'))),
      );
      await tester.pump(const Duration(milliseconds: 50));
      await tester.pump(const Duration(milliseconds: 50));
      expect(find.text('wallpaper off'), findsOneWidget);
      expect(find.byKey(_backdrop), findsNothing);
    });

    testWidgets('a photo that cannot be had shows the plain background', (
      tester,
    ) async {
      // Not on this device and not on the server.
      await tester.pumpWidget(
        probe(stores: stores0(const ChatWallpaper.photo('user-1/gone.jpg'))),
      );
      await tester.pump(const Duration(milliseconds: 50));
      await tester.pump(const Duration(milliseconds: 50));
      await tester.pump(const Duration(milliseconds: 50));
      expect(find.text('wallpaper off'), findsOneWidget);
      expect(find.byKey(_backdrop), findsNothing);
    });

    testWidgets('a photo on its way shows a quiet placeholder, not the plain '
        'background', (tester) async {
      final stores = stores0(const ChatWallpaper.photo('user-1/a.jpg'));
      stores.photos.photos['user-1/a.jpg'] = samplePhotoBytes(
        width: 80,
        height: 120,
      );
      await tester.pumpWidget(probe(stores: stores));
      await tester.pump(const Duration(milliseconds: 20));
      await tester.pump(const Duration(milliseconds: 20));
      expect(find.text('wallpaper on'), findsOneWidget);
      expect(find.byKey(_backdrop), findsOneWidget);
    });

    testWidgets('the settings row says what the default is', (tester) async {
      final stores = stores0(const ChatWallpaper.preset('sage'));
      final settingsWorld = PhoneWorld();
      settingsWorld.extraOverrides = stores.overrides;
      usePhoneViewport(tester, notchedPhone);
      await settingsWorld.open(tester, '/me');
      await settleWithImages(tester);
      final row = find.byKey(const ValueKey('chat-wallpaper-row'));
      await tester.drag(
        find.byKey(const ValueKey('settings-screen')),
        const Offset(0, -400),
      );
      await settle(tester);
      await tester.tap(row);
      await settleWithImages(tester);
      expect(
        find.text(
          'Used in every chat without its own wallpaper. '
          'Only you see it.',
        ),
        findsOneWidget,
      );
      // Choosing None for the default clears its row.
      await tester.tap(find.byKey(const ValueKey('wallpaper-none')));
      await settleWithImages(tester);
      await tester.tap(find.byKey(const ValueKey('wallpaper-apply')));
      await settleWithImages(tester);
      expect(stores.repository.clears, [null]);
      await settingsWorld.close(tester);
    });
  });
}
