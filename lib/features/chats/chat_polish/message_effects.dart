// Keyword effects (A12): a message that holds a wish like "Happy birthday"
// lets emoji fall (or rise) over the chat once.
//
// * Everything happens on this device; the server knows nothing of it.
// * A message plays its effect once: the ones played are remembered (the last
//   [playedEffectsLimit]) on this device.
// * Only messages that just arrived or were just sent play (not history).
// * Nothing plays when the person asked for reduced motion, switched
//   "Keyword effects" off in Settings -> Chats, or the chat is not the screen
//   in front. Screen readers never hear it, and it never takes a tap.
// * At most [maxEffectParticles] emoji are drawn, by one painter that repaints
//   from one animation, so the list under it does not rebuild or slow down.
import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wecord/features/chats/chat_polish/chat_polish_settings.dart';
import 'package:wecord/features/chats/offline/outbox.dart'
    show isPendingMessageId;
import 'package:wecord/shared/models/message.dart';
import 'package:wecord/shared/ui/motion.dart';

/// Most emoji on screen at once.
const maxEffectParticles = 36;

/// How long an effect runs.
const messageEffectDuration = Duration(milliseconds: 3200);

/// A message older than this when it is looked at does not play (it is
/// history, not news).
const messageEffectFreshness = Duration(seconds: 30);

/// How many played messages are remembered.
const playedEffectsLimit = 200;

/// Which way the emoji move.
enum EffectDirection { fall, rise }

/// One kind of effect: the words that call it and what it shows.
class MessageEffect {
  const MessageEffect({
    required this.id,
    required this.keywords,
    required this.emoji,
    this.direction = EffectDirection.fall,
  });

  final String id;

  /// Lower case; a message holding one of these anywhere plays the effect.
  final List<String> keywords;
  final List<String> emoji;
  final EffectDirection direction;
}

/// The built-in effects, Chinese and English. The first one a message
/// matches plays.
const messageEffects = <MessageEffect>[
  MessageEffect(
    id: 'birthday',
    keywords: ['生日快乐', 'happy birthday', 'happy bday'],
    emoji: ['🎂', '🎈', '🎉', '🎁'],
  ),
  MessageEffect(
    id: 'new-year',
    keywords: ['新年快乐', '春节快乐', '过年好', 'happy new year'],
    emoji: ['🧧', '🏮', '🎆', '🎊'],
  ),
  MessageEffect(
    id: 'congrats',
    keywords: ['恭喜', '祝贺', 'congratulations', 'congrats'],
    emoji: ['🎉', '🎊', '✨', '👏'],
  ),
  MessageEffect(
    id: 'miss-you',
    keywords: ['想你了', '我想你', 'miss you', 'i love you', '我爱你'],
    emoji: ['💗', '💖', '💕', '❤️'],
    direction: EffectDirection.rise,
  ),
  MessageEffect(
    id: 'cheers',
    keywords: ['干杯', 'cheers'],
    emoji: ['🥂', '🍻', '🍾', '✨'],
  ),
  MessageEffect(
    id: 'good-night',
    keywords: ['晚安', 'good night', 'sweet dreams'],
    emoji: ['🌙', '⭐', '✨', '💤'],
  ),
];

/// The effect [body] calls for, or null. Case does not matter.
MessageEffect? effectForText(String body) {
  if (body.isEmpty || body.length > 2000) {
    return null;
  }
  final text = body.toLowerCase();
  for (final effect in messageEffects) {
    for (final keyword in effect.keywords) {
      if (text.contains(keyword)) {
        return effect;
      }
    }
  }
  return null;
}

/// The effect a text [message] plays, or null for other messages.
MessageEffect? effectForMessage(ChatMessage message) {
  if (message.type != MessageType.text ||
      message.recalledAt != null ||
      message.reviewState != null ||
      isPendingMessageId(message.id)) {
    return null;
  }
  return effectForText(message.body);
}

/// The key a message is remembered by: the same for the copy being sent and
/// the copy that came back.
String effectKeyOf(ChatMessage message) => message.clientId ?? message.id;

