import 'package:wecord/features/pwa/pwa_gateway.dart';

PwaGateway createPlatformPwaGateway() => const UnsupportedPwaGateway();

/// Outside the web there is nothing to install or update.
class UnsupportedPwaGateway implements PwaGateway {
  const UnsupportedPwaGateway();

  @override
  PwaState get state => const PwaState();

  @override
  Stream<PwaState> get changes => const Stream.empty();

  @override
  Future<PwaInstallOutcome> promptInstall() async =>
      PwaInstallOutcome.unavailable;

  @override
  Future<void> applyUpdate() async {}

  @override
  void setBadge(int count) {}
}
