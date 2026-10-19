import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wecord/shared/l10n/l10n.dart';
import 'package:wecord/shared/ui/ui.dart';

/// The chat text sizes people can pick, as a factor of the text size they
/// already have from the system. The middle one changes nothing.
const chatTextScaleOptions = <double>[0.88, 1.0, 1.15, 1.3, 1.5];

/// The factor that changes nothing.
const defaultChatTextScale = 1.0;

/// The option nearest to [value].
double nearestChatTextScale(double value) {
  var best = chatTextScaleOptions.first;
  for (final option in chatTextScaleOptions) {
    if ((option - value).abs() < (best - value).abs()) {
      best = option;
    }
  }
  return best;
}

/// What the size [factor] is called.
String chatTextSizeName(double factor) {
  final index = chatTextScaleOptions.indexOf(nearestChatTextScale(factor));
  return switch (index) {
    0 => tr('Small'),
    1 => tr('Default'),
    2 => tr('Large'),
    3 => tr('Larger'),
    _ => tr('Largest'),
  };
}

const _chatTextScaleKey = 'wecord.appearance.chat_text_scale';

/// Where the chat text size is kept; tests swap in memory.
abstract interface class ChatTextScaleStore {
  Future<double?> load();

  Future<void> save(double factor);
}

class SharedPreferencesChatTextScaleStore implements ChatTextScaleStore {
  const SharedPreferencesChatTextScaleStore();

  @override
  Future<double?> load() async {
    final preferences = await SharedPreferences.getInstance();
    final value = preferences.getDouble(_chatTextScaleKey);
    return value == null ? null : nearestChatTextScale(value);
  }

  @override
  Future<void> save(double factor) async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.setDouble(_chatTextScaleKey, factor);
  }
}

class InMemoryChatTextScaleStore implements ChatTextScaleStore {
  InMemoryChatTextScaleStore([this.factor]);

  double? factor;

  @override
  Future<double?> load() async => factor;

  @override
  Future<void> save(double factor) async => this.factor = factor;
}

final chatTextScaleStoreProvider = Provider<ChatTextScaleStore>(
  (ref) => const SharedPreferencesChatTextScaleStore(),
);

/// The size of text in chats, on top of the system's text size, remembered on
/// this device. [defaultChatTextScale] until the saved choice has loaded.
final chatTextScaleProvider = NotifierProvider<ChatTextScaleController, double>(
  ChatTextScaleController.new,
);

class ChatTextScaleController extends Notifier<double> {
  var _changed = false;

  @override
  double build() {
    ref.read(chatTextScaleStoreProvider).load().then((factor) {
      // A choice made while loading wins over the saved one.
      if (factor != null && !_changed) {
        state = factor;
      }
    }, onError: (Object _) {});
    return defaultChatTextScale;
  }

  Future<void> set(double factor) async {
    final next = nearestChatTextScale(factor);
    _changed = true;
    state = next;
    try {
      await ref.read(chatTextScaleStoreProvider).save(next);
    } on Object {
      // Still applies for this session.
    }
  }
}

/// A text scaler that scales what [base] (the system's) does by [factor].
@immutable
class ChatTextScaler extends TextScaler {
  const ChatTextScaler(this.base, this.factor);

  final TextScaler base;
  final double factor;

  @override
  double scale(double fontSize) => base.scale(fontSize) * factor;

  @override
  double get textScaleFactor => scale(14) / 14;

  @override
  bool operator ==(Object other) =>
      other is ChatTextScaler && other.base == base && other.factor == factor;

  @override
  int get hashCode => Object.hash(base, factor);
}

/// Scales the text below it by the person's chat text size, on top of the
/// system's. Wrap the message list in it; with the default size it adds
/// nothing.
class ChatTextScale extends ConsumerWidget {
  const ChatTextScale({required this.child, super.key});

  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final factor = ref.watch(chatTextScaleProvider);
    if (factor == defaultChatTextScale) {
      return child;
    }
    final media = MediaQuery.of(context);
    return MediaQuery(
      data: media.copyWith(
        textScaler: ChatTextScaler(media.textScaler, factor),
      ),
      child: child,
    );
  }
}

/// Settings → Appearance: the size of text in chats, apart from the size set
/// in the device's settings, with a sample of what it looks like.
class ChatTextSizeRow extends ConsumerWidget {
  const ChatTextSizeRow({this.showIcon = true, super.key});

  final bool showIcon;

  static const sliderKey = ValueKey('chat-text-size-slider');
  static const sampleKey = ValueKey('chat-text-size-sample');

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.tokens.colors;
    final factor = ref.watch(chatTextScaleProvider);
    final index = chatTextScaleOptions.indexOf(nearestChatTextScale(factor));
    final name = chatTextSizeName(factor);
    return Padding(
      key: const ValueKey('chat-text-size-row'),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              if (showIcon) ...[
                const SettingsIconTile(icon: Icons.text_fields_rounded),
                const SizedBox(width: 12),
              ],
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      tr('Chat text size'),
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: c.ink,
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Text(
                        tr(
                          'The size of messages in chats, on top of the text size in your device settings.',
                        ),
                        style: TextStyle(fontSize: 12.5, color: c.muted),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Text(
                name,
                key: const ValueKey('chat-text-size-name'),
                textAlign: TextAlign.end,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                  color: c.muted,
                ),
              ),
            ],
          ),
          Row(
            children: [
              Text('A', style: TextStyle(fontSize: 13, color: c.muted)),
              Expanded(
                child: Slider(
                  key: sliderKey,
                  value: index.toDouble(),
                  max: (chatTextScaleOptions.length - 1).toDouble(),
                  divisions: chatTextScaleOptions.length - 1,
                  label: name,
                  semanticFormatterCallback: (value) =>
                      chatTextSizeName(chatTextScaleOptions[value.round()]),
                  onChanged: (value) => ref
                      .read(chatTextScaleProvider.notifier)
                      .set(chatTextScaleOptions[value.round()]),
                ),
              ),
              Text('A', style: TextStyle(fontSize: 22, color: c.muted)),
            ],
          ),
          // What a message looks like at this size.
          ExcludeSemantics(
            child: Align(
              alignment: AlignmentDirectional.centerStart,
              child: Container(
                key: sampleKey,
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 10,
                ),
                decoration: BoxDecoration(
                  color: c.raised,
                  borderRadius: BorderRadius.circular(WeCordRadii.lg),
                ),
                child: Text(
                  tr('This is how messages look.'),
                  style: TextStyle(
                    fontSize: 15 * math.max(factor, 0.1),
                    color: c.ink,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