/// One emoji of an effect.
class EffectParticle {
  const EffectParticle({
    required this.emojiIndex,
    required this.lane,
    required this.delay,
    required this.size,
    required this.sway,
    required this.swayTurns,
    required this.spin,
    required this.speed,
  });

  final int emojiIndex;

  /// Across the screen, 0 to 1.
  final double lane;

  /// Fraction of the effect before it starts, 0 to 0.45.
  final double delay;
  final double size;
  final double sway;
  final double swayTurns;
  final double spin;
  final double speed;
}

/// The emoji of an effect, the same for the same [seed].
List<EffectParticle> effectParticles(
  MessageEffect effect,
  int seed, {
  int count = 30,
}) {
  final random = math.Random(seed);
  final total = count.clamp(0, maxEffectParticles);
  return [
    for (var index = 0; index < total; index++)
      EffectParticle(
        emojiIndex: random.nextInt(effect.emoji.length),
        lane: random.nextDouble(),
        delay: random.nextDouble() * 0.45,
        size: 20 + random.nextDouble() * 18,
        sway: 6 + random.nextDouble() * 18,
        swayTurns: 1 + random.nextDouble() * 2,
        spin: (random.nextDouble() - 0.5) * 2.4,
        speed: 0.85 + random.nextDouble() * 0.3,
      ),
  ];
}

/// Which messages have played their effect on this device.
final playedEffectsProvider =
    AsyncNotifierProvider<PlayedEffects, List<String>>(PlayedEffects.new);

class PlayedEffects extends AsyncNotifier<List<String>> {
  @override
  Future<List<String>> build() async {
    try {
      return await ref.read(chatPolishStoreProvider).loadPlayed();
    } on Object {
      return const [];
    }
  }

  /// Remembers [key]; the oldest are forgotten past [playedEffectsLimit].
  Future<void> add(String key) async {
    final current = state.value ?? const <String>[];
    if (current.contains(key)) {
      return;
    }
    final next = [...current, key];
    final kept = next.length > playedEffectsLimit
        ? next.sublist(next.length - playedEffectsLimit)
        : next;
    state = AsyncData(kept);
    try {
      await ref.read(chatPolishStoreProvider).savePlayed(kept);
    } on Object {
      // Still applies for this session.
    }
  }
}

/// Plays the effects of the chat's new messages over [child]. Put it in the
/// chat's stack; it takes no taps and no space.
class MessageEffectsOverlay extends ConsumerStatefulWidget {
  const MessageEffectsOverlay({required this.messages, this.now, super.key});

  /// The loaded messages, oldest first.
  final List<ChatMessage> messages;

  /// The time "now" for what counts as new; tests set it.
  final DateTime Function()? now;

  @override
  ConsumerState<MessageEffectsOverlay> createState() =>
      _MessageEffectsOverlayState();
}

