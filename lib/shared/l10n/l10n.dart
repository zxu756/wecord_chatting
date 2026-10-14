import 'dart:ui' show PlatformDispatcher;

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wecord/shared/l10n/zh/zh.dart';

/// The interface languages; [system] follows the device.
enum AppLanguage { system, english, chinese }

/// The language strings are shown in right now. The app sets it from the
/// Language setting; tests run in English.
abstract final class AppStrings {
  static var isChinese = false;
}

/// [english], in the current language, with `{name}` placeholders filled
/// from [args]. English text is the key: translations live in
/// `lib/shared/l10n/zh/`, and text without one stays English.
///
/// Pass whole sentences with placeholders rather than gluing translated
/// pieces together, since word order differs between languages:
/// `tr('Banned {name}.', {'name': name})`.
String tr(String english, [Map<String, Object?> args = const {}]) {
  var text = AppStrings.isChinese ? (zhStrings[english] ?? english) : english;
  for (final MapEntry(:key, :value) in args.entries) {
    text = text.replaceAll('{$key}', '$value');
  }
  return text;
}

/// [english] where the same English means something else elsewhere: looks
/// up `'[context]|[english]'` first, so one screen can word it differently
/// (the audit log's "Messages" filter is 消息, the Messages tab 私信).
String trIn(
  String context,
  String english, [
  Map<String, Object?> args = const {},
]) {
  if (AppStrings.isChinese) {
    final specific = zhStrings['$context|$english'];
    if (specific != null) {
      return tr(specific, args);
    }
  }
  return tr(english, args);
}

/// Whether [language] means Chinese on this device.
bool resolvesToChinese(AppLanguage language, {Locale? deviceLocale}) {
  return switch (language) {
    AppLanguage.chinese => true,
    AppLanguage.english => false,
    AppLanguage.system =>
      (deviceLocale ?? PlatformDispatcher.instance.locale).languageCode == 'zh',
  };
}

const _languageKey = 'wecord.appearance.language';

/// Where the language choice is kept; tests swap in memory.
abstract interface class AppLanguageStore {
  Future<AppLanguage?> load();

  Future<void> save(AppLanguage language);
}

class SharedPreferencesAppLanguageStore implements AppLanguageStore {
  const SharedPreferencesAppLanguageStore();

  @override
  Future<AppLanguage?> load() async {
    final preferences = await SharedPreferences.getInstance();
    final name = preferences.getString(_languageKey);
    return AppLanguage.values.where((value) => value.name == name).firstOrNull;
  }

  @override
  Future<void> save(AppLanguage language) async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.setString(_languageKey, language.name);
  }
}

class InMemoryAppLanguageStore implements AppLanguageStore {
  InMemoryAppLanguageStore([this._language]);

  AppLanguage? _language;

  @override
  Future<AppLanguage?> load() async => _language;

  @override
  Future<void> save(AppLanguage language) async => _language = language;
}

final appLanguageStoreProvider = Provider<AppLanguageStore>(
  (ref) => const SharedPreferencesAppLanguageStore(),
);

/// System, English or Chinese, remembered on this device. Follows the
/// system until the saved choice has loaded.
final appLanguageProvider =
    NotifierProvider<AppLanguageController, AppLanguage>(
      AppLanguageController.new,
    );

class AppLanguageController extends Notifier<AppLanguage> {
  var _changed = false;

  @override
  AppLanguage build() {
    ref.read(appLanguageStoreProvider).load().then((language) {
      // A choice made while loading wins over the saved one.
      if (language != null && !_changed) {
        state = language;
      }
    }, onError: (Object _) {});
    return AppLanguage.system;
  }

  Future<void> set(AppLanguage language) async {
    _changed = true;
    state = language;
    try {
      await ref.read(appLanguageStoreProvider).save(language);
    } on Object {
      // Still applies for this session.
    }
  }
}

/// Rebuilds everything under [context], so text picks up a new language
/// without losing navigation or scroll state.
void rebuildAllText(BuildContext context) {
  void rebuild(Element element) {
    element.markNeedsBuild();
    element.visitChildren(rebuild);
  }

  (context as Element).visitChildren(rebuild);
}
