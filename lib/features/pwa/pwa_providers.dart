import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wecord/features/circles/circle_rail.dart';
import 'package:wecord/features/inbox/inbox_screen.dart';
import 'package:wecord/features/pwa/pwa_gateway.dart';

final pwaGatewayProvider = Provider<PwaGateway>((ref) => createPwaGateway());

/// Whether WeCord is installed, can be installed, or has an update waiting.
final pwaStateProvider = NotifierProvider<PwaController, PwaState>(
  PwaController.new,
);

class PwaController extends Notifier<PwaState> {
  @override
  PwaState build() {
    final gateway = ref.watch(pwaGatewayProvider);
    final subscription = gateway.changes.listen((next) => state = next);
    ref.onDispose(subscription.cancel);
    return gateway.state;
  }

  /// Shows the browser's install dialog.
  Future<PwaInstallOutcome> install() =>
      ref.read(pwaGatewayProvider).promptInstall();

  /// Switches to the new version and reloads.
  Future<void> applyUpdate() => ref.read(pwaGatewayProvider).applyUpdate();
}

/// Remembers that the iOS "Add to Home Screen" hint was dismissed.
abstract interface class PwaHintStore {
  Future<bool> isDismissed();
  Future<void> dismiss();
}

class SharedPreferencesPwaHintStore implements PwaHintStore {
  const SharedPreferencesPwaHintStore();

  static const _key = 'pwa.ios_hint_dismissed';

  @override
  Future<bool> isDismissed() async =>
      (await SharedPreferences.getInstance()).getBool(_key) ?? false;

  @override
  Future<void> dismiss() async =>
      (await SharedPreferences.getInstance()).setBool(_key, true);
}

final pwaHintStoreProvider = Provider<PwaHintStore>(
  (ref) => const SharedPreferencesPwaHintStore(),
);

/// Whether to show the "Share, then Add to Home Screen" hint: in an iOS
/// Safari tab, until dismissed once.
final iosInstallHintProvider = NotifierProvider<IosInstallHint, bool>(
  IosInstallHint.new,
);

class IosInstallHint extends Notifier<bool> {
  var _dismissed = false;

  @override
  bool build() {
    final iosSafari = ref.watch(pwaStateProvider.select((s) => s.iosSafari));
    if (!iosSafari) {
      return false;
    }
    // Hidden until the saved choice has been read, so a dismissed hint
    // never flashes.
    ref.read(pwaHintStoreProvider).isDismissed().then((dismissed) {
      if (ref.mounted && !dismissed && !_dismissed) {
        state = true;
      }
    }, onError: (Object _) {});
    return false;
  }

  Future<void> dismiss() async {
    _dismissed = true;
    state = false;
    try {
      await ref.read(pwaHintStoreProvider).dismiss();
    } on Object {
      // Hidden for this session at least.
    }
  }
}

/// What the installed app's icon badge shows: unread messages in direct and
/// group chats plus the Notifications count.
final appBadgeCountProvider = Provider.autoDispose<int>(
  (ref) =>
      ref.watch(directUnreadCountProvider) + ref.watch(inboxBadgeCountProvider),
);
