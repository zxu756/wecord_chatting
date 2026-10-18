import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:wecord/features/pwa/install_app_tile.dart';
import 'package:wecord/features/pwa/pwa_detect.dart';
import 'package:wecord/features/pwa/pwa_gateway.dart';
import 'package:wecord/features/pwa/pwa_overlay.dart';
import 'package:wecord/features/pwa/pwa_providers.dart';
import 'package:wecord/features/pwa/pwa_shell_listener.dart';
import 'package:wecord/shared/l10n/l10n.dart';
import 'package:wecord/shared/theme/wecord_theme.dart';

class FakePwaGateway implements PwaGateway {
  FakePwaGateway([this._state = const PwaState()]);

  PwaState _state;
  final _changes = StreamController<PwaState>.broadcast();
  var installs = 0;
  var updates = 0;
  PwaInstallOutcome outcome = PwaInstallOutcome.accepted;
  final badges = <int>[];

  void emit(PwaState next) {
    _state = next;
    _changes.add(next);
  }

  @override
  PwaState get state => _state;

  @override
  Stream<PwaState> get changes => _changes.stream;

  @override
  Future<PwaInstallOutcome> promptInstall() async {
    installs++;
    return outcome;
  }

  @override
  Future<void> applyUpdate() async => updates++;

  @override
  void setBadge(int count) => badges.add(count);
}

class FakeHintStore implements PwaHintStore {
  FakeHintStore({this.dismissed = false});

  bool dismissed;

  @override
  Future<bool> isDismissed() async => dismissed;

  @override
  Future<void> dismiss() async => dismissed = true;
}

