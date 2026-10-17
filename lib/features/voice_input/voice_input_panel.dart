import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wecord/features/voice_input/voice_input_controller.dart';
import 'package:wecord/features/voice_input/voice_input_models.dart';
import 'package:wecord/features/voice_input/voice_waveform.dart';
import 'package:wecord/shared/l10n/l10n.dart';
import 'package:wecord/shared/ui/ui.dart';

/// The glass panel above the composer while the person dictates: a live
/// waveform, the words as they come in, a language switch (中文 / English),
/// and Cancel / Done. It also asks before a speech service that is not the
/// device hears them, and says what went wrong. Esc cancels (desktop and
/// web).
class VoiceInputPanel extends ConsumerStatefulWidget {
  const VoiceInputPanel({required this.owner, super.key});

  /// The conversation whose composer this panel belongs to; the panel only
  /// shows for a dictation started there.
  final String owner;

  @override
  ConsumerState<VoiceInputPanel> createState() => _VoiceInputPanelState();
}

class _VoiceInputPanelState extends ConsumerState<VoiceInputPanel>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    HardwareKeyboard.instance.addHandler(_onKey);
  }

  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(_onKey);
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  VoiceInputState get _state => ref.read(voiceInputProvider);

  bool get _mine => _state.isActive && _state.owner == widget.owner;

  bool _onKey(KeyEvent event) {
    if (event is! KeyDownEvent ||
        event.logicalKey != LogicalKeyboardKey.escape ||
        !_mine ||
        ModalRoute.of(context)?.isCurrent == false) {
      return false;
    }
    unawaited(ref.read(voiceInputProvider.notifier).cancel());
    return true;
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // The microphone is not left on behind the person's back.
    if (state != AppLifecycleState.resumed && _mine) {
      unawaited(ref.read(voiceInputProvider.notifier).done());
    }
  }

  String _caption(VoiceInputEngine engine) => switch (engine) {
    VoiceInputEngine.onDevice => tr('Recognized on this device'),
    VoiceInputEngine.appleServer => tr("Processed by Apple's speech service"),
    VoiceInputEngine.browser => tr(
      "Processed by your browser's speech service",
    ),
  };

  String _consentText(VoiceInputEngine engine) => switch (engine) {
    VoiceInputEngine.browser => tr(
      "Your browser's speech service turns what you say into text. Chrome and Edge send the audio to their makers' servers to do it. WeCord only receives the words.",
    ),
    _ => tr(
      "This device can't recognize this language by itself. To go on, what you say is sent to Apple's speech service.",
    ),
  };

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(voiceInputProvider);
    final visible = state.isActive && state.owner == widget.owner;
    final spring = WeCordMotion.smooth;
    return AnimatedSize(
      duration: spring.durationOf(context),
      curve: spring.curve,
      alignment: Alignment.bottomCenter,
      child: visible
          ? Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: _content(context, state),
            )
          : const SizedBox(width: double.infinity),
    );
  }

  Widget _content(BuildContext context, VoiceInputState state) {
    final c = context.tokens.colors;
    final controller = ref.read(voiceInputProvider.notifier);
    final listening = state.phase == VoicePhase.listening;
    final consent = state.phase == VoicePhase.consent;
    final failed = state.phase == VoicePhase.error;
    final status = switch (state.phase) {
      VoicePhase.listening => tr('Listening…'),
      VoicePhase.stopping => tr('Finishing…'),
      VoicePhase.consent => tr('Before you speak'),
      VoicePhase.error => tr('Voice input'),
      _ => tr('Getting ready…'),
    };

    final header = Row(
      children: [
        ExcludeSemantics(
          child: Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(
              color: failed
                  ? c.danger
                  : listening
                  ? c.accent
                  : c.faint,
              shape: BoxShape.circle,
            ),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Semantics(
            liveRegion: true,
            child: Text(
              status,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w700,
                color: c.ink,
              ),
            ),
          ),
        ),
        const SizedBox(width: 8),
        SizedBox(
          width: 156,
          child: WeCordSegmented<VoiceInputLanguage>(
            height: 32,
            expand: true,
            semanticLabel: tr('Language'),
            selected: state.language,
            onChanged: state.phase == VoicePhase.stopping
                ? null
                : (language) => unawaited(controller.setLanguage(language)),
            segments: [
              for (final language in VoiceInputLanguage.values)
                WeCordSegment(
                  value: language,
                  label: language.label,
                  key: ValueKey('voice-language-${language.name}'),
                ),
            ],
          ),
        ),
      ],
    );

    final List<Widget> body;
    if (consent) {
      body = [
        Text(
          _consentText(state.engine),
          key: const ValueKey('voice-consent-text'),
          style: TextStyle(fontSize: 14, height: 1.4, color: c.ink),
        ),
        const SizedBox(height: 12),
        _buttons(
          secondaryLabel: tr('Not now'),
          onSecondary: () => unawaited(controller.cancel()),
          primaryLabel: tr('Continue'),
          onPrimary: () => unawaited(controller.grantConsent()),
          primaryKey: const ValueKey('voice-consent-continue'),
        ),
      ];
    } else if (failed) {
      body = [
        Semantics(
          liveRegion: true,
          child: Text(
            state.failure?.message ?? VoiceInputFailure.failed.message,
            key: const ValueKey('voice-error-text'),
            style: TextStyle(fontSize: 14, height: 1.4, color: c.dangerText),
          ),
        ),
        const SizedBox(height: 12),
        _buttons(
          secondaryLabel: tr('Close'),
          onSecondary: controller.dismissError,
          primaryLabel: tr('Try again'),
          onPrimary: () => unawaited(controller.retry()),
          primaryKey: const ValueKey('voice-retry'),
        ),
      ];
    } else {
      final heard = state.partial.trim();
      body = [
        VoiceWaveform(
          levels: state.levels,
          color: c.accent,
          restColor: c.track,
        ),
        const SizedBox(height: 6),
        ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 40),
          child: Align(
            alignment: Alignment.centerLeft,
            child: Text(
              heard.isEmpty ? tr('Say something…') : heard,
              key: const ValueKey('voice-partial-text'),
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 16,
                height: 1.35,
                color: heard.isEmpty ? c.muted : c.ink,
              ),
            ),
          ),
        ),
        const SizedBox(height: 6),
        Row(
          children: [
            Icon(
              state.engine == VoiceInputEngine.onDevice
                  ? Icons.lock_outline_rounded
                  : Icons.cloud_outlined,
              size: 14,
              color: c.muted,
            ),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                _caption(state.engine),
                style: TextStyle(fontSize: 12, color: c.muted),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        _buttons(
          secondaryLabel: tr('Cancel'),
          onSecondary: () => unawaited(controller.cancel()),
          primaryLabel: tr('Done'),
          onPrimary: state.phase == VoicePhase.stopping
              ? null
              : () => unawaited(controller.done()),
          primaryKey: const ValueKey('voice-done'),
        ),
      ];
    }

    return Semantics(
      container: true,
      label: tr('Voice input'),
      child: WeCordGlass(
        key: const ValueKey('voice-input-panel'),
        elevation: GlassElevation.menu,
        borderRadius: BorderRadius.circular(WeCordRadii.xl),
        padding: const EdgeInsets.all(14),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [header, const SizedBox(height: 10), ...body],
        ),
      ),
    );
  }

  Widget _buttons({
    required String secondaryLabel,
    required VoidCallback onSecondary,
    required String primaryLabel,
    required VoidCallback? onPrimary,
    required Key primaryKey,
  }) {
    return Row(
      children: [
        Expanded(
          child: WeCordButton(
            label: secondaryLabel,
            variant: WeCordButtonVariant.secondary,
            expand: true,
            onPressed: onSecondary,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: WeCordButton(
            key: primaryKey,
            label: primaryLabel,
            variant: WeCordButtonVariant.accent,
            expand: true,
            onPressed: onPrimary,
          ),
        ),
      ],
    );
  }
}
