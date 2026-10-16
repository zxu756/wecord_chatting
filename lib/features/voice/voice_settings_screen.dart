import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wecord/features/voice/voice_call.dart';
import 'package:wecord/features/voice/voice_session.dart';
import 'package:wecord/features/voice/voice_settings.dart';
import 'package:wecord/shared/l10n/l10n.dart';
import 'package:wecord/shared/layout/adaptive_layout.dart';
import 'package:wecord/shared/ui/ui.dart';

/// Opens Settings → Voice.
Future<void> openVoiceSettings(BuildContext context) {
  return Navigator.of(context).push(
    MaterialPageRoute<void>(builder: (context) => const VoiceSettingsScreen()),
  );
}

/// Settings → Voice, on paper: input mode and push to talk key,
/// microphone processing, the soundboard volume and the volumes set for
/// people.
class VoiceSettingsScreen extends ConsumerWidget {
  const VoiceSettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(voiceSettingsProvider);
    final controller = ref.read(voiceSettingsProvider.notifier);
    final c = context.tokens.colors;
    final touch = usesTouchInput(context);
    final key = settings.pushToTalkKey;
    final canPop = ModalRoute.of(context)?.impliesAppBarDismissal ?? false;
    final soundboardPercent = (settings.soundboardVolume * 100).round();
    // In a call, what the microphone really uses; otherwise what this
    // device can do (the server's say comes with the call).
    final session = ref.watch(voiceSessionProvider);
    final aiSupported = ref.watch(voiceAiNoiseSupportedProvider).value;
    final noiseMode = session != null && session.isConnected
        ? session.noiseMode
        : aiSupported == null
        ? null
        : aiSupported
        ? VoiceNoiseMode.ai
        : VoiceNoiseMode.standard;

