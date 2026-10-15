import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wecord/features/voice/voice_settings.dart';
import 'package:wecord/shared/l10n/l10n.dart';
import 'package:wecord/shared/layout/adaptive_layout.dart';

/// Opens Settings → Voice.
Future<void> openVoiceSettings(BuildContext context) {
  return Navigator.of(context).push(
    MaterialPageRoute<void>(builder: (context) => const VoiceSettingsScreen()),
  );
}

/// Settings → Voice: input mode and push to talk key, microphone
/// processing, the soundboard volume and the volumes set for people.
class VoiceSettingsScreen extends ConsumerWidget {
  const VoiceSettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(voiceSettingsProvider);
    final controller = ref.read(voiceSettingsProvider.notifier);
    final theme = Theme.of(context);
    final touch = usesTouchInput(context);
    final key = settings.pushToTalkKey;

    Widget heading(String text) {
      return Padding(
        padding: const EdgeInsets.only(top: 8, bottom: 4),
        child: Text(text, style: theme.textTheme.titleMedium),
      );
    }

    return Scaffold(
      key: const ValueKey('voice-settings-screen'),
      appBar: AppBar(title: Text(tr('Voice'))),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          heading(tr('Input mode')),
          const SizedBox(height: 4),
          SegmentedButton<VoiceInputMode>(
            key: const ValueKey('voice-input-mode'),
            segments: [
              ButtonSegment(
                value: VoiceInputMode.voiceActivity,
                icon: const Icon(Icons.graphic_eq),
                label: Text(tr('Voice activity')),
              ),
              ButtonSegment(
                value: VoiceInputMode.pushToTalk,
                icon: const Icon(Icons.touch_app_outlined),
                label: Text(tr('Push to talk')),
              ),
            ],
            selected: {settings.inputMode},
            showSelectedIcon: false,
            onSelectionChanged: (selection) =>
                controller.setInputMode(selection.single),
          ),
          const SizedBox(height: 8),
          Text(
            settings.pushToTalk
                ? touch
                      ? tr(
                          'Hold the talk button in the voice view to speak. '
                          'Your microphone stays quiet otherwise.',
                        )
                      : tr(
                          'Hold your push to talk key to speak, anywhere in '
                          'the app. Without a key, hold the talk button in '
                          'the voice view.',
                        )
                : tr('Your microphone sends whenever you are not muted.'),
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          if (settings.pushToTalk && !touch)
            ListTile(
              key: const ValueKey('voice-push-to-talk-key'),
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.keyboard_outlined),
              title: Text(tr('Push to talk key')),
              subtitle: Text(key == null ? tr('Not set') : voiceKeyLabel(key)),
              trailing: OutlinedButton(
                key: const ValueKey('voice-record-key'),
                onPressed: () async {
                  final picked = await showVoiceKeyRecorder(context);
                  if (picked != null) {
                    await controller.setPushToTalkKey(picked);
                  }
                },
                child: Text(key == null ? tr('Set key') : tr('Change key')),
              ),
            ),
          const Divider(height: 32),
          heading(tr('Audio processing')),
          SwitchListTile(
            key: const ValueKey('voice-noise-suppression'),
            contentPadding: EdgeInsets.zero,
            title: Text(tr('Noise suppression')),
            subtitle: Text(tr('Filters out background noise.')),
            value: settings.noiseSuppression,
            onChanged: controller.setNoiseSuppression,
          ),
          SwitchListTile(
            key: const ValueKey('voice-echo-cancellation'),
            contentPadding: EdgeInsets.zero,
            title: Text(tr('Echo cancellation')),
            subtitle: Text(
              tr('Keeps others from hearing themselves through your speakers.'),
            ),
            value: settings.echoCancellation,
            onChanged: controller.setEchoCancellation,
          ),
          SwitchListTile(
            key: const ValueKey('voice-auto-gain'),
            contentPadding: EdgeInsets.zero,
            title: Text(tr('Automatic gain control')),
            subtitle: Text(tr('Evens out how loud your voice sends.')),
            value: settings.autoGainControl,
            onChanged: controller.setAutoGainControl,
          ),
          const Divider(height: 32),
          heading(tr('Soundboard')),
          Row(
            children: [
              Icon(
                settings.soundboardVolume <= 0
                    ? Icons.volume_off_outlined
                    : Icons.volume_up_outlined,
                color: theme.colorScheme.onSurfaceVariant,
              ),
              Expanded(
                child: Slider(
                  key: const ValueKey('voice-soundboard-volume'),
                  value: settings.soundboardVolume,
                  divisions: 20,
                  label: '${(settings.soundboardVolume * 100).round()}%',
                  semanticFormatterCallback: (value) =>
                      '${(value * 100).round()}%',
                  onChanged: controller.setSoundboardVolume,
                ),
              ),
              SizedBox(
                width: 48,
                child: Text(
                  '${(settings.soundboardVolume * 100).round()}%',
                  key: const ValueKey('voice-soundboard-volume-value'),
                  textAlign: TextAlign.end,
                  style: theme.textTheme.labelMedium,
                ),
              ),
            ],
          ),
          Text(
            tr(
              'How loud sounds from the soundboard play for you. At 0% you '
              "don't hear them.",
            ),
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const Divider(height: 32),
          heading(tr('User volumes')),
          Text(
            tr(
              "Right-click (or long-press) someone in a voice channel or "
              "call to change how loud they are for you. Only you hear the "
              "difference.",
            ),
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          if (settings.userVolumes.isNotEmpty) ...[
            const SizedBox(height: 8),
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: TextButton.icon(
                key: const ValueKey('voice-reset-volumes'),
                onPressed: () =>
                    controller.update(settings.copyWith(userVolumes: const {})),
                icon: const Icon(Icons.restart_alt),
                label: Text(
                  tr('Reset volumes for {count} people', {
                    'count': settings.userVolumes.length,
                  }),
                ),
              ),
            ),
          ],
        ],
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
        content: Text(tr('Press the key to hold while talking.')),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(tr('Cancel')),
          ),
        ],
      ),
    );
  }
}
