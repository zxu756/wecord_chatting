// Switches for the chat touches that can be turned off (A10, A12), kept on
// this device: Settings -> Chats -> "Play voice messages one after another"
// and "Keyword effects".
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Where the choices are kept; tests swap in memory.
abstract interface class ChatPolishStore {
  /// Null until the choice was ever made.
  Future<bool?> load(String key);

  Future<void> save(String key, bool value);

  /// The messages whose keyword effect already played here.
  Future<List<String>> loadPlayed();

  Future<void> savePlayed(List<String> keys);
}

const voiceAutoplayKey = 'wecord.chat_polish.voice_autoplay';
const keywordEffectsKey = 'wecord.chat_polish.keyword_effects';
const playedEffectsKey = 'wecord.chat_polish.played_effects';

class SharedPreferencesChatPolishStore implements ChatPolishStore {
  const SharedPreferencesChatPolishStore();

  @override
  Future<bool?> load(String key) async {
    final preferences = await SharedPreferences.getInstance();
    return preferences.getBool(key);
  }

  @override
  Future<void> save(String key, bool value) async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.setBool(key, value);
  }

  @override
  Future<List<String>> loadPlayed() async {
    final preferences = await SharedPreferences.getInstance();
    return preferences.getStringList(playedEffectsKey) ?? const [];
  }

  @override
  Future<void> savePlayed(List<String> keys) async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.setStringList(playedEffectsKey, keys);
  }
}

class InMemoryChatPolishStore implements ChatPolishStore {
  InMemoryChatPolishStore([Map<String, bool>? values]) : values = values ?? {};

  final Map<String, bool> values;
  List<String> played = const [];

  @override
  Future<bool?> load(String key) async => values[key];

  @override
  Future<void> save(String key, bool value) async => values[key] = value;

  @override
  Future<List<String>> loadPlayed() async => played;

  @override
  Future<void> savePlayed(List<String> keys) async => played = keys;
}

final chatPolishStoreProvider = Provider<ChatPolishStore>(
  (ref) => const SharedPreferencesChatPolishStore(),
);

/// A switch that is on until the person turns it off, kept on the device.
class ChatPolishSwitch extends Notifier<bool> {
  ChatPolishSwitch(this.key);

  final String key;
  var _changed = false;

  /// Completes once the saved choice has been read (or could not be).
  Future<void> ready = Future<void>.value();

  @override
  bool build() {
    ready = ref
        .read(chatPolishStoreProvider)
        .load(key)
        .then((saved) {
          // A choice made while loading wins over the saved one.
          if (saved != null && !_changed && ref.mounted) {
            state = saved;
          }
        })
        .catchError((Object _) {});
    return true;
  }

  Future<void> set(bool value) async {
    _changed = true;
    state = value;
    try {
      await ref.read(chatPolishStoreProvider).save(key, value);
    } on Object {
      // Still applies for this session.
    }
  }
}

/// Play the next voice message you have not heard when one ends.
final voiceAutoplayProvider = NotifierProvider<ChatPolishSwitch, bool>(
  () => ChatPolishSwitch(voiceAutoplayKey),
);

/// Confetti and the like when a message holds a wish like "Happy birthday".
final keywordEffectsProvider = NotifierProvider<ChatPolishSwitch, bool>(
  () => ChatPolishSwitch(keywordEffectsKey),
);