Future<void> pump(
  WidgetTester tester,
  FakePwaGateway gateway,
  Widget child, {
  FakeHintStore? hints,
  List<Override> overrides = const [],
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        pwaGatewayProvider.overrideWithValue(gateway),
        pwaHintStoreProvider.overrideWithValue(hints ?? FakeHintStore()),
        ...overrides,
      ],
      child: MaterialApp(
        theme: WeCordTheme.light(),
        home: Scaffold(body: child),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  tearDown(() => AppStrings.isChinese = false);

  group('isIosSafariUserAgent', () {
    const safariPhone =
        'Mozilla/5.0 (iPhone; CPU iPhone OS 17_5 like Mac OS X) AppleWebKit/605.1.15 '
        '(KHTML, like Gecko) Version/17.5 Mobile/15E148 Safari/604.1';
    const chromeOnPhone =
        'Mozilla/5.0 (iPhone; CPU iPhone OS 17_5 like Mac OS X) AppleWebKit/605.1.15 '
        '(KHTML, like Gecko) CriOS/126.0.0.0 Mobile/15E148 Safari/604.1';
    const macSafari =
        'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 '
        '(KHTML, like Gecko) Version/17.5 Safari/605.1.15';

    test('iPhone Safari', () {
      expect(isIosSafariUserAgent(safariPhone), isTrue);
    });

    test('iPadOS reports a Mac, told apart by touch', () {
      expect(isIosSafariUserAgent(macSafari, maxTouchPoints: 5), isTrue);
      expect(isIosSafariUserAgent(macSafari), isFalse);
    });

    test('other browsers on iOS and desktop browsers are not it', () {
      expect(isIosSafariUserAgent(chromeOnPhone), isFalse);
      expect(
        isIosSafariUserAgent(
          'Mozilla/5.0 (Windows NT 10.0) Chrome/126 Edg/126',
        ),
        isFalse,
      );
    });
  });

  test('titleWithUnread', () {
    expect(titleWithUnread('WeCord', 0), 'WeCord');
    expect(titleWithUnread('WeCord', 3), '(3) WeCord');
    expect(titleWithUnread('WeCord', 250), '(99+) WeCord');
  });

  group('update toast', () {
    testWidgets('appears when the worker says an update is ready', (
      tester,
    ) async {
      final gateway = FakePwaGateway();
      await pump(tester, gateway, const PwaOverlayHost(child: Text('app')));
      expect(find.byKey(const ValueKey('pwa-update-toast')), findsNothing);

      gateway.emit(const PwaState(updateReady: true));
      await tester.pumpAndSettle();

      expect(find.text('Update available'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('pwa-update-reload')));
      await tester.pump();
      expect(gateway.updates, 1);
    });

    testWidgets('is there from the start when an update was waiting', (
      tester,
    ) async {
      await pump(
        tester,
        FakePwaGateway(const PwaState(updateReady: true)),
        const PwaOverlayHost(child: Text('app')),
      );
      expect(find.text('Update available'), findsOneWidget);
    });

    testWidgets('reads in Chinese', (tester) async {
      AppStrings.isChinese = true;
      await pump(
        tester,
        FakePwaGateway(const PwaState(updateReady: true)),
        const PwaOverlayHost(child: Text('app')),
      );
      expect(find.text('有可用更新'), findsOneWidget);
      expect(find.text('刷新'), findsOneWidget);
    });
  });

  group('iOS hint', () {
    const ios = PwaState(iosSafari: true);

    testWidgets('shows once in iOS Safari and stays gone once dismissed', (
      tester,
    ) async {
      final hints = FakeHintStore();
      await pump(
        tester,
        FakePwaGateway(ios),
        const PwaOverlayHost(child: Text('app')),
        hints: hints,
      );
      expect(find.byKey(const ValueKey('pwa-ios-hint')), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('pwa-ios-hint-dismiss')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('pwa-ios-hint')), findsNothing);
      expect(hints.dismissed, isTrue);

      // The next start reads the saved choice.
      await pump(
        tester,
        FakePwaGateway(ios),
        const PwaOverlayHost(child: Text('app')),
        hints: hints,
      );
      expect(find.byKey(const ValueKey('pwa-ios-hint')), findsNothing);
    });

    testWidgets('never shows elsewhere', (tester) async {
      await pump(
        tester,
        FakePwaGateway(),
        const PwaOverlayHost(child: Text('app')),
      );
      expect(find.byKey(const ValueKey('pwa-ios-hint')), findsNothing);
    });
  });

  group('install entry', () {
    testWidgets('offers the browser prompt where it exists', (tester) async {
      final gateway = FakePwaGateway(const PwaState(canInstall: true));
      await pump(tester, gateway, const InstallAppTile());

      expect(find.text('Install WeCord'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('install-app')));
      await tester.pump();
      expect(gateway.installs, 1);
    });

    testWidgets('hides when installed already', (tester) async {
      await pump(
        tester,
        FakePwaGateway(const PwaState(standalone: true, canInstall: true)),
        const InstallAppTile(),
      );
      expect(find.text('Install WeCord'), findsNothing);
    });

    testWidgets('hides where the browser offers no install', (tester) async {
      await pump(tester, FakePwaGateway(), const InstallAppTile());
      expect(find.text('Install WeCord'), findsNothing);
    });

    testWidgets('on iOS Safari explains Share, Add to Home Screen', (
      tester,
    ) async {
      await pump(
        tester,
        FakePwaGateway(const PwaState(iosSafari: true)),
        const InstallAppTile(),
      );
      expect(find.byKey(const ValueKey('install-app-ios')), findsOneWidget);
      expect(find.text('Tap Share, then Add to Home Screen.'), findsOneWidget);
    });

    testWidgets('appears when the browser fires beforeinstallprompt late', (
      tester,
    ) async {
      final gateway = FakePwaGateway();
      await pump(tester, gateway, const InstallAppGroup());
      expect(find.text('Install WeCord'), findsNothing);

      gateway.emit(const PwaState(canInstall: true));
      await tester.pumpAndSettle();
      expect(find.text('Install WeCord'), findsOneWidget);

      gateway.emit(const PwaState(standalone: true));
      await tester.pumpAndSettle();
      expect(find.text('Install WeCord'), findsNothing);
    });
  });

  group('app badge', () {
    testWidgets('follows the unread count and clears on leaving', (
      tester,
    ) async {
      final gateway = FakePwaGateway();
      await pump(
        tester,
        gateway,
        const PwaShellListener(child: Text('shell')),
        overrides: [
          appBadgeCountProvider.overrideWith((ref) => ref.watch(_unread)),
        ],
      );
      expect(gateway.badges, [0]);

      final container = ProviderScope.containerOf(
        tester.element(find.byType(PwaShellListener)),
      );
      container.read(_unread.notifier).value = 4;
      await tester.pump();
      container.read(_unread.notifier).value = 0;
      await tester.pump();
      container.read(_unread.notifier).value = 7;
      await tester.pump();
      expect(gateway.badges, [0, 4, 0, 7]);

      await tester.pumpWidget(const SizedBox());
      await tester.pump();
      expect(gateway.badges.last, 0);
    });
  });
}

final _unread = NotifierProvider<_Unread, int>(_Unread.new);

class _Unread extends Notifier<int> {
  @override
  int build() => 0;

  set value(int next) => state = next;
}
