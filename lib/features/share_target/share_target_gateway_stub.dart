import 'package:wecord/features/share_target/share_target_gateway.dart';
import 'package:wecord/features/share_target/shared_content.dart';

ShareTargetGateway createPlatformShareTargetGateway() =>
    const NoShareTargetGateway();

/// Outside the web nothing is ever shared to WeCord this way.
class NoShareTargetGateway implements ShareTargetGateway {
  const NoShareTargetGateway();

  @override
  Future<SharedContent?> read() async => null;

  @override
  Future<void> clear() async {}
}
