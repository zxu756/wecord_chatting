import 'package:web/web.dart' as web;
import 'package:wecord/features/privacy/device_info.dart';

/// (device name, platform) for the Devices list: the browser and system.
(String, String) deviceNameAndPlatform() {
  final description = describeUserAgent(web.window.navigator.userAgent);
  return (description.isEmpty ? 'Web browser' : description, 'Web');
}
