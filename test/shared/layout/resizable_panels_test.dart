import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wecord/shared/layout/panel_layout.dart';
import 'package:wecord/shared/layout/resizable_panels.dart';
import 'package:wecord/shared/theme/wecord_theme.dart';
import 'package:wecord/shared/ui/ui.dart';

const _sidebar = ValueKey('test-sidebar');
const _members = ValueKey('test-members');
final _sidebarDivider = find.byKey(const ValueKey('resize-sidebar'));
final _membersDivider = find.byKey(const ValueKey('resize-members'));

/// A sidebar, content and a member list like the circle workspace, in a
/// window [width] wide (right of the rail).
class _Harness extends ConsumerWidget {
  const _Harness();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final layout = ref.watch(panelLayoutProvider);
    return ResizableSidebarRow(
      sidebar: const ColoredBox(key: _sidebar, color: Color(0xFFEEEEEE)),
      content: LayoutBuilder(
        builder: (context, constraints) {
          final placement = resolveSidePanel(
            ResizablePanel.members,
            width: layout.membersWidth,
            collapsed: layout.membersCollapsed,
            rowWidth: constraints.maxWidth,
          );
          return ResizableSidePanelRow(
            panel: ResizablePanel.members,
            placement: placement,
            content: const SizedBox.expand(),
            side: const ColoredBox(key: _members, color: Color(0xFFDDDDDD)),
          );
        },
      ),
    );
  }
}

Future<InMemoryPanelLayoutStore> _pump(
  WidgetTester tester, {
  double width = 1200,
  PanelLayout? saved,
  bool reduceMotion = false,
}) async {
  tester.view.physicalSize = Size(width, 700);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final store = InMemoryPanelLayoutStore(saved);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [panelLayoutStoreProvider.overrideWithValue(store)],
      child: MaterialApp(
        theme: WeCordTheme.light(),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(disableAnimations: reduceMotion),
          child: child!,
        ),
        home: const Scaffold(body: _Harness()),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return store;
}

double _width(WidgetTester tester, Key key) =>
    tester.getSize(find.byKey(key)).width;

