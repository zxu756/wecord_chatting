import 'package:flutter/foundation.dart';
import 'package:wecord/features/pwa/pwa_gateway_stub.dart'
    if (dart.library.js_interop) 'package:wecord/features/pwa/pwa_gateway_web.dart';

/// What the browser says about WeCord as an installable app.
@immutable
class PwaState {
  const PwaState({
    this.standalone = false,
    this.iosSafari = false,
    this.canInstall = false,
    this.updateReady = false,
  });

  /// Running as an installed app (its own window, no browser tabs).
  final bool standalone;

  /// A tab in iOS Safari, where installing means Share, then Add to Home
  /// Screen (there is no install prompt to call).
  final bool iosSafari;

  /// The browser holds an install prompt (Chrome and Edge) that
  /// [PwaGateway.promptInstall] can show.
  final bool canInstall;

  /// A new deploy has been downloaded and waits for a reload.
  final bool updateReady;

  PwaState copyWith({
    bool? standalone,
    bool? iosSafari,
    bool? canInstall,
    bool? updateReady,
  }) {
    return PwaState(
      standalone: standalone ?? this.standalone,
      iosSafari: iosSafari ?? this.iosSafari,
      canInstall: canInstall ?? this.canInstall,
      updateReady: updateReady ?? this.updateReady,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is PwaState &&
      other.standalone == standalone &&
      other.iosSafari == iosSafari &&
      other.canInstall == canInstall &&
      other.updateReady == updateReady;

  @override
  int get hashCode =>
      Object.hash(standalone, iosSafari, canInstall, updateReady);
}

/// What the person chose in the browser's install dialog.
enum PwaInstallOutcome { accepted, dismissed, unavailable }

/// The browser side of the installed app: the install prompt, the service
/// worker's "update ready" message and the app badge. Everything is a no-op
/// outside the web, and tests use a fake.
abstract interface class PwaGateway {
  PwaState get state;

  /// Fires with the new state whenever any part of it changes.
  Stream<PwaState> get changes;

  /// Shows the browser's install dialog.
  Future<PwaInstallOutcome> promptInstall();

  /// Switches to the downloaded version and reloads the page.
  Future<void> applyUpdate();

  /// Shows [count] on the installed app's icon (and in the tab title);
  /// 0 clears it.
  void setBadge(int count);
}

PwaGateway createPwaGateway() => createPlatformPwaGateway();
