import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:wecord/features/wallpapers/wallpaper_model.dart';

void main() {
  group('ChatWallpaper', () {
    test('reads a preset row', () {
      final wallpaper = ChatWallpaper.fromJson({
        'kind': 'preset',
        'preset_id': 'dawn',
        'photo_path': null,
      });
      expect(wallpaper, const ChatWallpaper.preset('dawn'));
      expect(wallpaper.isPreset, isTrue);
      expect(wallpaper.isPhoto, isFalse);
    });

    test('reads a photo row with its dim, blur and position', () {
      final wallpaper = ChatWallpaper.fromJson({
        'kind': 'photo',
        'photo_path': 'u/p.jpg',
        'dim': 0.5,
        'blur': true,
        'focus_x': -0.25,
        'focus_y': 1,
      });
      expect(
        wallpaper,
        const ChatWallpaper.photo(
          'u/p.jpg',
          dim: 0.5,
          blur: true,
          focusX: -0.25,
          focusY: 1,
        ),
      );
    });

    test('keeps numbers in range and falls back to the plain background', () {
      final wild = ChatWallpaper.fromJson({
        'kind': 'photo',
        'photo_path': 'u/p.jpg',
        'dim': 9,
        'focus_x': -7,
        'focus_y': 'left',
      });
      expect(wild.dim, 1);
      expect(wild.focusX, -1);
      expect(wild.focusY, 0);
      // Missing pieces, unknown kinds and rows from the future are plain.
      for (final json in <Map<String, dynamic>>[
        {'kind': 'preset'},
        {'kind': 'preset', 'preset_id': ''},
        {'kind': 'photo'},
        {'kind': 'sticker', 'preset_id': 'dawn'},
        {'kind': null},
        {},
      ]) {
        expect(ChatWallpaper.fromJson(json).isNone, isTrue, reason: '$json');
      }
    });

    test('survives a round trip through JSON', () {
      for (final wallpaper in const [
        ChatWallpaper.none(),
        ChatWallpaper.preset('grid'),
        ChatWallpaper.photo('u/p.jpg', dim: 0.3, blur: true, focusX: 0.5),
      ]) {
        final copy = ChatWallpaper.fromJson(
          jsonDecode(jsonEncode(wallpaper.toJson())) as Map<String, dynamic>,
        );
        expect(copy, wallpaper);
        expect(copy.hashCode, wallpaper.hashCode);
      }
    });

    test('copyWith changes a photo\'s options only', () {
      const photo = ChatWallpaper.photo('u/p.jpg');
      final changed = photo.copyWith(dim: 0.6, blur: true, focusY: -1);
      expect(changed.photoPath, 'u/p.jpg');
      expect(changed.dim, 0.6);
      expect(changed.blur, isTrue);
      expect(changed.focusY, -1);
      expect(photo.blur, isFalse);
    });
  });

  group('WallpaperSettings', () {
    const dawn = ChatWallpaper.preset('dawn');
    const dots = ChatWallpaper.preset('dots');

    test('a chat uses its own wallpaper, else the default, else none', () {
      const settings = WallpaperSettings(
        defaultWallpaper: dawn,
        chats: {'a': dots, 'b': ChatWallpaper.none()},
      );
      expect(settings.effective('a'), dots);
      expect(settings.effective('c'), dawn);
      // None is a choice: it opts a chat out of the default.
      expect(settings.effective('b').isNone, isTrue);
      expect(settings.hasOwn('a'), isTrue);
      expect(settings.hasOwn('c'), isFalse);
      expect(const WallpaperSettings().effective('a').isNone, isTrue);
    });

    test('reads rows: a null conversation is the default', () {
      final settings = WallpaperSettings.fromRows([
        {'kind': 'preset', 'preset_id': 'dawn', 'conversation_id': null},
        {'kind': 'preset', 'preset_id': 'dots', 'conversation_id': 'a'},
        {'kind': 'none', 'conversation_id': 'b'},
      ]);
      expect(settings.defaultWallpaper, dawn);
      expect(settings.chats['a'], dots);
      expect(settings.chats['b']!.isNone, isTrue);
    });

    test('setting and clearing leaves the others alone', () {
      const start = WallpaperSettings(defaultWallpaper: dawn);
      final withChat = start.withWallpaper('a', dots);
      expect(withChat.defaultWallpaper, dawn);
      expect(withChat.chats, {'a': dots});
      final withoutDefault = withChat.withWallpaper(null, null);
      expect(withoutDefault.defaultWallpaper, isNull);
      expect(withoutDefault.chats, {'a': dots});
      expect(withoutDefault.withWallpaper('a', null).chats, isEmpty);
      // The original is untouched.
      expect(start.chats, isEmpty);
    });

    test('survives a round trip through JSON and compares by value', () {
      const settings = WallpaperSettings(
        defaultWallpaper: dawn,
        chats: {'a': ChatWallpaper.photo('u/p.jpg', blur: true)},
      );
      final copy = WallpaperSettings.fromJson(
        jsonDecode(jsonEncode(settings.toJson())) as Map<String, dynamic>,
      );
      expect(copy, settings);
      expect(copy.hashCode, settings.hashCode);
      expect(copy == const WallpaperSettings(), isFalse);
    });

    test('a damaged copy reads as empty', () {
      expect(
        WallpaperSettings.fromJson({'default': 5, 'chats': 'x'}),
        const WallpaperSettings(),
      );
    });
  });
}
