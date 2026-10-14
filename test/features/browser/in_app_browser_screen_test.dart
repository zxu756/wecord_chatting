import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:webview_flutter_platform_interface/webview_flutter_platform_interface.dart';
import 'package:wecord/features/browser/in_app_browser_screen.dart';
import 'package:wecord/features/chats/message_markdown_text.dart';

void main() {
  late FakeWebViewPlatform platform;

  setUp(() {
    platform = FakeWebViewPlatform();
    WebViewPlatform.instance = platform;
  });

  Future<void> openBrowser(WidgetTester tester, String url) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: TextButton(
                onPressed: () => openInAppBrowser(context, Uri.parse(url)),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await settle(tester);
  }

  test('only web pages open in the browser', () {
    expect(isWebPageUri(Uri.parse('https://example.com/a')), isTrue);
    expect(isWebPageUri(Uri.parse('http://example.com')), isTrue);
    expect(isWebPageUri(Uri.parse('mailto:ada@example.com')), isFalse);
    expect(isWebPageUri(Uri.parse('tel:+15550100')), isFalse);
    expect(isWebPageUri(Uri.parse('https:///no-host')), isFalse);
  });

  testWidgets('loads the link and shows its host, then the page title', (
    tester,
  ) async {
    await openBrowser(tester, 'https://example.com/docs');

    expect(platform.controller.loadedUris, [
      Uri.parse('https://example.com/docs'),
    ]);
    expect(find.byType(InAppBrowserScreen), findsOneWidget);
    expect(find.byKey(const ValueKey('browser-progress')), findsOneWidget);
    expect(
      tester.widget<Text>(find.byKey(const ValueKey('browser-title'))).data,
      'example.com',
    );

    platform.controller.title = 'Example Docs';
    platform.delegate.finishPage('https://example.com/docs');
    await settle(tester);

    expect(
      tester.widget<Text>(find.byKey(const ValueKey('browser-title'))).data,
      'Example Docs',
    );
    expect(
      tester.widget<Text>(find.byKey(const ValueKey('browser-host'))).data,
      'example.com',
    );
    expect(find.byKey(const ValueKey('browser-progress')), findsNothing);
  });

  testWidgets('back and forward follow the page history', (tester) async {
    await openBrowser(tester, 'https://example.com');

    IconButton button(String key) =>
        tester.widget<IconButton>(find.byKey(ValueKey(key)));
    expect(button('browser-back').onPressed, isNull);
    expect(button('browser-forward').onPressed, isNull);

    platform.controller.canGoBackValue = true;
    platform.delegate.finishPage('https://example.org/next');
    await settle(tester);

    expect(
      tester.widget<Text>(find.byKey(const ValueKey('browser-host'))).data,
      'example.org',
    );
    expect(button('browser-back').onPressed, isNotNull);
    await tester.tap(find.byKey(const ValueKey('browser-back')));
    await tester.pump();
    expect(platform.controller.backCount, 1);

    // The system back gesture also goes back in the page first.
    final popped = await tester.binding.handlePopRoute();
    await tester.pump();
    expect(popped, isTrue);
    expect(platform.controller.backCount, 2);
    expect(find.byType(InAppBrowserScreen), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('browser-reload')));
    await tester.pump();
    expect(platform.controller.reloadCount, 1);
  });

  testWidgets('close leaves the browser', (tester) async {
    await openBrowser(tester, 'https://example.com');

    await tester.tap(find.byKey(const ValueKey('browser-close')));
    await settle(tester);

    expect(find.byType(InAppBrowserScreen), findsNothing);
    expect(find.text('open'), findsOneWidget);
  });

  testWidgets('non-web links are kept out of the page', (tester) async {
    await openBrowser(tester, 'https://example.com');

    Future<NavigationDecision> decide(String url) async =>
        platform.delegate.onNavigationRequest!(
          NavigationRequest(url: url, isMainFrame: false),
        );

    expect(await decide('https://example.com/b'), NavigationDecision.navigate);
    expect(await decide('about:blank'), NavigationDecision.navigate);
    expect(await decide('mailto:ada@example.com'), NavigationDecision.prevent);
    expect(
      await decide('intent://scan/#Intent;end'),
      NavigationDecision.prevent,
    );
  });

  testWidgets('a failed page offers to retry', (tester) async {
    await openBrowser(tester, 'https://example.com');

    platform.delegate.onWebResourceError!(
      const WebResourceError(
        errorCode: -1009,
        description: 'The Internet connection appears to be offline.',
        isForMainFrame: true,
      ),
    );
    await settle(tester);

    expect(find.byKey(const ValueKey('browser-error')), findsOneWidget);
    expect(
      find.text('The Internet connection appears to be offline.'),
      findsOneWidget,
    );

    await tester.tap(find.text('Try again'));
    await settle(tester);
    expect(platform.controller.reloadCount, 1);
    expect(find.byKey(const ValueKey('browser-error')), findsNothing);
  });

  testWidgets('tapped message links open in the in-app browser', (
    tester,
  ) async {
    await tester.pumpWidget(
      const ProviderScope(
        child: MaterialApp(
          home: Scaffold(
            body: Center(
              child: MessageMarkdownText(
                body: 'see https://example.com/page',
                color: Colors.black,
              ),
            ),
          ),
        ),
      ),
    );

    final container = ProviderScope.containerOf(
      tester.element(find.byType(MessageMarkdownText)),
    );
    // The launcher finishes when the browser closes.
    unawaited(
      container.read(linkLauncherProvider)(
        tester.element(find.byType(MessageMarkdownText)),
        Uri.parse('https://example.com/page'),
      ),
    );
    await settle(tester);

    expect(find.byType(InAppBrowserScreen), findsOneWidget);
    expect(platform.controller.loadedUris, [
      Uri.parse('https://example.com/page'),
    ]);
  });
}

