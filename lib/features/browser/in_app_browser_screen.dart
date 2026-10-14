import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:webview_flutter/webview_flutter.dart';

/// Whether links open in WeCord's own browser here. Web pages can't embed
/// most sites (they forbid framing), so the web app opens a new tab, as do
/// desktop platforms without a web view.
bool get inAppBrowserSupported {
  if (kIsWeb) {
    return false;
  }
  return switch (defaultTargetPlatform) {
    TargetPlatform.android ||
    TargetPlatform.iOS ||
    TargetPlatform.macOS => true,
    _ => false,
  };
}

/// Web pages (http and https) open in the browser; mail, phone and app
/// links go to the system.
bool isWebPageUri(Uri uri) {
  return (uri.scheme == 'http' || uri.scheme == 'https') && uri.host.isNotEmpty;
}

/// Shows [uri] in the in-app browser over the whole window.
Future<void> openInAppBrowser(BuildContext context, Uri uri) {
  return Navigator.of(context, rootNavigator: true).push(
    MaterialPageRoute<void>(
      fullscreenDialog: true,
      builder: (context) => InAppBrowserScreen(initialUri: uri),
    ),
  );
}

Future<void> _openExternally(Uri uri) async {
  try {
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  } on Object {
    // Nothing handles the link; the page stays as it is.
  }
}

/// A web page opened from a message, with its title and address on top
/// and back, forward, reload and "open in browser" below.
class InAppBrowserScreen extends StatefulWidget {
  const InAppBrowserScreen({required this.initialUri, super.key});

  final Uri initialUri;

  @override
  State<InAppBrowserScreen> createState() => _InAppBrowserScreenState();
}

class _InAppBrowserScreenState extends State<InAppBrowserScreen> {
  late final WebViewController _controller;
  late Uri _currentUri = widget.initialUri;
  String? _pageTitle;
  var _progress = 0;
  var _canGoBack = false;
  var _canGoForward = false;
  String? _errorText;

  @override
  void initState() {
    super.initState();
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setNavigationDelegate(
        NavigationDelegate(
          onNavigationRequest: _onNavigationRequest,
          onPageStarted: (url) {
            _setUrl(url);
            if (mounted) {
              setState(() => _errorText = null);
            }
          },
          onProgress: (progress) {
            if (mounted) {
              setState(() => _progress = progress);
            }
          },
          onPageFinished: (url) {
            _setUrl(url);
            unawaited(_refreshState());
          },
          onUrlChange: (change) {
            if (change.url case final url?) {
              _setUrl(url);
            }
            unawaited(_refreshState());
          },
          onWebResourceError: (error) {
            if (error.isForMainFrame != false && mounted) {
              setState(() => _errorText = error.description);
            }
          },
        ),
      )
      ..loadRequest(widget.initialUri);
  }

  NavigationDecision _onNavigationRequest(NavigationRequest request) {
    final uri = Uri.tryParse(request.url);
    if (uri == null) {
      return NavigationDecision.prevent;
    }
    // Pages may load blank, data and blob frames; anything else that isn't
    // a web page (mail, phone, store links) belongs to the system.
    if (isWebPageUri(uri) ||
        const {'about', 'data', 'blob'}.contains(uri.scheme)) {
      return NavigationDecision.navigate;
    }
    if (request.isMainFrame) {
      unawaited(_openExternally(uri));
    }
    return NavigationDecision.prevent;
  }

  void _setUrl(String url) {
    final uri = Uri.tryParse(url);
    if (uri == null || !isWebPageUri(uri) || !mounted) {
      return;
    }
    setState(() => _currentUri = uri);
  }

  Future<void> _refreshState() async {
    final title = await _controller.getTitle();
    final canGoBack = await _controller.canGoBack();
    final canGoForward = await _controller.canGoForward();
    if (!mounted) {
      return;
    }
    setState(() {
      _pageTitle = title?.trim().isNotEmpty == true ? title!.trim() : null;
      _canGoBack = canGoBack;
      _canGoForward = canGoForward;
    });
  }

  Future<void> _copyLink() async {
    await Clipboard.setData(ClipboardData(text: _currentUri.toString()));
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Link copied')));
  }

