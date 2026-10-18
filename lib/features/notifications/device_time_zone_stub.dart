import 'dart:io';

/// The zone of an Apple or Linux device, read from where `/etc/localtime`
/// points ('/var/db/timezone/zoneinfo/Asia/Shanghai'). Null where that isn't
/// readable (a sandbox, Windows): the server then keeps the zone it has.
String? platformDeviceTimeZone() {
  try {
    final target = Link('/etc/localtime').resolveSymbolicLinksSync();
    final match = RegExp(r'zoneinfo/(.+)$').firstMatch(target);
    return match?.group(1);
  } catch (_) {
    return null;
  }
}