class _MessageEffectsOverlayState extends ConsumerState<MessageEffectsOverlay>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  MessageEffect? _effect;
  MessageEffectPainter? _painter;
  var _scanQueued = false;

  @override
  void initState() {
    super.initState();
    _controller =
        AnimationController(vsync: this, duration: messageEffectDuration)
          ..addStatusListener((status) {
            if (status == AnimationStatus.completed && mounted) {
              setState(() => _effect = null);
              _queueScan();
            }
          });
    _queueScan();
  }

  @override
  void didUpdateWidget(covariant MessageEffectsOverlay oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.messages, widget.messages)) {
      _queueScan();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    _painter?.dispose();
    super.dispose();
  }

  /// Looks at the newest messages after this frame (never while building).
  void _queueScan() {
    if (_scanQueued) {
      return;
    }
    _scanQueued = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scanQueued = false;
      if (mounted) {
        unawaited(_scan());
      }
    });
  }

  Future<void> _scan() async {
    if (_effect != null) {
      return;
    }
    // What was saved on this device decides, so wait for it.
    await Future.wait([
      ref.read(keywordEffectsProvider.notifier).ready,
      ref.read(playedEffectsProvider.future),
    ]);
    if (!mounted ||
        _effect != null ||
        !ref.read(keywordEffectsProvider) ||
        WeCordMotion.reduceMotion(context) ||
        !TickerMode.getValuesNotifier(context).value.enabled ||
        !(ModalRoute.of(context)?.isCurrent ?? true)) {
      return;
    }
    final played = ref.read(playedEffectsProvider).value ?? const <String>[];
    final now = (widget.now ?? DateTime.now)();
    final messages = widget.messages;
    for (var index = messages.length - 1; index >= 0; index--) {
      final message = messages[index];
      final age = now.difference(message.createdAt);
      if (age > messageEffectFreshness) {
        // Oldest first: everything before this is older still.
        return;
      }
      if (age < -messageEffectFreshness) {
        // From the future (a clock that is off): not news.
        continue;
      }
      final effect = effectForMessage(message);
      if (effect == null) {
        continue;
      }
      final key = effectKeyOf(message);
      if (played.contains(key)) {
        continue;
      }
      unawaited(ref.read(playedEffectsProvider.notifier).add(key));
      _play(effect, key.hashCode);
      return;
    }
  }

  void _play(MessageEffect effect, int seed) {
    _painter?.dispose();
    setState(() {
      _effect = effect;
      _painter = MessageEffectPainter(
        effect: effect,
        particles: effectParticles(effect, seed),
        progress: _controller,
        seed: seed,
      );
    });
    unawaited(_controller.forward(from: 0));
  }

  @override
  Widget build(BuildContext context) {
    final effect = _effect;
    final painter = _painter;
    if (effect == null || painter == null) {
      return const SizedBox.shrink();
    }
    return Positioned.fill(
      child: IgnorePointer(
        child: ExcludeSemantics(
          child: RepaintBoundary(
            child: CustomPaint(
              key: ValueKey('message-effect-${effect.id}'),
              painter: painter,
              size: Size.infinite,
            ),
          ),
        ),
      ),
    );
  }
}

/// Draws an effect's emoji for the animation's value; repaints from the
/// animation alone.
class MessageEffectPainter extends CustomPainter {
  MessageEffectPainter({
    required this.effect,
    required this.particles,
    required this.progress,
    required this.seed,
  }) : super(repaint: progress) {
    _glyphs = [
      for (final emoji in effect.emoji)
        TextPainter(
          text: TextSpan(text: emoji, style: const TextStyle(fontSize: 32)),
          textDirection: TextDirection.ltr,
        )..layout(),
    ];
  }

  final MessageEffect effect;
  final List<EffectParticle> particles;
  final Animation<double> progress;
  final int seed;
  late final List<TextPainter> _glyphs;

  @override
  void paint(Canvas canvas, Size size) {
    final t = progress.value;
    final falling = effect.direction == EffectDirection.fall;
    for (final particle in particles) {
      final local =
          ((t - particle.delay) / (1 - particle.delay) * particle.speed).clamp(
            0.0,
            1.0,
          );
      if (local <= 0 || local >= 1) {
        continue;
      }
      final travel = size.height + particle.size * 2;
      final y = falling
          ? -particle.size + travel * local
          : size.height + particle.size - travel * local;
      final x =
          particle.lane * size.width +
          math.sin(local * particle.swayTurns * math.pi * 2) * particle.sway;
      final glyph = _glyphs[particle.emojiIndex];
      final scale = particle.size / 32;
      canvas
        ..save()
        ..translate(x, y)
        ..rotate(particle.spin * local * math.pi)
        ..scale(scale)
        ..translate(-glyph.width / 2, -glyph.height / 2);
      glyph.paint(canvas, Offset.zero);
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(MessageEffectPainter old) =>
      old.effect != effect || old.seed != seed || old.progress != progress;

  /// Releases the glyphs' native text layouts.
  void dispose() {
    for (final glyph in _glyphs) {
      glyph.dispose();
    }
  }
}
