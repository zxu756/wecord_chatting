import 'dart:async';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import 'package:web/web.dart' as web;
import 'package:wecord/features/pwa/pwa_detect.dart';
import 'package:wecord/features/pwa/pwa_gateway.dart';

PwaGateway createPlatformPwaGateway() => BrowserPwaGateway();

/// The installed-app side of the browser.
///
/// `web/index.html` does the parts that cannot wait for Flutter to start:
/// it registers `wecord_sw.js` and keeps the `beforeinstallprompt` event
/// (Chrome fires it long before the app is up) on `window.__wecordPwa`,
/// announcing it with `wecord-install-available` / `wecord-installed`
/// events. The service worker tells open pages about a new deploy with
/// `{type: 'wecord-update-ready'}`; [applyUpdate] answers with
/// `{type: 'wecord-skip-waiting'}`.
class BrowserPwaGateway implements PwaGateway {
  BrowserPwaGateway() {
    _state = PwaState(
      standalone: _isStandalone(),
      iosSafari: _isIosSafari(),
      canInstall: _installPrompt != null,
    );
    _listen();
  }

  /// How often an open app asks the server whether a new version exists, on
  /// top of the browser's own check on every page load.
  static const _updateCheckEvery = Duration(minutes: 30);

  final _changes = StreamController<PwaState>.broadcast();
  late PwaState _state;
  Timer? _updateTimer;
  var _reloading = false;

  @override
  PwaState get state => _state;

  @override
  Stream<PwaState> get changes => _changes.stream;

  void _update(PwaState Function(PwaState state) change) {
    final next = change(_state);
    if (next == _state) {
      return;
    }
    _state = next;
    _changes.add(next);
  }

  JSObject? get _installPrompt {
    final holder = globalContext['__wecordPwa'];
    if (!holder.isA<JSObject>()) {
      return null;
    }
    final prompt = (holder as JSObject)['installPrompt'];
    return prompt.isA<JSObject>() ? prompt as JSObject : null;
  }

  bool _isStandalone() {
    try {
      for (final mode in const [
        'standalone',
        'window-controls-overlay',
        'minimal-ui',
      ]) {
        if (web.window.matchMedia('(display-mode: $mode)').matches) {
          return true;
        }
      }
      // iOS Safari's "Add to Home Screen" apps.
      return web.window.navigator['standalone'].dartify() == true;
    } catch (_) {
      return false;
    }
  }

  bool _isIosSafari() {
    try {
      final navigator = web.window.navigator;
      return !_isStandalone() &&
          isIosSafariUserAgent(
            navigator.userAgent,
            maxTouchPoints: navigator.maxTouchPoints,
          );
    } catch (_) {
      return false;
    }
  }

  void _syncInstallState() {
    _update(
      (state) => state.copyWith(
        standalone: _isStandalone(),
        iosSafari: _isIosSafari(),
        canInstall: _installPrompt != null,
      ),
    );
  }

  void _listen() {
    web.window.addEventListener(
      'wecord-install-available',
      ((web.Event _) => _syncInstallState()).toJS,
    );
    web.window.addEventListener(
      'wecord-installed',
      ((web.Event _) => _syncInstallState()).toJS,
    );
    try {
      web.window
          .matchMedia('(display-mode: standalone)')
          .addEventListener(
            'change',
            ((web.Event _) => _syncInstallState()).toJS,
          );
    } catch (_) {
      // Older browsers: the state is read once at start.
    }
    if (web.window.navigator['serviceWorker'].isUndefinedOrNull) {
      return;
    }
    final container = web.window.navigator.serviceWorker;
    container.addEventListener(
      'message',
      ((web.MessageEvent event) {
        final data = event.data;
        if (data == null || !data.isA<JSObject>()) {
          return;
        }
        final type = (data as JSObject)['type'];
        if (type.isA<JSString>() &&
            (type as JSString).toDart == 'wecord-update-ready') {
          _update((state) => state.copyWith(updateReady: true));
        }
      }).toJS,
    );
    // Listeners added with addEventListener only get messages once the
    // container's queue is started.
    container.startMessages();
    unawaited(_watchRegistration(container));
    web.document.addEventListener(
      'visibilitychange',
      ((web.Event _) {
        if (web.document.visibilityState == 'visible') {
          unawaited(_checkForUpdate());
        }
      }).toJS,
    );
  }