Future<void> _doubleTap(WidgetTester tester, Finder finder) async {
  await tester.tap(finder);
  await tester.pump(kDoubleTapMinTime);
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

FocusNode _focusOf(WidgetTester tester, Finder divider) {
  final focus = find.descendant(of: divider, matching: find.byType(Focus));
  return Focus.of(
    tester.element(
      find
          .descendant(of: focus.first, matching: find.byType(MouseRegion))
          .first,
    ),
  );
}

void main() {
  group('PanelLayout', () {
    test('reads saved widths clamped to their ranges', () {
      final layout = PanelLayout.fromJson({
        'sidebar': 9999,
        'members': 10,
        'profile': 'wide',
        'profileCollapsed': true,
      });
      expect(layout.sidebarWidth, WeCordSizes.sidebarMax);
      expect(layout.membersWidth, WeCordSizes.memberListMin);
      expect(layout.profileWidth, WeCordSizes.profilePanelDefault);
      expect(layout.profileCollapsed, isTrue);
      expect(layout.membersCollapsed, isFalse);
      expect(PanelLayout.fromJson(layout.toJson()), layout);
    });

    test('right panels close before the sidebar shrinks', () {
      // 1028 right of the rail: 292 + 248 + 420 fits.
      expect(resolveSidebarWidth(292, 1028), 292);
      expect(
        resolveSidePanel(
          ResizablePanel.members,
          width: 248,
          collapsed: false,
          rowWidth: 1028 - 292,
        ).shown,
        isTrue,
      );
      // 900: the member list closes, the sidebar keeps its width.
      expect(resolveSidebarWidth(292, 900), 292);
      expect(
        resolveSidePanel(
          ResizablePanel.members,
          width: 248,
          collapsed: false,
          rowWidth: 900 - 292,
        ).shown,
        isFalse,
      );
      // A wide sidebar gives way to keep the content at 420, down to 220.
      expect(resolveSidebarWidth(400, 700), 280);
      expect(resolveSidebarWidth(400, 500), WeCordSizes.sidebarMin);
      // Asked for while there isn't room, it shows at its minimum.
      final forced = resolveSidePanel(
        ResizablePanel.members,
        width: 300,
        collapsed: false,
        rowWidth: 560,
        forced: true,
      );
      expect(forced.shown, isTrue);
      expect(forced.width, WeCordSizes.memberListMin);
    });
  });

  testWidgets('dragging the divider resizes live and saves on release', (
    tester,
  ) async {
    final store = await _pump(tester);
    expect(_width(tester, _sidebar), 292);

    final gesture = await tester.startGesture(
      tester.getCenter(_sidebarDivider),
    );
    await gesture.moveBy(const Offset(30, 0));
    await gesture.moveBy(const Offset(30, 0));
    await tester.pump();
    // Live while dragging, not saved yet.
    expect(_width(tester, _sidebar), 352);
    expect(store.layout, isNull);

    await gesture.up();
    await tester.pumpAndSettle();
    expect(_width(tester, _sidebar), 352);
    expect(store.layout?.sidebarWidth, 352);
  });

  testWidgets('dragging past the range springs back to the limit', (
    tester,
  ) async {
    final store = await _pump(tester);
    final gesture = await tester.startGesture(
      tester.getCenter(_sidebarDivider),
    );
    await gesture.moveBy(const Offset(300, 0));
    await tester.pump();
    // A little past the maximum, with resistance.
    final stretched = _width(tester, _sidebar);
    expect(stretched, greaterThan(WeCordSizes.sidebarMax));
    expect(stretched, lessThan(WeCordSizes.sidebarMax + 17));

    await gesture.up();
    await tester.pumpAndSettle();
    expect(_width(tester, _sidebar), WeCordSizes.sidebarMax);
    expect(store.layout?.sidebarWidth, WeCordSizes.sidebarMax);
  });

  testWidgets('double-click resets the default width', (tester) async {
    final store = await _pump(
      tester,
      saved: const PanelLayout(sidebarWidth: 380, membersWidth: 300),
    );
    expect(_width(tester, _sidebar), 380);
    expect(_width(tester, _members), 300);

    await _doubleTap(tester, _sidebarDivider);
    expect(_width(tester, _sidebar), WeCordSizes.sidebarDefault);
    expect(store.layout?.sidebarWidth, WeCordSizes.sidebarDefault);

    await _doubleTap(tester, _membersDivider);
    expect(_width(tester, _members), WeCordSizes.memberListDefault);
    expect(store.layout?.membersWidth, WeCordSizes.memberListDefault);
  });

  testWidgets('a right panel widens to the left and closes when dragged '
      'shut', (tester) async {
    final store = await _pump(tester);
    expect(_width(tester, _members), 248);

    await tester.drag(_membersDivider, const Offset(-40, 0));
    await tester.pumpAndSettle();
    expect(_width(tester, _members), 288);
    expect(store.layout?.membersWidth, 288);

    // Below the minimum it holds on; past min − 60 it snaps shut.
    final gesture = await tester.startGesture(
      tester.getCenter(_membersDivider),
    );
    await gesture.moveBy(const Offset(110, 0));
    await tester.pump();
    expect(_width(tester, _members), greaterThan(170));
    await gesture.moveBy(const Offset(40, 0));
    await tester.pumpAndSettle();
    // Slid away under the edge of the window, still laid out at 200.
    expect(tester.getTopLeft(find.byKey(_members)).dx, 1200);
    expect(_width(tester, _members), 200);
    await gesture.up();
    await tester.pumpAndSettle();
    expect(store.layout?.membersCollapsed, isTrue);
    expect(find.byKey(_members), findsNothing);
    expect(_membersDivider, findsNothing);
    // The width it had stays for when it opens again.
    expect(store.layout?.membersWidth, 288);

    final container = ProviderScope.containerOf(
      tester.element(find.byType(_Harness)),
    );
    await container
        .read(panelLayoutProvider.notifier)
        .setCollapsed(ResizablePanel.members, false);
    await tester.pumpAndSettle();
    expect(_width(tester, _members), 288);
  });

  testWidgets('with reduced motion the width lands at once', (tester) async {
    final store = await _pump(tester, reduceMotion: true);
    final gesture = await tester.startGesture(
      tester.getCenter(_sidebarDivider),
    );
    await gesture.moveBy(const Offset(400, 0));
    await gesture.up();
    await tester.pump();
    expect(_width(tester, _sidebar), WeCordSizes.sidebarMax);
    expect(store.layout?.sidebarWidth, WeCordSizes.sidebarMax);
    await tester.pump(const Duration(seconds: 1));
  });

  testWidgets('the keyboard resizes: arrows, Home, End and Enter', (
    tester,
  ) async {
    final store = await _pump(tester);
    _focusOf(tester, _sidebarDivider).requestFocus();
    await tester.pump();

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pump();
    expect(_width(tester, _sidebar), 308);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    await tester.pump();
    expect(_width(tester, _sidebar), 276);
    expect(store.layout?.sidebarWidth, 276);

    await tester.sendKeyEvent(LogicalKeyboardKey.home);
    await tester.pump();
    expect(_width(tester, _sidebar), WeCordSizes.sidebarMin);
    await tester.sendKeyEvent(LogicalKeyboardKey.end);
    await tester.pump();
    expect(_width(tester, _sidebar), WeCordSizes.sidebarMax);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();
    expect(_width(tester, _sidebar), WeCordSizes.sidebarDefault);

    // The member list's edge is on its left: ← widens it.
    _focusOf(tester, _membersDivider).requestFocus();
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    await tester.pump();
    expect(_width(tester, _members), 264);
    expect(store.layout?.membersWidth, 264);
  });

  testWidgets('the divider reads as a slider with its width', (tester) async {
    final semantics = tester.ensureSemantics();
    await _pump(tester);
    final slider = find.bySemanticsLabel('Sidebar width');
    expect(
      tester.getSemantics(slider),
      isSemantics(
        isSlider: true,
        label: 'Sidebar width',
        value: '292 px',
        increasedValue: '308 px',
        decreasedValue: '276 px',
        hasIncreaseAction: true,
        hasDecreaseAction: true,
      ),
    );
    tester.semantics.increase(find.semantics.byLabel('Sidebar width'));
    await tester.pumpAndSettle();
    expect(_width(tester, _sidebar), 308);
    semantics.dispose();
  });

  testWidgets('hovering shows the accent line and the resize cursor', (
    tester,
  ) async {
    await _pump(tester);
    final mouse = await tester.createGesture(
      kind: PointerDeviceKind.mouse,
      pointer: 1,
    );
    await mouse.addPointer(location: tester.getCenter(_sidebarDivider));
    await tester.pump(const Duration(seconds: 1));
    await tester.pumpAndSettle();
    expect(
      RendererBinding.instance.mouseTracker.debugDeviceActiveCursor(1),
      SystemMouseCursors.resizeColumn,
    );
    final line = tester.widget<AnimatedContainer>(
      find.descendant(
        of: _sidebarDivider,
        matching: find.byType(AnimatedContainer),
      ),
    );
    expect(
      (line.decoration! as BoxDecoration).color,
      WeCordTokens.light.colors.accent,
    );
    expect(find.text('Drag to resize · double-click to reset'), findsOneWidget);
  });

  testWidgets('saved widths come back on launch', (tester) async {
    await _pump(
      tester,
      saved: const PanelLayout(sidebarWidth: 340, membersWidth: 320),
    );
    expect(_width(tester, _sidebar), 340);
    expect(_width(tester, _members), 320);
  });
}