    Widget note(String text) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(4, 10, 4, 0),
        child: Text(
          text,
          style: TextStyle(fontSize: 12.5, color: c.muted, height: 1.4),
        ),
      );
    }

    return Scaffold(
      key: const ValueKey('voice-settings-screen'),
      backgroundColor: c.paper,
      body: SafeArea(
        bottom: false,
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 680),
            child: ListView(
              padding: EdgeInsets.fromLTRB(
                WeCordSpace.gutter,
                8,
                WeCordSpace.gutter,
                32 + MediaQuery.paddingOf(context).bottom,
              ),
              children: [
                Row(
                  children: [
                    if (canPop) ...[
                      WeCordIconButton(
                        icon: Icons.arrow_back_rounded,
                        tooltip: tr('Back'),
                        variant: WeCordButtonVariant.onPaper,
                        onPressed: () => Navigator.maybePop(context),
                      ),
                      const SizedBox(width: 10),
                    ],
                    Expanded(
                      child: Semantics(
                        header: true,
                        child: Text(
                          tr('Voice'),
                          style: TextStyle(
                            fontSize: 26,
                            fontWeight: FontWeight.w800,
                            letterSpacing: -0.6,
                            color: c.ink,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                SettingsSectionHeader(tr('Input mode')),
                SettingsGroup(
                  children: [
                    Padding(
                      padding: const EdgeInsets.all(14),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          WeCordSegmented<VoiceInputMode>(
                            key: const ValueKey('voice-input-mode'),
                            expand: true,
                            height: 40,
                            semanticLabel: tr('Input mode'),
                            selected: settings.inputMode,
                            onChanged: controller.setInputMode,
                            segments: [
                              WeCordSegment(
                                value: VoiceInputMode.voiceActivity,
                                icon: Icons.graphic_eq_rounded,
                                label: tr('Voice activity'),
                              ),
                              WeCordSegment(
                                value: VoiceInputMode.pushToTalk,
                                icon: Icons.touch_app_outlined,
                                label: tr('Push to talk'),
                              ),
                            ],
                          ),
                          const SizedBox(height: 10),
                          Text(
                            settings.pushToTalk
                                ? touch
                                      ? tr(
                                          'Hold the talk button in the voice '
                                          'view to speak. Your microphone '
                                          'stays quiet otherwise.',
                                        )
                                      : tr(
                                          'Hold your push to talk key to '
                                          'speak, anywhere in the app. '
                                          'Without a key, hold the talk '
                                          'button in the voice view.',
                                        )
                                : tr(
                                    'Your microphone sends whenever you are '
                                    'not muted.',
                                  ),
                            style: TextStyle(
                              fontSize: 13,
                              color: c.muted,
                              height: 1.4,
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (settings.pushToTalk && !touch)
                      SettingsRow(
                        key: const ValueKey('voice-push-to-talk-key'),
                        icon: Icons.keyboard_outlined,
                        tone: SettingsTone.accent,
                        title: tr('Push to talk key'),
                        value: key == null ? tr('Not set') : voiceKeyLabel(key),
                        trailing: WeCordButton(
                          key: const ValueKey('voice-record-key'),
                          label: key == null ? tr('Set key') : tr('Change key'),
                          variant: WeCordButtonVariant.secondary,
                          size: WeCordButtonSize.small,
                          onPressed: () async {
                            final picked = await showVoiceKeyRecorder(context);
                            if (picked != null) {
                              await controller.setPushToTalkKey(picked);
                            }
                          },
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 20),
                SettingsSectionHeader(tr('Audio processing')),
                SettingsGroup(
                  children: [
                    SettingsRow.toggle(
                      key: const ValueKey('voice-noise-suppression'),
                      icon: Icons.noise_aware_rounded,
                      tone: SettingsTone.accent,
                      title: tr('Noise suppression'),
                      subtitle: switch (settings.noiseSuppression
                          ? noiseMode
                          : null) {
                        VoiceNoiseMode.ai =>
                          '${tr('Filters out background noise.')}\n'
                              '${tr('AI noise suppression active')}',
                        VoiceNoiseMode.standard =>
                          '${tr('Filters out background noise.')}\n'
                              '${tr('Standard noise suppression (AI not available on this device)')}',
                        null => tr('Filters out background noise.'),
                      },
                      value: settings.noiseSuppression,
                      onChanged: controller.setNoiseSuppression,
                    ),
                    SettingsRow.toggle(
                      key: const ValueKey('voice-echo-cancellation'),
                      icon: Icons.surround_sound_outlined,
                      tone: SettingsTone.success,
                      title: tr('Echo cancellation'),
                      subtitle: tr(
                        'Keeps others from hearing themselves through your '
                        'speakers.',
                      ),
                      value: settings.echoCancellation,
                      onChanged: controller.setEchoCancellation,
                    ),
                    SettingsRow.toggle(
                      key: const ValueKey('voice-auto-gain'),
                      icon: Icons.tune_rounded,
                      tone: SettingsTone.warning,
                      title: tr('Automatic gain control'),
                      subtitle: tr('Evens out how loud your voice sends.'),
                      value: settings.autoGainControl,
                      onChanged: controller.setAutoGainControl,
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                SettingsSectionHeader(tr('Soundboard')),
                SettingsGroup(
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(14, 10, 14, 6),
                      child: Row(
                        children: [
                          SettingsIconTile(
                            icon: settings.soundboardVolume <= 0
                                ? Icons.volume_off_rounded
                                : Icons.music_note_rounded,
                            tone: SettingsTone.danger,
                          ),
                          Expanded(
                            child: Slider(
                              key: const ValueKey('voice-soundboard-volume'),
                              value: settings.soundboardVolume,
                              semanticFormatterCallback: (value) =>
                                  '${(value * 100).round()}%',
                              onChanged: controller.setSoundboardVolume,
                            ),
                          ),
                          SizedBox(
                            width: 44,
                            child: Text(
                              '$soundboardPercent%',
                              key: const ValueKey(
                                'voice-soundboard-volume-value',
                              ),
                              textAlign: TextAlign.end,
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w700,
                                color: c.muted,
                                fontFeatures: const [
                                  FontFeature.tabularFigures(),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                note(
                  tr(
                    'How loud sounds from the soundboard play for you. At 0% '
                    "you don't hear them.",
                  ),
                ),
                const SizedBox(height: 20),
                SettingsSectionHeader(tr('User volumes')),
                SettingsGroup(
                  children: [
                    Padding(
                      padding: const EdgeInsets.all(14),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const SettingsIconTile(
                            icon: Icons.people_alt_outlined,
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              tr(
                                "Right-click (or long-press) someone in a "
                                "voice channel or call to change how loud "
                                "they are for you. Only you hear the "
                                "difference.",
                              ),
                              style: TextStyle(
                                fontSize: 13,
                                color: c.muted,
                                height: 1.4,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (settings.userVolumes.isNotEmpty)
                      SettingsRow(
                        key: const ValueKey('voice-reset-volumes'),
                        icon: Icons.restart_alt_rounded,
                        tone: SettingsTone.accent,
                        title: tr('Reset volumes for {count} people', {
                          'count': settings.userVolumes.length,
                        }),
                        showChevron: false,
                        onTap: () => controller.update(
                          settings.copyWith(userVolumes: const {}),
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Waits for a key press and returns it; null when cancelled (Escape or
/// Cancel).
Future<LogicalKeyboardKey?> showVoiceKeyRecorder(BuildContext context) {
  return showDialog<LogicalKeyboardKey>(
    context: context,
    builder: (context) => const _KeyRecorderDialog(),
  );
}

class _KeyRecorderDialog extends StatelessWidget {
  const _KeyRecorderDialog();

  @override
  Widget build(BuildContext context) {
    final c = context.tokens.colors;
    return Focus(
      autofocus: true,
      onKeyEvent: (node, event) {
        if (event is! KeyDownEvent) {
          return KeyEventResult.handled;
        }
        if (event.logicalKey == LogicalKeyboardKey.escape) {
          Navigator.of(context).pop();
        } else {
          Navigator.of(context).pop(event.logicalKey);
        }
        return KeyEventResult.handled;
      },
      child: AlertDialog(
        key: const ValueKey('voice-key-recorder'),
        title: Text(tr('Push to talk key')),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 72,
              height: 72,
              decoration: ShapeDecoration(
                color: c.raised,
                shape: RoundedSuperellipseBorder(
                  borderRadius: BorderRadius.circular(22),
                ),
              ),
              child: Icon(Icons.keyboard_rounded, size: 34, color: c.ink),
            ),
            const SizedBox(height: 14),
            Text(
              tr('Press the key to hold while talking.'),
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 14, color: c.muted),
            ),
          ],
        ),
        actions: [
          WeCordButton(
            label: tr('Cancel'),
            variant: WeCordButtonVariant.ghost,
            onPressed: () => Navigator.of(context).pop(),
          ),
        ],
      ),
    );
  }
}