  Future<web.ServiceWorkerRegistration?> _registration() async {
    try {
      return await web.window.navigator.serviceWorker.getRegistration().toDart;
    } catch (_) {
      return null;
    }
  }

  Future<void> _watchRegistration(web.ServiceWorkerContainer container) async {
    // index.html registers the worker once the app is on screen, which can
    // be a little after this runs.
    var registration = await _registration();
    for (var attempt = 0; registration == null && attempt < 6; attempt++) {
      await Future<void>.delayed(const Duration(seconds: 10));
      registration = await _registration();
    }
    if (registration == null) {
      return;
    }
    // A version that finished downloading before the app started (the page
    // was open while it arrived, or it came in on the last visit).
    if (registration.waiting != null && container.controller != null) {
      _update((state) => state.copyWith(updateReady: true));
    }
    _updateTimer ??= Timer.periodic(
      _updateCheckEvery,
      (_) => unawaited(_checkForUpdate()),
    );
  }

  Future<void> _checkForUpdate() async {
    try {
      final registration = await _registration();
      await registration?.update().toDart;
    } catch (_) {
      // Offline or the check failed: the next one tries again.
    }
  }

  @override
  Future<PwaInstallOutcome> promptInstall() async {
    final prompt = _installPrompt;
    if (prompt == null) {
      return PwaInstallOutcome.unavailable;
    }
    try {
      // The browser lets a saved prompt be used once.
      (globalContext['__wecordPwa'] as JSObject)['installPrompt'] = null;
      _syncInstallState();
      await prompt.callMethod<JSPromise<JSAny?>>('prompt'.toJS).toDart;
      final choice = await (prompt['userChoice'] as JSPromise<JSAny?>).toDart;
      final outcome = choice.isA<JSObject>()
          ? (choice as JSObject)['outcome']
          : null;
      return outcome.isA<JSString>() &&
              (outcome as JSString).toDart == 'accepted'
          ? PwaInstallOutcome.accepted
          : PwaInstallOutcome.dismissed;
    } catch (_) {
      return PwaInstallOutcome.unavailable;
    }
  }

  @override
  Future<void> applyUpdate() async {
    if (_reloading) {
      return;
    }
    _reloading = true;
    final registration = await _registration();
    final waiting = registration?.waiting;
    if (waiting == null) {
      web.window.location.reload();
      return;
    }
    // The new worker takes over, then the page reloads onto it.
    web.window.navigator.serviceWorker.addEventListener(
      'controllerchange',
      ((web.Event _) => web.window.location.reload()).toJS,
    );
    waiting.postMessage({'type': 'wecord-skip-waiting'}.jsify());
    // If the switch never comes, reloading still picks the new version up
    // once the old worker lets go.
    Timer(const Duration(seconds: 4), () => web.window.location.reload());
  }

  @override
  void setBadge(int count) {
    final shown = count < 0 ? 0 : count;
    try {
      web.document.title = titleWithUnread('WeCord', shown);
    } catch (_) {}
    // Only an installed app has an icon to badge.
    if (!_state.standalone) {
      return;
    }
    try {
      final navigator = web.window.navigator as JSObject;
      final name = shown > 0 ? 'setAppBadge' : 'clearAppBadge';
      if (!navigator.has(name)) {
        return;
      }
      final result = shown > 0
          ? navigator.callMethod<JSAny?>(name.toJS, shown.toJS)
          : navigator.callMethod<JSAny?>(name.toJS);
      if (result.isA<JSPromise<JSAny?>>()) {
        unawaited(
          (result as JSPromise<JSAny?>).toDart.then<void>((_) {}).catchError((
            Object _,
          ) {
            // Badging refused: nothing to show.
          }),
        );
      }
    } catch (_) {}
  }
}