  void _reload() {
    setState(() => _errorText = null);
    unawaited(_controller.reload());
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final host = _currentUri.host;
    final isSecure = _currentUri.scheme == 'https';
    final loading = _progress < 100 && _errorText == null;

    // Back first walks the page's own history, then closes the browser.
    return PopScope(
      canPop: !_canGoBack,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) {
          unawaited(_controller.goBack());
        }
      },
      child: Scaffold(
        appBar: AppBar(
          leading: IconButton(
            key: const ValueKey('browser-close'),
            tooltip: 'Close',
            icon: const Icon(Icons.close),
            onPressed: () => Navigator.of(context).maybePop(),
          ),
          titleSpacing: 0,
          title: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                _pageTitle ?? host,
                key: const ValueKey('browser-title'),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.titleMedium,
              ),
              Row(
                children: [
                  Icon(
                    isSecure ? Icons.lock_outline : Icons.lock_open_outlined,
                    size: 12,
                    color: isSecure
                        ? colorScheme.onSurfaceVariant
                        : colorScheme.error,
                  ),
                  const SizedBox(width: 4),
                  Flexible(
                    child: Text(
                      host,
                      key: const ValueKey('browser-host'),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
          actions: [
            PopupMenuButton<_BrowserMenuAction>(
              key: const ValueKey('browser-menu'),
              tooltip: 'More',
              onSelected: (action) => switch (action) {
                _BrowserMenuAction.copyLink => unawaited(_copyLink()),
                _BrowserMenuAction.openExternally => unawaited(
                  _openExternally(_currentUri),
                ),
              },
              itemBuilder: (context) => const [
                PopupMenuItem(
                  value: _BrowserMenuAction.copyLink,
                  child: ListTile(
                    leading: Icon(Icons.copy_outlined),
                    title: Text('Copy link'),
                  ),
                ),
                PopupMenuItem(
                  value: _BrowserMenuAction.openExternally,
                  child: ListTile(
                    leading: Icon(Icons.open_in_browser),
                    title: Text('Open in browser'),
                  ),
                ),
              ],
            ),
          ],
          bottom: PreferredSize(
            preferredSize: const Size.fromHeight(2),
            child: loading
                ? LinearProgressIndicator(
                    key: const ValueKey('browser-progress'),
                    minHeight: 2,
                    value: _progress == 0 ? null : _progress / 100,
                  )
                : const SizedBox(height: 2),
          ),
        ),
        // The page stays mounted under the error, so retrying reuses it.
        body: Stack(
          fit: StackFit.expand,
          children: [
            WebViewWidget(controller: _controller),
            if (_errorText case final error?)
              ColoredBox(
                color: colorScheme.surface,
                child: _BrowserError(
                  message: error,
                  onRetry: _reload,
                  onOpenExternally: () =>
                      unawaited(_openExternally(_currentUri)),
                ),
              ),
          ],
        ),
        bottomNavigationBar: BottomAppBar(
          height: 56,
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              IconButton(
                key: const ValueKey('browser-back'),
                tooltip: 'Back',
                icon: const Icon(Icons.arrow_back_ios_new),
                onPressed: _canGoBack
                    ? () => unawaited(_controller.goBack())
                    : null,
              ),
              IconButton(
                key: const ValueKey('browser-forward'),
                tooltip: 'Forward',
                icon: const Icon(Icons.arrow_forward_ios),
                onPressed: _canGoForward
                    ? () => unawaited(_controller.goForward())
                    : null,
              ),
              IconButton(
                key: const ValueKey('browser-reload'),
                tooltip: 'Reload',
                icon: const Icon(Icons.refresh),
                onPressed: _reload,
              ),
              IconButton(
                key: const ValueKey('browser-open-externally'),
                tooltip: 'Open in browser',
                icon: const Icon(Icons.open_in_browser),
                onPressed: () => unawaited(_openExternally(_currentUri)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

enum _BrowserMenuAction { copyLink, openExternally }

class _BrowserError extends StatelessWidget {
  const _BrowserError({
    required this.message,
    required this.onRetry,
    required this.onOpenExternally,
  });

  final String message;
  final VoidCallback onRetry;
  final VoidCallback onOpenExternally;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          key: const ValueKey('browser-error'),
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.public_off_outlined,
              size: 48,
              color: theme.colorScheme.onSurfaceVariant,
            ),
            const SizedBox(height: 12),
            Text(
              'Could not load this page',
              style: theme.textTheme.titleMedium,
            ),
            const SizedBox(height: 4),
            Text(
              message,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              alignment: WrapAlignment.center,
              children: [
                FilledButton(
                  onPressed: onRetry,
                  child: const Text('Try again'),
                ),
                OutlinedButton(
                  onPressed: onOpenExternally,
                  child: const Text('Open in browser'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
