import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:wecord/features/voice/background/video_background.dart';

/// The effects of the platform this app runs on.
VideoBackgroundEffects platformVideoBackgroundEffects() {
  return switch (defaultTargetPlatform) {
    TargetPlatform.iOS || TargetPlatform.macOS => const AppleVideoEffects(),
    _ => const NoVideoBackgroundEffects(),
  };
}

/// iOS and macOS: the system's Portrait effect, which blurs the background
/// behind the camera for any app using it. Apps can't switch it on
/// themselves; they can open the system's video effects (Control Center) and
/// read whether it is on. `VideoEffectsPlugin.swift` is the native side
/// (channel `wecord/video_effects`):
///
/// * `status` → `{supported: bool, enabled: bool}`: whether a camera here
///   offers the effect, and whether the user has it on.
/// * `show`: opens the system's video effects.
class AppleVideoEffects implements VideoBackgroundEffects {
  const AppleVideoEffects([
    this.channel = const MethodChannel('wecord/video_effects'),
  ]);

  final MethodChannel channel;

  Future<({bool supported, bool enabled})> _status() async {
    try {
      final status = await channel.invokeMapMethod<String, Object?>('status');
      return (
        supported: status?['supported'] == true,
        enabled: status?['enabled'] == true,
      );
    } on PlatformException {
      return (supported: false, enabled: false);
    } on MissingPluginException {
      return (supported: false, enabled: false);
    }
  }

  @override
  Future<VideoBackgroundSupport> detect() async {
    return (await _status()).supported
        ? VideoBackgroundSupport.system
        : VideoBackgroundSupport.none;
  }

  @override
  BlurProcessor? createBlurProcessor() => null;

  @override
  Future<bool> systemBlurEnabled() async => (await _status()).enabled;

  @override
  Future<void> showSystemEffects() async {
    try {
      await channel.invokeMethod<void>('show');
    } on PlatformException {
      // Nothing to show on this system.
    } on MissingPluginException {
      // Neither here.
    }
  }
}
