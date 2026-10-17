import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wecord/features/voice_input/voice_input_controller.dart';
import 'package:wecord/shared/l10n/l10n.dart';
import 'package:wecord/shared/ui/ui.dart';

/// Starts voice input from the composer: tap to start and tap again to
/// finish (the way a mouse works), or press and hold to dictate and let go
/// to finish. Either way the words land in the text field to edit and send
/// as text; this is not a voice message.
class VoiceInputButton extends ConsumerStatefulWidget {
  const VoiceInputButton({
    required this.owner,
    required this.field,
    this.focus,
    this.size = 40,
    this.enabled = true,
    super.key,
  });

  /// The conversation whose composer this is.
  final String owner;
  final TextEditingController field;
  final FocusNode? focus;
  final double size;

  /// False while the composer is busy (sending, editing, recording).
  final bool enabled;

  @override
  ConsumerState<VoiceInputButton> createState() => _VoiceInputButtonState();
}

class _VoiceInputButtonState extends ConsumerState<VoiceInputButton> {
  var _holding = false;

  bool get _listeningHere {
    final state = ref.read(voiceInputProvider);
    return state.isActive && state.owner == widget.owner;
  }

  Future<void> _start() {
    return ref
        .read(voiceInputProvider.notifier)
        .start(owner: widget.owner, field: widget.field, focus: widget.focus);
  }

  void _toggle() {
    WeCordHaptics.selection();
    if (_listeningHere) {
      unawaited(ref.read(voiceInputProvider.notifier).done());
    } else {
      unawaited(_start());
    }
  }

  void _hold() {
    if (_listeningHere) {
      return;
    }
    WeCordHaptics.medium();
    _holding = true;
    unawaited(_start());
  }

  void _release() {
    if (!_holding) {
      return;
    }
    _holding = false;
    final phase = ref.read(voiceInputProvider).phase;
    // Letting go while the system still asks for permission keeps listening
    // (as if it had been a tap): the question took the finger's time.
    if (phase == VoicePhase.listening || phase == VoicePhase.stopping) {
      unawaited(ref.read(voiceInputProvider.notifier).done());
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(voiceInputProvider);
    final active = state.isActive && state.owner == widget.owner;
    return Listener(
      onPointerUp: (_) => _release(),
      onPointerCancel: (_) => _release(),
      child: WeCordIconButton(
        key: const ValueKey('composer-voice-input-button'),
        tooltip: active ? tr('Finish voice input') : tr('Voice input'),
        icon: Icons.graphic_eq_rounded,
        size: widget.size,
        iconSize: 22,
        variant: WeCordButtonVariant.ghost,
        selected: active,
        onPressed: widget.enabled ? _toggle : null,
        onLongPress: widget.enabled ? _hold : null,
      ),
    );
  }
}
