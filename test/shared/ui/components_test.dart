import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wecord/shared/theme/wecord_theme.dart';
import 'package:wecord/shared/ui/ui.dart';

Widget _host(Widget child, {bool glass = true, bool dark = false}) {
  return MaterialApp(
    theme: dark ? WeCordTheme.dark() : WeCordTheme.light(),
    home: WeCordAppearance(
      glassEffects: glass,
      child: Scaffold(body: Center(child: child)),
    ),
  );
}

void main() {
  testWidgets('buttons press, and do nothing when disabled', (tester) async {
    var presses = 0;
    await tester.pumpWidget(
      _host(
        Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            WeCordButton(label: 'Sign in', onPressed: () => presses++),
            const WeCordButton(label: 'Later', onPressed: null),
            WeCordIconButton(
              icon: Icons.search,
              tooltip: 'Search',
              onPressed: () => presses++,
              badgeCount: 4,
            ),
          ],
        ),
      ),
    );

    await tester.tap(find.text('Sign in'));
    await tester.tap(find.text('Later'));
    await tester.tap(find.byTooltip('Search'));
    await tester.pumpAndSettle();

    expect(presses, 2);
    expect(find.text('4'), findsOneWidget);
    // The 40 round button is padded to the platform's touch target (48 on
    // Android, which is what widget tests run as).
    expect(tester.getSize(find.byType(WeCordIconButton)).height, 48);
  });

  testWidgets('a button activates from the keyboard', (tester) async {
    var presses = 0;
    final focus = FocusNode();
    addTearDown(focus.dispose);
    await tester.pumpWidget(
      _host(
        WeCordButton(
          label: 'Save',
          focusNode: focus,
          onPressed: () => presses++,
        ),
      ),
    );
    focus.requestFocus();
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();

    expect(presses, 1);
  });

  testWidgets('switch, segmented control and chip report changes', (
    tester,
  ) async {
    var on = false;
    var mode = 'light';
    var chipTaps = 0;
    await tester.pumpWidget(
      _host(
        StatefulBuilder(
          builder: (context, setState) => Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              WeCordSwitch(
                key: const ValueKey('switch'),
                value: on,
                onChanged: (value) => setState(() => on = value),
              ),
              WeCordSegmented<String>(
                segments: const [
                  WeCordSegment(value: 'light', label: 'Light'),
                  WeCordSegment(value: 'dark', label: 'Dark'),
                ],
                selected: mode,
                onChanged: (value) => setState(() => mode = value),
              ),
              WeCordChip(
                label: 'Mentions',
                count: 2,
                onPressed: () => chipTaps++,
              ),
            ],
          ),
        ),
      ),
    );

    await tester.tap(find.byKey(const ValueKey('switch')));
    await tester.tap(find.text('Dark'));
    await tester.tap(find.text('Mentions 2'));
    await tester.pumpAndSettle();

    expect(on, isTrue);
    expect(mode, 'dark');
    expect(chipTaps, 1);
  });

  testWidgets('settings rows open, toggle and group with separators', (
    tester,
  ) async {
    var opened = 0;
    var push = false;
    await tester.pumpWidget(
      _host(
        StatefulBuilder(
          builder: (context, setState) => SettingsGroup(
            header: 'Preferences',
            children: [
              SettingsRow(
                icon: Icons.language,
                title: 'Language',
                value: 'English',
                onTap: () => opened++,
              ),
              SettingsRow.toggle(
                icon: Icons.notifications_outlined,
                title: 'Push notifications',
                value: push,
                onChanged: (value) => setState(() => push = value),
              ),
            ],
          ),
        ),
      ),
    );

    expect(find.text('Preferences'), findsOneWidget);
    expect(find.byIcon(Icons.chevron_right_rounded), findsOneWidget);

    await tester.tap(find.text('Language'));
    await tester.tap(find.text('Push notifications'));
    await tester.pumpAndSettle();

    expect(opened, 1);
    expect(push, isTrue);
  });

  testWidgets('glass blurs only while glass effects are on', (tester) async {
    const panel = WeCordGlass(child: SizedBox(width: 200, height: 60));

    await tester.pumpWidget(_host(panel));
    expect(find.byType(BackdropFilter), findsOneWidget);

    await tester.pumpWidget(_host(panel, glass: false));
    expect(find.byType(BackdropFilter), findsNothing);
  });

  testWidgets('avatars, badges and the user panel lay out', (tester) async {
    await tester.pumpWidget(
      _host(
        SizedBox(
          width: 320,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Row(
                children: [
                  PersonAvatar(name: 'lin xiao', presence: Colors.green),
                  ThingAvatar(
                    label: '徒步',
                    badge: CountBadge(count: 120, ringColor: Colors.white),
                  ),
                ],
              ),
              FloatingUserPanel(
                avatar: const PersonAvatar(name: 'Ada', size: 46),
                title: 'Ada Lovelace',
                subtitle: 'Online',
                onTap: () {},
                actions: [
                  WeCordIconButton(
                    icon: Icons.notifications_none,
                    tooltip: 'Notifications',
                    onPressed: () {},
                  ),
                ],
              ),
            ],
          ),
        ),
        dark: true,
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('L'), findsOneWidget);
    expect(find.text('徒'), findsOneWidget);
    expect(find.text('99+'), findsOneWidget);
    expect(find.text('Ada Lovelace'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('sheets show a grabber and title, with or without detents', (
    tester,
  ) async {
    await tester.pumpWidget(
      _host(
        Builder(
          builder: (context) => Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextButton(
                onPressed: () => showWeCordSheet<void>(
                  context,
                  title: 'Fitted',
                  builder: (context, _) => const Text('Small content'),
                ),
                child: const Text('Open fitted'),
              ),
              TextButton(
                onPressed: () => showWeCordSheet<void>(
                  context,
                  title: 'Tall',
                  detents: const [0.5, 0.9],
                  builder: (context, controller) => ListView(
                    controller: controller,
                    children: const [Text('Row 1')],
                  ),
                ),
                child: const Text('Open tall'),
              ),
            ],
          ),
        ),
      ),
    );

    await tester.tap(find.text('Open fitted'));
    await tester.pumpAndSettle();
    expect(find.text('Fitted'), findsOneWidget);
    expect(find.text('Small content'), findsOneWidget);
    Navigator.of(tester.element(find.text('Small content'))).pop();
    await tester.pumpAndSettle();

    await tester.tap(find.text('Open tall'));
    await tester.pumpAndSettle();
    expect(find.text('Tall'), findsOneWidget);
    expect(find.text('Row 1'), findsOneWidget);
    expect(find.byType(DraggableScrollableSheet), findsOneWidget);
  });

  test('springs settle in a sensible time and end at 1', () {
    for (final spring in [
      WeCordMotion.snappy,
      WeCordMotion.smooth,
      WeCordMotion.bouncy,
    ]) {
      expect(spring.duration.inMilliseconds, inInclusiveRange(150, 900));
      expect(spring.curve.transform(1), 1);
      expect(spring.curve.transform(0), 0);
    }
  });

  testWidgets('the macOS app keeps the title bar strip clear', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    late EdgeInsets padding;
    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) => MacosTitleBarFrame(child: child!),
        home: Builder(
          builder: (context) {
            padding = MediaQuery.paddingOf(context);
            return const SizedBox();
          },
        ),
      ),
    );
    expect(padding.top, WeCordSizes.macosTitleBar);
    expect(find.byType(MacosWindowDragArea), findsOneWidget);
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('segment labels shrink to fit instead of being cut off', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(330, 400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MediaQuery(
        data: const MediaQueryData(
          size: Size(330, 400),
          textScaler: TextScaler.linear(1.3),
        ),
        child: _host(
          SizedBox(
            width: 300,
            child: WeCordSegmented<int>(
              expand: true,
              selected: 1,
              onChanged: (_) {},
              segments: const [
                WeCordSegment(value: 0, label: 'Comfortable'),
                WeCordSegment(value: 1, label: 'Default'),
                WeCordSegment(value: 2, label: 'Compact'),
              ],
            ),
          ),
        ),
      ),
    );

    // No overflow errors, no ellipsis: the text is the whole word and
    // scaled down into its segment.
    expect(tester.takeException(), isNull);
    final label = tester.widget<Text>(find.text('Comfortable'));
    expect(label.overflow, isNot(TextOverflow.ellipsis));
    expect(label.softWrap, isFalse);
    final segment = tester.getRect(
      find.ancestor(
        of: find.text('Comfortable'),
        matching: find.byType(WeCordPressable),
      ),
    );
    expect(
      segment.contains(tester.getRect(find.text('Comfortable')).topLeft),
      isTrue,
    );
    expect(
      segment.contains(tester.getRect(find.text('Comfortable')).bottomRight),
      isTrue,
    );
    expect(find.bySemanticsLabel('Comfortable'), findsOneWidget);
  });

  for (final dark in [false, true]) {
    testWidgets('only mentions are red: badges are gray unless told otherwise '
        '(${dark ? 'dark' : 'light'})', (tester) async {
      await tester.pumpWidget(
        _host(
          const Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CountBadge(count: 3, key: ValueKey('plain')),
              CountBadge(
                count: 4,
                tone: BadgeTone.mention,
                key: ValueKey('mention'),
              ),
              CountBadge.dot(key: ValueKey('dot')),
            ],
          ),
          dark: dark,
        ),
      );
      await tester.pumpAndSettle();
      final colors = (dark ? WeCordTokens.dark : WeCordTokens.light).colors;
      Color fillOf(String key) {
        final box = tester.widget<Container>(
          find.descendant(
            of: find.byKey(ValueKey(key)),
            matching: find.byType(Container),
          ),
        );
        return (box.decoration! as BoxDecoration).color!;
      }

      expect(fillOf('plain'), colors.badgeUnread);
      expect(fillOf('dot'), colors.badgeUnread);
      expect(fillOf('mention'), colors.badgeMention);
      expect(colors.badgeUnread, isNot(colors.badgeMention));
    });
  }
}
