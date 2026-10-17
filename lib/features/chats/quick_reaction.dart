import 'dart:async';

import 'package:clock/clock.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wecord/features/chats/message_reactions.dart';
import 'package:wecord/shared/l10n/l10n.dart';
import 'package:wecord/shared/ui/ui.dart';

const _quickReactionKey = 'wecord.chat.quickReaction';

/// The reaction a double tap adds until the user picks another.
const defaultQuickReaction = '👍';

/// Where the quick reaction is kept; tests swap in memory.
abstract interface class QuickReactionStore {
  Future<String?> load();

  Future<void> save(String emoji);
}

class SharedPreferencesQuickReactionStore implements QuickReactionStore {
  const SharedPreferencesQuickReactionStore();

  @override
  Future<String?> load() async {
    final preferences = await SharedPreferences.getInstance();
    return preferences.getString(_quickReactionKey);
  }

  @override
  Future<void> save(String emoji) async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.setString(_quickReactionKey, emoji);
  }
}

class InMemoryQuickReactionStore implements QuickReactionStore {
  InMemoryQuickReactionStore([this._emoji]);

  String? _emoji;

  @override
  Future<String?> load() async => _emoji;

  @override
  Future<void> save(String emoji) async => _emoji = emoji;
}

final quickReactionStoreProvider = Provider<QuickReactionStore>(
  (ref) => const SharedPreferencesQuickReactionStore(),
);

/// The emoji a double tap (touch) or double click (desktop) on a message
/// reacts with, kept on this device. 👍 until the saved choice loads.
final quickReactionProvider = NotifierProvider<QuickReactionController, String>(
  QuickReactionController.new,
);

class QuickReactionController extends Notifier<String> {
  var _changed = false;

  @override
  String build() {
    ref.read(quickReactionStoreProvider).load().then((emoji) {
      // A choice made while loading wins over the saved one.
      if (emoji != null && emoji.isNotEmpty && !_changed) {
        state = emoji;
      }
    }, onError: (Object _) {});
    return defaultQuickReaction;
  }

  Future<void> set(String emoji) async {
    _changed = true;
    state = emoji;
    try {
      await ref.read(quickReactionStoreProvider).save(emoji);
    } on Object {
      // Still applies for this session.
    }
  }
}

/// Reports a second quick tap (or click) on its child without taking part
/// in the gesture arena, so single taps on links, pictures and buttons in
/// the child work at once, long presses and swipes still win, and nothing
/// waits for a double tap that may not come.
class QuickDoubleTap extends StatefulWidget {
  const QuickDoubleTap({
    required this.child,
    required this.onDoubleTap,
    this.enabled = true,
    super.key,
  });

  final Widget child;
  final VoidCallback onDoubleTap;
  final bool enabled;

  /// A tap is a press that ends within this time without moving much.
  static const tapTime = Duration(milliseconds: 250);

  /// The second tap must come this soon after the first.
  static const gap = Duration(milliseconds: 300);

  @override
  State<QuickDoubleTap> createState() => _QuickDoubleTapState();
}

class _QuickDoubleTapState extends State<QuickDoubleTap> {
  DateTime? _downAt;
  Offset? _downPosition;
  var _moved = false;
  DateTime? _lastTapAt;
  Offset? _lastTapPosition;

  void _down(PointerDownEvent event) {
    if (!widget.enabled || (event.buttons & kPrimaryButton) == 0) {
      _downAt = null;
      return;
    }
    _downAt = clock.now();
    _downPosition = event.position;
    _moved = false;
  }

  void _move(PointerMoveEvent event) {
    final start = _downPosition;
    if (start != null && (event.position - start).distance > kTouchSlop) {
      _moved = true;
    }
  }

