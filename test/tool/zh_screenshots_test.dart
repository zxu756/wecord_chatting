// Chinese screenshots of key screens for eyeballing truncation and overflow.
//
//   ZH_AUDIT=1 flutter test test/tool/zh_screenshots_test.dart
//
// Writes PNGs into build/zh-audit/. Skipped without ZH_AUDIT (and when no CJK
// font is found on this machine): the font is a macOS system font loaded only
// here, never bundled into the app.
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wecord/features/auth/auth_repository.dart';
import 'package:wecord/features/notifications/local_notification_service.dart';
import 'package:wecord/features/notifications/notification_preferences_repository.dart';
import 'package:wecord/features/presence/presence_repository.dart';
import 'package:wecord/features/profile/profile_extras_repository.dart';
import 'package:wecord/features/settings/settings_repository.dart';
import 'package:wecord/features/settings/settings_screen.dart';
import 'package:wecord/shared/l10n/l10n.dart';
import 'package:wecord/shared/theme/glass_effects_controller.dart';
import 'package:wecord/shared/theme/theme_mode_controller.dart';
import 'package:wecord/shared/theme/wecord_theme.dart';

import '../features/presence/presence_repository_test.dart' as presence_fakes;
import '../features/profile/profile_extras_repository_test.dart';
import '../features/settings/settings_screen_test.dart' as settings_fakes;

const _fontCandidates = [
  '/System/Library/Fonts/Supplemental/Arial Unicode.ttf',
  '/Library/Fonts/Arial Unicode.ttf',
];

Future<bool> _loadCjkFont() async {
  for (final path in _fontCandidates) {
    final file = File(path);
    if (!file.existsSync()) {
      continue;
    }
    final bytes = file.readAsBytesSync();
    // Every family name the theme falls back to, so Chinese text finds it.
    for (final family in const [
      'Noto Sans SC',
      'PingFang SC',
      'Hiragino Sans GB',
      'Microsoft YaHei',
    ]) {
      final loader = FontLoader(
        family,
      )..addFont(Future.value(ByteData.sublistView(Uint8List.fromList(bytes))));
      await loader.load();
    }
    return true;
  }
  return false;
}

Widget _settings() {
  return ProviderScope(
    overrides: [
      profileExtrasRepositoryProvider.overrideWithValue(
        ProfileExtrasRepository(
          FakeProfileExtrasDataSource(),
          currentUserId: () => 'user-1',
          storagePathSeed: () => '7',
        ),
      ),
      presenceRepositoryProvider.overrideWithValue(
        presence_fakes.FakePresenceRepository(),
      ),
      settingsRepositoryProvider.overrideWithValue(
        settings_fakes.FakeSettingsRepository(),
      ),
      themeModeStoreProvider.overrideWithValue(InMemoryThemeModeStore()),
      glassEffectsStoreProvider.overrideWithValue(InMemoryGlassEffectsStore()),
      authRepositoryProvider.overrideWithValue(
        settings_fakes.FakeAuthRepository(),
      ),
      notificationPreferencesRepositoryProvider.overrideWithValue(
        NotificationPreferencesRepository.withStore(
          InMemoryNotificationPreferencesStore(),
        ),
      ),
      localNotificationServiceProvider.overrideWithValue(
        FakeLocalNotificationService(),
      ),
    ],
    child: MaterialApp(
      theme: WeCordTheme.light(),
      home: const SettingsScreen(),
    ),
  );
}

Future<void> _shoot(WidgetTester tester, Size size, String name) async {
  tester.view.physicalSize = size * 2;
  tester.view.devicePixelRatio = 2;
  final key = GlobalKey();
  await tester.pumpWidget(RepaintBoundary(key: key, child: _settings()));
  await tester.pump(const Duration(milliseconds: 600));
  final png = await tester.runAsync(() async {
    final boundary =
        key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    final image = await boundary.toImage(pixelRatio: 1);
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    return data!.buffer.asUint8List();
  });
  final directory = Directory('build/zh-audit')..createSync(recursive: true);
  File('${directory.path}/$name.png').writeAsBytesSync(png!);
}

void main() {
  final enabled = Platform.environment['ZH_AUDIT'] == '1';

  testWidgets('settings in Chinese', (tester) async {
    expect(await tester.runAsync(_loadCjkFont), isTrue);
    AppStrings.isChinese = true;
    addTearDown(() => AppStrings.isChinese = false);
    addTearDown(tester.view.reset);
    await _shoot(tester, const Size(390, 844), 'settings-phone');
  }, skip: !enabled);
}