class FakeWebViewPlatform extends WebViewPlatform {
  late FakeWebViewController controller;
  late FakeNavigationDelegate delegate;

  @override
  PlatformWebViewController createPlatformWebViewController(
    PlatformWebViewControllerCreationParams params,
  ) {
    return controller = FakeWebViewController(params);
  }

  @override
  PlatformNavigationDelegate createPlatformNavigationDelegate(
    PlatformNavigationDelegateCreationParams params,
  ) {
    return delegate = FakeNavigationDelegate(params);
  }

  @override
  PlatformWebViewWidget createPlatformWebViewWidget(
    PlatformWebViewWidgetCreationParams params,
  ) {
    return FakeWebViewWidget(params);
  }
}

class FakeWebViewController extends PlatformWebViewController {
  FakeWebViewController(super.params) : super.implementation();

  final loadedUris = <Uri>[];
  String? title;
  var canGoBackValue = false;
  var canGoForwardValue = false;
  var backCount = 0;
  var reloadCount = 0;

  @override
  Future<void> setJavaScriptMode(JavaScriptMode javaScriptMode) async {}

  @override
  Future<void> setPlatformNavigationDelegate(
    PlatformNavigationDelegate handler,
  ) async {}

  @override
  Future<void> loadRequest(LoadRequestParams params) async {
    loadedUris.add(params.uri);
  }

  @override
  Future<String?> getTitle() async => title;

  @override
  Future<bool> canGoBack() async => canGoBackValue;

  @override
  Future<bool> canGoForward() async => canGoForwardValue;

  @override
  Future<void> goBack() async => backCount++;

  @override
  Future<void> reload() async => reloadCount++;
}

class FakeNavigationDelegate extends PlatformNavigationDelegate {
  FakeNavigationDelegate(super.params) : super.implementation();

  NavigationRequestCallback? onNavigationRequest;
  PageEventCallback? onPageStarted;
  PageEventCallback? onPageFinished;
  ProgressCallback? onProgress;
  WebResourceErrorCallback? onWebResourceError;
  UrlChangeCallback? onUrlChange;

  void finishPage(String url) {
    onProgress?.call(100);
    onPageFinished?.call(url);
  }

  @override
  Future<void> setOnNavigationRequest(
    NavigationRequestCallback onNavigationRequest,
  ) async {
    this.onNavigationRequest = onNavigationRequest;
  }

  @override
  Future<void> setOnPageStarted(PageEventCallback onPageStarted) async {
    this.onPageStarted = onPageStarted;
  }

  @override
  Future<void> setOnPageFinished(PageEventCallback onPageFinished) async {
    this.onPageFinished = onPageFinished;
  }

  @override
  Future<void> setOnProgress(ProgressCallback onProgress) async {
    this.onProgress = onProgress;
  }

  @override
  Future<void> setOnWebResourceError(
    WebResourceErrorCallback onWebResourceError,
  ) async {
    this.onWebResourceError = onWebResourceError;
  }

  @override
  Future<void> setOnUrlChange(UrlChangeCallback onUrlChange) async {
    this.onUrlChange = onUrlChange;
  }
}

class FakeWebViewWidget extends PlatformWebViewWidget {
  FakeWebViewWidget(super.params) : super.implementation();

  @override
  Widget build(BuildContext context) {
    return const ColoredBox(
      key: ValueKey('fake-web-view'),
      color: Colors.white,
    );
  }
}

/// Lets route transitions finish; the loading bar animates until a page
/// finishes, so the tester can't wait for everything to settle.
Future<void> settle(WidgetTester tester) async {
  for (var frame = 0; frame < 10; frame++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}
