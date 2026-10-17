import 'package:livekit_client/livekit_client.dart' as lk;
import 'package:wecord/shared/l10n/l10n.dart';

/// How a device can blur the background behind the camera.
enum VideoBackgroundSupport {
  /// Not at all here: the option is not offered.
  none,

  /// WeCord blurs the camera picture itself, before it is sent (browsers,
  /// with LiveKit's track processors and MediaPipe's person segmentation).
  inApp,

  /// The system's Portrait effect (iOS, macOS): the user switches it in the
  /// system's video effects, which the app opens. The system applies it to
  /// the camera for every app, so nothing is processed here.
  system,
}

/// The camera can't be sent blurred, so it was not started. A camera that
/// should be blurred is never sent unblurred.
class BackgroundBlurUnavailable implements Exception {
  const BackgroundBlurUnavailable();

  @override
  String toString() =>
      tr('Could not blur the background, so the camera stayed off.');
}

/// A LiveKit track processor that blurs the background of a camera, and can
/// let the picture through unchanged without restarting.
abstract interface class BlurProcessor
    implements lk.TrackProcessor<lk.VideoProcessorOptions> {
  Future<void> setBlurEnabled(bool enabled);
}

/// What a platform offers for the camera's background.
abstract interface class VideoBackgroundEffects {
  /// Whether (and how) this device can blur the camera background. Never
  /// throws.
  Future<VideoBackgroundSupport> detect();

  /// A processor for [VideoBackgroundSupport.inApp]; null otherwise.
  BlurProcessor? createBlurProcessor();

  /// Whether the system's blur is on for the camera
  /// ([VideoBackgroundSupport.system]).
  Future<bool> systemBlurEnabled();

  /// Opens the system's video effects ([VideoBackgroundSupport.system]).
  Future<void> showSystemEffects();
}

/// A platform without any background effect.
class NoVideoBackgroundEffects implements VideoBackgroundEffects {
  const NoVideoBackgroundEffects();

  @override
  Future<VideoBackgroundSupport> detect() async => VideoBackgroundSupport.none;

  @override
  BlurProcessor? createBlurProcessor() => null;

  @override
  Future<bool> systemBlurEnabled() async => false;

  @override
  Future<void> showSystemEffects() async {}
}