  void _up(PointerUpEvent event) {
    final downAt = _downAt;
    _downAt = null;
    if (downAt == null || _moved || !widget.enabled) {
      _lastTapAt = null;
      return;
    }
    final now = clock.now();
    if (now.difference(downAt) > QuickDoubleTap.tapTime) {
      _lastTapAt = null;
      return;
    }
    final lastAt = _lastTapAt;
    final lastPosition = _lastTapPosition;
    if (lastAt != null &&
        lastPosition != null &&
        now.difference(lastAt) <= QuickDoubleTap.gap &&
        (event.position - lastPosition).distance <= kDoubleTapSlop) {
      _lastTapAt = null;
      widget.onDoubleTap();
      return;
    }
    _lastTapAt = now;
    _lastTapPosition = event.position;
  }

  void _cancel(PointerCancelEvent event) {
    _downAt = null;
    _lastTapAt = null;
  }

  @override
  Widget build(BuildContext context) {
    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: _down,
      onPointerMove: _move,
      onPointerUp: _up,
      onPointerCancel: _cancel,
      child: widget.child,
    );
  }
}

/// Floats [emoji] up from the middle of [context]'s widget, growing and
/// fading: the pop after a double tap. Nothing moves when the platform
/// asks for reduced motion.
void playQuickReactionPop(BuildContext context, String emoji) {
  if (WeCordMotion.reduceMotion(context)) {
    return;
  }
  final overlay = Overlay.maybeOf(context, rootOverlay: true);
  final box = context.findRenderObject();
  if (overlay == null || box is! RenderBox || !box.hasSize) {
    return;
  }
  final center = box.localToGlobal(box.size.center(Offset.zero));
  late final OverlayEntry entry;
  entry = OverlayEntry(
    builder: (context) => Positioned(
      left: center.dx - 40,
      top: center.dy - 40,
      width: 80,
      height: 80,
      child: IgnorePointer(
        child: ExcludeSemantics(
          child: TweenAnimationBuilder<double>(
            key: const ValueKey('quick-reaction-pop'),
            tween: Tween(begin: 0, end: 1),
            duration: const Duration(milliseconds: 650),
            curve: Curves.linear,
            onEnd: () => entry.remove(),
            builder: (context, t, _) {
              // Springs up past its size and settles, then drifts off.
              final grow = Curves.elasticOut.transform((t * 2).clamp(0, 1));
              final fade = t < 0.6 ? 1.0 : 1 - (t - 0.6) / 0.4;
              return Opacity(
                opacity: fade.clamp(0, 1),
                child: Transform.translate(
                  offset: Offset(0, -24 * t),
                  child: Transform.scale(
                    scale: 0.4 + 0.9 * grow,
                    child: Center(
                      // Material gives the overlay its text style (the pop
                      // sits outside the page's).
                      child: Material(
                        type: MaterialType.transparency,
                        child: Text(
                          emoji,
                          style: const TextStyle(fontSize: 44, height: 1),
                        ),
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ),
    ),
  );
  overlay.insert(entry);
}

/// Settings → Chats: the quick reaction.
class QuickReactionSettingsGroup extends ConsumerWidget {
  const QuickReactionSettingsGroup({this.header, super.key});

  final String? header;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final emoji = ref.watch(quickReactionProvider);
    return SettingsGroup(
      header: header,
      footer: tr(
        'Double-tap a message (double-click on a computer) to react with it.',
      ),
      children: [
        SettingsRow(
          key: const ValueKey('quick-reaction-row'),
          icon: Icons.add_reaction_outlined,
          title: tr('Quick reaction'),
          subtitle: tr('Added when you double-tap a message'),
          trailing: Text(emoji, style: const TextStyle(fontSize: 22)),
          showChevron: true,
          onTap: () async {
            final picked = await showEmojiReactionPicker(
              context,
              title: tr('Quick reaction'),
            );
            if (picked != null && picked.isNotEmpty) {
              WeCordHaptics.selection();
              unawaited(ref.read(quickReactionProvider.notifier).set(picked));
            }
          },
        ),
        if (emoji != defaultQuickReaction)
          SettingsRow(
            key: const ValueKey('quick-reaction-reset'),
            title: tr('Back to {emoji}', {'emoji': defaultQuickReaction}),
            onTap: () => unawaited(
              ref
                  .read(quickReactionProvider.notifier)
                  .set(defaultQuickReaction),
            ),
          ),
      ],
    );
  }
}
