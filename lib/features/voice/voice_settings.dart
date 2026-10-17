import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wecord/features/voice/voice_call.dart';
import 'package:wecord/shared/l10n/l10n.dart';

/// How the microphone decides when to send.
enum VoiceInputMode {
  /// Sends whenever the microphone is unmuted.
  voiceActivity,

  /// Sends only while the push to talk key (or button) is held.
  pushToTalk,
}

/// The lowest and highest volume a participant can be set to locally.
const minUserVolume = 0.0;
const maxUserVolume = 2.0;

/// How loud soundboard sounds play unless changed.
const defaultSoundboardVolume = 0.8;

/// Voice settings kept on this device: input mode and push to talk key,
/// microphone processing, how loud each person plays and how loud
/// soundboard sounds play.
@immutable
class VoiceSettings {
  const VoiceSettings({
    this.inputMode = VoiceInputMode.voiceActivity,
    this.pushToTalkKeyId,
    this.noiseSuppression = true,
    this.echoCancellation = true,
    this.autoGainControl = true,
    this.userVolumes = const {},
    this.soundboardVolume = defaultSoundboardVolume,
    this.backgroundBlur = false,
  });

  factory VoiceSettings.fromJson(Map<String, dynamic> json) {
    final volumes = json['user_volumes'];
    return VoiceSettings(
      inputMode: json['input_mode'] == 'push_to_talk'
          ? VoiceInputMode.pushToTalk
          : VoiceInputMode.voiceActivity,
      pushToTalkKeyId: (json['push_to_talk_key'] as num?)?.toInt(),
      noiseSuppression: json['noise_suppression'] != false,
      echoCancellation: json['echo_cancellation'] != false,
      autoGainControl: json['auto_gain_control'] != false,
      userVolumes: {
        if (volumes is Map)
          for (final MapEntry(:key, :value) in volumes.entries)
            if (key is String && value is num)
              key: value.toDouble().clamp(minUserVolume, maxUserVolume),
      },
      soundboardVolume: switch (json['soundboard_volume']) {
        final num volume => volume.toDouble().clamp(0.0, 1.0),
        _ => defaultSoundboardVolume,
      },
      backgroundBlur: json['background_blur'] == true,
    );
  }

  final VoiceInputMode inputMode;

  /// The [LogicalKeyboardKey.keyId] held to talk, or null when none is set.
  final int? pushToTalkKeyId;
  final bool noiseSuppression;
  final bool echoCancellation;
  final bool autoGainControl;

  /// Volumes set for people, by user id: 1 is as sent, 0 silent, 2 twice
  /// as loud. People not listed play at 1.
  final Map<String, double> userVolumes;

  /// How loud soundboard sounds play, 0 (off) to 1.
  final double soundboardVolume;

  /// Blur the background behind the camera where the device can (see
  /// [VideoBackgroundSupport.inApp]); cameras start blurred.
  final bool backgroundBlur;

  bool get pushToTalk => inputMode == VoiceInputMode.pushToTalk;

  LogicalKeyboardKey? get pushToTalkKey {
    final id = pushToTalkKeyId;
    if (id == null) {
      return null;
    }
    return LogicalKeyboardKey.findKeyByKeyId(id) ?? LogicalKeyboardKey(id);
  }

  double volumeFor(String userId) => userVolumes[userId] ?? 1;

  VoiceAudioProcessing get audioProcessing => VoiceAudioProcessing(
    noiseSuppression: noiseSuppression,
    echoCancellation: echoCancellation,
    autoGainControl: autoGainControl,
    keepMicrophoneOpen: pushToTalk,
  );

  VoiceSettings copyWith({
    VoiceInputMode? inputMode,
    int? pushToTalkKeyId,
    bool? noiseSuppression,
    bool? echoCancellation,
    bool? autoGainControl,
    Map<String, double>? userVolumes,
    double? soundboardVolume,
    bool? backgroundBlur,
  }) {
    return VoiceSettings(
      inputMode: inputMode ?? this.inputMode,
      pushToTalkKeyId: pushToTalkKeyId ?? this.pushToTalkKeyId,
      noiseSuppression: noiseSuppression ?? this.noiseSuppression,
      echoCancellation: echoCancellation ?? this.echoCancellation,
      autoGainControl: autoGainControl ?? this.autoGainControl,
      userVolumes: userVolumes ?? this.userVolumes,
      soundboardVolume: soundboardVolume ?? this.soundboardVolume,
      backgroundBlur: backgroundBlur ?? this.backgroundBlur,
    );
  }

  Map<String, dynamic> toJson() => {
    'input_mode': pushToTalk ? 'push_to_talk' : 'voice_activity',
    if (pushToTalkKeyId != null) 'push_to_talk_key': pushToTalkKeyId,
    'noise_suppression': noiseSuppression,
    'echo_cancellation': echoCancellation,
    'auto_gain_control': autoGainControl,
    'user_volumes': userVolumes,
    'soundboard_volume': soundboardVolume,
    if (backgroundBlur) 'background_blur': true,
  };

