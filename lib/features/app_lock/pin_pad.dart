import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:wecord/features/app_lock/app_lock_models.dart';
import 'package:wecord/shared/l10n/l10n.dart';
import 'package:wecord/shared/ui/ui.dart';

/// The PIN being typed: [filled] of [length] dots. Read by screen readers as
/// a count, never as the digits.
class PinDots extends StatelessWidget {
  const PinDots({
    required this.filled,
    this.length = pinLength,
    this.error = false,
    super.key,
  });

  final int filled;
  final int length;
  final bool error;

  @override
  Widget build(BuildContext context) {
    final c = context.tokens.colors;
    return Semantics(
      label: tr('PIN: {filled} of {length} digits', {
        'filled': filled,
        'length': length,
      }),
      excludeSemantics: true,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var i = 0; i < length; i++)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 7),
              child: AnimatedContainer(
                duration: WeCordMotion.quick,
                width: 14,
                height: 14,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: i < filled
                      ? (error ? c.danger : c.ink)
                      : Colors.transparent,
                  border: Border.all(
                    color: error ? c.danger : (i < filled ? c.ink : c.track),
                    width: 1.6,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// A PIN keypad: six dots above ten digits and a delete key. It also takes
/// the digits and Backspace of a keyboard. [onSubmit] is called with the PIN
/// when the last digit is typed; the entry is cleared after it answers.
class PinPad extends StatefulWidget {
  const PinPad({
    required this.onSubmit,
    this.enabled = true,
    this.error = false,
    this.autofocus = true,
    super.key,
  });

  final Future<void> Function(String pin) onSubmit;

  /// False while the person must wait, or while a try is being checked.
  final bool enabled;

  /// Paints the dots red (a wrong try).
  final bool error;
  final bool autofocus;

  static const deleteKey = ValueKey('pin-key-delete');

  /// The key of the digit [digit].
  static Key digitKey(int digit) => ValueKey('pin-key-$digit');

  @override
  State<PinPad> createState() => _PinPadState();
}

class _PinPadState extends State<PinPad> {
  var _digits = '';
  var _busy = false;
  final _focusNode = FocusNode(debugLabel: 'pin pad');

  @override
  void dispose() {
    _focusNode.dispose();
    super.dispose();
  }

  bool get _active => widget.enabled && !_busy;

  Future<void> _add(int digit) async {
    if (!_active || _digits.length >= pinLength) {
      return;
    }
    setState(() => _digits += '$digit');
    if (_digits.length == pinLength) {
      final pin = _digits;
      setState(() => _busy = true);
      try {
        await widget.onSubmit(pin);
      } finally {
        if (mounted) {
          setState(() {
            _digits = '';
            _busy = false;
          });
        }
      }
    }
  }

  void _delete() {
    if (!_active || _digits.isEmpty) {
      return;
    }
    setState(() => _digits = _digits.substring(0, _digits.length - 1));
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is KeyUpEvent) {
      return KeyEventResult.ignored;
    }
    if (event.logicalKey == LogicalKeyboardKey.backspace) {
      _delete();
      return KeyEventResult.handled;
    }
    final character = event.character;
    if (character != null && RegExp(r'^[0-9]$').hasMatch(character)) {
      unawaited(_add(int.parse(character)));
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    return Focus(
      focusNode: _focusNode,
      autofocus: widget.autofocus,
      onKeyEvent: _onKey,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          PinDots(filled: _digits.length, error: widget.error),
          const SizedBox(height: 28),
          LayoutBuilder(
            builder: (context, constraints) {
              final available = constraints.maxWidth.isFinite
                  ? constraints.maxWidth
                  : 300.0;
              const gap = 14.0;
              final size = math.max(
                0.0,
                math.min(72.0, (available - gap * 2) / 3),
              );
              Widget key(Widget child) =>
                  SizedBox(width: size, height: size, child: child);
              Widget digit(int value) => key(
                _PinKey(
                  key: PinPad.digitKey(value),
                  label: '$value',
                  semanticLabel: '$value',
                  onPressed: _active ? () => unawaited(_add(value)) : null,
                ),
              );
              Widget row(List<Widget> children) => Padding(
                padding: const EdgeInsets.only(bottom: gap),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    for (var i = 0; i < children.length; i++) ...[
                      if (i > 0) const SizedBox(width: gap),
                      children[i],
                    ],
                  ],
                ),
              );
              return Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  row([digit(1), digit(2), digit(3)]),
                  row([digit(4), digit(5), digit(6)]),
                  row([digit(7), digit(8), digit(9)]),
                  row([
                    key(const SizedBox.shrink()),
                    digit(0),
                    key(
                      _PinKey(
                        key: PinPad.deleteKey,
                        icon: Icons.backspace_outlined,
                        semanticLabel: tr('Delete'),
                        onPressed: _active && _digits.isNotEmpty
                            ? _delete
                            : null,
                      ),
                    ),
                  ]),
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}

class _PinKey extends StatelessWidget {
  const _PinKey({
    required this.semanticLabel,
    required this.onPressed,
    this.label,
    this.icon,
    super.key,
  });

  final String semanticLabel;
  final VoidCallback? onPressed;
  final String? label;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final c = context.tokens.colors;
    final enabled = onPressed != null;
    return WeCordPressable(
      onPressed: onPressed,
      shape: const CircleBorder(),
      semanticLabel: semanticLabel,
      excludeSemantics: true,
      minTapSize: Size.zero,
      builder: (context, states) {
        final hovered = states.contains(WidgetState.hovered);
        return DecoratedBox(
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: label == null
                ? Colors.transparent
                : (hovered ? c.raisedStrong : c.raised),
          ),
          child: Center(
            child: label != null
                ? FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(
                      label!,
                      style: TextStyle(
                        fontSize: 26,
                        fontWeight: FontWeight.w600,
                        color: enabled ? c.ink : c.faint,
                      ),
                    ),
                  )
                : Icon(icon, size: 22, color: enabled ? c.ink : c.faint),
          ),
        );
      },
    );
  }
}
