import 'dart:io';

/// (device name, platform) for the Devices list: the computer's name, as
/// its owner set it, and the operating system.
(String, String) deviceNameAndPlatform() {
  final platform = switch (Platform.operatingSystem) {
    'ios' => 'iOS',
    'macos' => 'macOS',
    'android' => 'Android',
    'windows' => 'Windows',
    'linux' => 'Linux',
    final other => other,
  };
  var name = '';
  try {
    name = Platform.localHostname
        .replaceAll(RegExp(r'\.(local|lan|home)$'), '')
        .replaceAll('-', ' ')
        .trim();
  } catch (_) {
    name = '';
  }
  // Phones report a generic host name.
  if (name.isEmpty ||
      name.toLowerCase() == 'localhost' ||
      platform == 'iOS' ||
      platform == 'Android') {
    name = switch (platform) {
      'iOS' => 'iPhone or iPad',
      'Android' => 'Android phone',
      _ => platform,
    };
  }
  return (name, platform);
}
