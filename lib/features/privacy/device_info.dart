import 'package:wecord/features/privacy/device_info_io.dart'
    if (dart.library.js_interop) 'package:wecord/features/privacy/device_info_web.dart'
    as platform;

/// What this device calls itself in the Devices list.
class CurrentDevice {
  const CurrentDevice({
    required this.name,
    required this.platform,
    required this.appVersion,
  });

  final String name;
  final String platform;
  final String appVersion;
}

/// The app's version, set at build time (`--dart-define=APP_VERSION=1.2.3`).
const appVersion = String.fromEnvironment('APP_VERSION', defaultValue: '0.1.0');

CurrentDevice currentDevice() {
  final (name, platformLabel) = platform.deviceNameAndPlatform();
  return CurrentDevice(
    name: name,
    platform: platformLabel,
    appVersion: appVersion,
  );
}

/// "Chrome on macOS" from a browser's user agent; the system or browser
/// alone when it cannot tell both, empty when it knows neither.
String describeUserAgent(String agent) {
  final os = switch (agent) {
    _ when agent.contains('iPhone') => 'iPhone',
    _ when agent.contains('iPad') => 'iPad',
    _ when agent.contains('Android') => 'Android',
    _ when agent.contains('Mac OS X') || agent.contains('Macintosh') => 'macOS',
    _ when agent.contains('Windows') => 'Windows',
    _ when agent.contains('CrOS') => 'ChromeOS',
    _ when agent.contains('Linux') => 'Linux',
    _ => '',
  };
  final browser = switch (agent) {
    _ when agent.contains('Edg/') => 'Edge',
    _ when agent.contains('OPR/') || agent.contains('Opera') => 'Opera',
    _ when agent.contains('Firefox/') || agent.contains('FxiOS') => 'Firefox',
    _ when agent.contains('Chrome/') || agent.contains('CriOS') => 'Chrome',
    _ when agent.contains('Safari/') => 'Safari',
    _ => '',
  };
  if (browser.isNotEmpty && os.isNotEmpty) {
    return '$browser on $os';
  }
  return browser.isNotEmpty ? browser : os;
}
