// H4: WeCord on an iPad. The Xcode project must target iPad (device family
// 1,2) in every orientation and allow Split View and Stage Manager (no
// UIRequiresFullScreen); the layout follows the window's width; a trackpad
// or mouse shows hover actions; the hardware keyboard's shortcuts are
// offered on tablets.
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wecord/features/chats/chats_screen.dart';
import 'package:wecord/features/chats/message_action_menu.dart';
import 'package:wecord/shared/layout/adaptive_layout.dart';
import 'package:wecord/shared/models/conversation.dart';

import '../mobile/phone_test_support.dart';

String _read(String path) => File(path).readAsStringSync();

const _ipadPortrait = PhoneViewport(
  name: '1024x1366',
  size: Size(1024, 1366),
  devicePixelRatio: 1,
  topInset: 24,
  bottomInset: 20,
);

const _splitView = PhoneViewport(
  name: '507x1366',
  size: Size(507, 1366),
  devicePixelRatio: 1,
  topInset: 24,
  bottomInset: 20,
);

void main() {
  group('iOS project', () {
    final plist = _read('ios/Runner/Info.plist');
    final project = _read('ios/Runner.xcodeproj/project.pbxproj');

    test('targets iPhone and iPad in every build configuration', () {
      final families = RegExp(
        r'TARGETED_DEVICE_FAMILY = "([^"]*)";',
      ).allMatches(project).map((m) => m.group(1)).toList();
      expect(families, isNotEmpty);
      expect(families.toSet(), {'1,2'});
    });

    test('iPad supports all four orientations', () {
      final block = RegExp(
        r'UISupportedInterfaceOrientations~ipad</key>\s*<array>(.*?)</array>',
        dotAll: true,
      ).firstMatch(plist)!.group(1)!;
      for (final orientation in [
        'Portrait',
        'PortraitUpsideDown',
        'LandscapeLeft',
        'LandscapeRight',
      ]) {
        expect(block, contains('UIInterfaceOrientation$orientation</string>'));
      }
    });

    test('allows Split View, Slide Over and Stage Manager resizing', () {
      // UIRequiresFullScreen would opt the app out of all of them.
      expect(plist, isNot(contains('UIRequiresFullScreen')));
      expect(plist, contains('UIApplicationSceneManifest'));
      expect(plist, contains('UIWindowSceneSessionRoleApplication'));
    });

    test('has the iPad home screen icons', () {
      final icons = _read(
        'ios/Runner/Assets.xcassets/AppIcon.appiconset/Contents.json',
      );
      expect(icons, contains('"idiom" : "ipad"'));
      expect(
        File(
          'ios/Runner/Assets.xcassets/AppIcon.appiconset/'
          'Icon-App-83.5x83.5@2x.png',
        ).existsSync(),
        isTrue,
      );
    });
  });

  group('layout follows the window width', () {
    test(
      'Split View windows use the phone layout, a full iPad the desktop one',
      () {
        expect(isCompactWidth(507), isTrue);
        expect(isWideLayout(507), isFalse);
        // iPad Air and 11" Pro in portrait: not compact, not yet desktop.
        expect(isCompactWidth(834), isFalse);
        expect(isWideLayout(834), isFalse);
        expect(isWideLayout(1024), isTrue);
        expect(isWideLayout(1366), isTrue);
      },
    );
  });

  group('keyboard shortcuts are offered', () {
    Future<bool> offered(
      WidgetTester tester,
      TargetPlatform platform,
      Size size,
    ) async {
      late bool result;
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(platform: platform),
          home: MediaQuery(
            data: MediaQueryData(size: size),
            child: Builder(
              builder: (context) {
                result = usesKeyboardShortcuts(context);
                return const SizedBox.shrink();
              },
            ),
          ),
        ),
      );
      return result;
    }

    testWidgets('on desktops', (tester) async {
      expect(
        await offered(tester, TargetPlatform.macOS, const Size(1440, 900)),
        isTrue,
      );
    });

    testWidgets('on an iPad, even in a narrow Split View window', (
      tester,
    ) async {
      expect(
        await offered(tester, TargetPlatform.iOS, const Size(1024, 1366)),
        isTrue,
      );
      expect(
        await offered(tester, TargetPlatform.iOS, const Size(507, 1366)),
        isTrue,
      );
      expect(
        await offered(tester, TargetPlatform.iOS, const Size(1366, 1024)),
        isTrue,
      );
    });

    testWidgets('not on phones', (tester) async {
      for (final size in const [
        Size(390, 844),
        Size(844, 390),
        Size(430, 932),
        Size(360, 640),
      ]) {
        expect(await offered(tester, TargetPlatform.iOS, size), isFalse);
        expect(await offered(tester, TargetPlatform.android, size), isFalse);
      }
    });
  });

  group('on an iPad', () {
    setUp(() => debugDefaultTargetPlatformOverride = TargetPlatform.iOS);
    // Reset in the body: the binding checks the override before tearDown.

    testWidgets('a trackpad hovering a message shows its actions', (
      tester,
    ) async {
      usePhoneViewport(tester, _ipadPortrait);
      final world = PhoneWorld();
      world.chats.messages = richMessages();
      await world.open(
        tester,
        '${ChatsScreen.path}/dm-1',
        extra: ChatThreadRouteExtra(
          title: bart.displayName,
          type: ConversationType.direct,
        ),
      );
      expect(find.byType(MessageHoverToolbar), findsNothing);

      final pointer = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await pointer.addPointer(location: Offset.zero);
      await pointer.moveTo(tester.getCenter(find.text('Forwarding this one.')));
      await settle(tester);
      expect(find.byType(MessageHoverToolbar), findsOneWidget);

      await pointer.moveTo(const Offset(5, 5));
      await settle(tester);
      expect(find.byType(MessageHoverToolbar), findsNothing);
      await pointer.removePointer();
      await world.close(tester);
      debugDefaultTargetPlatformOverride = null;
    });

    testWidgets('a finger never shows hover actions', (tester) async {
      usePhoneViewport(tester, _ipadPortrait);
      final world = PhoneWorld();
      world.chats.messages = richMessages();
      await world.open(
        tester,
        '${ChatsScreen.path}/dm-1',
        extra: ChatThreadRouteExtra(
          title: bart.displayName,
          type: ConversationType.direct,
        ),
      );
      await tester.tap(find.text('Forwarding this one.'));
      await settle(tester);
      expect(find.byType(MessageHoverToolbar), findsNothing);
      await world.close(tester);
      debugDefaultTargetPlatformOverride = null;
    });

    testWidgets('the chat re-lays out when the window narrows (Split View)', (
      tester,
    ) async {
      usePhoneViewport(tester, _ipadPortrait);
      final world = PhoneWorld();
      world.chats.messages = richMessages();
      await world.open(
        tester,
        '${ChatsScreen.path}/dm-1',
        extra: ChatThreadRouteExtra(
          title: bart.displayName,
          type: ConversationType.direct,
        ),
      );
      // The desktop layout keeps the conversation list beside the chat.
      expect(find.text('Messages'), findsWidgets);
      expect(find.text('Forwarding this one.'), findsOneWidget);

      tester.view.physicalSize = _splitView.size;
      await settle(tester);
      // Phone layout: the chat fills the window, nothing is lost.
      expect(find.text('Forwarding this one.'), findsOneWidget);
      expect(tester.takeException(), isNull);

      tester.view.physicalSize = _ipadPortrait.size;
      await settle(tester);
      expect(find.text('Forwarding this one.'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await world.close(tester);
      debugDefaultTargetPlatformOverride = null;
    });
  });
}