  @override
  bool operator ==(Object other) {
    return other is VoiceSettings &&
        other.inputMode == inputMode &&
        other.pushToTalkKeyId == pushToTalkKeyId &&
        other.noiseSuppression == noiseSuppression &&
        other.echoCancellation == echoCancellation &&
        other.autoGainControl == autoGainControl &&
        mapEquals(other.userVolumes, userVolumes) &&
        other.soundboardVolume == soundboardVolume &&
        other.backgroundBlur == backgroundBlur;
  }

  @override
  int get hashCode => Object.hash(
    inputMode,
    pushToTalkKeyId,
    noiseSuppression,
    echoCancellation,
    autoGainControl,
    Object.hashAllUnordered(
      userVolumes.entries.map((entry) => Object.hash(entry.key, entry.value)),
    ),
    soundboardVolume,
    backgroundBlur,
  );
}

const _voiceSettingsKey = 'wecord.voice.settings';

/// Where voice settings are kept; tests swap in memory.
abstract interface class VoiceSettingsStore {
  Future<VoiceSettings?> load();

  Future<void> save(VoiceSettings settings);
}

class SharedPreferencesVoiceSettingsStore implements VoiceSettingsStore {
  const SharedPreferencesVoiceSettingsStore();

  @override
  Future<VoiceSettings?> load() async {
    final preferences = await SharedPreferences.getInstance();
    final raw = preferences.getString(_voiceSettingsKey);
    if (raw == null) {
      return null;
    }
    final decoded = jsonDecode(raw);
    if (decoded is! Map) {
      return null;
    }
    return VoiceSettings.fromJson(Map<String, dynamic>.from(decoded));
  }

  @override
  Future<void> save(VoiceSettings settings) async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.setString(
      _voiceSettingsKey,
      jsonEncode(settings.toJson()),
    );
  }
}

class InMemoryVoiceSettingsStore implements VoiceSettingsStore {
  InMemoryVoiceSettingsStore([this.saved]);

  VoiceSettings? saved;

  @override
  Future<VoiceSettings?> load() async => saved;

  @override
  Future<void> save(VoiceSettings settings) async => saved = settings;
}

final voiceSettingsStoreProvider = Provider<VoiceSettingsStore>(
  (ref) => const SharedPreferencesVoiceSettingsStore(),
);

/// The voice settings, remembered on this device. Defaults apply until the
/// saved ones have loaded.
final voiceSettingsProvider =
    NotifierProvider<VoiceSettingsController, VoiceSettings>(
      VoiceSettingsController.new,
    );

class VoiceSettingsController extends Notifier<VoiceSettings> {
  var _changed = false;

  @override
  VoiceSettings build() {
    ref.read(voiceSettingsStoreProvider).load().then((settings) {
      // A change made while loading wins over the saved settings.
      if (settings != null && !_changed) {
        state = settings;
      }
    }, onError: (Object _) {});
    return const VoiceSettings();
  }

  Future<void> update(VoiceSettings settings) async {
    _changed = true;
    state = settings;
    try {
      await ref.read(voiceSettingsStoreProvider).save(settings);
    } on Object {
      // Still applies for this session.
    }
  }

  Future<void> setInputMode(VoiceInputMode mode) {
    return update(state.copyWith(inputMode: mode));
  }

  Future<void> setPushToTalkKey(LogicalKeyboardKey key) {
    return update(state.copyWith(pushToTalkKeyId: key.keyId));
  }

  Future<void> setNoiseSuppression(bool enabled) {
    return update(state.copyWith(noiseSuppression: enabled));
  }

  Future<void> setEchoCancellation(bool enabled) {
    return update(state.copyWith(echoCancellation: enabled));
  }

  Future<void> setAutoGainControl(bool enabled) {
    return update(state.copyWith(autoGainControl: enabled));
  }

  Future<void> setBackgroundBlur(bool enabled) {
    return update(state.copyWith(backgroundBlur: enabled));
  }

  /// Sets how loud soundboard sounds play, 0 (off) to 1.
  Future<void> setSoundboardVolume(double volume) {
    return update(state.copyWith(soundboardVolume: volume.clamp(0.0, 1.0)));
  }

  /// Sets how loud [userId] plays for the current user; 1 forgets it.
  Future<void> setUserVolume(String userId, double volume) {
    final clamped = volume.clamp(minUserVolume, maxUserVolume);
    final volumes = Map.of(state.userVolumes);
    if ((clamped - 1).abs() < 0.005) {
      volumes.remove(userId);
    } else {
      volumes[userId] = clamped;
    }
    return update(state.copyWith(userVolumes: volumes));
  }
}

/// A key's name for the push to talk setting.
String voiceKeyLabel(LogicalKeyboardKey key) {
  if (key == LogicalKeyboardKey.space) {
    return tr('Space');
  }
  final label = key.keyLabel.trim();
  if (label.isEmpty) {
    return key.debugName ?? tr('Key {id}', {'id': key.keyId});
  }
  return label.length == 1 ? label.toUpperCase() : label;
}
